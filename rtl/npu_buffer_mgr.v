`include "npu_defs.vh"

// ============================================================
// npu_buffer_mgr - 数据缓存管理模块（标准FSM三分法重构）
// 管理 A/B/C 三个数据 Buffer，支持 AXI 端口和数据搬运模块双端口访问
// 
// FSM设计原则：
// 1. 时序逻辑块：BRAM读写操作
// 2. 组合逻辑块：地址解码和使能信号
// 3. 组合逻辑块：读有效信号生成
// ============================================================
module npu_buffer_mgr #(
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH,
    parameter DATA_WIDTH = `NPU_AXI_DATA_WIDTH
)(
    input  wire                    clk,
    input  wire                    rst_n,
    // ---- 端口 A：AXI 接口访问 ----
    input  wire                    axi_wr_en,
    input  wire [ADDR_WIDTH-1:0]   axi_wr_addr,
    input  wire [DATA_WIDTH-1:0]   axi_wr_data,
    input  wire [3:0]              axi_wr_strb,
    input  wire                    axi_rd_en,
    input  wire [ADDR_WIDTH-1:0]   axi_rd_addr,
    output reg  [DATA_WIDTH-1:0]   axi_rd_data,
    output reg                     axi_rd_valid,
    // ---- 端口 B：数据搬运模块访问 ----
    input  wire                    mover_rd_en,
    input  wire [ADDR_WIDTH-1:0]   mover_rd_addr,
    output reg  [DATA_WIDTH-1:0]   mover_rd_data,
    output reg                     mover_rd_valid,
    input  wire                    mover_wr_en,
    input  wire [ADDR_WIDTH-1:0]   mover_wr_addr,
    input  wire [DATA_WIDTH-1:0]   mover_wr_data,
    input  wire [3:0]              mover_wr_strb
);

    // ========================================================
    //  BRAM 实例化（时序逻辑块1：存储器阵列）
    // ========================================================
    // A Buffer: 16KB = 4096 x 32bit
    reg [31:0] a_buf [0:`NPU_A_BUF_DEPTH-1];
    // B Buffer: 16KB = 4096 x 32bit
    reg [31:0] b_buf [0:`NPU_B_BUF_DEPTH-1];
    // C Buffer: 8KB = 2048 x 32bit
    reg [31:0] c_buf [0:`NPU_C_BUF_DEPTH-1];

    // ========================================================
    //  地址解码逻辑（组合逻辑块1：地址解码）
    // ========================================================
    // 端口 A（AXI）写地址解码
    wire axi_wr_is_a;
    wire axi_wr_is_b;
    wire axi_wr_is_c;
    
    assign axi_wr_is_a = (axi_wr_addr >= `NPU_A_BUFFER_BASE) &&
                         (axi_wr_addr <  `NPU_A_BUFFER_BASE + `NPU_A_BUFFER_SIZE);
    assign axi_wr_is_b = (axi_wr_addr >= `NPU_B_BUFFER_BASE) &&
                         (axi_wr_addr <  `NPU_B_BUFFER_BASE + `NPU_B_BUFFER_SIZE);
    assign axi_wr_is_c = (axi_wr_addr >= `NPU_C_BUFFER_BASE) &&
                         (axi_wr_addr <  `NPU_C_BUFFER_BASE + `NPU_C_BUFFER_SIZE);

    // 端口 A（AXI）读地址解码
    wire axi_rd_is_a;
    wire axi_rd_is_b;
    wire axi_rd_is_c;
    
    assign axi_rd_is_a = (axi_rd_addr >= `NPU_A_BUFFER_BASE) &&
                         (axi_rd_addr <  `NPU_A_BUFFER_BASE + `NPU_A_BUFFER_SIZE);
    assign axi_rd_is_b = (axi_rd_addr >= `NPU_B_BUFFER_BASE) &&
                         (axi_rd_addr <  `NPU_B_BUFFER_BASE + `NPU_B_BUFFER_SIZE);
    assign axi_rd_is_c = (axi_rd_addr >= `NPU_C_BUFFER_BASE) &&
                         (axi_rd_addr <  `NPU_C_BUFFER_BASE + `NPU_C_BUFFER_SIZE);

    // 端口 B（Mover）读地址解码
    wire mover_rd_is_a;
    wire mover_rd_is_b;
    wire mover_rd_is_c;
    
    assign mover_rd_is_a = (mover_rd_addr >= `NPU_A_BUFFER_BASE) &&
                           (mover_rd_addr <  `NPU_A_BUFFER_BASE + `NPU_A_BUFFER_SIZE);
    assign mover_rd_is_b = (mover_rd_addr >= `NPU_B_BUFFER_BASE) &&
                           (mover_rd_addr <  `NPU_B_BUFFER_BASE + `NPU_B_BUFFER_SIZE);
    assign mover_rd_is_c = (mover_rd_addr >= `NPU_C_BUFFER_BASE) &&
                           (mover_rd_addr <  `NPU_C_BUFFER_BASE + `NPU_C_BUFFER_SIZE);

    // 端口 B（Mover）写地址解码
    wire mover_wr_is_c;
    
    assign mover_wr_is_c = (mover_wr_addr >= `NPU_C_BUFFER_BASE) &&
                           (mover_wr_addr <  `NPU_C_BUFFER_BASE + `NPU_C_BUFFER_SIZE);

    // ========================================================
    //  内部地址计算（组合逻辑块2：地址转换）
    // ========================================================
    // 端口 A 写地址
    wire [11:0] axi_wr_word_a = axi_wr_addr[13:2];  // A: 16KB -> 12bit word addr
    wire [11:0] axi_wr_word_b = axi_wr_addr[13:2];  // B: 16KB -> 12bit word addr
    wire [10:0] axi_wr_word_c = axi_wr_addr[12:2];  // C: 8KB  -> 11bit word addr

    // 端口 A 读地址
    wire [11:0] axi_rd_word_a = axi_rd_addr[13:2];
    wire [11:0] axi_rd_word_b = axi_rd_addr[13:2];
    wire [10:0] axi_rd_word_c = axi_rd_addr[12:2];

    // 端口 B 读地址
    wire [11:0] mover_rd_word_a = mover_rd_addr[13:2];
    wire [11:0] mover_rd_word_b = mover_rd_addr[13:2];
    wire [10:0] mover_rd_word_c = mover_rd_addr[12:2];

    // 端口 B 写地址
    wire [10:0] mover_wr_word_c = mover_wr_addr[12:2];

    // ========================================================
    //  A Buffer 读写（时序逻辑块2：A Buffer操作）
    // ========================================================
    wire a_wr;
    
    assign a_wr = axi_wr_en && axi_wr_is_a;

    always @(posedge clk) begin
        // 端口 A 写
        if (a_wr) begin
            if (axi_wr_strb[0]) a_buf[axi_wr_word_a][ 7: 0] <= axi_wr_data[ 7: 0];
            if (axi_wr_strb[1]) a_buf[axi_wr_word_a][15: 8] <= axi_wr_data[15: 8];
            if (axi_wr_strb[2]) a_buf[axi_wr_word_a][23:16] <= axi_wr_data[23:16];
            if (axi_wr_strb[3]) a_buf[axi_wr_word_a][31:24] <= axi_wr_data[31:24];
        end
        // 端口 A 读
        if (axi_rd_en && axi_rd_is_a)
            axi_rd_data <= a_buf[axi_rd_word_a];
        // 端口 B 读（mover 只读 A）
        if (mover_rd_en && mover_rd_is_a)
            mover_rd_data <= a_buf[mover_rd_word_a];
    end

    // ========================================================
    //  B Buffer 读写（时序逻辑块3：B Buffer操作）
    // ========================================================
    wire b_wr;
    
    assign b_wr = axi_wr_en && axi_wr_is_b;

    always @(posedge clk) begin
        if (b_wr) begin
            if (axi_wr_strb[0]) b_buf[axi_wr_word_b][ 7: 0] <= axi_wr_data[ 7: 0];
            if (axi_wr_strb[1]) b_buf[axi_wr_word_b][15: 8] <= axi_wr_data[15: 8];
            if (axi_wr_strb[2]) b_buf[axi_wr_word_b][23:16] <= axi_wr_data[23:16];
            if (axi_wr_strb[3]) b_buf[axi_wr_word_b][31:24] <= axi_wr_data[31:24];
        end
        if (axi_rd_en && axi_rd_is_b)
            axi_rd_data <= b_buf[axi_rd_word_b];
        if (mover_rd_en && mover_rd_is_b)
            mover_rd_data <= b_buf[mover_rd_word_b];
    end

    // ========================================================
    //  C Buffer 读写（时序逻辑块4：C Buffer操作）
    // ========================================================
    wire c_wr_axi;
    wire c_wr_mover;
    
    assign c_wr_axi  = axi_wr_en  && axi_wr_is_c;
    assign c_wr_mover = mover_wr_en && mover_wr_is_c;

    always @(posedge clk) begin
        // AXI 写（优先级高）
        if (c_wr_axi) begin
            if (axi_wr_strb[0]) c_buf[axi_wr_word_c][ 7: 0] <= axi_wr_data[ 7: 0];
            if (axi_wr_strb[1]) c_buf[axi_wr_word_c][15: 8] <= axi_wr_data[15: 8];
            if (axi_wr_strb[2]) c_buf[axi_wr_word_c][23:16] <= axi_wr_data[23:16];
            if (axi_wr_strb[3]) c_buf[axi_wr_word_c][31:24] <= axi_wr_data[31:24];
        end
        // Mover 写（AXI 优先，同周期 AXI 写时 mover 写被忽略）
        if (c_wr_mover && !c_wr_axi) begin
            if (mover_wr_strb[0]) c_buf[mover_wr_word_c][ 7: 0] <= mover_wr_data[ 7: 0];
            if (mover_wr_strb[1]) c_buf[mover_wr_word_c][15: 8] <= mover_wr_data[15: 8];
            if (mover_wr_strb[2]) c_buf[mover_wr_word_c][23:16] <= mover_wr_data[23:16];
            if (mover_wr_strb[3]) c_buf[mover_wr_word_c][31:24] <= mover_wr_data[31:24];
        end
        // 读
        if (axi_rd_en && axi_rd_is_c)
            axi_rd_data <= c_buf[axi_rd_word_c];
        if (mover_rd_en && mover_rd_is_c)
            mover_rd_data <= c_buf[mover_rd_word_c];
    end

    // ========================================================
    //  读有效信号（时序逻辑块5：读有效标志）
    //  延迟一拍匹配 BRAM 输出
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_rd_valid   <= 1'b0;
            mover_rd_valid <= 1'b0;
        end else begin
            axi_rd_valid   <= axi_rd_en;
            mover_rd_valid <= mover_rd_en;
        end
    end

endmodule