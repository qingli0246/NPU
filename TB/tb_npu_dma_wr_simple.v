`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_npu_dma_wr_simple;

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
    reg cmd_ready;
    reg rsp_valid;
    reg [31:0] rsp_rdata;
    
    // 内部信号（用于波形查看）
    wire [2:0] state;
    wire [15:0] wr_cnt;

    // 实例化DMA写模块（添加内部信号暴露）
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
        .cmd_ready(cmd_ready),
        .rsp_valid(rsp_valid),
        .rsp_rdata(rsp_rdata)
    );
    
    // 通过层次化引用获取内部信号
    assign state = u_dma_wr.state_out;
    assign wr_cnt = u_dma_wr.wr_cnt_out;

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 生成VCD波形文件
    initial begin
        $dumpfile("TB/dma_wr_simple.vcd");
        $dumpvars(0, tb_npu_dma_wr_simple);
    end

    // 测试流程
    initial begin
        // 初始化
        rst_n = 0;
        start = 0;
        base_addr = 32'h00002000;
        word_count = 16'd4;
        data_in = 0;
        data_in_valid = 0;
        cmd_ready = 1;
        rsp_valid = 0;
        rsp_rdata = 0;

        $display("\n========================================");
        $display("[Test] DMA Write Complete Test");
        $display("========================================");
        $display("[%0t] Test started", $time);
        
        #20;
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        #10;

        // 启动DMA写
        @(posedge clk);
        start = 1;
        repeat(2) @(posedge clk);
        start = 0;
        
        $display("[%0t] DMA write started: addr=0x%h, words=%d", $time, base_addr, word_count);
        
        // 等待DMA进入忙碌状态
        wait(busy == 1);
        $display("[%0t] DMA is busy, state=%d", $time, state);
        
        // 连续传输4个字
        for (integer i = 0; i < 4; i = i + 1) begin
            $display("[%0t] --- Transferring word %0d ---", $time, i);
            
            // 步骤1: 提供新数据
            data_in = (i + 1) * 32'hAABBCCDD;
            data_in_valid = 1;
            $display("[%0t] Data presented for word %0d: 0x%h", $time, i, data_in);
            
            // 步骤2: 等待DMA确认（握手完成）
            wait(data_in_ready == 1);
            @(posedge clk);
            $display("[%0t] Word %0d handshake complete: state=%d", $time, i, state);
            
            // 步骤3: 清除有效信号（保持一个时钟周期后清除）
            @(posedge clk);
            data_in_valid = 0;
            data_in = 0;
            $display("[%0t] Data cleared for word %0d", $time, i);
            
            // 步骤4: 等待DMA发送AXI命令并进入ST_WAIT
            // 在ST_WAIT状态，data_in_ready会被清除为0
            wait(data_in_ready == 0);
            $display("[%0t] DMA entered ST_WAIT for word %0d", $time, i);
            
            // 步骤5: 发送AXI响应（保持足够长时间让DMA检测）
            #10;
            rsp_valid = 1;
            repeat(2) @(posedge clk);  // 保持2个时钟周期
            rsp_valid = 0;
            $display("[%0t] Response sent for word %0d", $time, i);
            
            // 步骤6: 等待DMA回到ST_CMD并准备好接收下一个字
            if (i < 3) begin  // 最后一个字不需要等待
                wait(data_in_ready == 1);
                $display("[%0t] DMA ready for next word", $time);
            end
            
            #5;
        end
        
        // 等待DMA完成
        wait(done == 1);
        $display("[%0t] DMA write completed! Final state=%d", $time, state);
        
        $display("\n========================================");
        $display("[SUCCESS] DMA write test passed!");
        $display("========================================");
        $display("[TB] VCD file: TB/dma_wr_simple.vcd");
        $display("[TB] Use 'gtkwave TB/dma_wr_simple.vcd' to view waveforms");
        #100;
        $finish;
    end

endmodule
