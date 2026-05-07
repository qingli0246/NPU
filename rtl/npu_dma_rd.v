`timescale 1ns/1ps
`include "npu_defs.vh"

module npu_dma_rd #(
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH,
    parameter DATA_WIDTH  = `NPU_AXI_DATA_WIDTH
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [ADDR_WIDTH-1:0]    base_addr,
    input  wire [15:0]              word_count,
    output reg                      busy,
    output reg                      done,
    output reg                      cmd_valid,
    output reg                      cmd_write,
    output reg  [ADDR_WIDTH-1:0]    cmd_addr,
    output reg  [DATA_WIDTH-1:0]    cmd_wdata,
    output reg  [DATA_WIDTH/8-1:0]  cmd_wstrb,
    input  wire                     cmd_ready,
    input  wire                     rsp_valid,
    input  wire [DATA_WIDTH-1:0]    rsp_rdata,
    output reg                      data_valid,
    output reg  [DATA_WIDTH-1:0]    data_word,
    output reg  [15:0]              data_index
);

    localparam ST_IDLE = 2'd0;
    localparam ST_CMD  = 2'd1;
    localparam ST_WAIT = 2'd2;
    localparam ST_DONE = 2'd3;

    reg [1:0] state;
    reg [15:0] rd_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            rd_cnt     <= 16'd0;
            busy       <= 1'b0;
            done       <= 1'b0;
            cmd_valid  <= 1'b0;
            cmd_write  <= 1'b0;
            cmd_addr   <= {ADDR_WIDTH{1'b0}};
            cmd_wdata  <= {DATA_WIDTH{1'b0}};
            cmd_wstrb  <= {DATA_WIDTH/8{1'b0}};
            data_valid <= 1'b0;
            data_word  <= {DATA_WIDTH{1'b0}};
            data_index <= 16'd0;
        end else begin
            done       <= 1'b0;
            data_valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy      <= 1'b0;
                    cmd_valid <= 1'b0;
                    if (start) begin
                        $display("[%0t] [DMA_RD] IDLE->CMD: 启动DMA读, base=0x%h, count=%d", $time, base_addr, word_count);
                        busy   <= 1'b1;
                        rd_cnt <= 16'd0;
                        state  <= ST_CMD;
                    end
                end

                ST_CMD: begin
                    cmd_write <= 1'b0;
                    cmd_valid <= 1'b1;
                    cmd_addr  <= base_addr + {rd_cnt, 2'b00};
                    cmd_wdata <= {DATA_WIDTH{1'b0}};
                    cmd_wstrb <= {DATA_WIDTH/8{1'b0}};
                    if (cmd_ready) begin
                        cmd_valid <= 1'b0;
                        state     <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (rsp_valid) begin
                        data_valid <= 1'b1;
                        data_word  <= rsp_rdata;
                        data_index <= rd_cnt;
                        if (rd_cnt == word_count - 1'b1) begin
                            $display("[%0t] [DMA_RD] WAIT->DONE: 读取完成, 共读取 %d 个字", $time, rd_cnt + 1);
                            state <= ST_DONE;
                        end else begin
                            rd_cnt <= rd_cnt + 1'b1;
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