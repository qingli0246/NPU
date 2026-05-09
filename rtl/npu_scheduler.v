`include "npu_defs.vh"

// ============================================================
// npu_scheduler - 计算调度模块（标准FSM三分法重构）
// 控制 LOAD → COMPUTE → STORE 流水线，支持多次迭代
// 
// FSM设计原则：
// 1. 时序逻辑块：状态寄存器和迭代计数器
// 2. 组合逻辑块（下一状态）：计算next_state
// 3. 组合逻辑块（输出）：控制信号和状态输出
// ============================================================
module npu_scheduler (
    input  wire        clk,
    input  wire        rst_n,
    // 配置输入
    input  wire [1:0]  cfg_mode,
    input  wire [5:0]  cfg_m,
    input  wire [5:0]  cfg_n,
    input  wire [5:0]  cfg_k,
    input  wire [3:0]  cfg_iterations,
    input  wire        cfg_start,
    // 控制输出
    output reg         load_start,
    output reg         compute_start,
    output reg         store_start,
    // 状态输入
    input  wire        load_done,
    input  wire        compute_done,
    input  wire        store_done,
    // 状态输出
    output reg         npu_done,
    output reg         npu_error,
    output reg  [3:0]  npu_state,
    output reg         computing
);

    // ========================================================
    //  内部信号定义
    // ========================================================
    reg [3:0] iter_cnt;
    reg [3:0] next_state;
    reg [3:0] iter_cnt_next;

    // 组合逻辑输出信号
    wire comb_load_start;
    wire comb_compute_start;
    wire comb_store_start;
    wire comb_npu_done;
    wire comb_npu_error;
    wire comb_computing;

    // ========================================================
    //  1. 时序逻辑块：状态寄存器和迭代计数器
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            npu_state <= `NPU_ST_IDLE;
            iter_cnt  <= 4'd0;
        end else begin
            npu_state <= next_state;
            iter_cnt  <= iter_cnt_next;
        end
    end

    // ========================================================
    //  2. 组合逻辑块：下一状态逻辑
    // ========================================================
    always @(*) begin
        // 默认值保持
        next_state    = npu_state;
        iter_cnt_next = iter_cnt;

        case (npu_state)
            `NPU_ST_IDLE: begin
                if (cfg_start) begin
                    next_state    = `NPU_ST_LOAD;
                    iter_cnt_next = 4'd0;
                end
            end

            `NPU_ST_LOAD: begin
                if (load_done) begin
                    next_state = `NPU_ST_RUN;
                end
            end

            `NPU_ST_RUN: begin
                if (compute_done) begin
                    next_state = `NPU_ST_STORE;
                end
            end

            `NPU_ST_STORE: begin
                if (store_done) begin
                    if (iter_cnt + 1 < cfg_iterations) begin
                        next_state    = `NPU_ST_LOAD;
                        iter_cnt_next = iter_cnt + 4'd1;
                    end else begin
                        next_state = `NPU_ST_DONE;
                    end
                end
            end

            `NPU_ST_DONE: begin
                if (cfg_start) begin
                    next_state    = `NPU_ST_LOAD;
                    iter_cnt_next = 4'd0;
                end
            end

            `NPU_ST_ERROR: begin
                next_state = `NPU_ST_ERROR;
            end

            default: next_state = `NPU_ST_IDLE;
        endcase
    end

    // ========================================================
    //  3. 组合逻辑块：输出逻辑
    // ========================================================
    always @(*) begin
        // 默认输出
        comb_load_start    = 1'b0;
        comb_compute_start = 1'b0;
        comb_store_start   = 1'b0;
        comb_npu_done      = 1'b0;
        comb_npu_error     = 1'b0;
        comb_computing     = 1'b0;

        // ---- computing 信号 ----
        if (npu_state == `NPU_ST_LOAD || npu_state == `NPU_ST_RUN || npu_state == `NPU_ST_STORE) begin
            comb_computing = 1'b1;
        end
        if ((npu_state == `NPU_ST_IDLE || npu_state == `NPU_ST_DONE) && cfg_start) begin
            comb_computing = 1'b1;
        end

        // ---- load_start 脉冲 ----
        if (npu_state == `NPU_ST_IDLE && cfg_start) begin
            comb_load_start = 1'b1;
        end
        if (npu_state == `NPU_ST_STORE && store_done && (iter_cnt + 1 < cfg_iterations)) begin
            comb_load_start = 1'b1;
        end
        if (npu_state == `NPU_ST_DONE && cfg_start) begin
            comb_load_start = 1'b1;
        end

        // ---- compute_start 脉冲 ----
        if (npu_state == `NPU_ST_LOAD && load_done) begin
            comb_compute_start = 1'b1;
        end

        // ---- store_start 脉冲 ----
        if (npu_state == `NPU_ST_RUN && compute_done) begin
            comb_store_start = 1'b1;
        end

        // ---- npu_done 信号（电平锁存）----
        if (npu_state == `NPU_ST_DONE) begin
            comb_npu_done = 1'b1;
        end
        if (npu_state == `NPU_ST_STORE && store_done && !(iter_cnt + 1 < cfg_iterations)) begin
            comb_npu_done = 1'b1;
        end

        // ---- npu_error 信号（电平锁存）----
        if (npu_state == `NPU_ST_ERROR) begin
            comb_npu_error = 1'b1;
        end
    end

    // ========================================================
    //  4. 输出寄存器（同步输出）
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_start    <= 1'b0;
            compute_start <= 1'b0;
            store_start   <= 1'b0;
            npu_done      <= 1'b0;
            npu_error     <= 1'b0;
            computing     <= 1'b0;
        end else begin
            load_start    <= comb_load_start;
            compute_start <= comb_compute_start;
            store_start   <= comb_store_start;
            npu_done      <= comb_npu_done;
            npu_error     <= comb_npu_error;
            computing     <= comb_computing;
        end
    end

endmodule