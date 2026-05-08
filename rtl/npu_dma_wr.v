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
    input  wire [7:0]               burst_len,      // Burst长度-1 (0=单拍, 15=16-beat)
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
    output reg  [7:0]               cmd_burst_len,   // 输出给bridge的burst长度
    output reg  [1:0]               cmd_burst_type,  // 输出给bridge的burst类型 (01=INCR)
    input  wire                     cmd_ready,
    input  wire                     rsp_valid,
    input  wire [DATA_WIDTH-1:0]    rsp_rdata
);

    localparam ST_IDLE      = 3'd0;
    localparam ST_CMD       = 3'd1;
    localparam ST_WAIT      = 3'd2;
    localparam ST_DONE      = 3'd3;
    localparam ST_BURST_SEND = 3'd4;  // Burst数据发送

    reg [2:0] state;
    reg [15:0] wr_cnt;
    reg [7:0]  burst_cnt;      // 已发送的Burst数据计数
    reg [7:0]  burst_len_reg;  // 保存的Burst长度
    reg [15:0] burst_total;    // 本次Burst需要发送的总数据量

    reg data_latched;
    reg [ADDR_WIDTH-1:0] latched_addr;
    reg [DATA_WIDTH-1:0] latched_data;

    // 计算实际的Burst长度: 取min(burst_len, word_count-1)
    wire [7:0] actual_burst_len = (word_count - 1 < {8'd0, burst_len}) ?
                                  word_count[7:0] - 8'd1 : burst_len;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            wr_cnt          <= 16'd0;
            burst_cnt       <= 8'd0;
            burst_len_reg   <= 8'd0;
            burst_total     <= 16'd0;
            busy            <= 1'b0;
            done            <= 1'b0;
            cmd_valid        <= 1'b0;
            cmd_write        <= 1'b1;
            cmd_addr         <= {ADDR_WIDTH{1'b0}};
            cmd_wdata        <= {DATA_WIDTH{1'b0}};
            cmd_wstrb        <= {DATA_WIDTH/8{1'b0}};
            cmd_burst_len    <= 8'd0;
            cmd_burst_type   <= 2'd0;
            data_in_ready    <= 1'b0;
            data_latched     <= 1'b0;
            latched_addr     <= {ADDR_WIDTH{1'b0}};
            latched_data     <= {DATA_WIDTH{1'b0}};
        end else begin
            done          <= 1'b0;
            data_in_ready <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy         <= 1'b0;
                    cmd_valid    <= 1'b0;
                    data_latched <= 1'b0;
                    if (start) begin
                        $display("[%0t] [DMA_WR] IDLE->CMD: 启动DMA写, base=0x%h, count=%d, burst_len=%d",
                                 $time, base_addr, word_count, burst_len);
                        busy          <= 1'b1;
                        wr_cnt        <= 16'd0;
                        burst_cnt     <= 8'd0;
                        burst_len_reg <= actual_burst_len;
                        // 计算本次Burst需要发送的数据量
                        if (word_count <= {8'd0, actual_burst_len} + 16'd1) begin
                            burst_total <= word_count[7:0];
                        end else begin
                            burst_total <= {8'd0, actual_burst_len} + 16'd1;
                        end
                        state <= ST_CMD;
                    end
                end

                ST_CMD: begin
                    cmd_write      <= 1'b1;
                    data_in_ready  <= 1'b1;

                    // 锁存输入数据
                    if (data_in_valid && !data_latched) begin
                        latched_data <= data_in;
                        latched_addr <= base_addr + {wr_cnt, 2'b00};
                        data_latched <= 1'b1;
                        $display("[%0t] [DMA_WR] 锁存数据: addr=0x%h, data=0x%h",
                                 $time, base_addr + {wr_cnt, 2'b00}, data_in);
                    end

                    // 发送命令(带Burst参数)
                    if (data_latched) begin
                        cmd_valid      <= 1'b1;
                        cmd_addr       <= latched_addr;
                        cmd_wdata      <= latched_data;
                        cmd_wstrb      <= {DATA_WIDTH/8{1'b1}};
                        cmd_burst_len  <= burst_len_reg;
                        cmd_burst_type <= 2'b01;  // INCR模式

                        if (cmd_ready) begin
                            cmd_valid    <= 1'b0;
                            data_latched <= 1'b0;
                            burst_cnt    <= 8'd0;

                            // 单拍直接等待响应
                            if (burst_len_reg == 8'd0) begin
                                state <= ST_WAIT;
                            end
                            // Burst: 继续发送剩余数据
                            else begin
                                wr_cnt    <= wr_cnt + 1'b1;
                                burst_cnt <= 8'd1;  // 已发送1个
                                state     <= ST_BURST_SEND;
                            end
                        end
                    end
                end

                // 单拍等待响应
                ST_WAIT: begin
                    if (rsp_valid) begin
                        if (wr_cnt == word_count - 1'b1) begin
                            $display("[%0t] [DMA_WR] 写入完成, 共 %d 个字", $time, wr_cnt + 1);
                            state <= ST_DONE;
                        end else begin
                            wr_cnt <= wr_cnt + 1'b1;
                            state  <= ST_CMD;
                        end
                    end
                end

                // Burst数据发送
                ST_BURST_SEND: begin
                    data_in_ready <= 1'b1;

                    // 等待并锁存数据
                    if (data_in_valid && !data_latched) begin
                        latched_data <= data_in;
                        data_latched <= 1'b1;
                        $display("[%0t] [DMA_WR] Burst数据[%0d]: data=0x%h",
                                 $time, burst_cnt, data_in);
                    end

                    // 发送数据到bridge
                    if (data_latched) begin
                        cmd_valid <= 1'b1;
                        cmd_wdata <= latched_data;
                        cmd_wstrb <= {DATA_WIDTH/8{1'b1}};

                        if (cmd_ready) begin
                            cmd_valid    <= 1'b0;
                            data_latched <= 1'b0;
                            burst_cnt    <= burst_cnt + 1'b1;
                            wr_cnt       <= wr_cnt + 1'b1;

                            // 检查是否完成本次Burst
                            if (burst_cnt == burst_total - 8'd1) begin
                                // 等待写响应
                                state <= ST_WAIT;
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