`include "npu_defs.vh"

// ============================================================
// tb_npu_data_mover_test - npu_data_mover 模块测试平台
// 测试数据搬运模块的三种工作模式：INDEP/MERGE/SPLIT
// ============================================================
module tb_npu_data_mover_test;

    // ========================================================
    //  参数定义
    // ========================================================
    parameter CLK_PERIOD = 10;  // 10ns, 100MHz
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH;
    parameter DATA_WIDTH = `NPU_AXI_DATA_WIDTH;
    parameter TILE_COUNT = `NPU_NUM_TILES;

    // ========================================================
    //  时钟和复位
    // ========================================================
    reg clk;
    reg rst_n;

    // ========================================================
    //  配置信号
    // ========================================================
    reg [1:0]  cfg_mode;
    reg [5:0]  cfg_m;
    reg [5:0]  cfg_n;
    reg [5:0]  cfg_k;
    reg [31:0] cfg_tile_mask;

    // ========================================================
    //  控制信号
    // ========================================================
    reg load_start;
    reg store_start;
    wire load_done;
    wire store_done;

    // ========================================================
    //  Buffer 接口（模拟 Buffer Manager）
    // ========================================================
    wire buf_rd_en;
    wire [ADDR_WIDTH-1:0] buf_rd_addr;
    reg [DATA_WIDTH-1:0] buf_rd_data;
    reg buf_rd_valid;

    wire buf_wr_en;
    wire [ADDR_WIDTH-1:0] buf_wr_addr;
    wire [DATA_WIDTH-1:0] buf_wr_data;
    wire [3:0] buf_wr_strb;

    // ========================================================
    //  Tile 接口
    // ========================================================
    wire [TILE_COUNT-1:0] tile_en;
    wire [8*TILE_COUNT-1:0] tile_a_data;
    wire tile_a_valid;
    wire [8*TILE_COUNT-1:0] tile_b_data;
    wire tile_b_valid;
    reg [`NPU_TILE_C_BITS*TILE_COUNT-1:0] tile_c_data;  // 2048 * 32 = 65536位
    reg tile_c_valid;
    wire tile_c_ready;

    // ========================================================
    //  内部寄存器（模拟 Buffer 存储）
    // ========================================================
    reg [31:0] a_buffer [0:4095];  // 16KB A Buffer
    reg [31:0] b_buffer [0:4095];  // 16KB B Buffer
    reg [31:0] c_buffer [0:2047];  // 8KB C Buffer

    // ========================================================
    //  实例化被测模块
    // ========================================================
    npu_data_mover dut_mover (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_mode(cfg_mode),
        .cfg_m(cfg_m),
        .cfg_n(cfg_n),
        .cfg_k(cfg_k),
        .cfg_tile_mask(cfg_tile_mask),
        .load_start(load_start),
        .store_start(store_start),
        .load_done(load_done),
        .store_done(store_done),
        .buf_rd_en(buf_rd_en),
        .buf_rd_addr(buf_rd_addr),
        .buf_rd_data(buf_rd_data),
        .buf_rd_valid(buf_rd_valid),
        .buf_wr_en(buf_wr_en),
        .buf_wr_addr(buf_wr_addr),
        .buf_wr_data(buf_wr_data),
        .buf_wr_strb(buf_wr_strb),
        .tile_en(tile_en),
        .tile_a_data(tile_a_data),
        .tile_a_valid(tile_a_valid),
        .tile_b_data(tile_b_data),
        .tile_b_valid(tile_b_valid),
        .tile_c_data(tile_c_data),
        .tile_c_valid(tile_c_valid),
        .tile_c_ready(tile_c_ready)
    );

    // ========================================================
    //  时钟生成
    // ========================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================
    //  Buffer 读响应逻辑（模拟 BRAM 延迟）
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_rd_valid <= 1'b0;
            buf_rd_data <= 32'd0;
        end else begin
            if (buf_rd_en) begin
                // 1拍延迟模拟BRAM读取
                buf_rd_valid <= 1'b1;
                // 地址解码：判断是A Buffer还是B Buffer
                if (buf_rd_addr >= `NPU_A_BUFFER_BASE && 
                    buf_rd_addr < `NPU_B_BUFFER_BASE) begin
                    buf_rd_data <= a_buffer[buf_rd_addr[13:2]];
                end else if (buf_rd_addr >= `NPU_B_BUFFER_BASE && 
                             buf_rd_addr < `NPU_C_BUFFER_BASE) begin
                    buf_rd_data <= b_buffer[buf_rd_addr[13:2]];
                end else begin
                    buf_rd_data <= 32'hDEAD_BEEF;  // 错误地址标记
                end
            end else begin
                buf_rd_valid <= 1'b0;
            end
        end
    end

    // ========================================================
    //  Buffer 写响应逻辑
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时清空C Buffer
            integer i;
            for (i = 0; i < 2048; i = i + 1)
                c_buffer[i] <= 32'd0;
        end else begin
            if (buf_wr_en) begin
                if (buf_wr_addr >= `NPU_C_BUFFER_BASE && 
                    buf_wr_addr < `NPU_C_BUFFER_BASE + `NPU_C_BUFFER_SIZE) begin
                    c_buffer[buf_wr_addr[12:2]] <= buf_wr_data;
                end
            end
        end
    end

    // ========================================================
    //  测试任务：初始化
    // ========================================================
    task init_system;
        input [5:0] m_val;
        input [5:0] n_val;
        input [5:0] k_val;
        input [1:0] mode;
        input [31:0] tile_mask;
    begin
        $display("\n======== 系统初始化 ========");
        $display("M=%d, N=%d, K=%d, Mode=%d, TileMask=0x%08X", 
                 m_val, n_val, k_val, mode, tile_mask);
        $fflush;
        
        cfg_m <= m_val;
        cfg_n <= n_val;
        cfg_k <= k_val;
        cfg_mode <= mode;
        cfg_tile_mask <= tile_mask;
        
        load_start <= 1'b0;
        store_start <= 1'b0;
        
        #20;  // 等待稳定
    end
    endtask

    // ========================================================
    //  测试任务：填充 A Buffer
    // ========================================================
    task fill_a_buffer;
        input [5:0] k_val;
        input [31:0] base_value;
    begin
        integer tile_idx, word_idx;
        integer addr_offset;
        
        $display("\n======== 填充 A Buffer ========");
        $fflush;
        
        // 为每个Tile填充不同的数据
        for (tile_idx = 0; tile_idx < TILE_COUNT; tile_idx = tile_idx + 1) begin
            for (word_idx = 0; word_idx < (k_val << 1); word_idx = word_idx + 1) begin
                addr_offset = tile_idx * (k_val << 1) + word_idx;
                a_buffer[addr_offset] = base_value + (tile_idx << 16) + word_idx;
            end
        end
        
        $display("A Buffer 填充完成: %d Tiles × %d words", TILE_COUNT, k_val << 1);
        $fflush;
    end
    endtask

    // ========================================================
    //  测试任务：填充 B Buffer
    // ========================================================
    task fill_b_buffer;
        input [5:0] k_val;
        input [31:0] base_value;
        input is_split_mode;
    begin
        integer tile_idx, word_idx;
        integer addr_offset;
        
        $display("\n======== 填充 B Buffer ========");
        $fflush;
        
        if (!is_split_mode) begin
            // INDEP/MERGE 模式：每个Tile独立B矩阵
            for (tile_idx = 0; tile_idx < TILE_COUNT; tile_idx = tile_idx + 1) begin
                for (word_idx = 0; word_idx < (k_val << 1); word_idx = word_idx + 1) begin
                    addr_offset = tile_idx * (k_val << 1) + word_idx;
                    b_buffer[addr_offset] = base_value + (tile_idx << 16) + word_idx + 32'h1000;
                end
            end
        end else begin
            // SPLIT 模式：B矩阵按列分组
            for (word_idx = 0; word_idx < (k_val >> 1); word_idx = word_idx + 1) begin
                for (tile_idx = 0; tile_idx < TILE_COUNT; tile_idx = tile_idx + 1) begin
                    addr_offset = tile_idx * (k_val >> 1) + word_idx;
                    b_buffer[addr_offset] = base_value + (tile_idx << 16) + word_idx + 32'h2000;
                end
            end
        end
        
        $display("B Buffer 填充完成");
        $fflush;
    end
    endtask

    // ========================================================
    //  测试任务：执行 Load 操作
    // ========================================================
    task execute_load;
    begin
        $display("\n======== 开始 Load 操作 ========");
        $fflush;
        
        $display("[t=%0t] 设置 load_start = 1", $time);
        $fflush;
        load_start <= 1'b1;
        #1;
        @(posedge clk);
        $display("[t=%0t] 时钟上升沿后，设置 load_start = 0", $time);
        $fflush;
        load_start <= 1'b0;
        
        // 等待 load_done
        $display("[t=%0t] 等待 load_done...", $time);
        $fflush;
        wait(load_done);
        $display("[t=%0t] load_done 检测到！", $time);
        $fflush;
        $display("[PASS] Load 操作完成");
        $fflush;
        
        #10;
    end
    endtask

    // ========================================================
    //  测试任务：准备 Tile C 数据（只准备数据，不触发 valid）
    // ========================================================
    task prepare_tile_c_data;
        input [5:0] num_tiles;
    begin
        integer i, w;

        $display("\n======== 准备 Tile C 数据 ========");
        $fflush;

        // 为启用的Tile准备C数据
        // 每个Tile有256位（8个32-bit word），需要为每个word设置正确的值
        for (i = 0; i < num_tiles; i = i + 1) begin
            if (cfg_tile_mask[i]) begin
                // 为每个word设置数据（只设置第一个word，其他word为0）
                tile_c_data[i*256 +: 32] = 32'hCAFE_0000 + i;
                // 其他word设置为0
                for (w = 1; w < 8; w = w + 1) begin
                    tile_c_data[i*256 + w*32 +: 32] = 32'h0000_0000;
                end
            end
        end

        $display("Tile C 数据准备完成");
        $fflush;
    end
    endtask

    // ========================================================
    //  测试任务：执行 Store 操作（修复时序问题）
    // ========================================================
    task execute_store;
        input [5:0] num_tiles;
    begin
        $display("\n======== 开始 Store 操作 ========");
        $fflush;

        // 1. 先准备数据（不触发 tile_c_valid）
        prepare_tile_c_data(num_tiles);

        // 2. 拉高 store_start，触发状态机进入 S_STORE
        store_start <= 1'b1;
        #1;
        @(posedge clk);
        store_start <= 1'b0;

        // 3. 等待状态机进入 S_STORE 状态
        #1;
        @(posedge clk);

        // 4. 拉高 tile_c_valid，保持高电平直到 store_done 被置位
        $display("[t=%0t] 设置 tile_c_valid = 1", $time);
        $fflush;
        tile_c_valid <= 1'b1;
        #1;

        // 5. 等待 store_done 信号（状态机完成所有 32 个 tile 处理）
        // store_done 会在状态机进入 DONE 状态时被置位
        $display("[t=%0t] 等待 store_done...", $time);
        $fflush;
        wait(store_done);
        $display("[t=%0t] store_done 检测到！", $time);
        $fflush;

        // 6. 拉低 tile_c_valid
        #1;
        @(posedge clk);
        tile_c_valid <= 1'b0;

        $display("[PASS] Store 操作完成");
        $fflush;

        #10;
    end
    endtask

    // ========================================================
    //  测试任务：验证 C Buffer 数据
    // ========================================================
    task verify_c_buffer;
        input [5:0] num_tiles;
        input [31:0] expected_base;
    begin
        integer i;
        integer errors;
        integer buf_idx;

        $display("\n======== 验证 C Buffer ========");
        $fflush;
        errors = 0;

        // 每个Tile有64个word（256字节），数据在c_buffer中的偏移是 i*64
        for (i = 0; i < num_tiles; i = i + 1) begin
            if (cfg_tile_mask[i]) begin
                buf_idx = i * 64;  // 每个Tile 64个word
                if (c_buffer[buf_idx] !== (expected_base + i)) begin
                    $display("[FAIL] C[%d] (buf[%d]): Expected=0x%08X, Actual=0x%08X",
                             i, buf_idx, expected_base + i, c_buffer[buf_idx]);
                    errors = errors + 1;
                end else begin
                    $display("[PASS] C[%d] (buf[%d]) = 0x%08X", i, buf_idx, c_buffer[buf_idx]);
                end
            end
        end

        if (errors == 0) begin
            $display("[PASS] C Buffer 验证通过");
        end else begin
            $display("[FAIL] C Buffer 验证失败: %d 个错误", errors);
        end
        $fflush;
    end
    endtask

    // ========================================================
    //  主测试流程
    // ========================================================
    initial begin
        integer test_num;
        
        // ========================================
        //  波形输出配置
        // ========================================
        $dumpfile("tb_npu_data_mover_test.vcd");  // 生成VCD波形文件
        $dumpvars(0, tb_npu_data_mover_test);     // 记录所有信号变化
        
        $display("========================================");
        $display("  NPU Data Mover 模块测试");
        $display("========================================\n");
        $fflush;
        
        // 初始化
        rst_n <= 1'b0;
        cfg_mode <= 2'd0;
        cfg_m <= 6'd0;
        cfg_n <= 6'd0;
        cfg_k <= 6'd0;
        cfg_tile_mask <= 32'd0;
        load_start <= 1'b0;
        store_start <= 1'b0;
        buf_rd_data <= 32'd0;
        buf_rd_valid <= 1'b0;
        tile_c_data <= {`NPU_TILE_C_BITS*TILE_COUNT{1'b0}};  // ✅ 使用重复操作符，2048*32位
        tile_c_valid <= 1'b0;
        
        #20;
        rst_n <= 1'b1;
        #20;
        
        // ========================================
        //  测试 1: INDEP 模式 - 单Tile Load
        // ========================================
        test_num = 1;
        $display("\n\n======== 测试 %d: INDEP 模式 - 单Tile Load ========", test_num);
        $fflush;
        
        init_system(8, 8, 8, `NPU_MODE_INDEP, 32'h0000_0001);
        fill_a_buffer(8, 32'h0000_1000);
        fill_b_buffer(8, 32'h0000_2000, 0);
        execute_load();
        
        // 验证Tile A/B数据是否正确分发
        if (tile_a_valid && tile_b_valid) begin
            $display("[PASS] Tile A/B 数据分发成功");
            $fflush;
        end
        
        // ========================================
        //  测试 2: MERGE 模式 - 多Tile Load（简化测试）
        // ========================================
        test_num = 2;
        $display("\n\n======== 测试 %d: MERGE 模式 - 4 Tiles Load ========", test_num);
        $fflush;
        
        init_system(8, 8, 8, `NPU_MODE_MERGE, 32'h0000_000F);
        fill_a_buffer(8, 32'h0000_1000);
        fill_b_buffer(8, 32'h0000_2000, 0);
        execute_load();
        
        // ========================================
        //  测试 3: MERGE 模式 - 完整 Load+Store（简化测试）
        // ========================================
        test_num = 3;
        $display("\n\n======== 测试 %d: MERGE 模式 - 完整 Load+Store ========", test_num);
        $fflush;
        
        init_system(8, 8, 8, `NPU_MODE_MERGE, 32'h0000_000F);
        fill_a_buffer(8, 32'h0000_1000);
        fill_b_buffer(8, 32'h0000_2000, 0);
        execute_load();
        execute_store(4);
        verify_c_buffer(4, 32'hCAFE_0000);
        
        // ========================================
        //  测试 4: INDEP 模式 - 完整 Load+Store
        // ========================================
        test_num = 4;
        $display("\n\n======== 测试 %d: INDEP 模式 - 完整 Load+Store ========", test_num);
        $fflush;
        
        init_system(8, 8, 8, `NPU_MODE_INDEP, 32'h0000_000F);
        fill_a_buffer(8, 32'h0000_1000);
        fill_b_buffer(8, 32'h0000_2000, 0);
        execute_load();
        execute_store(4);
        verify_c_buffer(4, 32'hCAFE_0000);
        
        // ========================================
        //  测试 5: MERGE 模式 - Load
        // ========================================
        test_num = 5;
        $display("\n\n======== 测试 %d: MERGE 模式 - Load ========", test_num);
        $fflush;
        
        init_system(8, 8, 8, `NPU_MODE_MERGE, 32'h0000_000F);
        fill_a_buffer(8, 32'h0000_3000);
        fill_b_buffer(8, 32'h0000_4000, 0);
        execute_load();
        
        // ========================================
        //  测试 6: SPLIT 模式 - Load
        // ========================================
        test_num = 6;
        $display("\n\n======== 测试 %d: SPLIT 模式 - Load ========", test_num);
        $fflush;
        
        init_system(8, 8, 16, `NPU_MODE_SPLIT, 32'h0000_000F);
        fill_a_buffer(16, 32'h0000_5000);
        fill_b_buffer(16, 32'h0000_6000, 1);
        execute_load();
        
        // ========================================
        //  测试 7: 不同K值测试
        // ========================================
        test_num = 7;
        $display("\n\n======== 测试 %d: 大K值测试 (K=32) ========", test_num);
        $fflush;
        
        init_system(8, 8, 32, `NPU_MODE_INDEP, 32'h0000_0003);
        fill_a_buffer(32, 32'h0000_7000);
        fill_b_buffer(32, 32'h0000_8000, 0);
        execute_load();
        
        // ========================================
        //  测试 8: 边界测试 - 最大Tile数
        // ========================================
        test_num = 8;
        $display("\n\n======== 测试 %d: 最大Tile数测试 ========", test_num);
        $fflush;
        
        init_system(8, 8, 8, `NPU_MODE_INDEP, 32'hFFFF_FFFF);
        fill_a_buffer(8, 32'h0000_9000);
        fill_b_buffer(8, 32'h0000_A000, 0);
        execute_load();
        
        // ========================================
        //  测试 9: 综合压力测试
        // ========================================
        test_num = 9;
        $display("\n\n======== 测试 %d: 综合压力测试 ========", test_num);
        $fflush;
        // 连续执行多次Load/Store
        init_system(8, 8, 8, `NPU_MODE_INDEP, 32'h0000_0007);
        fill_a_buffer(8, 32'h0000_B000);
        fill_b_buffer(8, 32'h0000_C000, 0);
        execute_load();
        execute_store(3);
        
        // 第二次迭代
        fill_a_buffer(8, 32'h0000_D000);
        fill_b_buffer(8, 32'h0000_E000, 0);
        execute_load();
        execute_store(3);
        
        // ========================================
        //  测试完成
        // ========================================
        $display("\n\n========================================");
        $display("  所有测试完成！");
        $display("========================================\n");
        $fflush;
        
        #50;
        $finish;
    end

    // ========================================================
    //  监控输出（优化版 - 减少冗余输出 + 强制刷新）
    // ========================================================
    reg [31:0] prev_buf_rd_addr;
    reg [31:0] prev_buf_wr_addr;
    reg prev_tile_a_valid;
    reg prev_tile_b_valid;
    
    always @(posedge clk) begin
        // Buffer 读请求（仅在地址变化时输出）
        if (buf_rd_en && buf_rd_addr != prev_buf_rd_addr) begin
            $display("[t=%0t] RD: addr=0x%04X", $time, buf_rd_addr);
            $fflush;  // 强制刷新输出缓冲区
            prev_buf_rd_addr <= buf_rd_addr;
        end
        
        // Buffer 写操作（每次写入都记录）
        if (buf_wr_en) begin
            $display("[t=%0t] WR: addr=0x%04X data=0x%08X strb=0x%X", 
                     $time, buf_wr_addr, buf_wr_data, buf_wr_strb);
            $fflush;  // 强制刷新输出缓冲区
            prev_buf_wr_addr <= buf_wr_addr;
        end
        
        // Tile A 数据（仅在上升沿时输出，并简化数据显示）
        if (tile_a_valid && !prev_tile_a_valid) begin
            $display("[t=%0t] Tile A: valid", $time);
            $fflush;  // 强制刷新输出缓冲区
            prev_tile_a_valid <= tile_a_valid;
        end else if (!tile_a_valid) begin
            prev_tile_a_valid <= 1'b0;
        end
        
        // Tile B 数据（仅在上升沿时输出，并简化数据显示）
        if (tile_b_valid && !prev_tile_b_valid) begin
            $display("[t=%0t] Tile B: valid", $time);
            $fflush;  // 强制刷新输出缓冲区
            prev_tile_b_valid <= tile_b_valid;
        end else if (!tile_b_valid) begin
            prev_tile_b_valid <= 1'b0;
        end
    end

    // ========================================================
    //  超时保护（防止死锁）
    // ========================================================
    initial begin
        #200000;  // 200us 超时
        $display("\n[ERROR] 仿真超时！可能存在死锁。");
        $fflush;
        $finish;
    end

endmodule
