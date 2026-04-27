`timescale 1ns/1ps
`include "npu_defs.vh"

// 简化版 AXI4 主设备桥：把内部命令握手翻译成 AXI4 读写通道。
module npu_axi4_bridge #(
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH,
    parameter DATA_WIDTH  = `NPU_AXI_DATA_WIDTH
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     rd_cmd_valid,
    output reg                      rd_cmd_ready,
    input  wire [ADDR_WIDTH-1:0]    rd_cmd_addr,
    output reg                      rd_rsp_valid,
    output reg  [DATA_WIDTH-1:0]    rd_rsp_rdata,

    input  wire                     wr_cmd_valid,
    output reg                      wr_cmd_ready,
    input  wire [ADDR_WIDTH-1:0]    wr_cmd_addr,
    input  wire [DATA_WIDTH-1:0]    wr_cmd_wdata,
    input  wire [DATA_WIDTH/8-1:0]  wr_cmd_wstrb,
    output reg                      wr_rsp_valid,

    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,

    output reg  [DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,

    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,

    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,

    input  wire [DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready
);

    localparam ST_IDLE = 3'd0;
    localparam ST_RD   = 3'd1;
    localparam ST_WR_A = 3'd2;
    localparam ST_WR_B = 3'd3;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            rd_cmd_ready   <= 1'b0;
            rd_rsp_valid   <= 1'b0;
            rd_rsp_rdata   <= {DATA_WIDTH{1'b0}};
            wr_cmd_ready   <= 1'b0;
            wr_rsp_valid   <= 1'b0;
            m_axi_awaddr   <= {ADDR_WIDTH{1'b0}};
            m_axi_awvalid  <= 1'b0;
            m_axi_wdata    <= {DATA_WIDTH{1'b0}};
            m_axi_wstrb    <= {DATA_WIDTH/8{1'b0}};
            m_axi_wvalid   <= 1'b0;
            m_axi_bready   <= 1'b0;
            m_axi_araddr   <= {ADDR_WIDTH{1'b0}};
            m_axi_arvalid  <= 1'b0;
            m_axi_rready   <= 1'b0;
        end else begin
            rd_rsp_valid <= 1'b0;
            wr_rsp_valid <= 1'b0;
            rd_cmd_ready <= 1'b0;
            wr_cmd_ready <= 1'b0;

            case (state)
                ST_IDLE: begin
                    m_axi_bready  <= 1'b0;
                    m_axi_rready  <= 1'b0;

                    if (rd_cmd_valid) begin
                        rd_cmd_ready <= 1'b1;
                        m_axi_araddr  <= rd_cmd_addr;
                        m_axi_arvalid <= 1'b1;
                        state         <= ST_RD;
                    end else if (wr_cmd_valid) begin
                        wr_cmd_ready <= 1'b1;
                        m_axi_awaddr  <= wr_cmd_addr;
                        m_axi_wdata   <= wr_cmd_wdata;
                        m_axi_wstrb   <= wr_cmd_wstrb;
                        m_axi_awvalid <= 1'b1;
                        m_axi_wvalid  <= 1'b1;
                        state         <= ST_WR_A;
                    end
                end

                ST_RD: begin
                    // AR通道握手完成后，设置rready等待数据
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;  // 准备好接收读响应
                    end
                    
                    // 当R通道有效且ready时，捕获数据并返回IDLE
                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_rsp_valid <= 1'b1;
                        rd_rsp_rdata <= m_axi_rdata;
                        m_axi_rready  <= 1'b0;  // 清除ready
                        state         <= ST_IDLE;
                    end
                    // 注意：在等待m_axi_rvalid期间，m_axi_rready必须保持为1
                end

                ST_WR_A: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                    end
                    if (!m_axi_awvalid && !m_axi_wvalid) begin
                        m_axi_bready <= 1'b1;
                        state <= ST_WR_B;
                    end
                end

                ST_WR_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        wr_rsp_valid <= 1'b1;
                        m_axi_bready  <= 1'b0;
                        state         <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule