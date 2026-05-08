`timescale 1ns/1ps
`include "npu_defs.vh"

// AXI4 主设备桥：支持单拍和Burst传输
module npu_axi4_bridge #(
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH,
    parameter DATA_WIDTH  = `NPU_AXI_DATA_WIDTH
) (
    input  wire                     clk,
    input  wire                     rst_n,

    // 内部读命令接口
    input  wire                     rd_cmd_valid,
    output reg                      rd_cmd_ready,
    input  wire [ADDR_WIDTH-1:0]    rd_cmd_addr,
    input  wire [7:0]               rd_cmd_burst_len,   // Burst长度-1 (0=单拍, 15=16-beat)
    input  wire [1:0]               rd_cmd_burst_type,  // 00=FIXED, 01=INCR, 10=WRAP
    output reg                      rd_rsp_valid,
    output reg  [DATA_WIDTH-1:0]    rd_rsp_rdata,

    // 内部写命令接口
    input  wire                     wr_cmd_valid,
    output reg                      wr_cmd_ready,
    input  wire [ADDR_WIDTH-1:0]    wr_cmd_addr,
    input  wire [DATA_WIDTH-1:0]    wr_cmd_wdata,
    input  wire [DATA_WIDTH/8-1:0]  wr_cmd_wstrb,
    input  wire [7:0]               wr_cmd_burst_len,
    input  wire [1:0]               wr_cmd_burst_type,
    output reg                      wr_rsp_valid,

    // AXI4 主设备接口
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg  [7:0]               m_axi_awlen,
    output reg  [2:0]               m_axi_awsize,
    output reg  [1:0]               m_axi_awburst,
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,

    output reg  [DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output reg                      m_axi_wlast,
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,

    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,

    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]               m_axi_arlen,
    output reg  [2:0]               m_axi_arsize,
    output reg  [1:0]               m_axi_arburst,
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,

    input  wire [DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready
);

    localparam ST_IDLE  = 3'd0;
    localparam ST_RD    = 3'd1;
    localparam ST_RD_BURST = 3'd2;  // Burst读数据接收
    localparam ST_WR_A  = 3'd3;
    localparam ST_WR_B  = 3'd4;
    localparam ST_WR_BURST = 3'd5;  // Burst写数据发送

    reg [2:0] state;
    reg [7:0] burst_cnt;      // Burst计数器
    reg [7:0] burst_len_reg;  // 保存的Burst长度
    reg [1:0] burst_type_reg; // 保存的Burst类型

    // 计算AXI4信号
    wire [2:0] axi_size = (DATA_WIDTH == 32) ? 3'b010 :  // 4字节
                          (DATA_WIDTH == 64) ? 3'b011 :  // 8字节
                          3'b010;  // 默认4字节

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            rd_cmd_ready    <= 1'b0;
            rd_rsp_valid    <= 1'b0;
            rd_rsp_rdata    <= {DATA_WIDTH{1'b0}};
            wr_cmd_ready    <= 1'b0;
            wr_rsp_valid    <= 1'b0;
            m_axi_awaddr    <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen     <= 8'd0;
            m_axi_awsize    <= 3'd0;
            m_axi_awburst   <= 2'd0;
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= {DATA_WIDTH{1'b0}};
            m_axi_wstrb     <= {DATA_WIDTH/8{1'b0}};
            m_axi_wlast     <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
            m_axi_araddr    <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen     <= 8'd0;
            m_axi_arsize    <= 3'd0;
            m_axi_arburst   <= 2'd0;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            burst_cnt       <= 8'd0;
            burst_len_reg   <= 8'd0;
            burst_type_reg  <= 2'd0;
        end else begin
            rd_rsp_valid <= 1'b0;
            wr_rsp_valid <= 1'b0;
            rd_cmd_ready <= 1'b0;
            wr_cmd_ready <= 1'b0;

            case (state)
                ST_IDLE: begin
                    m_axi_bready  <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    m_axi_wlast   <= 1'b0;

                    // 读命令
                    if (rd_cmd_valid) begin
                        rd_cmd_ready   <= 1'b1;
                        m_axi_araddr   <= rd_cmd_addr;
                        m_axi_arlen    <= rd_cmd_burst_len;
                        m_axi_arsize   <= axi_size;
                        m_axi_arburst  <= rd_cmd_burst_type;
                        m_axi_arvalid  <= 1'b1;
                        burst_cnt      <= 8'd0;
                        burst_len_reg  <= rd_cmd_burst_len;
                        burst_type_reg <= rd_cmd_burst_type;
                        state          <= ST_RD;
                    end
                    // 写命令
                    else if (wr_cmd_valid) begin
                        wr_cmd_ready   <= 1'b1;
                        m_axi_awaddr   <= wr_cmd_addr;
                        m_axi_awlen    <= wr_cmd_burst_len;
                        m_axi_awsize   <= axi_size;
                        m_axi_awburst  <= wr_cmd_burst_type;
                        m_axi_awvalid  <= 1'b1;
                        m_axi_wdata    <= wr_cmd_wdata;
                        m_axi_wstrb    <= wr_cmd_wstrb;
                        m_axi_wvalid   <= 1'b1;
                        m_axi_wlast    <= (wr_cmd_burst_len == 8'd0);  // 单拍时直接last
                        burst_cnt      <= 8'd0;
                        burst_len_reg  <= wr_cmd_burst_len;
                        burst_type_reg <= wr_cmd_burst_type;
                        state          <= ST_WR_A;
                    end
                end

                // ========== 读通道 ==========
                ST_RD: begin
                    // AR通道握手完成
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;  // 准备接收数据
                        state         <= ST_RD_BURST;
                    end
                end

                ST_RD_BURST: begin
                    // 接收读数据
                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_rsp_valid <= 1'b1;
                        rd_rsp_rdata <= m_axi_rdata;
                        burst_cnt    <= burst_cnt + 1'b1;

                        // 检查是否是最后一个数据
                        if (m_axi_rlast || burst_cnt == burst_len_reg) begin
                            m_axi_rready <= 1'b0;
                            state        <= ST_IDLE;
                        end
                    end
                end

                // ========== 写通道 ==========
                ST_WR_A: begin
                    // AW通道握手完成
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                    end

                    // W通道握手完成
                    if (m_axi_wvalid && m_axi_wready) begin
                        burst_cnt <= burst_cnt + 1'b1;

                        // 单拍传输完成
                        if (burst_len_reg == 8'd0) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state        <= ST_WR_B;
                        end
                        // Burst传输: 发送剩余数据
                        else if (burst_cnt < burst_len_reg) begin
                            m_axi_wlast <= (burst_cnt == burst_len_reg - 1'b1);
                            // 注意: wdata和wstrb需要由DMA持续提供
                        end else begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state        <= ST_WR_B;
                        end
                    end
                end

                ST_WR_B: begin
                    // 等待写响应
                    if (m_axi_bvalid && m_axi_bready) begin
                        wr_rsp_valid <= 1'b1;
                        m_axi_bready <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule