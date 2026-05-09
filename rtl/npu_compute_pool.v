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
    parameter C_BUS_WIDTH = 256 * `NPU_NUM_TILES;

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
                .c_data       (tile_c_data[t*256 +: 256]),
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
    assign tile_c_valid = pool_calc_done;

endmodule