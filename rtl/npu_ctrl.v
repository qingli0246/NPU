`timescale 1ns/1ps
`include "npu_defs.vh"

module npu_ctrl (
    input  wire                     clk,
    input  wire                     rst_n,

    // AXI-Lite 写寄存器后的抽象控制脉冲
    input  wire                     cfg_start_pulse,
    input  wire [1:0]               cfg_mode,
    input  wire                     cfg_b_static,      // B矩阵静态权重标志（来自reg_mode[2]）
    input  wire                     cfg_b_independent, // B矩阵独立权重标志（来自reg_mode[3]）
    input  wire [4:0]               cfg_tile_mask_lo,
    input  wire [4:0]               cfg_tile_mask_hi,
    input  wire [31:0]              cfg_a_base,
    input  wire [31:0]              cfg_b_base,
    input  wire [31:0]              cfg_c_base,
    input  wire [31:0]              cfg_matrix_m,
    input  wire [31:0]              cfg_matrix_n,
    input  wire [31:0]              cfg_matrix_k,
    input  wire                     pool_busy,
    input  wire                     pool_done,
    input  wire                     rd_busy,
    input  wire                     rd_done,
    input  wire                     wr_busy,
    input  wire                     wr_done,

    output reg  [`NPU_NUM_TILES-1:0] pool_tile_start_mask,
    output reg  [`NPU_NUM_TILES-1:0] pool_tile_clk_en_mask,
    output reg  [1:0]               pool_mode,
    output reg                      rd_start,
    output reg                      wr_start,
    output reg  [31:0]              rd_base_addr,
    output reg  [31:0]              wr_base_addr,
    output reg  [15:0]              rd_word_count,
    output reg  [15:0]              wr_word_count,
    output reg                      cache_we,
    output reg  [4:0]               cache_waddr,
    output reg  [`NPU_TILE_B_BITS-1:0] cache_wdata,
    output reg                      global_busy,
    output reg                      global_done,
    output reg                      global_error,
    output reg  [3:0]               global_state
);

    reg [3:0] state;
    
    // B矩阵加载策略标志
    reg b_matrix_static;      // B矩阵是否为静态权重（不改变）
    reg b_weight_independent; // B矩阵是否为独立权重（每个Tile不同）
    
    // A矩阵加载完成标志
    reg a_load_done_flag;
    
    // Tile启动掩码发送标志（用于产生一个周期的start脉冲）
    reg tile_start_mask_sent;
    reg [`NPU_NUM_TILES-1:0] tile_start_mask_value;
    reg [1:0] run_start_delay;

    // A 矩阵读取字数计算：取决于工作模式
    // A 矩阵大小：M×K，每个元素 8bit
    // 按 32bit 分片，所以字数 = ceil((M*K*8) / 32) = ceil(M*K/4)
    // 在不同模式下读取量有所不同：
    //   - INDEP：需要完整的 M×K 矩阵分发到所有 Tile
    //   - MERGE：级联模式，仍然需要完整的 M×K 矩阵
    //   - SPLIT：拆分模式，同样需要完整的 M×K 矩阵
    function [15:0] calc_rd_word_count;
        input [1:0]  mode;
        input [31:0] m;
        input [31:0] n;
        input [31:0] k;
        input [31:0] tile_mask;  // 新增参数
        reg [63:0] a_elems_per_tile;
        reg [63:0] words_per_tile;
        reg [31:0] enabled_count;
        reg [63:0] total_words;
        integer i;
        begin
            // 每个 Tile 处理 8 行，需要 8×K 个元素
            a_elems_per_tile = 8 * k;
            words_per_tile = (a_elems_per_tile * 8 + 31) >> 5;  // ceil(8*K*8 / 32)
            
            // 计算启用的 Tile 数量
            enabled_count = 0;
            for (i = 0; i < 32; i = i + 1) begin
                if (tile_mask[i]) begin
                    enabled_count = enabled_count + 1;
                end
            end
            
            // 根据模式计算总字数
            case (mode)
                `NPU_MODE_INDEP: begin
                    // 每个 Tile 需要 8×K 的数据
                    total_words = words_per_tile * enabled_count;
                end
                `NPU_MODE_MERGE: begin
                    // 只有主 Tile 需要外部数据（假设 1 个主 Tile）
                    total_words = words_per_tile;
                end
                `NPU_MODE_SPLIT: begin
                    // 每个 Tile 需要 8×K 的数据
                    total_words = words_per_tile * enabled_count;
                end
                default: begin
                    total_words = words_per_tile * enabled_count;
                end
            endcase
            
            // 返回值保护
            if (total_words == 0) begin
                calc_rd_word_count = 16'd1;
            end else if (total_words > 16'hFFFF) begin
                calc_rd_word_count = 16'hFFFF;
            end else begin
                calc_rd_word_count = total_words[15:0];
            end
        end
    endfunction

    // B 矩阵读取字数计算函数
    function [15:0] calc_b_rd_word_count;
        input [31:0] k;
        input [31:0] n;
        input        is_static;
        input        is_independent;
        reg [63:0] b_elems;
        reg [63:0] words_per_tile;
        reg [63:0] total_words;
        begin
            if (is_static) begin
                // 静态权重：不需要从外部读取，使用缓存中的值
                calc_b_rd_word_count = 16'd0;
            end else begin
                // 动态权重：需要从外部存储器读取B矩阵
                // B 矩阵大小：K×N × 8bit 元素
                // 转换为 32bit 字：ceil((K*N*8) / 32) = ceil(K*N/4)
                b_elems = k * n;
                words_per_tile = (b_elems * 8 + 31) >> 5;  // 每个Tile的字数
                
                if (is_independent) begin
                    // 独立权重模式（优化版）：分组共享
                    // 将32个Tile分为4组，每组8个Tile共享相同权重
                    // 只需加载4个不同的权重矩阵
                    total_words = words_per_tile * 4;  // 4组而非32个
                end else begin
                    // 权重共享模式：只加载一次，所有Tile共享
                    total_words = words_per_tile;
                end
                
                if (total_words == 0) begin
                    calc_b_rd_word_count = 16'd1;
                end else if (total_words > 16'hFFFF) begin
                    calc_b_rd_word_count = 16'hFFFF;
                end else begin
                    calc_b_rd_word_count = total_words[15:0];
                end
            end
        end
    endfunction

    // C 矩阵写入字数计算函数
    function [15:0] calc_c_wr_word_count;
        input [1:0] mode;
        input [31:0] m;
        input [31:0] n;
        reg [63:0] c_elems;
        reg [63:0] total_words;
        begin
            // C 矩阵大小：M×N × 32bit 元素（根据NPU_TILE_C_BITS定义）
            // 转换为 32bit 字：M*N（每个元素占1个word）
            c_elems = m * n;
            total_words = c_elems;
            
            if (total_words == 0) begin
                calc_c_wr_word_count = 16'd1;
            end else if (total_words > 16'hFFFF) begin
                calc_c_wr_word_count = 16'hFFFF;
            end else begin
                calc_c_wr_word_count = total_words[15:0];
            end
        end
    endfunction

    // C 矩阵写回字数计算
    // 结果矩阵 C 按 32bit/元素存储；AXI 数据宽度为 32bit，所以每个 word 存 1 个元素。
    // wr_word_count = M*N。
    function [15:0] calc_wr_word_count;
        input [1:0]  mode;
        input [31:0] m;
        input [31:0] n;
        input [31:0] k;
        reg [63:0] c_elems;
        reg [63:0] words;
        begin
            // 预留 mode 分支，后续若不同模式写回格式不同，可在这里单独处理。
            case (mode)
                `NPU_MODE_INDEP: c_elems = m * n;
                `NPU_MODE_MERGE: c_elems = m * n;
                `NPU_MODE_SPLIT: c_elems = m * n;
                default:         c_elems = m * n;
            endcase

            words = c_elems;

            // 防止 word_count 为 0 触发 DMA 比较下溢；同时对 16bit 计数做饱和。
            if (words == 0) begin
                calc_wr_word_count = 16'd1;
            end else if (words > 16'hFFFF) begin
                calc_wr_word_count = 16'hFFFF;
            end else begin
                calc_wr_word_count = words[15:0];
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= `NPU_ST_IDLE;
            pool_tile_start_mask  <= {`NPU_NUM_TILES{1'b0}};
            pool_tile_clk_en_mask <= {`NPU_NUM_TILES{1'b0}};
            pool_mode             <= `NPU_MODE_INDEP;
            rd_start              <= 1'b0;
            wr_start              <= 1'b0;
            rd_base_addr          <= 32'd0;
            wr_base_addr          <= 32'd0;
            rd_word_count         <= 16'd0;
            wr_word_count         <= 16'd0;
            cache_we              <= 1'b0;
            cache_waddr           <= 5'd0;
            cache_wdata           <= {`NPU_TILE_B_BITS{1'b0}};
            global_busy           <= 1'b0;
            global_done           <= 1'b0;
            global_error          <= 1'b0;
            global_state          <= `NPU_ST_IDLE;
            b_matrix_static       <= 1'b0;
            b_weight_independent  <= 1'b0;
            a_load_done_flag      <= 1'b0;
            tile_start_mask_sent  <= 1'b0;
            tile_start_mask_value <= {`NPU_NUM_TILES{1'b0}};
            run_start_delay       <= 2'd0;
        end else begin
            rd_start     <= 1'b0;
            wr_start     <= 1'b0;
            cache_we     <= 1'b0;
            global_done  <= 1'b0;
            global_error <= 1'b0;
            // a_load_done_flag不在这里清除，而是在进入下一阶段时清除

            case (state)
                `NPU_ST_IDLE: begin
                    global_busy <= 1'b0;
                    pool_tile_start_mask  <= {`NPU_NUM_TILES{1'b0}};
                    pool_tile_clk_en_mask <= {`NPU_NUM_TILES{1'b0}};
                    pool_mode             <= cfg_mode;
                    a_load_done_flag      <= 1'b0;  // 确保在IDLE状态清除
                    
                    if (cfg_start_pulse) begin
                        // 启动时把 CPU 配置锁存下来，后续流程完全由状态机推进。
                        pool_mode             <= cfg_mode;
                        
                        // 根据cfg_tile_mask配置启用的Tile
                        // cfg_tile_mask_lo[4:0]对应Tile#0-4, cfg_tile_mask_hi[9:5]对应Tile#5-9
                        // 对于32个Tile，需要扩展掩码
                        pool_tile_clk_en_mask <= {`NPU_NUM_TILES{1'b1}};  // 所有Tile时钟使能
                        
                        // 注意：tile_start_mask不在这里设置，而是在进入RUN状态时产生一个周期脉冲
                        pool_tile_start_mask  <= {`NPU_NUM_TILES{1'b0}};  // 初始为0
                        
                        rd_base_addr          <= cfg_a_base;
                        wr_base_addr          <= cfg_c_base;
                        
                        // 判断B矩阵是否为静态权重（通过cfg_b_static信号控制）
                        // cfg_b_static=0: 动态权重，需要重新加载
                        // cfg_b_static=1: 静态权重，使用缓存值，跳过DMA读取
                        b_matrix_static       <= cfg_b_static;
                        
                        // 判断B矩阵是否为独立权重（通过cfg_b_independent信号控制）
                        // cfg_b_independent=0: 权重共享，所有Tile使用相同B矩阵
                        // cfg_b_independent=1: 独立权重，每个Tile使用不同B矩阵
                        b_weight_independent  <= cfg_b_independent;
                        
                        // A 矩阵总是需要读取（激活数据每次都变）
                        rd_word_count <= calc_rd_word_count(
                            cfg_mode, 
                            cfg_matrix_m, 
                            cfg_matrix_n, 
                            cfg_matrix_k,
                            {cfg_tile_mask_hi, cfg_tile_mask_lo}  // 传入完整的 32 位 tile_mask
                        );
                        
                        // C 矩阵写回字数（结果矩阵）
                        wr_word_count         <= calc_c_wr_word_count(cfg_mode, cfg_matrix_m, cfg_matrix_n);
                        
                        // 保存Tile启动掩码，供RUN状态使用
                        tile_start_mask_value <= {{(`NPU_NUM_TILES-10){1'b0}}, cfg_tile_mask_hi, cfg_tile_mask_lo};
                        run_start_delay       <= 2'd0;
                        
                        state                 <= `NPU_ST_CFG;
                        global_busy           <= 1'b1;
                    end
                end

                `NPU_ST_CFG: begin
                    // CFG阶段：只配置参数，不写入权重缓存
                    // 权重缓存在LOAD阶段通过DMA加载
                    
                    // 注意：原代码在这里写入全零到缓存，这是错误的
                    // 已移除该逻辑，避免覆盖静态模式下的有效权重数据
                    
                    state <= `NPU_ST_LOAD;
                end

                `NPU_ST_LOAD: begin
                    // LOAD阶段分为两个子阶段：
                    // 1. 加载A矩阵（激活数据）- 总是执行
                    // 2. 加载B矩阵（权重数据）- 仅在动态模式下执行
                    
                    if (!a_load_done_flag) begin
                        // 第一阶段：加载A矩阵
                        if (!rd_busy) begin
                            rd_start <= 1'b1;  // 启动DMA读取A矩阵
                        end
                        if (rd_done) begin
                            a_load_done_flag <= 1'b1;
                        end
                    end else if (!b_matrix_static) begin
                        // 第二阶段：加载B矩阵（仅动态模式）
                        // 切换到B矩阵基地址和字数
                        if (!rd_busy) begin
                            rd_base_addr <= cfg_b_base;
                            rd_word_count <= calc_b_rd_word_count(cfg_matrix_k, cfg_matrix_n, b_matrix_static, b_weight_independent);
                            rd_start <= 1'b1;  // 启动DMA读取B矩阵
                        end
                        if (rd_done) begin
                            // B矩阵加载完成，进入RUN阶段
                            run_start_delay <= 2'd2;
                            state <= `NPU_ST_RUN;
                        end
                    end else begin
                        // 静态模式：A矩阵加载完成后直接进入RUN阶段
                        a_load_done_flag <= 1'b0;  // 清除标志，为下次计算做准备
                        run_start_delay <= 2'd2;
                        state <= `NPU_ST_RUN;
                    end
                end

                `NPU_ST_RUN: begin
                    // 等待B矩阵广播稳定后，再触发Tile开始计算
                    if (run_start_delay != 2'd0) begin
                        run_start_delay <= run_start_delay - 1'b1;
                        pool_tile_start_mask <= {`NPU_NUM_TILES{1'b0}};
                    end else if (!tile_start_mask_sent) begin
                        pool_tile_start_mask <= tile_start_mask_value;  // 周期1：设置start
                        tile_start_mask_sent <= 1'b1;
                    end else if (pool_done) begin
                        pool_tile_start_mask <= {`NPU_NUM_TILES{1'b0}};  // 计算完成，清除start
                        tile_start_mask_sent <= 1'b0;
                        state <= `NPU_ST_STORE;
                    end
                end

                `NPU_ST_STORE: begin
                    // STORE阶段：将C矩阵结果写回外部存储器
                    if (!wr_busy) begin
                        wr_start <= 1'b1;  // 启动DMA写
                    end
                    
                    // 等待DMA写完成
                    if (wr_done) begin
                        wr_start <= 1'b0;
                        state <= `NPU_ST_DONE;
                    end
                end

                `NPU_ST_DONE: begin
                    global_busy  <= 1'b0;
                    global_done  <= 1'b1;
                    pool_tile_start_mask <= {`NPU_NUM_TILES{1'b0}};
                    state <= `NPU_ST_IDLE;
                end

                default: begin
                    global_error <= 1'b1;
                    state <= `NPU_ST_ERROR;
                end
            endcase

            global_state <= state;
        end
    end

endmodule