`include "npu_defs.vh"

// ============================================================
// npu_axi_master - AXI4 Master 接口模块（DMA 引擎）
// 将内部 DMA 请求转换为 AXI4 Full 协议事务，支持 INCR Burst
//
// 数据通路：
// - Load：外部 BRAM → AXI 读通道 → 内部 A/B Buffer
// - Store：内部 C Buffer → AXI 写通道 → 外部 BRAM
//
// FSM 设计原则（三分法）：
// 1. 时序逻辑块：状态寄存器和计数器更新
// 2. 组合逻辑块1：计算 next_state 和辅助信号
// 3. 组合逻辑块2：生成 AXI 输出和 Buffer 控制信号
// ============================================================
module npu_axi_master (
    input  wire                    clk,
    input  wire                    rst_n,

    // ---- AXI4 Master 接口（对外连接共享 BRAM） ----
    output reg  [31:0]             m_axi_awaddr,
    output reg  [7:0]              m_axi_awlen,
    output reg  [2:0]              m_axi_awsize,
    output reg  [1:0]              m_axi_awburst,
    output reg                     m_axi_awvalid,
    input  wire                    m_axi_awready,

    output reg  [31:0]             m_axi_wdata,
    output reg  [3:0]              m_axi_wstrb,
    output reg                     m_axi_wlast,
    output reg                     m_axi_wvalid,
    input  wire                    m_axi_wready,

    input  wire [1:0]              m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output reg                     m_axi_bready,
    output reg  [31:0]             m_axi_araddr,
    output reg  [7:0]              m_axi_arlen,
    output reg  [2:0]              m_axi_arsize,
    output reg  [1:0]              m_axi_arburst,
    output reg                     m_axi_arvalid,
    input  wire                    m_axi_arready,

    input  wire [31:0]             m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output reg                     m_axi_rready,

    // ---- DMA 请求接口（来自 npu_data_mover） ----
    input  wire                    dma_rd_req,        // 读请求脉冲（Load）
    input  wire [31:0]             dma_rd_addr,       // 外部 BRAM 读起始地址
    input  wire [7:0]              dma_rd_len,        // Burst 长度 - 1
    input  wire [15:0]             dma_buf_wr_addr,   // 内部 Buffer 写起始地址

    input  wire                    dma_wr_req,        // 写请求脉冲（Store）
    input  wire [31:0]             dma_wr_addr,       // 外部 BRAM 写起始地址
    input  wire [11:0]             dma_wr_total_len,        // Burst 长度 - 1
    input  wire [15:0]             dma_buf_rd_addr,   // 内部 C Buffer 读起始地址

    // ---- DMA 状态输出 ----
    output wire                    dma_rd_done,       // 读完成脉冲
    output wire                    dma_wr_done,       // 写完成脉冲

    // ---- 内部 Buffer 写端口（Load: AXI Master → A/B Buffer） ----
    output reg                     buf_wr_en,
    output reg  [15:0]             buf_wr_addr,
    output reg  [31:0]             buf_wr_data,
    output reg  [3:0]              buf_wr_strb,

    // ---- 内部 Buffer 读端口（Store: C Buffer → AXI Master） ----
    output reg                     buf_rd_en,
    output reg  [15:0]             buf_rd_addr,
    input  wire [31:0]             buf_rd_data
);

    // ========================================================
    //  状态定义
    // ========================================================
    localparam RD_IDLE  = 2'd0;
    localparam RD_ADDR  = 2'd1;
    localparam RD_DATA  = 2'd2;
    localparam RD_DONE  = 2'd3;

    localparam WR_IDLE  = 3'd0;
    localparam WR_ADDR  = 3'd1;
    localparam WR_DATA  = 3'd2;
    localparam WR_RESP  = 3'd3;
    localparam WR_DONE  = 3'd4;

    // ========================================================
    //  寄存器定义
    // ========================================================
    // 读通道
    reg [1:0]  rd_state;
    reg [7:0]  rd_cnt;
    reg [31:0] rd_addr_latched;
    reg [7:0]  rd_len_latched;
    reg [15:0] rd_buf_wr_base;     // 内部 Buffer 写起始地址
    reg [15:0] rd_buf_wr_offset;   // 当前写偏移
    reg        rd_req_latched;

    // 写通道
    reg [2:0]  wr_state;
    reg [7:0]  wr_cnt;
    reg [31:0] wr_addr_latched;
    reg [7:0]  wr_len_latched;
    reg [15:0] wr_buf_rd_base;     // 内部 C Buffer 读起始地址
    reg [15:0] wr_buf_rd_offset;   // 当前读偏移
    reg        wr_req_latched;
    reg [11:0] wr_remaining_len;   // 剩余待传输总长度（支持最大2047字节）
    reg [31:0] wr_next_addr;       // 下一轮突发的起始地址

    // ========================================================
    //  组合逻辑块1：读通道下一状态
    // ========================================================
    reg [1:0]  rd_next_state;
    reg [7:0]  rd_cnt_next;
    reg [15:0] rd_buf_wr_offset_next;

    always @(*) begin
        rd_next_state = rd_state;
        rd_cnt_next = rd_cnt;
        rd_buf_wr_offset_next = rd_buf_wr_offset;

        case (rd_state)
            RD_IDLE: begin
                if (dma_rd_req && !rd_req_latched)
                    rd_next_state = RD_ADDR;
            end
            RD_ADDR: begin
                if (m_axi_arready) begin
                    rd_next_state = RD_DATA;
                    rd_cnt_next = 8'd0;
                    rd_buf_wr_offset_next = 16'd0;
                end
            end
            RD_DATA: begin
                if (m_axi_rvalid) begin
                    if (m_axi_rlast) begin
                        rd_next_state = RD_DONE;
                    end else begin
                        rd_cnt_next = rd_cnt + 1'b1;
                        rd_buf_wr_offset_next = rd_buf_wr_offset + 16'd4;
                    end
                end
            end
            RD_DONE: begin
                rd_next_state = RD_IDLE;
            end
            default: rd_next_state = RD_IDLE;
        endcase
    end

    // ========================================================
    //  组合逻辑块1：写通道下一状态
    // ========================================================
    reg [2:0]  wr_next_state;
    reg [7:0]  wr_cnt_next;
    reg [15:0] wr_buf_rd_offset_next;
    reg [11:0] wr_remaining_len_next;

    always @(*) begin
        wr_next_state = wr_state;
        wr_cnt_next = wr_cnt;
        wr_buf_rd_offset_next = wr_buf_rd_offset;
        wr_remaining_len_next = wr_remaining_len;

        case (wr_state)
            WR_IDLE: begin
                if (dma_wr_req && !wr_req_latched)
                    wr_next_state = WR_ADDR;
            end
            WR_ADDR: begin
                if (m_axi_awvalid && m_axi_awready) begin
                    wr_next_state = WR_DATA;
                    wr_cnt_next = 8'd0;
                    wr_buf_rd_offset_next = 16'd4;  // 保持+4偏移，防止首拍重复
                end
            end
            WR_DATA: begin
                if (m_axi_wvalid && m_axi_wready) begin
                    // 先判断是否为最后一拍，再递增计数器
                    if (wr_cnt == wr_len_latched) begin
                        // 当前是最后一拍，发送完数据后进入WR_RESP
                        wr_next_state = WR_RESP;
                        // 最后一拍也需要递增，但不需要更新地址（因为没有下一拍了）
                        wr_cnt_next = wr_cnt + 1'b1;
                    end else begin
                        // 非最后一拍：递增计数器和地址偏移
                        wr_cnt_next = wr_cnt + 1'b1;
                        wr_buf_rd_offset_next = wr_buf_rd_offset + 16'd4;
                    end
                end
            end
            WR_RESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    // 计算本轮实际传输的数据个数 (len_latched + 1)
                    // 注意：这里使用当前的 wr_remaining_len 和 wr_len_latched 计算下一次剩余的
                    wr_remaining_len_next = wr_remaining_len - (wr_len_latched + 12'd1);
                    
                    // 检查是否还有剩余数据需要传输
                    if (wr_remaining_len_next > 12'd0) begin
                        wr_next_state = WR_ADDR;  // 继续下一轮突发
                        wr_cnt_next = 8'd0;
                        wr_buf_rd_offset_next = 16'd0;
                    end else begin
                        wr_next_state = WR_DONE;  // 全部传输完成
                    end
                end
            end
            WR_DONE: begin
                wr_next_state = WR_IDLE;
            end
            default: wr_next_state = WR_IDLE;
        endcase
    end

    // ========================================================
    //  时序逻辑块：状态寄存器和计数器更新
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state           <= RD_IDLE;
            rd_cnt             <= 8'd0;
            rd_addr_latched    <= 32'd0;
            rd_len_latched     <= 8'd0;
            rd_buf_wr_base     <= 16'd0;
            rd_buf_wr_offset   <= 16'd0;
            rd_req_latched     <= 1'b0;

            wr_state           <= WR_IDLE;
            wr_cnt             <= 8'd0;
            wr_addr_latched    <= 32'd0;
            wr_len_latched     <= 8'd0;
            wr_buf_rd_base     <= 16'd0;
            wr_buf_rd_offset   <= 16'd0;
            wr_req_latched     <= 1'b0;
            wr_remaining_len   <= 12'd0;
            wr_next_addr       <= 32'd0;
        end else begin
            // 读通道
            rd_state         <= rd_next_state;
            rd_cnt           <= rd_cnt_next;
            rd_buf_wr_offset <= rd_buf_wr_offset_next;

            if (dma_rd_req && !rd_req_latched) begin
                rd_req_latched   <= 1'b1;
                rd_addr_latched  <= dma_rd_addr;
                rd_len_latched   <= dma_rd_len;
                rd_buf_wr_base   <= dma_buf_wr_addr;
                rd_buf_wr_offset <= 16'd0;
            end else if (rd_state == RD_DONE) begin
                rd_req_latched <= 1'b0;
            end

            // 写通道
            wr_state           <= wr_next_state;
            wr_cnt             <= wr_cnt_next;
            wr_buf_rd_offset   <= wr_buf_rd_offset_next;
            wr_remaining_len   <= wr_remaining_len_next;

            if (dma_wr_req && !wr_req_latched) begin
                wr_req_latched   <= 1'b1;
                wr_addr_latched  <= dma_wr_addr;
                wr_remaining_len <= dma_wr_total_len + 12'd1;  // 转换为实际数据个数
                wr_buf_rd_base   <= dma_buf_rd_addr;
                wr_buf_rd_offset <= 16'd0;
                
                // 计算本轮突发长度：取min(剩余个数, 256个)
                if ((dma_wr_total_len + 12'd1) >= 12'd256) begin
                    wr_len_latched <= 8'd255;  // 最大burst: 256个数据
                    wr_next_addr   <= dma_wr_addr + 32'd1024;  // 256 * 4字节
                end else begin
                    wr_len_latched <= dma_wr_total_len;  // 直接使用burst长度，无需再减1
                    wr_next_addr   <= dma_wr_addr + ((dma_wr_total_len + 12'd1) << 2);  // 个数 * 4字节
                end
            end else if (wr_state == WR_RESP) begin
                // 在WR_RESP状态更新剩余长度和下一轮参数
                // wr_remaining_len 已经在上面通过 wr_remaining_len_next 更新了
                
                if (wr_remaining_len_next > 12'd0) begin
                    // 还有剩余数据，准备下一轮突发
                    wr_addr_latched <= wr_next_addr;
                    if (wr_remaining_len_next >= 12'd256) begin
                        wr_len_latched <= 8'd255;  // 传输256个数据
                        wr_next_addr   <= wr_next_addr + 32'd1024;
                    end else begin
                        wr_len_latched <= wr_remaining_len_next - 1'b1;  // AXI burst长度 = 个数-1
                        wr_next_addr   <= wr_next_addr + (wr_remaining_len_next << 2);
                    end
                end
            end else if (wr_state == WR_DONE) begin
                wr_req_latched <= 1'b0;
            end
        end
    end

    // ========================================================
    //  组合逻辑块2：AXI 读通道输出
    // ========================================================
    always @(*) begin
        m_axi_araddr  = 32'd0;
        m_axi_arlen   = 8'd0;
        m_axi_arsize  = 3'd2;    // 4 字节
        m_axi_arburst = 2'b01;   // INCR
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        case (rd_state)
            RD_ADDR: begin
                m_axi_araddr  = rd_addr_latched;
                m_axi_arlen   = rd_len_latched;
                m_axi_arvalid = 1'b1;
            end
            RD_DATA: begin
                m_axi_rready = 1'b1;
            end
            default: ;
        endcase
    end

    // ========================================================
    //  组合逻辑块2：AXI 写通道输出
    //  注意：m_axi_wdata 直接来自 buf_rd_data（C Buffer 输出）
    // ========================================================
    always @(*) begin
        m_axi_awaddr  = 32'd0;
        m_axi_awlen   = 8'd0;
        m_axi_awsize  = 3'd2;
        m_axi_awburst = 2'b01;
        m_axi_awvalid = 1'b0;

        m_axi_wdata   = buf_rd_data;   // 从 C Buffer 读出的数据直接送 AXI
        m_axi_wstrb   = 4'hF;
        m_axi_wlast   = 1'b0;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;

        case (wr_state)
            WR_ADDR: begin
                m_axi_awaddr  = wr_addr_latched;
                m_axi_awlen   = wr_len_latched;
                m_axi_awvalid = 1'b1;
            end
            WR_DATA: begin
                m_axi_wvalid = 1'b1;
                m_axi_wlast  = (wr_cnt >= wr_len_latched) ? 1'b1 : 1'b0;
            end
            WR_RESP: begin
                m_axi_bready = 1'b1;
            end
            default: ;
        endcase
    end

    // ========================================================
    //  组合逻辑块2：内部 Buffer 控制信号
    // ========================================================

    // Load 时：AXI Master 写入 A/B Buffer（地址自动递增）
    always @(*) begin
        buf_wr_en   = 1'b0;
        buf_wr_addr = 16'd0;
        buf_wr_data = 32'd0;
        buf_wr_strb = 4'h0;

        if (rd_state == RD_DATA && m_axi_rvalid && m_axi_rready) begin
            buf_wr_en   = 1'b1;
            buf_wr_addr = rd_buf_wr_base + rd_buf_wr_offset;
            buf_wr_data = m_axi_rdata;
            buf_wr_strb = 4'hF;
        end
    end

    // Store 时：AXI Master 从 C Buffer 读取（提前一拍发地址）
    always @(*) begin
        buf_rd_en   = 1'b0;
        buf_rd_addr = 16'd0;

        if (wr_state == WR_ADDR || wr_state == WR_DATA) begin
            buf_rd_en   = 1'b1;
            buf_rd_addr = wr_buf_rd_base + wr_buf_rd_offset;
        end
    end

    // ========================================================
    //  DMA 完成信号
    // ========================================================
    assign dma_rd_done = (rd_state == RD_DONE);
    assign dma_wr_done = (wr_state == WR_DONE);

endmodule