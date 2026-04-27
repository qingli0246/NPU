`timescale 1ns/1ps
`include "npu_defs.vh"

module npu_compute_pool (
    // 时钟与复位
    input  wire                                     clk,
    input  wire                                     rst_n,
    input  wire                                     clk_en,

    // Tile 启动与门控控制
    input  wire [`NPU_NUM_TILES-1:0]                tile_start_mask,
    input  wire [`NPU_NUM_TILES-1:0]                tile_clk_en_mask,

    // 重构配置接口：模式、分组主从、横/纵级联开关
    input  wire [1:0]                               cfg_top_mode,
    input  wire [`NPU_NUM_TILES-1:0]                cfg_group_master,
    input  wire [`NPU_NUM_TILES-1:0]                cfg_h_link_en,
    input  wire [`NPU_NUM_TILES-1:0]                cfg_v_link_en,

    // Tile 批量输入数据总线
    input  wire [`NPU_NUM_TILES*`NPU_TILE_A_BITS-1:0] tile_a_bus,
    input  wire [`NPU_NUM_TILES*`NPU_TILE_B_BITS-1:0] tile_b_bus,

    // Tile 批量输出结果总线
    output wire [`NPU_NUM_TILES*`NPU_TILE_C_BITS-1:0] tile_c_bus,

    // 运行状态与模式指示
    output wire [`NPU_NUM_TILES-1:0]                tile_busy_mask,
    output wire [`NPU_NUM_TILES-1:0]                tile_done_mask,
    output wire                                     pool_busy,
    output wire                                     pool_done,
    output wire                                     merge_link_active,
    output wire                                     split_link_active,
    output wire                                     indep_link_active
);

    // =============================================================
    // 重构规则总览（软件配置 -> 阵列排列）
    // =============================================================
    // 1) INDEP（cfg_top_mode = NPU_MODE_INDEP）
    //    - 横向/纵向链路均不生效（即使 cfg_h_link_en/cfg_v_link_en 置 1 也会被模式门控关闭）
    //    - 32 个 Tile 完全独立运行，分别使用各自 tile_a_bus/tile_b_bus
    //
    // 2) MERGE（cfg_top_mode = NPU_MODE_MERGE）
    //    - 横向链路条件：cfg_h_link_en[i] = 1 且 i 不在每行首列
    //      a_left[i] <- a_right[i-1]
    //    - 纵向链路条件：cfg_v_link_en[i] = 1 且 i >= NPU_TILE_COLS
    //      b_top[i] <- b_down[i-NPU_TILE_COLS]
    //    - cfg_group_master[i] 用于标记分组主 Tile（主 Tile 保留本地注入，从 Tile 优先级联注入）
    //
    // 3) SPLIT（cfg_top_mode = NPU_MODE_SPLIT）
    //    - 互联链路关闭，每个 Tile 在内部切成 4 个 4x4 子阵列（由 npu_tile 内部实现）
    //
    // Tile 索引采用行优先：
    // idx = row * NPU_TILE_COLS + col，其中 NPU_TILE_COLS = 8
    // 例如：第 2 行第 3 列 Tile 的 idx = 1*8+2 = 10

    // ---------------------------
    // 脉动互联总线（MERGE 模式）
    // ---------------------------
    wire [`TILE_PORT_W-1:0] tile_a_left  [0:`NPU_NUM_TILES-1];
    wire [`TILE_PORT_W-1:0] tile_b_top   [0:`NPU_NUM_TILES-1];
    wire [`TILE_PORT_W-1:0] tile_a_right [0:`NPU_NUM_TILES-1];
    wire [`TILE_PORT_W-1:0] tile_b_down  [0:`NPU_NUM_TILES-1];

    genvar i;
    generate
        // 边界默认值：左边界和上边界没有前驱 Tile，默认注入 0。
        // 因此：每行最左 Tile 不会从左侧级联取数；第一行 Tile 不会从上侧级联取数。
        for (i = 0; i < `NPU_NUM_TILES; i = i + 1) begin : g_boundary
            if ((i % `NPU_TILE_COLS) == 0) begin : g_left_boundary
                assign tile_a_left[i] = {`TILE_PORT_W{1'b0}};
            end
            if (i < `NPU_TILE_COLS) begin : g_top_boundary
                assign tile_b_top[i] = {`TILE_PORT_W{1'b0}};
            end
        end

        // 水平级联：左 Tile 的右输出，送到右 Tile 的左输入。
        // 典型用途：把同一行多个 Tile 拼成更宽阵列。
        for (i = 1; i < `NPU_NUM_TILES; i = i + 1) begin : g_horizontal_link
            if ((i % `NPU_TILE_COLS) != 0) begin : g_h_link_valid
                assign tile_a_left[i] = ((cfg_top_mode == `NPU_MODE_MERGE) && cfg_h_link_en[i])
                                      ? tile_a_right[i-1]
                                      : {`TILE_PORT_W{1'b0}};
            end
        end

        // 垂直级联：上 Tile 的下输出，送到下 Tile 的上输入。
        // 典型用途：把同一列多个 Tile 拼成更高阵列。
        for (i = `NPU_TILE_COLS; i < `NPU_NUM_TILES; i = i + 1) begin : g_vertical_link
            assign tile_b_top[i] = ((cfg_top_mode == `NPU_MODE_MERGE) && cfg_v_link_en[i])
                                 ? tile_b_down[i-`NPU_TILE_COLS]
                                 : {`TILE_PORT_W{1'b0}};
        end

        for (i = 0; i < `NPU_NUM_TILES; i = i + 1) begin : g_tiles
            npu_tile #(.TILE_ID(i)) u_tile (
                .clk       (clk),
                .rst_n     (rst_n),
                .clk_en    (clk_en & tile_clk_en_mask[i]),
                .start     (tile_start_mask[i]),
                .top_mode  (cfg_top_mode),
                .is_master (cfg_group_master[i]),
                .a_flat    (tile_a_bus[i*`NPU_TILE_A_BITS +: `NPU_TILE_A_BITS]),
                .b_flat    (tile_b_bus[i*`NPU_TILE_B_BITS +: `NPU_TILE_B_BITS]),
                .a_left_i  (tile_a_left[i]),
                .b_top_i   (tile_b_top[i]),
                .a_right_o (tile_a_right[i]),
                .b_down_o  (tile_b_down[i]),
                .busy      (tile_busy_mask[i]),
                .done      (tile_done_mask[i]),
                .c_flat    (tile_c_bus[i*`NPU_TILE_C_BITS +: `NPU_TILE_C_BITS])
            );
        end
    endgenerate

    // 典型配置示例：
    // A) 全独立（32x 8x8）
    //    cfg_top_mode=INDEP, cfg_h_link_en=0, cfg_v_link_en=0, cfg_group_master=全1
    //
    // B) 单行 4 Tile 合并（1x4）
    //    假设使用第 0 行 idx:0,1,2,3
    //    cfg_top_mode=MERGE
    //    cfg_h_link_en[1]=1,cfg_h_link_en[2]=1,cfg_h_link_en[3]=1
    //    cfg_group_master[0]=1, 其余从 Tile 可置 0
    //
    // C) 2x2 Tile 合并（形成 16x16 级联骨架）
    //    假设左上角 idx=t，右上 t+1，左下 t+8，右下 t+9
    //    cfg_top_mode=MERGE
    //    横向：cfg_h_link_en[t+1]=1, cfg_h_link_en[t+9]=1
    //    纵向：cfg_v_link_en[t+8]=1, cfg_v_link_en[t+9]=1
    //    主 Tile：cfg_group_master[t]=1，其余可置 0
    //
    // D) 全部拆分（128x 4x4）
    //    cfg_top_mode=SPLIT, cfg_h_link_en=0, cfg_v_link_en=0

    // 互联状态指示：当前骨架中先输出配置态，便于后续把真实路由逻辑补进来。
    assign merge_link_active = (cfg_top_mode == `NPU_MODE_MERGE);
    assign split_link_active = (cfg_top_mode == `NPU_MODE_SPLIT);
    assign indep_link_active = (cfg_top_mode == `NPU_MODE_INDEP);

    assign pool_busy = |tile_busy_mask;
    
    // 修正：pool_done只检查被启用的Tile（根据tile_start_mask）
    // 未启用的Tile视为已完成（done=1）
    wire [31:0] effective_tile_done;
    genvar j;
    generate
        for (j = 0; j < `NPU_NUM_TILES; j = j + 1) begin : g_effective_done
            // 如果Tile被启动，使用其实际done信号；否则视为已完成
            assign effective_tile_done[j] = tile_start_mask[j] ? tile_done_mask[j] : 1'b1;
        end
    endgenerate
    
    assign pool_done = &effective_tile_done;

endmodule
