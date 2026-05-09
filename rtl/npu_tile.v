`include "npu_defs.vh"

// ============================================================
// npu_tile - 单个 8×8 矩阵乘法计算单元（标准FSM三分法重构）
// INT8 输入，INT32 累加，串行加载 A/B，并行输出 C
// 
// FSM设计原则：
// 1. 时序逻辑块：状态寄存器更新
// 2. 组合逻辑块（下一状态）：计算next_state
// 3. 组合逻辑块（输出）：控制信号和数据输出
// ============================================================
module npu_tile #(
    parameter K_MAX = `NPU_K_MAX
)(
    input  wire        clk,
    input  wire        rst_n,
    // 配置
    input  wire [5:0]  cfg_k,
    input  wire        tile_en,
    // A 矩阵串行输入（8bit/周期）
    input  wire [7:0]  a_data,
    input  wire        a_valid,
    output wire        a_ready,
    // B 矩阵串行输入（8bit/周期）
    input  wire [7:0]  b_data,
    input  wire        b_valid,
    output wire        b_ready,
    // C 结果并行输出（8×32bit = 256bit）
    output wire [255:0] c_data,
    output reg         c_valid,
    input  wire        c_ready,
    // 状态
    output reg         compute_done
);

    // ========================================================
    //  本地 Buffer（时序逻辑块1：本地存储器）
    // ========================================================
    reg [7:0]  a_local [0:8*K_MAX-1];   // 8×K
    reg [7:0]  b_local [0:K_MAX*8-1];   // K×8
    reg [31:0] c_local [0:63];           // 8×8 INT32

    // ========================================================
    //  状态机寄存器（时序逻辑块2：状态寄存器）
    // ========================================================
    reg [2:0]  state;
    reg [8:0]  load_cnt;                 // 加载计数 (0 ~ 8K-1)
    reg [5:0]  k_cnt;                    // K 迭代计数

    // ---- 状态寄存器更新（时序）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= `TILE_IDLE;
            load_cnt <= 9'd0;
            k_cnt    <= 6'd0;
        end else begin
            state    <= next_state;
            load_cnt <= load_cnt_next;
            k_cnt    <= k_cnt_next;
        end
    end

    // ========================================================
    //  下一状态逻辑（组合逻辑块1：状态转移）
    // ========================================================
    wire [2:0] next_state;
    wire [8:0] load_cnt_next;
    wire [5:0] k_cnt_next;
    
    wire [8:0] load_target = {cfg_k, 3'b000};  // 8 * cfg_k

    always @(*) begin
        // 默认值
        next_state    = state;
        load_cnt_next = load_cnt;
        k_cnt_next    = k_cnt;

        case (state)
            // ---- TILE_IDLE: 空闲 ----
            `TILE_IDLE: begin
                if (tile_en && a_valid && b_valid) begin
                    next_state    = `TILE_LOAD;
                    load_cnt_next = 9'd0;
                end
            end

            // ---- TILE_LOAD: 加载 A/B 数据 ----
            `TILE_LOAD: begin
                if (a_valid && b_valid) begin
                    load_cnt_next = load_cnt + 9'd1;
                    if (load_cnt + 9'd1 >= load_target) begin
                        next_state = `TILE_COMPUTE;
                        k_cnt_next = 6'd0;
                    end
                end
            end

            // ---- TILE_COMPUTE: 计算（K 个周期）----
            `TILE_COMPUTE: begin
                k_cnt_next = k_cnt + 6'd1;
                if (k_cnt + 6'd1 >= cfg_k) begin
                    next_state = `TILE_DONE;
                end
            end

            // ---- TILE_DONE: 完成，输出结果 ----
            `TILE_DONE: begin
                if (c_ready) begin
                    next_state = `TILE_IDLE;
                end
            end

            default: next_state = `TILE_IDLE;
        endcase
    end

    // ========================================================
    //  输出逻辑（组合逻辑块2：输出控制）
    // ========================================================
    wire tile_a_ready;
    wire tile_b_ready;

    always @(*) begin
        // 默认值
        tile_a_ready = 1'b0;
        tile_b_ready = 1'b0;

        case (state)
            // ---- TILE_IDLE: 空闲 ----
            `TILE_IDLE: begin
                if (tile_en && a_valid && b_valid) begin
                    tile_a_ready = 1'b1;
                    tile_b_ready = 1'b1;
                end
            end

            // ---- TILE_LOAD: 加载数据 ----
            `TILE_LOAD: begin
                if (a_valid && b_valid) begin
                    tile_a_ready = 1'b1;
                    tile_b_ready = 1'b1;
                end
            end

            // ---- TILE_COMPUTE: 计算 ----
            `TILE_COMPUTE: begin
                // 无特殊输出
            end

            // ---- TILE_DONE: 完成 ----
            `TILE_DONE: begin
                // 输出信号由时序逻辑块控制
            end

            default: ;
        endcase
    end

    // ---- 输出信号赋值 ----
    assign a_ready = tile_a_ready;
    assign b_ready = tile_b_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compute_done <= 1'b0;
            c_valid      <= 1'b0;
        end else begin
            compute_done <= (state == `TILE_DONE);
            c_valid      <= (state == `TILE_DONE);
        end
    end

    // ========================================================
    //  MAC 阵列计算（时序逻辑块3：累加器阵列）
    //  C[i][j] += A[i][k] * B[k][j]
    //  每个 k 周期，所有 64 个 MAC 并行计算
    // ========================================================
    integer i, j;

    // 乘法操作数（组合逻辑）
    wire signed [7:0]  a_val [0:7];
    wire signed [7:0]  b_val [0:7];
    wire signed [15:0] prod [0:7][0:7];

    genvar gi, gj;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : gen_a
            assign a_val[gi] = a_local[gi * K_MAX + k_cnt];
        end
        for (gj = 0; gj < 8; gj = gj + 1) begin : gen_b
            assign b_val[gj] = b_local[k_cnt * 8 + gj];
        end
        for (gi = 0; gi < 8; gi = gi + 1) begin : gen_prod_row
            for (gj = 0; gj < 8; gj = gj + 1) begin : gen_prod_col
                assign prod[gi][gj] = a_val[gi] * b_val[gj];
            end
        end
    endgenerate

    // 累加逻辑（时序）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 64; i = i + 1)
                c_local[i] <= 32'd0;
        end else begin
            if (state == `TILE_IDLE && tile_en && a_valid && b_valid) begin
                for (i = 0; i < 64; i = i + 1)
                    c_local[i] <= 32'd0;
            end else if (state == `TILE_COMPUTE) begin
                for (i = 0; i < 8; i = i + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        c_local[i*8+j] <= c_local[i*8+j] +
                                           {{16{prod[i][j][15]}}, prod[i][j]};
                    end
                end
            end
        end
    end

    // ========================================================
    //  C 输出组装（组合逻辑块3：数据组装）
    //  256bit 并行输出
    // ========================================================
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : gen_c_row
            for (gj = 0; gj < 8; gj = gj + 1) begin : gen_c_col
                assign c_data[(gi*8+gj)*32 +: 32] = c_local[gi*8+gj];
            end
        end
    endgenerate

endmodule