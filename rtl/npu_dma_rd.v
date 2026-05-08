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
    input  wire [7:0]               burst_len,     // Burst长度-1 (0=单拍, 15=16-beat)
    output reg                      busy,
    output reg                      done,
    output reg                      cmd_valid,
    output reg                      cmd_write,
    output reg  [ADDR_WIDTH-1:0]    cmd_addr,
    output reg  [DATA_WIDTH-1:0]    cmd_wdata,
    output reg  [DATA_WIDTH/8-1:0]  cmd_wstrb,
    output reg  [7:0]               cmd_burst_len,  // 输出给bridge的burst长度
    output reg  [1:0]               cmd_burst_type, // 输出给bridge的burst类型 (01=INCR)
    input  wire                     cmd_ready,
    input  wire                     rsp_valid,
    input  wire [DATA_WIDTH-1:0]    rsp_rdata,
    output reg                      data_valid,
    output reg  [DATA_WIDTH-1:0]    data_word,
    output reg  [15:0]              data_index
);

    localparam ST_IDLE     = 3'd0;
    localparam ST_CMD      = 3'd1;
    localparam ST_WAIT     = 3'd2;
    localparam ST_DONE     = 3'd3;
    localparam ST_BURST_WAIT = 3'd4;  // 等待Burst数据返回

    reg [2:0] state;
    reg [15:0] rd_cnt;
    reg [15:0] burst_cnt;      // 已接收的Burst数据计数
    reg [7:0]  burst_len_reg;  // 保存的Burst长度
    reg [15:0] burst_total;    // 本次Burst需要接收的总数据量

    // 计算实际的Burst长度: 取min(burst_len, word_count-1)
    wire [7:0] actual_burst_len = (word_count - 1 < {8'd0, burst_len}) ?
                                  word_count[7:0] - 8'd1 : burst_len;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            rd_cnt          <= 16'd0;
            burst_cnt       <= 16'd0;
            burst_len_reg   <= 8'd0;
            burst_total     <= 16'd0;
            busy            <= 1'b0;
            done            <= 1'b0;
            cmd_valid        <= 1'b0;
            cmd_write        <= 1'b0;
            cmd_addr         <= {ADDR_WIDTH{1'b0}};
            cmd_wdata        <= {DATA_WIDTH{1'b0}};
            cmd_wstrb        <= {DATA_WIDTH/8{1'b0}};
            cmd_burst_len    <= 8'd0;
            cmd_burst_type   <= 2'd0;
            data_valid       <= 1'b0;
            data_word        <= {DATA_WIDTH{1'b0}};
            data_index       <= 16'd0;
        end else begin
            done       <= 1'b0;
            data_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy         <= 1'b0;
                    cmd_valid    <= 1'b0;
                    if (start) begin
                        $display("[%0t] [DMA_RD] IDLE->CMD: 启动DMA读, base=0x%h, count=%d, burst_len=%d",
                                 $time, base_addr, word_count, burst_len);
                        busy          <= 1'b1;
                        rd_cnt        <= 16'd0;
                        burst_cnt     <= 16'd0;
                        burst_len_reg <= actual_burst_len;
                        // 计算本次Burst需要接收的数据量
                        if (word_count <= {8'd0, actual_burst_len} + 16'd1) begin
                            burst_total <= word_count;
                        end else begin
                            burst_total <= {8'd0, actual_burst_len} + 16'd1;
                        end
                        state <= ST_CMD;
                    end
                end

                ST_CMD: begin
                    cmd_write      <= 1'b0;
                    cmd_valid      <= 1'b1;
                    cmd_addr       <= base_addr + {rd_cnt, 2'b00};
                    cmd_wdata      <= {DATA_WIDTH{1'b0}};
                    cmd_wstrb      <= {DATA_WIDTH/8{1'b0}};
                    cmd_burst_len  <= burst_len_reg;
                    cmd_burst_type <= 2'b01;  // INCR模式
                    if (cmd_ready) begin
                        cmd_valid <= 1'b0;
                        burst_cnt <= 16'd0;
                        // 如果是单拍，直接等待；否则进入Burst等待
                        if (burst_len_reg == 8'd0) begin
                            state <= ST_WAIT;
                        end else begin
                            state <= ST_BURST_WAIT;
                        end
                    end
                end

                // 单拍等待
                ST_WAIT: begin
                    if (rsp_valid) begin
                        data_valid <= 1'b1;
                        data_word  <= rsp_rdata;
                        data_index <= rd_cnt;
                        rd_cnt     <= rd_cnt + 1'b1;

                        if (rd_cnt == word_count - 1'b1) begin
                            $display("[%0t] [DMA_RD] WAIT->DONE: 读取完成, 共读取 %d 个字", $time, rd_cnt + 1);
                            state <= ST_DONE;
                        end else begin
                            state <= ST_CMD;
                        end
                    end
                end

                // Burst等待: 连续接收多个数据
                ST_BURST_WAIT: begin
                    if (rsp_valid) begin
                        data_valid <= 1'b1;
                        data_word  <= rsp_rdata;
                        data_index <= rd_cnt;
                        rd_cnt     <= rd_cnt + 1'b1;
                        burst_cnt  <= burst_cnt + 1'b1;

                        // 检查是否接收完本次Burst的所有数据
                        if (burst_cnt == burst_total - 16'd1) begin
                            // 检查是否完成所有数据
                            if (rd_cnt == word_count - 16'd1) begin
                                $display("[%0t] [DMA_RD] BURST->DONE: 读取完成, 共读取 %d 个字",
                                         $time, rd_cnt + 1);
                                state <= ST_DONE;
                            end else begin
                                // 继续下一次Burst
                                $display("[%0t] [DMA_RD] BURST->CMD: 继续读取, 已完成 %d/%d",
                                         $time, rd_cnt + 1, word_count);
                                // 更新下次Burst长度
                                if (word_count - rd_cnt - 16'd1 <= {8'd0, burst_len_reg} + 16'd1) begin
                                    burst_total <= word_count - rd_cnt - 16'd1;
                                end else begin
                                    burst_total <= {8'd0, burst_len_reg} + 16'd1;
                                end
                                state <= ST_CMD;
                            end
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