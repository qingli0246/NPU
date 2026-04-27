`timescale 1ns/1ps
`include "npu_defs.vh"

module npu_tile #(
    parameter TILE_ID = 0
) (
    // 时钟与控制
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clk_en,
    input  wire                         start,

    // 模式配置：由上层计算池统一下发
    input  wire [1:0]                   top_mode,
    input  wire                         is_master,  // 1: 组主Tile，0: 从Tile

    // 本地矩阵输入（INDEP/SPLIT 主要使用）
    input  wire [`NPU_TILE_A_BITS-1:0]   a_flat,
    input  wire [`NPU_TILE_B_BITS-1:0]   b_flat,

    // 脉动级联输入（MERGE 主要使用）
    input  wire [`TILE_PORT_W-1:0]       a_left_i,
    input  wire [`TILE_PORT_W-1:0]       b_top_i,

    // 脉动级联输出（连接到右侧/下侧相邻Tile）
    output reg  [`TILE_PORT_W-1:0]       a_right_o,
    output reg  [`TILE_PORT_W-1:0]       b_down_o,

    // Tile运行状态与计算结果
    output reg                          busy,
    output reg                          done,
    output reg  [`NPU_TILE_C_BITS-1:0]   c_flat
);

    reg [1:0] state;
    reg [`NPU_TILE_A_BITS-1:0] a_lat;
    reg [`NPU_TILE_B_BITS-1:0] b_lat;
    wire split_mode;
    wire merge_mode;

    assign split_mode = (top_mode == `NPU_MODE_SPLIT);
    assign merge_mode = (top_mode == `NPU_MODE_MERGE);

    localparam ST_IDLE = 2'd0;
    localparam ST_RUN  = 2'd1;
    localparam ST_DONE = 2'd2;

    // 计算 4x4 或 8x8 的点积。split_mode 时只取前 4 个乘加项，便于做 4x4 子阵列骨架。
    function [31:0] dot_block;
        input [`NPU_TILE_A_BITS-1:0] a_mat;
        input [`NPU_TILE_B_BITS-1:0] b_mat;
        input [2:0] row_idx;
        input [2:0] col_idx;
        input       use_split;
        integer k;
        integer limit;
        reg [31:0] sum;
        reg [7:0] a_val;
        reg [7:0] b_val;
        begin
            sum = 32'd0;
            limit = use_split ? 4 : 8;
            for (k = 0; k < 8; k = k + 1) begin
                if (k < limit) begin
                    a_val = a_mat[((row_idx * 8 + k) * 8) +: 8];
                    b_val = b_mat[((k * 8 + col_idx) * 8) +: 8];
                    sum = sum + a_val * b_val;
                end
            end
            dot_block = sum;
        end
    endfunction

    integer ri;
    integer ci;
    reg [2:0] row_sel;
    reg [2:0] col_sel;
    reg [31:0] dot_val;

    // 调试信号：捕获C[0][0]的计算过程（使用独立信号而非数组）
    reg [31:0] debug_c00_sum;
    reg [7:0] debug_c00_a_val_0, debug_c00_a_val_1, debug_c00_a_val_2, debug_c00_a_val_3;
    reg [7:0] debug_c00_a_val_4, debug_c00_a_val_5, debug_c00_a_val_6, debug_c00_a_val_7;
    reg [7:0] debug_c00_b_val_0, debug_c00_b_val_1, debug_c00_b_val_2, debug_c00_b_val_3;
    reg [7:0] debug_c00_b_val_4, debug_c00_b_val_5, debug_c00_b_val_6, debug_c00_b_val_7;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= ST_IDLE;
            busy   <= 1'b0;
            done   <= 1'b0;
            c_flat <= {`NPU_TILE_C_BITS{1'b0}};
            a_lat  <= {`NPU_TILE_A_BITS{1'b0}};
            b_lat  <= {`NPU_TILE_B_BITS{1'b0}};
            a_right_o <= {`TILE_PORT_W{1'b0}};
            b_down_o  <= {`TILE_PORT_W{1'b0}};
        end else if (clk_en) begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    // 简化：使用电平触发
                    if (start) begin
                        // 启动时锁存输入，后续计算不再受外部数据抖动影响。
                        a_lat <= a_flat;
                        b_lat <= b_flat;
                        
                        // 调试输出
                        $display("[%0t] [TILE%0d] ST_IDLE: a_flat[63:0]=%h, b_flat[63:0]=%h", 
                                 $time, TILE_ID, a_flat[63:0], b_flat[63:0]);

                        // MERGE 模式下，从单元优先接受级联输入；主单元保留本地注入。
                        // 该策略便于支持"组主控 + 从属级联"的软件可重构拓扑。
                        if (merge_mode) begin
                            if (!is_master) begin
                                a_lat[0 +: `TILE_PORT_W] <= a_left_i;
                                b_lat[0 +: `TILE_PORT_W] <= b_top_i;
                            end
                        end

                        // 导出本 Tile 的右/下级联输出，供相邻 Tile 取用。
                        a_right_o <= a_flat[`NPU_TILE_A_BITS-`TILE_PORT_W +: `TILE_PORT_W];
                        b_down_o  <= b_flat[`NPU_TILE_B_BITS-`TILE_PORT_W +: `TILE_PORT_W];

                        busy  <= 1'b1;
                        state <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    // 这里采用"骨架式"计算：一次性算完整个 Tile 输出，便于先把层次结构跑通。
                    for (ri = 0; ri < 8; ri = ri + 1) begin
                        for (ci = 0; ci < 8; ci = ci + 1) begin
                            row_sel = ri[2:0];
                            col_sel = ci[2:0];
                            dot_val = dot_block(a_lat, b_lat, row_sel, col_sel, split_mode);
                            c_flat[((ri * 8 + ci) * 16) +: 16] <= dot_val[15:0];
                            
                            // 调试：捕获C[0][0]的计算过程
                            if (ri == 0 && ci == 0) begin
                                // 手动展开C[0][0]的计算以便调试
                                debug_c00_sum = 0;
                                debug_c00_a_val_0 = a_lat[((0 * 8 + 0) * 8) +: 8];
                                debug_c00_b_val_0 = b_lat[((0 * 8 + 0) * 8) +: 8];
                                debug_c00_sum = debug_c00_sum + debug_c00_a_val_0 * debug_c00_b_val_0;
                                
                                debug_c00_a_val_1 = a_lat[((0 * 8 + 1) * 8) +: 8];
                                debug_c00_b_val_1 = b_lat[((1 * 8 + 0) * 8) +: 8];
                                debug_c00_sum = debug_c00_sum + debug_c00_a_val_1 * debug_c00_b_val_1;
                                
                                debug_c00_a_val_2 = a_lat[((0 * 8 + 2) * 8) +: 8];
                                debug_c00_b_val_2 = b_lat[((2 * 8 + 0) * 8) +: 8];
                                debug_c00_sum = debug_c00_sum + debug_c00_a_val_2 * debug_c00_b_val_2;
                                
                                debug_c00_a_val_3 = a_lat[((0 * 8 + 3) * 8) +: 8];
                                debug_c00_b_val_3 = b_lat[((3 * 8 + 0) * 8) +: 8];
                                debug_c00_sum = debug_c00_sum + debug_c00_a_val_3 * debug_c00_b_val_3;
                                
                                debug_c00_a_val_4 = a_lat[((0 * 8 + 4) * 8) +: 8];
                                debug_c00_b_val_4 = b_lat[((4 * 8 + 0) * 8) +: 8];
                                debug_c00_sum = debug_c00_sum + debug_c00_a_val_4 * debug_c00_b_val_4;
                                
                                debug_c00_a_val_5 = a_lat[((0 * 8 + 5) * 8) +: 8];
                                debug_c00_b_val_5 = b_lat[((5 * 8 + 0) * 8) +: 8];
                                debug_c00_sum = debug_c00_sum + debug_c00_a_val_5 * debug_c00_b_val_5;
                                
                                debug_c00_a_val_6 = a_lat[((0 * 8 + 6) * 8) +: 8];
                                debug_c00_b_val_6 = b_lat[((6 * 8 + 0) * 8) +: 8];
                                debug_c00_sum = debug_c00_sum + debug_c00_a_val_6 * debug_c00_b_val_6;
                                
                                debug_c00_a_val_7 = a_lat[((0 * 8 + 7) * 8) +: 8];
                                debug_c00_b_val_7 = b_lat[((7 * 8 + 0) * 8) +: 8];
                                debug_c00_sum = debug_c00_sum + debug_c00_a_val_7 * debug_c00_b_val_7;
                            end
                        end
                    end
                    state <= ST_DONE;
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                    // 调试输出：在DONE状态打印c_flat的前32位
                    $display("[%0t] [TILE%0d] ST_DONE: c_flat[31:0]=%h", $time, TILE_ID, c_flat[31:0]);
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule