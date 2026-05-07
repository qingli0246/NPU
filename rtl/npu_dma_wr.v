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



    reg data_latched;              // 数据已锁存标志
    reg [ADDR_WIDTH-1:0] latched_addr;
    reg [DATA_WIDTH-1:0] latched_data;



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
                    data_latched <= 1'b0;
                    if (start) begin
                        $display("[%0t] [DMA_WR] IDLE->CMD: 启动DMA写, base=0x%h, count=%d", $time, base_addr, word_count);
                        busy   <= 1'b1;
                        wr_cnt <= 16'd0;
                        state  <= ST_CMD;
                    end
                end

                ST_CMD: begin
                    cmd_write <= 1'b1;
                    data_in_ready <= 1'b1;


                    // 第一步：锁存输入数据（单周期完成）
                    if (data_in_valid && !data_latched) begin
                        latched_data <= data_in;
                        latched_addr <= base_addr + {wr_cnt, 2'b00};
                        data_latched <= 1'b1;
                    end
                      // 第二步：等待AXI就绪后发送（可以跨多个周期）
                    if (data_latched) begin
                        cmd_valid <= 1'b1;
                        cmd_addr  <= latched_addr;
                        cmd_wdata <= latched_data;
                        cmd_wstrb <= {DATA_WIDTH/8{1'b1}};

                        if (cmd_ready) begin
                            cmd_valid    <= 1'b0;
                            data_latched <= 1'b0;  // 清除锁存标志
                            state        <= ST_WAIT;
                        end
                    end
                end

                ST_WAIT: begin
                    if (rsp_valid) begin
                        if (wr_cnt == word_count - 1'b1) begin
                            $display("[%0t] [DMA_WR] WAIT->DONE: 写入完成, 共写入 %d 个字", $time, wr_cnt + 1);
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