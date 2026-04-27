`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_npu_dma_wr_test;

    // 测试信号
    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;
    reg [31:0] base_addr;
    reg [15:0] word_count;
    reg [31:0] data_in;
    reg data_in_valid;
    wire data_in_ready;
    
    // 内部总线接口
    wire cmd_valid;
    wire cmd_write;
    wire [31:0] cmd_addr;
    wire [31:0] cmd_wdata;
    wire [3:0] cmd_wstrb;
    reg cmd_ready;
    reg rsp_valid;
    reg [31:0] rsp_rdata;

    // 实例化DMA写模块
    npu_dma_wr u_dma_wr (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .base_addr(base_addr),
        .word_count(word_count),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .data_in_ready(data_in_ready),
        .busy(busy),
        .done(done),
        .cmd_valid(cmd_valid),
        .cmd_write(cmd_write),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_wstrb(cmd_wstrb),
        .cmd_ready(cmd_ready),
        .rsp_valid(rsp_valid),
        .rsp_rdata(rsp_rdata)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 生成VCD波形文件
    initial begin
        $dumpfile("TB/dma_wr_test.vcd");
        $dumpvars(0, tb_npu_dma_wr_test);
    end

    // 监控信号变化（每10个时钟周期打印一次）
    initial begin
        integer cycle_count;
        cycle_count = 0;
        forever begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (cycle_count % 10 == 0) begin
                $display("[%0t] Cycle %0d: state=%d busy=%b done=%b data_valid=%b data_ready=%b cmd_valid=%b rsp_valid=%b",
                         $time, cycle_count, u_dma_wr.state, busy, done, data_in_valid, data_in_ready, cmd_valid, rsp_valid);
            end
        end
    end

    // 传输一个字到DMA写模块
    task transfer_word;
        input [31:0] word_data;
        input integer word_idx;
        begin
            $display("[TB] --- Transferring word %0d ---", word_idx);
            $display("[TB] Before: data_valid=%b data_ready=%b state=%d", 
                     data_in_valid, data_in_ready, u_dma_wr.state);
            
            // 步骤1: 提供数据
            data_in = word_data;
            data_in_valid = 1;
            $display("[TB] Data presented: 0x%h", word_data);
            
            // 步骤2: 等待DMA确认接收
            wait(data_in_ready == 1);
            $display("[TB] Word %0d accepted: 0x%h", word_idx, word_data);
            
            // 步骤3: 保持一个时钟周期
            @(posedge clk);
            data_in_valid = 0;
            data_in = 0;
            $display("[TB] Data cleared, state=%d", u_dma_wr.state);
            
            // 步骤4: 发送AXI响应（告诉DMA写操作完成）
            #15;
            rsp_valid = 1;
            @(posedge clk);
            rsp_valid = 0;
            $display("[TB] Response sent for word %0d, state=%d", word_idx, u_dma_wr.state);
            
            // 步骤5: 等待一小段时间让DMA进入下一个状态
            #10;
        end
    endtask

    // 测试流程
    initial begin
        // 初始化
        rst_n = 0;
        start = 0;
        base_addr = 32'h00002000;
        word_count = 16'd4;
        data_in = 0;
        data_in_valid = 0;
        cmd_ready = 1;  // 始终准备好接收AXI命令
        rsp_valid = 0;
        rsp_rdata = 0;

        #20;
        rst_n = 1;
        #10;

        // ========================================
        // 测试1: 基本写入操作
        // ========================================
        $display("\n========================================");
        $display("[Test 1] Basic Write Operation");
        $display("========================================");
        
        $display("[TB] Starting DMA write: addr=0x%h, words=%d", base_addr, word_count);
        
        // 启动DMA写 - 修正时序，确保start信号至少保持一个完整的时钟周期
        @(posedge clk);
        start = 1;
        $display("[TB] Start asserted at time %0t", $time);
        @(posedge clk);
        @(posedge clk);  // 保持两个时钟周期
        start = 0;
        $display("[TB] Start deasserted at time %0t", $time);
        
        $display("[TB] Start pulse sent, waiting for busy...");
        
        // 等待DMA进入忙碌状态（设置超时）
        fork
            begin
                wait(busy == 1);
                $display("[TB] DMA is busy, state=%d", u_dma_wr.state);
            end
            begin
                #1000;
                $display("[TB] ERROR: Timeout waiting for busy!");
                $display("[TB] Current state: %d", u_dma_wr.state);
                $finish;
            end
        join_any
        disable fork;
        
        if (busy) begin
            $display("[TB] Starting transfers...");
            
            // 传输4个字
            transfer_word(32'hAABBCCDD, 0);
            transfer_word(32'h557799BB, 1);
            transfer_word(32'h00336699, 2);
            transfer_word(32'hAAEEFF00, 3);
            
            // 等待DMA完成
            fork
                begin
                    wait(done == 1);
                    $display("[TB] DMA write completed successfully!");
                end
                begin
                    #1000;
                    $display("[TB] ERROR: Timeout waiting for done!");
                    $finish;
                end
            join_any
            disable fork;
        end
        
        // ========================================
        // 测试2: 测试2个字
        // ========================================
        $display("\n========================================");
        $display("[Test 2] Two Words Test");
        $display("========================================");
        
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;
        
        word_count = 16'd2;
        
        @(posedge clk);
        start = 1;
        @(posedge clk);
        @(posedge clk);
        start = 0;
        
        fork
            wait(busy == 1);
            begin
                #500;
                $display("[TB] ERROR: Timeout in Test 2!");
                $finish;
            end
        join_any
        disable fork;
        
        transfer_word(32'h11223344, 0);
        transfer_word(32'h55667788, 1);
        
        fork
            wait(done == 1);
            begin
                #500;
                $display("[TB] ERROR: Timeout in Test 2 done!");
                $finish;
            end
        join_any
        disable fork;
        $display("[TB] DMA write completed successfully!");
        
        // 测试完成
        $display("\n========================================");
        $display("[SUCCESS] DMA write tests completed!");
        $display("========================================");
        $display("[TB] VCD file generated: TB/dma_wr_test.vcd");
        $display("[TB] Use 'gtkwave TB/dma_wr_test.vcd' to view waveforms");
        #100;
        $finish;
    end

endmodule
