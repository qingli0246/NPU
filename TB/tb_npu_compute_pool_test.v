`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_npu_compute_pool_test;

    // 时钟与复位
    reg clk;
    reg rst_n;
    reg clk_en;

    // Tile控制信号
    reg [`NPU_NUM_TILES-1:0] tile_start_mask;
    reg [`NPU_NUM_TILES-1:0] tile_clk_en_mask;

    // 配置接口
    reg [1:0] cfg_top_mode;
    reg [`NPU_NUM_TILES-1:0] cfg_group_master;
    reg [`NPU_NUM_TILES-1:0] cfg_h_link_en;
    reg [`NPU_NUM_TILES-1:0] cfg_v_link_en;

    // 输入数据总线
    reg [`NPU_NUM_TILES*`NPU_TILE_A_BITS-1:0] tile_a_bus;
    reg [`NPU_NUM_TILES*`NPU_TILE_B_BITS-1:0] tile_b_bus;

    // 输出结果总线
    wire [`NPU_NUM_TILES*`NPU_TILE_C_BITS-1:0] tile_c_bus;

    // 状态信号
    wire [`NPU_NUM_TILES-1:0] tile_busy_mask;
    wire [`NPU_NUM_TILES-1:0] tile_done_mask;
    wire pool_busy;
    wire pool_done;
    wire merge_link_active;
    wire split_link_active;
    wire indep_link_active;

    // 实例化compute_pool
    npu_compute_pool u_compute_pool (
        .clk(clk),
        .rst_n(rst_n),
        .clk_en(clk_en),
        .tile_start_mask(tile_start_mask),
        .tile_clk_en_mask(tile_clk_en_mask),
        .cfg_top_mode(cfg_top_mode),
        .cfg_group_master(cfg_group_master),
        .cfg_h_link_en(cfg_h_link_en),
        .cfg_v_link_en(cfg_v_link_en),
        .tile_a_bus(tile_a_bus),
        .tile_b_bus(tile_b_bus),
        .tile_c_bus(tile_c_bus),
        .tile_busy_mask(tile_busy_mask),
        .tile_done_mask(tile_done_mask),
        .pool_busy(pool_busy),
        .pool_done(pool_done),
        .merge_link_active(merge_link_active),
        .split_link_active(split_link_active),
        .indep_link_active(indep_link_active)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 生成VCD波形文件
    initial begin
        $dumpfile("TB/compute_pool_test.vcd");
        $dumpvars(0, tb_npu_compute_pool_test);
    end

    // 监控关键信号
    initial begin
        integer cycle_count;
        cycle_count = 0;
        forever begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (cycle_count % 50 == 0) begin
                $display("[%0t] Cycle %0d: pool_busy=%b pool_done=%b mode=%d", 
                         $time, cycle_count, pool_busy, pool_done, cfg_top_mode);
            end
        end
    end

    // 测试流程
    initial begin
        // 初始化
        rst_n = 0;
        clk_en = 1;
        tile_start_mask = 0;
        tile_clk_en_mask = {`NPU_NUM_TILES{1'b1}};
        cfg_top_mode = `NPU_MODE_INDEP;
        cfg_group_master = {`NPU_NUM_TILES{1'b1}};
        cfg_h_link_en = 0;
        cfg_v_link_en = 0;
        tile_a_bus = 0;
        tile_b_bus = 0;

        $display("\n========================================");
        $display("[Test] NPU Compute Pool Test");
        $display("========================================");
        
        #20;
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        #10;

        // ========================================
        // 测试1: INDEP模式 - 启动单个Tile
        // ========================================
        $display("\n========================================");
        $display("[Test 1] INDEP Mode - Single Tile");
        $display("========================================");
        
        // 准备Tile#0的输入数据
        tile_a_bus[0*`NPU_TILE_A_BITS +: `NPU_TILE_A_BITS] = {`NPU_TILE_A_BITS{1'b1}};
        tile_b_bus[0*`NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] = {`NPU_TILE_B_BITS{1'b1}};
        
        $display("[%0t] Starting Tile #0 in INDEP mode", $time);
        
        // 启动Tile#0
        tile_start_mask[0] = 1;
        @(posedge clk);
        tile_start_mask[0] = 0;
        
        // 等待Tile完成
        wait(tile_done_mask[0] == 1);
        $display("[%0t] Tile #0 completed! Result C[0]=0x%h", $time, 
                 tile_c_bus[0*`NPU_TILE_C_BITS +: `NPU_TILE_C_BITS]);
        
        #50;

        // ========================================
        // 测试2: INDEP模式 - 启动多个Tile
        // ========================================
        $display("\n========================================");
        $display("[Test 2] INDEP Mode - Multiple Tiles");
        $display("========================================");
        
        // 准备Tile#0, #1, #2的数据
        tile_a_bus[0*`NPU_TILE_A_BITS +: `NPU_TILE_A_BITS] = {8{1'b1}};
        tile_b_bus[0*`NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] = {8{1'b1}};
        tile_a_bus[1*`NPU_TILE_A_BITS +: `NPU_TILE_A_BITS] = {16{1'b1}};
        tile_b_bus[1*`NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] = {16{1'b1}};
        tile_a_bus[2*`NPU_TILE_A_BITS +: `NPU_TILE_A_BITS] = {24{1'b1}};
        tile_b_bus[2*`NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] = {24{1'b1}};
        
        $display("[%0t] Starting Tiles #0, #1, #2 simultaneously", $time);
        
        // 同时启动3个Tile
        tile_start_mask[2:0] = 3'b111;
        @(posedge clk);
        tile_start_mask[2:0] = 3'b000;
        
        // 等待所有Tile完成
        wait(&tile_done_mask[2:0] == 1'b1);
        $display("[%0t] All tiles completed!", $time);
        for (integer i = 0; i < 3; i = i + 1) begin
            $display("[%0t]   Tile #%d result: C=0x%h", $time, i,
                     tile_c_bus[i*`NPU_TILE_C_BITS +: `NPU_TILE_C_BITS]);
        end
        
        #50;

        // ========================================
        // 测试3: MERGE模式 - 2个Tile横向级联
        // ========================================
        $display("\n========================================");
        $display("[Test 3] MERGE Mode - Horizontal Cascade");
        $display("========================================");
        
        // 重置系统
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;
        
        // 配置MERGE模式，启用Tile#0和#1的横向链路
        cfg_top_mode = `NPU_MODE_MERGE;
        cfg_h_link_en[1] = 1;  // Tile#1从左侧接收数据
        cfg_group_master[0] = 1;  // Tile#0为主Tile
        cfg_group_master[1] = 0;  // Tile#1为从Tile
        
        // 准备输入数据
        tile_a_bus[0*`NPU_TILE_A_BITS +: `NPU_TILE_A_BITS] = {`NPU_TILE_A_BITS{1'b1}};
        tile_b_bus[0*`NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] = {`NPU_TILE_B_BITS{1'b1}};
        tile_a_bus[1*`NPU_TILE_A_BITS +: `NPU_TILE_A_BITS] = {`NPU_TILE_A_BITS{1'b0}};  // 从Tile不需要A输入
        tile_b_bus[1*`NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] = {`NPU_TILE_B_BITS{1'b0}};  // 从Tile不需要B输入
        
        $display("[%0t] Starting MERGE mode with Tile #0 and #1", $time);
        
        // 启动主Tile和从Tile（两者都需要start信号）
        tile_start_mask[1:0] = 2'b11;
        @(posedge clk);
        tile_start_mask[1:0] = 2'b00;
        
        // 等待完成
        fork
            begin
                wait(tile_done_mask[0] == 1 && tile_done_mask[1] == 1);
                $display("[%0t] MERGE mode completed!", $time);
                $display("[%0t]   Tile #0 result: C=0x%h", $time,
                         tile_c_bus[0*`NPU_TILE_C_BITS +: `NPU_TILE_C_BITS]);
                $display("[%0t]   Tile #1 result: C=0x%h", $time,
                         tile_c_bus[1*`NPU_TILE_C_BITS +: `NPU_TILE_C_BITS]);
            end
            begin
                #10000;
                $display("[%0t] ERROR: Timeout waiting for MERGE completion!", $time);
                $finish;
            end
        join_any
        disable fork;
        
        #50;

        // 测试完成
        $display("\n========================================");
        $display("[SUCCESS] Compute pool tests completed!");
        $display("========================================");
        $display("[TB] VCD file: TB/compute_pool_test.vcd");
        $display("[TB] Use 'gtkwave TB/compute_pool_test.vcd' to view waveforms");
        #100;
        $finish;
    end

endmodule
