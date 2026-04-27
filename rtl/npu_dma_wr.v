`timescale 1ns/1ps
`include "npu_defs.vh"

module npu_dma_wr #(
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH,
    parameter DATA_WIDTH  = `NPU_AXI_DATA_WIDTH
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [ADDR_WIDTH-1:0]    base_addr,
    input  wire [15:0]              word_count,
    input  wire [DATA_WIDTH-1:0]    data_in,
    input  wire                     data_in_valid,
    output reg                      data_in_ready,
    output reg                      busy,
    output reg                      done,
    output reg                      cmd_valid,
    output reg                      cmd_write,
    output reg  [ADDR_WIDTH-1:0]    cmd_addr,
    output reg  [DATA_WIDTH-1:0]    cmd_wdata,
    output reg  [DATA_WIDTH/8-1:0]  cmd_wstrb,
    input  wire                     cmd_ready,
    input  wire                     rsp_valid,
    input  wire [DATA_WIDTH-1:0]    rsp_rdata
);

    localparam ST_IDLE = 3'd0;
    localparam ST_CMD  = 3'd1;
    localparam ST_WAIT = 3'd2;
    localparam ST_DONE = 3'd3;

    reg [2:0] state;
    wire [2:0] state_out;  // 输出状态供调试
    assign state_out = state;
    
    reg [15:0] wr_cnt;
    wire [15:0] wr_cnt_out;  // 输出计数器供调试
    assign wr_cnt_out = wr_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            wr_cnt        <= 16'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            cmd_valid     <= 1'b0;
            cmd_write     <= 1'b1;
            cmd_addr      <= {ADDR_WIDTH{1'b0}};
            cmd_wdata     <= {DATA_WIDTH{1'b0}};
            cmd_wstrb     <= {DATA_WIDTH/8{1'b0}};
            data_in_ready <= 1'b0;
        end else begin
            done          <= 1'b0;
            data_in_ready <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy      <= 1'b0;
                    cmd_valid <= 1'b0;
                    if (start) begin
                        busy   <= 1'b1;
                        wr_cnt <= 16'd0;
                        state  <= ST_CMD;
                    end
                end

                ST_CMD: begin
                    cmd_write <= 1'b1;
                    // 修正握手协议：在ST_CMD状态无条件表示准备好接收数据
                    // 这样发送端可以在任何时候提供数据，避免死锁
                    data_in_ready <= 1'b1;
                    
                    if (data_in_valid) begin
                        // 收到有效数据，立即发送AXI命令
                        cmd_valid <= 1'b1;
                        cmd_addr  <= base_addr + {wr_cnt, 2'b00};
                        cmd_wdata <= data_in;
                        cmd_wstrb <= {DATA_WIDTH/8{1'b1}};
                        
                        if (cmd_ready) begin
                            // AXI总线已接受命令
                            cmd_valid <= 1'b0;
                            state     <= ST_WAIT;
                        end
                    end
                end

                ST_WAIT: begin
                    if (rsp_valid) begin
                        if (wr_cnt == word_count - 1'b1) begin
                            state <= ST_DONE;
                        end else begin
                            wr_cnt <= wr_cnt + 1'b1;
                            state  <= ST_CMD;
                        end
                    end
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule