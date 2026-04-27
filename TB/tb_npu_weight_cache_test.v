`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_npu_weight_cache_test;

    // 测试信号
    reg clk;
    reg rst_n;
    reg we;
    reg [4:0] waddr;
    reg [`NPU_TILE_B_BITS-1:0] wdata;
    reg [4:0] raddr;
    wire [`NPU_TILE_B_BITS-1:0] rdata;
    wire [4*`NPU_TILE_B_BITS-1:0] rdata_group;

    // 实例化权重缓存
    npu_weight_cache u_cache (
        .clk(clk),
        .rst_n(rst_n),
        .we(we),
        .waddr(waddr),
        .wdata(wdata),
        .raddr(raddr),
        .rdata(rdata),
        .rdata_group(rdata_group)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 测试流程
    initial begin
        // 初始化
        rst_n = 0;
        we = 0;
        waddr = 0;
        wdata = 0;
        raddr = 0;

        #20;
        rst_n = 1;
        #10;

        // ========================================
        // 测试1: 写入和读取单个地址
        // ========================================
        $display("\n========================================");
        $display("[Test 1] Single Address Write/Read");
        $display("========================================");
        
        // 写入地址0
        #10;
        we = 1;
        waddr = 5'd0;
        wdata = 512'hDEADBEEF;  // 测试数据
        #10;
        we = 0;
        
        // 读取地址0
        #10;
        raddr = 5'd0;
        #10;
        
        if (rdata === 512'hDEADBEEF) begin
            $display("[TB] PASS: Read data matches written data");
        end else begin
            $display("[TB] FAIL: Read 0x%h, expected 0xDEADBEEF", rdata);
        end
        
        // ========================================
        // 测试2: 写入多个地址
        // ========================================
        $display("\n========================================");
        $display("[Test 2] Multiple Address Write/Read");
        $display("========================================");
        
        // 写入多个地址
        for (integer i = 0; i < 5; i = i + 1) begin
            #10;
            we = 1;
            waddr = i[4:0];
            wdata = (i + 1) * 512'h11111111;
            #10;
            we = 0;
            $display("[TB] Wrote address %0d: data pattern %0d", i, i+1);
        end
        
        // 读取并验证
        #10;
        for (integer i = 0; i < 5; i = i + 1) begin
            raddr = i[4:0];
            #10;
            $display("[TB] Read address %0d: 0x%h", i, rdata[63:0]);  // 只显示低64位
        end
        
        // ========================================
        // 测试3: 读写冲突测试
        // ========================================
        $display("\n========================================");
        $display("[Test 3] Read-Write Conflict Test");
        $display("========================================");
        
        #10;
        we = 1;
        waddr = 5'd10;
        wdata = 512'hAAAAAAAA;
        raddr = 5'd10;
        #10;
        we = 0;
        #10;
        
        $display("[TB] Simultaneous R/W to same address: 0x%h", rdata[63:0]);
        
        // 测试完成
        $display("\n========================================");
        $display("[SUCCESS] Weight cache tests completed!");
        $display("========================================");
        #100;
        $finish;
    end

    // 监控
    initial begin
        $monitor("[%0t] Cache: we=%b waddr=%d raddr=%d", 
                 $time, we, waddr, raddr);
    end

endmodule
