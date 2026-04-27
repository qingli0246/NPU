`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_npu_dma_rd_test;

    // 测试信号
    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;
    reg [31:0] base_addr;
    reg [15:0] word_count;
    
    // 内部总线接口
    wire cmd_valid;
    wire cmd_write;
    wire [31:0] cmd_addr;
    wire [31:0] cmd_wdata;
    wire [3:0] cmd_wstrb;
    reg cmd_ready;
    reg rsp_valid;
    reg [31:0] rsp_rdata;
    wire data_valid;
    wire [31:0] data_word;
    wire [15:0] data_index;

    // 实例化DMA读模块
    npu_dma_rd u_dma_rd (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .base_addr(base_addr),
        .word_count(word_count),
        .busy(busy),
        .done(done),
        .cmd_valid(cmd_valid),
        .cmd_write(cmd_write),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_wstrb(cmd_wstrb),
        .cmd_ready(cmd_ready),
        .rsp_valid(rsp_valid),
        .rsp_rdata(rsp_rdata),
        .data_valid(data_valid),
        .data_word(data_word),
        .data_index(data_index)
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
        start = 0;
        base_addr = 32'h00001000;
        word_count = 16'd4;
        cmd_ready = 0;
        rsp_valid = 0;
        rsp_rdata = 0;

        #20;
        rst_n = 1;
        #10;

        // ========================================
        // 测试1: 基本读取操作
        // ========================================
        $display("\n========================================");
        $display("[Test 1] Basic Read Operation");
        $display("========================================");
        
        $display("[TB] Starting DMA read: addr=0x%h, words=%d", base_addr, word_count);
        
        // 启动DMA读
        #10;
        start = 1;
        #10;
        start = 0;
        
        // 为每个字重复命令-响应循环
        for (integer i = 0; i < 4; i = i + 1) begin
            wait_for_cmd();
            cmd_ready = 1;
            #10;
            cmd_ready = 0;
            
            #20;
            rsp_valid = 1;
            rsp_rdata = (i + 1) * 32'hDEADBEEF;
            #10;
            rsp_valid = 0;
            
            $display("[TB] Transfer %0d: data=0x%h", i, rsp_rdata);
        end
        
        // 等待DMA完成
        wait_for_dma_done();
        
        // ========================================
        // 测试2: 多次读取
        // ========================================
        $display("\n========================================");
        $display("[Test 2] Multiple Read Operations");
        $display("========================================");
        
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;
        
        word_count = 16'd3;
        #10;
        start = 1;
        #10;
        start = 0;
        
        // 响应3次命令
        for (integer i = 0; i < 3; i = i + 1) begin
            wait_for_cmd();
            cmd_ready = 1;
            #10;
            cmd_ready = 0;
            
            #20;
            rsp_valid = 1;
            rsp_rdata = (i + 1) * 32'h11111111;
            #10;
            rsp_valid = 0;
            
            $display("[TB] Transfer %0d: data=0x%h", i, rsp_rdata);
        end
        
        wait_for_dma_done();
        
        // 测试完成
        $display("\n========================================");
        $display("[SUCCESS] DMA read tests completed!");
        $display("========================================");
        #100;
        $finish;
    end

    // 等待命令
    task wait_for_cmd;
        begin
            while (!cmd_valid) begin
                @(posedge clk);
            end
            $display("[TB] Command valid detected");
        end
    endtask

    // 等待DMA完成
    task wait_for_dma_done;
        integer timeout;
        begin
            timeout = 0;
            while (!done && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            if (done) begin
                $display("[TB] DMA read completed after %0d cycles", timeout);
            end else begin
                $display("[TB] ERROR: Timeout waiting for DMA done!");
            end
        end
    endtask

    // 监控
    initial begin
        $monitor("[%0t] DMA_RD: busy=%b done=%b cmd_valid=%b data_valid=%b", 
                 $time, busy, done, cmd_valid, data_valid);
    end

endmodule
