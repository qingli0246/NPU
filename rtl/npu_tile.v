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
    // C 结果并行输出（8×8×32bit = 2048bit）
    output wire [2047:0] c_data,
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
    //  调试用循环变量（模块级别声明）
    // ========================================================
    integer debug_i, debug_j;

    // ========================================================
    //  状态机寄存器（时序逻辑块2：状态寄存器）
    // ========================================================
    reg [2:0]  state;
    reg [8:0]  load_cnt;                 // 通用加载计数 (0 ~ 8K-1) - 保留以兼容部分逻辑或未来扩展，主要使用专用计数器
    reg [5:0]  k_cnt;                    // K 迭代计数
    
    // [NEW] 异步加载标志和计数器
    reg        a_loaded;                 // A数据加载完成标志
    reg        b_loaded;                 // B数据加载完成标志
    reg [8:0]  a_load_cnt;               // A数据加载计数器
    reg [8:0]  b_load_cnt;               // B数据加载计数器
    reg        c_result_printed;         // C矩阵结果已打印标志（防止重复打印）
    reg        a_printed;                // A矩阵已打印标志
    reg        b_printed;                // B矩阵已打印标志

    // ---- 状态寄存器更新（时序）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= `TILE_IDLE;
            load_cnt        <= 9'd0;
            k_cnt           <= 6'd0;
            a_loaded        <= 1'b0;
            b_loaded        <= 1'b0;
            a_load_cnt      <= 9'd0;
            b_load_cnt      <= 9'd0;
            c_result_printed<= 1'b0;
            a_printed       <= 1'b0;
            b_printed       <= 1'b0;
        end else begin
            state      <= next_state;
            load_cnt   <= load_cnt_next;
            k_cnt      <= k_cnt_next;
            a_loaded   <= a_loaded_next;
            b_loaded   <= b_loaded_next;
            a_load_cnt <= a_load_cnt_next;
            b_load_cnt <= b_load_cnt_next;

            // [DEBUG] 状态转换监控
            if (state != next_state) begin
                $display("[TILE DBG] t=%0t state: %d -> %d, a_loaded=%b, b_loaded=%b", 
                         $time, state, next_state, a_loaded_next, b_loaded_next);
            end
        end
    end

    // ========================================================
    //  下一状态逻辑（组合逻辑块1：状态转移）
    // ========================================================
    reg [2:0] next_state;
    reg [8:0] load_cnt_next;
    reg [5:0] k_cnt_next;
    
    // [NEW] 异步加载的下一状态信号
    reg       a_loaded_next;
    reg       b_loaded_next;
    reg [8:0] a_load_cnt_next;
    reg [8:0] b_load_cnt_next;
    
    wire [8:0] load_target = {cfg_k, 3'b000};  // 8 * cfg_k

    always @(*) begin
        // 默认值
        next_state      = state;
        load_cnt_next   = load_cnt;
        k_cnt_next      = k_cnt;
        a_loaded_next   = a_loaded;
        b_loaded_next   = b_loaded;
        a_load_cnt_next = a_load_cnt;
        b_load_cnt_next = b_load_cnt;

        case (state)
            // ---- TILE_IDLE: 空闲 ----
            `TILE_IDLE: begin
                if (!tile_en) begin
                    // Data Mover 不活跃时，清除残留加载标志
                    // 防止 tile_en 恢复后 a_loaded/b_loaded=1 直接跳到 COMPUTE
                    a_loaded_next = 1'b0;
                    b_loaded_next = 1'b0;
                    c_result_printed = 1'b0;  // 清除C矩阵打印标志
                    a_printed = 1'b0;          // 清除A矩阵打印标志
                    b_printed = 1'b0;          // 清除B矩阵打印标志
                end else if (tile_en) begin
                    if (!a_loaded) begin
                        next_state = `TILE_LOAD_A;
                        a_load_cnt_next = 9'd0;
                    end else if (!b_loaded) begin
                        next_state = `TILE_LOAD_B;
                        b_load_cnt_next = 9'd0;
                    end else begin
                        next_state = `TILE_COMPUTE;
                        k_cnt_next = 6'd0;
                    end
                end
            end

            // ---- TILE_LOAD_A: 加载 A 数据 ----
            `TILE_LOAD_A: begin
                if (a_valid) begin
                    a_load_cnt_next = a_load_cnt + 9'd1;
                    
                    if (a_load_cnt + 9'd1 >= load_target) begin
                        // [NEW] A数据加载完成
                        a_loaded_next = 1'b1;
                        next_state = `TILE_IDLE;  // 返回IDLE，等待B数据或下一步
                    end
                end
            end

            // ---- TILE_LOAD_B: 加载 B 数据 ----
            `TILE_LOAD_B: begin
                if (b_valid) begin
                    b_load_cnt_next = b_load_cnt + 9'd1;
                    if (b_load_cnt + 9'd1 >= load_target) begin
                        // [NEW] B数据加载完成
                        b_loaded_next = 1'b1;
                        next_state = `TILE_COMPUTE;  // B也加载完，开始计算
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
            // tile_en=0 表示 Data Mover 已完成 store（S_DONE）
            // 此时 c_local 数据已全部读取，可以安全清除加载标志
            `TILE_DONE: begin
                if (!tile_en) begin
                    next_state = `TILE_IDLE;
                    a_loaded_next = 1'b0;
                    b_loaded_next = 1'b0;
                end
            end

            // ---- TILE_IDLE: 空闲，清除残留加载标志 ----
            // 当 tile_en=0 时（Data Mover 不活跃），确保加载标志为0
            // 防止 tile_en 恢复后直接跳到 COMPUTE 而不重新 LOAD
            `TILE_IDLE: begin
                if (!tile_en) begin
                    a_loaded_next = 1'b0;
                    b_loaded_next = 1'b0;
                end
            end

            default: next_state = `TILE_IDLE;
        endcase
    end

    // ========================================================
    //  输出逻辑（组合逻辑块2：输出控制）
    // ========================================================
    reg tile_a_ready;
    reg tile_b_ready;

    always @(*) begin
        // 默认值
        tile_a_ready = 1'b0;
        tile_b_ready = 1'b0;

        case (state)
            // ---- TILE_IDLE: 空闲 ----
            `TILE_IDLE: begin
                if (tile_en && !a_loaded) begin
                    // [NEW] 准备接收A数据
                    tile_a_ready = 1'b1;
                end else if (tile_en && a_loaded && !b_loaded) begin
                    // [NEW] 准备接收B数据
                    tile_b_ready = 1'b1;
                end
            end

            // ---- TILE_LOAD_A: 加载A数据 ----
            `TILE_LOAD_A: begin
                // Tile在LOAD_A状态下始终准备好接收A数据
                tile_a_ready = 1'b1;
            end

            // ---- TILE_LOAD_B: 加载B数据 ----
            `TILE_LOAD_B: begin
                // Tile在LOAD_B状态下始终准备好接收B数据
                tile_b_ready = 1'b1;
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
            // [FIX] 使用实际的cfg_k而不是K_MAX来计算索引
            // A矩阵按行优先存储：a_local[i*cfg_k + k]
            assign a_val[gi] = a_local[gi * cfg_k + k_cnt];
        end
        for (gj = 0; gj < 8; gj = gj + 1) begin : gen_b
            // B矩阵按行优先存储：b_local[k*8 + j]
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
            // [NEW] 在LOAD_A阶段存储A数据
            if (state == `TILE_LOAD_A && a_valid) begin
                // 根据a_load_cnt计算存储位置：按行优先存储
                // a_local[i*K_MAX + k] = a_data
                // byte_idx = a_load_cnt, row = byte_idx / K_MAX, col_k = byte_idx % K_MAX
                a_local[a_load_cnt] <= a_data;
            end
            
            // [NEW] 在LOAD_B阶段存储B数据
            if (state == `TILE_LOAD_B && b_valid) begin
                // 根据b_load_cnt计算存储位置：按列优先存储
                // b_local[k*8 + j] = b_data
                // byte_idx = b_load_cnt, col_k = byte_idx / 8, row_j = byte_idx % 8
                b_local[b_load_cnt] <= b_data;
                
                // [DEBUG] B数据存储监控 - 打印前8个和最后8个字节
                if (b_load_cnt < 9'd8 || b_load_cnt >= 9'd56) begin
                    $display("[TILE LOAD_B DBG] t=%0t storing b_local[%d]=%d (0x%02X)", 
                             $time, b_load_cnt, $signed(b_data), b_data);
                end
            end
            
            // [DEBUG] 加载完成后打印完整的A/B矩阵（仅在第一个使能的Tile中打印）
            if (tile_en && ((state == `TILE_IDLE || state == `TILE_COMPUTE) && a_loaded && !a_printed)) begin
                integer ai, aj;
                $display("\n[TILE 0] ===== A Matrix Loaded (8×8 INT8) =====");
                for (ai = 0; ai < 8; ai = ai + 1) begin
                    $write("  A[%d] = [", ai);
                    for (aj = 0; aj < 8; aj = aj + 1) begin
                        if (aj > 0) $write(", ");
                        $write("%3d", $signed(a_local[ai*8+aj]));
                    end
                    $display("]");
                end
                $display("==========================================\n");
                a_printed = 1'b1;
            end
            
            if (tile_en && ((state == `TILE_COMPUTE) && b_loaded && !b_printed)) begin
                // B矩阵加载完成，打印完整矩阵
                integer bi, bj;
                $display("\n[TILE 0] ===== B Matrix Loaded (8×8 INT8) =====");
                for (bi = 0; bi < 8; bi = bi + 1) begin
                    $write("  B[%d] = [", bi);
                    for (bj = 0; bj < 8; bj = bj + 1) begin
                        if (bj > 0) $write(", ");
                        $write("%3d", $signed(b_local[bi*8+bj]));
                    end
                    $display("]");
                end
                $display("==========================================\n");
                b_printed = 1'b1;
            end
            
            // 初始化C矩阵：在LOAD_A状态的首个周期清零
            // 不能在IDLE清零，因为Data Mover此时可能还在读取上一轮的c_local结果
            // 只在a_load_cnt==0时清零（LOAD_A的第一个周期），避免重复清零
            if (state == `TILE_LOAD_A && a_load_cnt == 9'd0) begin
                for (i = 0; i < 64; i = i + 1)
                    c_local[i] <= 32'd0;
            end else if (state == `TILE_COMPUTE) begin
                // 累加逻辑：C[i][j] += A[i][k] * B[k][j]
                // 注意：Verilog时序逻辑中，所有非阻塞赋值并行执行，读取的都是旧值
                // 这正是MAC操作所需要的行为
                for (i = 0; i < 8; i = i + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        c_local[i*8+j] <= c_local[i*8+j] +
                                           {{16{prod[i][j][15]}}, prod[i][j]};
                    end
                end
            end else if (state == `TILE_DONE) begin
                // [DEBUG] 计算结果监控 - 输出完整的C矩阵（只打印一次，仅Tile 0）
                if (tile_en && !c_result_printed) begin
                    integer ci, cj;
                    $display("\n[TILE 0] ===== C Matrix Result (8×8 INT32) =====");
                    for (ci = 0; ci < 8; ci = ci + 1) begin
                        $write("  C[%d] = [", ci);
                        for (cj = 0; cj < 8; cj = cj + 1) begin
                            if (cj > 0) $write(", ");
                            $write("%6d", $signed(c_local[ci*8+cj]));
                        end
                        $display("]");
                    end
                    $display("==========================================\n");
                    c_result_printed <= 1'b1;
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