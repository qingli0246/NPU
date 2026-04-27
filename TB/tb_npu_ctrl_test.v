`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_npu_ctrl_test;

    // 时钟与复位
    reg clk;
    reg rst_n;

    // 配置接口
    reg cfg_start_pulse;
    reg [1:0] cfg_mode;
    reg cfg_b_static;
    reg cfg_b_independent;
    reg [4:0] cfg_tile_mask_lo;
    reg [4:0] cfg_tile_mask_hi;
    reg [31:0] cfg_a_base;
    reg [31:0] cfg_b_base;
    reg [31:0] cfg_c_base;
    reg [31:0] cfg_matrix_m;
    reg [31:0] cfg_matrix_n;
    reg [31:0] cfg_matrix_k;

    // 子模块状态反馈
    reg pool_busy;
    reg pool_done;
    reg rd_busy;
    reg rd_done;
    reg wr_busy;
    reg wr_done;

    // 控制器输出
    wire [`NPU_NUM_TILES-1:0] pool_tile_start_mask;
    wire [`NPU_NUM_TILES-1:0] pool_tile_clk_en_mask;
    wire [1:0] pool_mode;
    wire rd_start;
    wire wr_start;
    wire [31:0] rd_base_addr;
    wire [31:0] wr_base_addr;
    wire [15:0] rd_word_count;
    wire [15:0] wr_word_count;
    wire cache_we;
    wire [4:0] cache_waddr;
    wire [`NPU_TILE_B_BITS-1:0] cache_wdata;
    wire global_busy;
    wire global_done;
    wire global_error;
    wire [3:0] global_state;

    // 实例化控制器
    npu_ctrl u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_start_pulse(cfg_start_pulse),
        .cfg_mode(cfg_mode),
        .cfg_b_static(cfg_b_static),
        .cfg_b_independent(cfg_b_independent),
        .cfg_tile_mask_lo(cfg_tile_mask_lo),
        .cfg_tile_mask_hi(cfg_tile_mask_hi),
        .cfg_a_base(cfg_a_base),
        .cfg_b_base(cfg_b_base),
        .cfg_c_base(cfg_c_base),
        .cfg_matrix_m(cfg_matrix_m),
        .cfg_matrix_n(cfg_matrix_n),
        .cfg_matrix_k(cfg_matrix_k),
        .pool_busy(pool_busy),
        .pool_done(pool_done),
        .rd_busy(rd_busy),
        .rd_done(rd_done),
        .wr_busy(wr_busy),
        .wr_done(wr_done),
        .pool_tile_start_mask(pool_tile_start_mask),
        .pool_tile_clk_en_mask(pool_tile_clk_en_mask),
        .pool_mode(pool_mode),
        .rd_start(rd_start),
        .wr_start(wr_start),
        .rd_base_addr(rd_base_addr),
        .wr_base_addr(wr_base_addr),
        .rd_word_count(rd_word_count),
        .wr_word_count(wr_word_count),
        .cache_we(cache_we),
        .cache_waddr(cache_waddr),
        .cache_wdata(cache_wdata),
        .global_busy(global_busy),
        .global_done(global_done),
        .global_error(global_error),
        .global_state(global_state)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 生成VCD波形文件
    initial begin
        $dumpfile("TB/ctrl_test.vcd");
        $dumpvars(0, tb_npu_ctrl_test);
    end

    // 监控状态机变化和关键信号
    integer prev_state;
    initial begin
        prev_state = -1;
        forever begin
            @(posedge clk);
            if (global_state !== prev_state) begin
                case (global_state)
                    `NPU_ST_IDLE:  $display("[%0t] State: IDLE", $time);
                    `NPU_ST_CFG:   $display("[%0t] State: CFG", $time);
                    `NPU_ST_LOAD:  $display("[%0t] State: LOAD", $time);
                    `NPU_ST_RUN:   $display("[%0t] State: RUN", $time);
                    `NPU_ST_STORE: $display("[%0t] State: STORE", $time);
                    `NPU_ST_DONE:  $display("[%0t] State: DONE", $time);
                    `NPU_ST_ERROR: $display("[%0t] State: ERROR", $time);
                    default:       $display("[%0t] State: UNKNOWN(%d)", $time, global_state);
                endcase
                prev_state = global_state;
            end
            
            // 在LOAD状态时打印详细信息
            if (global_state == `NPU_ST_LOAD) begin
                $display("[%0t]   LOAD: rd_start=%b rd_busy=%b rd_done=%b a_load_done=%b b_static=%b", 
                         $time, rd_start, rd_busy, rd_done, u_ctrl.a_load_done_flag, u_ctrl.b_matrix_static);
            end
        end
    end

    // 模拟DMA读模块行为（使用计数器而非延迟）
    reg [7:0] rd_delay_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_busy <= 0;
            rd_done <= 0;
            rd_delay_counter <= 0;
        end else begin
            if (rd_start && !rd_busy) begin
                // DMA启动
                rd_busy <= 1;
                rd_done <= 0;
                rd_delay_counter <= 8'd10;  // 10个时钟周期延迟
            end else if (rd_busy) begin
                if (rd_delay_counter > 0) begin
                    rd_delay_counter <= rd_delay_counter - 1;
                end else begin
                    // 延迟结束，产生完成信号
                    rd_busy <= 0;
                    rd_done <= 1;
                end
            end else begin
                rd_done <= 0;
            end
        end
    end

    // 模拟DMA写模块行为（使用计数器）
    reg [7:0] wr_delay_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_busy <= 0;
            wr_done <= 0;
            wr_delay_counter <= 0;
        end else begin
            if (wr_start && !wr_busy) begin
                wr_busy <= 1;
                wr_done <= 0;
                wr_delay_counter <= 8'd10;
            end else if (wr_busy) begin
                if (wr_delay_counter > 0) begin
                    wr_delay_counter <= wr_delay_counter - 1;
                end else begin
                    wr_busy <= 0;
                    wr_done <= 1;
                end
            end else begin
                wr_done <= 0;
            end
        end
    end

    // 模拟计算池行为（使用计数器）
    reg [7:0] pool_delay_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool_busy <= 0;
            pool_done <= 0;
            pool_delay_counter <= 0;
        end else begin
            if (|pool_tile_start_mask && !pool_busy) begin
                pool_busy <= 1;
                pool_done <= 0;
                pool_delay_counter <= 8'd20;
            end else if (pool_busy) begin
                if (pool_delay_counter > 0) begin
                    pool_delay_counter <= pool_delay_counter - 1;
                end else begin
                    pool_busy <= 0;
                    pool_done <= 1;
                end
            end else begin
                pool_done <= 0;
            end
        end
    end

    // 测试流程
    initial begin
        // 初始化
        rst_n = 0;
        cfg_start_pulse = 0;
        cfg_mode = `NPU_MODE_INDEP;
        cfg_b_static = 0;
        cfg_b_independent = 0;
        cfg_tile_mask_lo = 5'h1F;
        cfg_tile_mask_hi = 5'h1F;
        cfg_a_base = 32'h00001000;
        cfg_b_base = 32'h00002000;
        cfg_c_base = 32'h00003000;
        cfg_matrix_m = 8;
        cfg_matrix_n = 8;
        cfg_matrix_k = 8;
        
        pool_busy = 0;
        pool_done = 0;
        rd_busy = 0;
        rd_done = 0;
        wr_busy = 0;
        wr_done = 0;

        $display("\n========================================");
        $display("[Test] NPU Controller Test");
        $display("========================================");
        
        #20;
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        #10;

        // ========================================
        // 测试1: 动态权重模式（完整流程）
        // ========================================
        $display("\n========================================");
        $display("[Test 1] Dynamic Weight Mode (Full Flow)");
        $display("========================================");
        
        cfg_mode = `NPU_MODE_INDEP;
        cfg_b_static = 0;  // 动态权重
        
        $display("[%0t] Starting controller in dynamic mode", $time);
        
        // 发送启动脉冲 - 保持至少2个时钟周期
        @(posedge clk);
        cfg_start_pulse = 1;
        @(posedge clk);
        @(posedge clk);
        cfg_start_pulse = 0;
        
        // 等待全局完成或超时
        fork
            begin
                wait(global_done == 1);
                $display("[%0t] Controller completed successfully!", $time);
                $display("[%0t] Final state: %d", $time, global_state);
            end
            begin
                #10000;
                $display("[%0t] ERROR: Timeout waiting for completion!", $time);
                $display("[%0t] Current state: %d", $time, global_state);
                $finish;
            end
        join_any
        disable fork;
        
        #100;

        // ========================================
        // 测试2: 静态权重模式（跳过B矩阵加载）
        // ========================================
        $display("\n========================================");
        $display("[Test 2] Static Weight Mode");
        $display("========================================");
        
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;
        
        cfg_b_static = 1;  // 静态权重
        
        $display("[%0t] Starting controller in static mode", $time);
        
        @(posedge clk);
        cfg_start_pulse = 1;
        @(posedge clk);
        @(posedge clk);
        cfg_start_pulse = 0;
        
        fork
            begin
                wait(global_done == 1);
                $display("[%0t] Controller completed successfully!", $time);
            end
            begin
                #10000;
                $display("[%0t] ERROR: Timeout in static mode!", $time);
                $finish;
            end
        join_any
        disable fork;
        
        #100;

        // ========================================
        // 测试3: MERGE模式
        // ========================================
        $display("\n========================================");
        $display("[Test 3] MERGE Mode");
        $display("========================================");
        
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;
        
        cfg_mode = `NPU_MODE_MERGE;
        cfg_b_static = 0;
        
        $display("[%0t] Starting controller in MERGE mode", $time);
        
        @(posedge clk);
        cfg_start_pulse = 1;
        @(posedge clk);
        @(posedge clk);
        cfg_start_pulse = 0;
        
        fork
            begin
                wait(global_done == 1);
                $display("[%0t] Controller completed in MERGE mode!", $time);
            end
            begin
                #10000;
                $display("[%0t] ERROR: Timeout in MERGE mode!", $time);
                $finish;
            end
        join_any
        disable fork;
        
        #100;

        // 测试完成
        $display("\n========================================");
        $display("[SUCCESS] Controller tests completed!");
        $display("========================================");
        $display("[TB] VCD file: TB/ctrl_test.vcd");
        $display("[TB] Use 'gtkwave TB/ctrl_test.vcd' to view waveforms");
        #100;
        $finish;
    end

endmodule
