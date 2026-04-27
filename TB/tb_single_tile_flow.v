`timescale 1ns/1ps
`include "npu_defs.vh"

// ============================================================
// 单Tile完整流程测试 - 极简版
// 直接实例化单个Tile，绕过compute_pool和复杂顶层
// ============================================================
module tb_single_tile_flow;

    reg clk;
    reg rst_n;
    
    // Tile接口
    wire [511:0] a_flat;   // 512位 = 64字节 (8x8矩阵)
    wire [511:0] b_flat;   // 512位 = 64字节 (8x8矩阵)
    wire [1023:0] c_flat;  // 1024位 = 128字节 (8x8结果，每个元素16bit)
    wire tile_busy;
    wire tile_done;
    
    // 实例化单个Tile
    npu_tile #(.TILE_ID(0)) u_tile (
        .clk       (clk),
        .rst_n     (rst_n),
        .clk_en    (1'b1),
        .start     (tile_start),
        .top_mode  (`NPU_MODE_INDEP),
        .is_master (1'b1),
        .a_flat    (a_flat),
        .b_flat    (b_flat),
        .a_left_i  (64'd0),
        .b_top_i   (64'd0),
        .a_right_o (),
        .b_down_o  (),
        .busy      (tile_busy),
        .done      (tile_done),
        .c_flat    (c_flat)
    );
    
    reg tile_start;
    reg [511:0] a_data, b_data;  // 修正为512位，匹配Tile端口
    integer i;  // 用于数据初始化的循环变量
    
    // 将测试数据连接到Tile输入端口
    assign a_flat = a_data;
    assign b_flat = b_data;
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 测试序列
    initial begin
        rst_n = 0;
        tile_start = 0;
        a_data = 0;
        b_data = 0;
        
        #20;
        rst_n = 1;
        #10;
        
        $display("[%0t] === 开始单Tile测试 ===", $time);
        
        // 准备A矩阵数据（8x8矩阵，64个元素，每个元素8bit）
        // A[i][j] = i*8 + j + 1 （行优先存储）
        // 第0行: 1,2,3,4,5,6,7,8
        a_data[7:0]   = 8'd1;  a_data[15:8]  = 8'd2;  a_data[23:16] = 8'd3;  a_data[31:24] = 8'd4;
        a_data[39:32] = 8'd5;  a_data[47:40] = 8'd6;  a_data[55:48] = 8'd7;  a_data[63:56] = 8'd8;
        // 第1行: 9,10,11,12,13,14,15,16
        a_data[71:64]  = 8'd9;  a_data[79:72]  = 8'd10; a_data[87:80]  = 8'd11; a_data[95:88]  = 8'd12;
        a_data[103:96] = 8'd13; a_data[111:104]= 8'd14; a_data[119:112]= 8'd15; a_data[127:120]= 8'd16;
        // 第2-7行：简化为递增序列
        for (i = 16; i < 64; i = i + 1) begin
            a_data[i*8+7 -:8] = i + 1;
        end
        
        // 准备B矩阵数据（8x8单位矩阵）
        // B[i][j] = 1 if i==j else 0
        // 行优先存储：每行8个元素，每元素8bit
        b_data = 0;
        b_data[7:0]    = 8'd1;  // B[0][0] = 1 (第0行第0列)
        b_data[15:8]   = 8'd0;  // B[0][1] = 0
        b_data[23:16]  = 8'd0;  // B[0][2] = 0
        b_data[31:24]  = 8'd0;  // B[0][3] = 0
        b_data[39:32]  = 8'd0;  // B[0][4] = 0
        b_data[47:40]  = 8'd0;  // B[0][5] = 0
        b_data[55:48]  = 8'd0;  // B[0][6] = 0
        b_data[63:56]  = 8'd0;  // B[0][7] = 0
        
        b_data[71:64]  = 8'd0;  // B[1][0] = 0
        b_data[79:72]  = 8'd1;  // B[1][1] = 1 (第1行第1列)
        b_data[87:80]  = 8'd0;  // B[1][2] = 0
        b_data[95:88]  = 8'd0;  // B[1][3] = 0
        b_data[103:96] = 8'd0;  // B[1][4] = 0
        b_data[111:104]= 8'd0;  // B[1][5] = 0
        b_data[119:112]= 8'd0;  // B[1][6] = 0
        b_data[127:120]= 8'd0;  // B[1][7] = 0
        
        b_data[135:128]= 8'd0;  // B[2][0] = 0
        b_data[143:136]= 8'd0;  // B[2][1] = 0
        b_data[151:144]= 8'd1;  // B[2][2] = 1 (第2行第2列)
        b_data[159:152]= 8'd0;  // B[2][3] = 0
        b_data[167:160]= 8'd0;  // B[2][4] = 0
        b_data[175:168]= 8'd0;  // B[2][5] = 0
        b_data[183:176]= 8'd0;  // B[2][6] = 0
        b_data[191:184]= 8'd0;  // B[2][7] = 0
        
        b_data[199:192]= 8'd0;  // B[3][0] = 0
        b_data[207:200]= 8'd0;  // B[3][1] = 0
        b_data[215:208]= 8'd0;  // B[3][2] = 0
        b_data[223:216]= 8'd1;  // B[3][3] = 1 (第3行第3列)
        b_data[231:224]= 8'd0;  // B[3][4] = 0
        b_data[239:232]= 8'd0;  // B[3][5] = 0
        b_data[247:240]= 8'd0;  // B[3][6] = 0
        b_data[255:248]= 8'd0;  // B[3][7] = 0
        
        b_data[263:256]= 8'd0;  // B[4][0] = 0
        b_data[271:264]= 8'd0;  // B[4][1] = 0
        b_data[279:272]= 8'd0;  // B[4][2] = 0
        b_data[287:280]= 8'd0;  // B[4][3] = 0
        b_data[295:288]= 8'd1;  // B[4][4] = 1 (第4行第4列)
        b_data[303:296]= 8'd0;  // B[4][5] = 0
        b_data[311:304]= 8'd0;  // B[4][6] = 0
        b_data[319:312]= 8'd0;  // B[4][7] = 0
        
        b_data[327:320]= 8'd0;  // B[5][0] = 0
        b_data[335:328]= 8'd0;  // B[5][1] = 0
        b_data[343:336]= 8'd0;  // B[5][2] = 0
        b_data[351:344]= 8'd0;  // B[5][3] = 0
        b_data[359:352]= 8'd0;  // B[5][4] = 0
        b_data[367:360]= 8'd1;  // B[5][5] = 1 (第5行第5列)
        b_data[375:368]= 8'd0;  // B[5][6] = 0
        b_data[383:376]= 8'd0;  // B[5][7] = 0
        
        b_data[391:384]= 8'd0;  // B[6][0] = 0
        b_data[399:392]= 8'd0;  // B[6][1] = 0
        b_data[407:400]= 8'd0;  // B[6][2] = 0
        b_data[415:408]= 8'd0;  // B[6][3] = 0
        b_data[423:416]= 8'd0;  // B[6][4] = 0
        b_data[431:424]= 8'd0;  // B[6][5] = 0
        b_data[439:432]= 8'd1;  // B[6][6] = 1 (第6行第6列)
        b_data[447:440]= 8'd0;  // B[6][7] = 0
        
        b_data[455:448]= 8'd0;  // B[7][0] = 0
        b_data[463:456]= 8'd0;  // B[7][1] = 0
        b_data[471:464]= 8'd0;  // B[7][2] = 0
        b_data[479:472]= 8'd0;  // B[7][3] = 0
        b_data[487:480]= 8'd0;  // B[7][4] = 0
        b_data[495:488]= 8'd0;  // B[7][5] = 0
        b_data[503:496]= 8'd0;  // B[7][6] = 0
        b_data[511:504]= 8'd1;  // B[7][7] = 1 (第7行第7列)
        
        // 启动Tile
        tile_start = 1;
        @(posedge clk);
        @(posedge clk);
        tile_start = 0;
        
        // 等待完成
        wait(tile_done);
        
        $display("[%0t] === Tile计算完成！===", $time);
        $display("C[0][0] = %d (期望: 1)", c_flat[15:0]);
        
        // 添加调试输出：打印B矩阵的关键位置
        $display("\n=== B矩阵调试信息 ===");
        $display("B[0][0] = %d (b_data[7:0])", b_data[7:0]);
        $display("B[1][0] = %d (b_data[63:56])", b_data[63:56]);
        $display("B[0][1] = %d (b_data[15:8])", b_data[15:8]);
        $display("B[1][1] = %d (b_data[71:64])", b_data[71:64]);
        
        // 打印A矩阵的前几个元素
        $display("\n=== A矩阵调试信息 ===");
        $display("A[0][0] = %d (a_data[7:0])", a_data[7:0]);
        $display("A[0][1] = %d (a_data[15:8])", a_data[15:8]);
        $display("A[1][0] = %d (a_data[71:64])", a_data[71:64]);
        
        // 添加十六进制显示
        $display("\n=== 十六进制格式 ===");
        $display("A[0][0] = 0x%h (期望: 0x01)", a_data[7:0]);
        $display("B[0][0] = 0x%h (期望: 0x01)", b_data[7:0]);
        $display("a_data[63:56] = 0x%h (这是A[0][7]，期望: 0x08)", a_data[63:56]);
        
        #100;
        $finish;
    end
    
    // VCD波形输出
    initial begin
        $dumpfile("TB/single_tile_flow.vcd");
        $dumpvars(0, tb_single_tile_flow);
    end
    
endmodule
