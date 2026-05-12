`include "npu_defs.vh"

// ============================================================
// npu_compute_pool - 计算池模块（标准FSM三分法重构）
// 实例化 32 个 npu_tile，分发数据并收集结果
// 每个 Tile 带独立时钟门控，未使能的 Tile 时钟停止以节省功耗
// 
// FSM设计原则：
// 1. 时序逻辑块：无（纯组合逻辑汇总）
// 2. 组合逻辑块1：Tile使能和时钟门控
// 3. 组合逻辑块2：状态汇总
// ============================================================
module npu_compute_pool (clk, rst_n,
    cfg_k, cfg_tile_mask,
    tile_en, tile_a_data, tile_a_valid,
    tile_b_data, tile_b_valid,
    tile_c_data, tile_c_valid, tile_c_ready,
    tile_done, pool_done
);

    parameter TILE_COUNT  = `NPU_NUM_TILES;
    parameter K_MAX       = `NPU_K_MAX;
    parameter A_BUS_WIDTH = 8 * `NPU_NUM_TILES;
    parameter C_BUS_WIDTH = `NPU_TILE_C_BITS * `NPU_NUM_TILES;  // 2048 * 32 = 65536位

    input  wire                       clk;
    input  wire                       rst_n;
    input  wire [5:0]                 cfg_k;
    input  wire [31:0]                cfg_tile_mask;
    input  wire [TILE_COUNT-1:0]      tile_en;
    input  wire [A_BUS_WIDTH-1:0]     tile_a_data;
    input  wire                       tile_a_valid;
    input  wire [A_BUS_WIDTH-1:0]     tile_b_data;
    input  wire                       tile_b_valid;
    output wire [C_BUS_WIDTH-1:0]     tile_c_data;
    output wire                       tile_c_valid;
    input  wire                       tile_c_ready;
    output wire [TILE_COUNT-1:0]      tile_done;
    output wire                       pool_done;

    // ========================================================
    //  内部信号定义
    // ========================================================
    wire [TILE_COUNT-1:0] tile_compute_done;
    wire [TILE_COUNT-1:0] tile_gated_clk;  // 每个 Tile 的门控时钟

    // ========================================================
    //  时钟门控 + Tile 实例化（时序逻辑块1：Tile阵列）
    // ========================================================
    genvar t;
    generate
        for (t = 0; t < TILE_COUNT; t = t + 1) begin : gen_tile

            // ---- ICG 时钟门控单元 ----
            npu_clock_gate u_clk_gate (
                .clk_in  (clk),
                .en      (tile_en[t]),
                .clk_out (tile_gated_clk[t])
            );

            // ---- Tile 实例化（使用门控时钟）----
            npu_tile #(
                .K_MAX(K_MAX)
            ) u_tile (
                .clk          (tile_gated_clk[t]),
                .rst_n        (rst_n),
                .cfg_k        (cfg_k),
                .tile_en      (tile_en[t]),
                .a_data       (tile_a_data[t*8 +: 8]),
                .a_valid      (tile_a_valid),
                .a_ready      (),
                .b_data       (tile_b_data[t*8 +: 8]),
                .b_valid      (tile_b_valid),
                .b_ready      (),
                .c_data       (tile_c_data[t*`NPU_TILE_C_BITS +: `NPU_TILE_C_BITS]),  // 2048位宽
                .c_valid      (),
                .c_ready      (tile_c_ready),
                .compute_done (tile_compute_done[t])
            );
        end
    endgenerate

    // ========================================================
    //  Tile 使能逻辑（组合逻辑块1）
    // ========================================================
    wire [TILE_COUNT-1:0] tile_active;
    
    assign tile_active = tile_en & cfg_tile_mask;
/*    
    // [DEBUG] Compute Pool使能监控
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时不输出
        end else begin
            if (|tile_en) begin
                $display("[POOL DBG] t=%0t tile_en=0x%08X, tile_active=0x%08X, cfg_tile_mask=0x%08X",
                         $time, tile_en, tile_active, cfg_tile_mask);
            end
        end
    end
*/
    // ========================================================
    //  状态汇总（组合逻辑块2：输出逻辑）
    // ========================================================
    wire pool_calc_done;
    
    assign pool_calc_done = &(tile_compute_done | ~tile_active);

    // ========================================================
    //  输出信号赋值
    // ========================================================
    assign tile_done = tile_compute_done;
    assign pool_done = pool_calc_done;
    // ========================================================
    //  tile_c_valid 寄存器锁存（修复时序问题）
    // ========================================================
    reg tile_c_valid_reg;
    reg [31:0] tile_en_prev;

    // 检测 tile_en 从非零变为全零的下降沿
    wire tile_en_all_fall = (tile_en_prev != 32'd0) && (tile_en == 32'd0);

    // tile_en_all_fall 后的保护期：屏蔽 pool_calc_done 的残留置位
    // tile_en 从 0→1 时 tile 仍在 DONE，pool_calc_done 仍为 1，需要等 tile 转到 IDLE
    reg tile_en_was_zero;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tile_en_was_zero <= 1'b0;
        else if (tile_en_all_fall)
            tile_en_was_zero <= 1'b1;  // 进入保护期
        else if (tile_en != 32'd0)
            tile_en_was_zero <= 1'b0;  // tile_en 恢复后一周期解除保护
    end

    // tile_c_valid_reg 状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tile_c_valid_reg <= 1'b0;
            tile_en_prev <= 32'd0;
        end else begin
            // 更新 tile_en 的历史值
            tile_en_prev <= tile_en;

            // 最高优先级：tile_en 下降沿时清除 tile_c_valid_reg
            if (tile_en_all_fall) begin
                tile_c_valid_reg <= 1'b0;
            end
            // 置位条件：所有 Tile 计算完成且当前未置位
            // tile_en_was_zero 保护期阻止 pool_calc_done 残留置位
            else if (pool_calc_done && !tile_c_valid_reg && !tile_en_was_zero) begin
                tile_c_valid_reg <= 1'b1;
            end
            // 其他情况保持不变
        end
    end

    // 输出赋值
    assign tile_c_valid = tile_c_valid_reg;

endmodule