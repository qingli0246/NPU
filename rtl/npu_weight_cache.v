`timescale 1ns/1ps
`include "npu_defs.vh"

module npu_weight_cache (
    input  wire                                 clk,
    input  wire                                 rst_n,
    input  wire                                 we,
    input  wire [4:0]                           waddr,
    input  wire [`NPU_TILE_B_BITS-1:0]          wdata,
    
    // 单端口读取（用于权重共享模式）
    input  wire [4:0]                           raddr,
    output reg  [`NPU_TILE_B_BITS-1:0]          rdata,
    
    // 分组多端口读取（用于独立权重模式 - 优化版）
    // 将32个Tile分为4组，每组8个Tile共享一个读端口
    // 总宽度 = 4 * NPU_TILE_B_BITS = 4 * 512 = 2048 bits
    // 相比全独立端口的16384位，节省87.5%资源
    output wire [4*`NPU_TILE_B_BITS-1:0]        rdata_group,
    
    output reg  [`NPU_NUM_TILES-1:0]            valid_bits
);

    reg [`NPU_TILE_B_BITS-1:0] mem [0:`NPU_NUM_TILES-1];

    integer idx;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_bits <= {`NPU_NUM_TILES{1'b0}};
            rdata      <= {`NPU_TILE_B_BITS{1'b0}};
            for (idx = 0; idx < `NPU_NUM_TILES; idx = idx + 1) begin
                mem[idx] <= {`NPU_TILE_B_BITS{1'b0}};
            end
        end else begin
            if (we) begin
                mem[waddr] <= wdata;
                valid_bits[waddr] <= 1'b1;
            end
            rdata <= mem[raddr];
        end
    end
    
    // 分组多端口输出：4组×8Tile
    // rdata_group[group_id * 512 +: 512] 对应第group_id组的权重
    // 每组内的8个Tile共享相同的权重数据
    // 
    // 分组映射：
    // Group 0 (bits 0-511):     Tile[0-7]   共享 mem[0]
    // Group 1 (bits 512-1023):  Tile[8-15]  共享 mem[8]
    // Group 2 (bits 1024-1535): Tile[16-23] 共享 mem[16]
    // Group 3 (bits 1536-2047): Tile[24-31] 共享 mem[24]
    //
    // 注意：这种设计假设同组内的Tile使用相同权重
    // 如果需要更细粒度的控制，可以调整为8组×4Tile或16组×2Tile
    
    generate
        genvar g_i;
        for (g_i = 0; g_i < 4; g_i = g_i + 1) begin : gen_group_port
            // 每组选择该组第一个Tile的权重作为代表
            // 例如：Group 0 使用 mem[0]，Group 1 使用 mem[8]
            assign rdata_group[g_i * `NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] = mem[g_i * 8];
        end
    endgenerate

endmodule