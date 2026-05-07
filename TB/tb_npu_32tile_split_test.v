`timescale 1ns/1ps
`include "npu_defs.vh"

/**
 * NPU 32-Tile SPLIT模式全量并行计算测试平台
 * 
 * 测试目标：
 * 1. 验证所有32个Tile在SPLIT模式下的并行计算能力
 * 2. SPLIT模式：每个Tile内部将8×8矩阵拆分为4个4×4子阵列计算
 * 3. 通过tile_c_bus直接检查每个Tile的计算结果
 * 4. 使用B=I（单位矩阵）简化验证：C应该等于A
 * 5. 为每个Tile配置不同的A矩阵数据，确保独立性
 * 
 * SPLIT模式特点：
 * - 每个Tile处理8×8矩阵，但内部拆分为4个4×4子块
 * - dot_block函数中split_mode=1时，只累加前4项（k<4）
 * - 数据分发策略与INDEP相同（轮转分配）
 * 
 * 测试场景：
 * - Test 1: 单Tile基准测试（Tile#0）
 * - Test 2: 4个连续Tile并行测试（Tile#0-3）
 * - Test 3: 全部32个Tile同时启用
 * - Test 4: 低位Tile块测试（Tile#0-15）
 * - Test 5: 高位Tile块测试（Tile#16-31）
 */

module tb_npu_32tile_test;

    // 时钟与复位
    reg clk;
    reg rst_n;

    // AXI-Lite 控制接口信号
    reg [31:0] s_axi_awaddr;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;
    reg [31:0] s_axi_araddr;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;

    // AXI4 数据接口信号（连接到模拟的BRAM）
    wire [31:0] m_axi_awaddr;
    wire m_axi_awvalid;
    wire [31:0] m_axi_wdata;
    wire [3:0] m_axi_wstrb;
    wire m_axi_wvalid;
    wire m_axi_wlast;
    wire m_axi_awready;
    wire m_axi_wready;
    wire [1:0] m_axi_bresp;
    wire m_axi_bvalid;
    wire m_axi_bready;
    
    wire [31:0] m_axi_araddr;
    wire m_axi_arvalid;
    wire m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0] m_axi_rresp;
    wire m_axi_rlast;
    wire m_axi_rvalid;
    wire m_axi_rready;

    // NPU状态信号
    wire npu_busy;
    wire npu_done;
    wire npu_error;
    wire npu_irq;

    // 测试用寄存器和计数器
    integer test_num;
    integer tests_passed;
    integer tests_failed;
    integer i, j;
    integer tile_id;
    integer ri, ci;  // 矩阵行列索引
    integer elem;    // 元素索引
    integer exp8;    // 期望值（8位）
    reg [31:0] act;  // 实际值（32位）
    integer err_count;
    reg pass_flag;

    // 实例化NPU顶层模块
    npu_top u_npu_top (
        .clk(clk),
        .rst_n(rst_n),
        // AXI-Lite Control Interface
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        // AXI4 Data Interface
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .npu_busy(npu_busy),
        .npu_done(npu_done),
        .npu_error(npu_error),
        .npu_irq(npu_irq)
    );

    // 时钟生成 (10 ns 周期 = 100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 生成VCD波形文件
    initial begin
        $dumpfile("TB/npu_32tile_test.vcd");
        $dumpvars(0, tb_npu_32tile_test);
    end

    // ============================================================
    // AXI4 BRAM 存储器模型
    // ============================================================
    
    axi4_bram_model u_axi4_bram_model (
        .clk(clk),
        .rst_n(rst_n),
        // Write Address Channel
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        // Write Data Channel
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wready(m_axi_wready),
        // Write Response Channel
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        // Read Address Channel
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        // Read Data Channel
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    // ============================================================
    // AXI-Lite 协议辅助任务
    // ============================================================

    // AXI-Lite写寄存器任务
    task axil_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1;
            s_axi_wdata = data;
            s_axi_wstrb = 4'hF;
            s_axi_wvalid = 1;
            
            wait(s_axi_awready && s_axi_wready);
            @(posedge clk);
            s_axi_awvalid = 0;
            s_axi_wvalid = 0;
            
            wait(s_axi_bvalid);
            s_axi_bready = 1;
            @(posedge clk);
            s_axi_bready = 0;
        end
    endtask

    // AXI-Lite读寄存器任务
    task axil_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1;
            
            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid = 0;
            
            wait(s_axi_rvalid);
            data = s_axi_rdata;
            s_axi_rready = 1;
            @(posedge clk);
            s_axi_rready = 0;
        end
    endtask

    // 等待 NPU 完成的任务
    task wait_for_done;
        input integer timeout_cycles;
        begin
            fork
                begin
                    wait(npu_done == 1);
                end
                begin
                    #(timeout_cycles * 10);  // timeout_cycles 个时钟周期
                    $display("[%0t] ERROR: Timeout waiting for NPU done signal", $time);
                    $finish;
                end
            join_any
            disable fork;
        end
    endtask

    // ============================================================
    // 初始化内存数据
    // 为32个Tile分别准备不同的A矩阵数据
    // B矩阵为单位矩阵（Identity），这样 C = A * I = A
    // ============================================================
    task init_memory_data;
        integer a_base_word;
        integer b_base_word;
        integer word_index;
        integer byte_index;
        integer idx;
        reg [31:0] w;
        integer val8;
        begin
            $display("[%0t] 开始初始化内存数据...", $time);

            // ========================================
            // A矩阵：为32个Tile分别准备不同的8x8数据
            // 每个Tile的A矩阵占用64字节（64个uint8元素 = 16个字）
            // Tile t 的 A[idx] = (t * 64 + idx + 1) & 0xFF
            // 起始地址：0x100
            // 【重要】所有Tile的A矩阵在内存中连续存储，无间隔
            //   Tile#0:  0x00000100 ~ 0x0000013F (64字节)
            //   Tile#1:  0x00000140 ~ 0x0000017F (64字节)
            //   ...
            //   Tile#31: 0x000008C0 ~ 0x000008FF (64字节)
            // 总占用：32 × 64 = 2048字节 = 0x800
            // ========================================
            for (tile_id = 0; tile_id < 32; tile_id = tile_id + 1) begin
                // 每个Tile的A矩阵起始地址（连续排列，每个Tile占64字节=16个字）
                a_base_word = (32'h00000100 + tile_id * 64) >> 2;
                
                // 先清零
                for (word_index = 0; word_index < 16; word_index = word_index + 1) begin
                    u_axi4_bram_model.axi4_mem[a_base_word + word_index] = 32'h00000000;
                end
                
                // 填充数据：tile t 的第idx个元素 = (t*64 + idx + 1) & 0xFF
                for (idx = 0; idx < 64; idx = idx + 1) begin
                    word_index = a_base_word + (idx >> 2);  // 除以4得到字地址
                    byte_index = idx & 3;  // 模4得到字节偏移
                    
                    w = u_axi4_bram_model.axi4_mem[word_index];
                    val8 = (tile_id * 64 + idx + 1) & 8'hFF;
                    
                    case (byte_index)
                        0: w[7:0]   = val8[7:0];
                        1: w[15:8]  = val8[7:0];
                        2: w[23:16] = val8[7:0];
                        3: w[31:24] = val8[7:0];
                    endcase
                    
                    u_axi4_bram_model.axi4_mem[word_index] = w;
                end
            end

            // ========================================
            // B矩阵：8x8单位矩阵（Identity Matrix）
            // B[i][j] = 1 if i==j, else 0
            // 存储在地址 0x2000（避开A矩阵区域，A矩阵占用到0x08FF）
            // ========================================
            b_base_word = (32'h00002000 >> 2);
            
            // 先全部清零
            for (word_index = 0; word_index < 16; word_index = word_index + 1) begin
                u_axi4_bram_model.axi4_mem[b_base_word + word_index] = 32'h00000000;
            end
            
            // 设置对角线元素为1
            for (i = 0; i < 8; i = i + 1) begin
                idx = i * 8 + i;  // 对角线索引：0, 9, 18, 27, 36, 45, 54, 63
                word_index = b_base_word + (idx >> 2);
                byte_index = idx & 3;
                
                w = u_axi4_bram_model.axi4_mem[word_index];
                case (byte_index)
                    0: w[7:0]   = 8'd1;
                    1: w[15:8]  = 8'd1;
                    2: w[23:16] = 8'd1;
                    3: w[31:24] = 8'd1;
                endcase
                u_axi4_bram_model.axi4_mem[word_index] = w;
            end

            $display("[%0t] 内存初始化完成：32个Tile的A矩阵 + 共享B矩阵（单位阵）", $time);
        end
    endtask

    // ============================================================
    // 严格验证任务：通过tile_c_bus直接检查每个Tile的结果
    // 期望：B=I时，C应该等于A
    // ============================================================
    task verify_all_tiles_cbus;
        input integer tile_count;  // 启用的Tile数量
        input [31:0] tile_mask;    // Tile使能掩码
        output reg pass;
        integer t;
        integer err;
        begin
            pass = 1'b1;
            err = 0;
            
            $display("\n[验证] 检查 %0d 个Tile的计算结果", tile_count);
            
            // 遍历所有32个Tile
            for (t = 0; t < 32; t = t + 1) begin
                // 只检查被启用的Tile
                if (tile_mask[t]) begin
                    // 打印样本点
                    act = u_npu_top.tile_c_bus[t*`NPU_TILE_C_BITS + 0*32 +: 32];
                    $display("  [Tile#%0d] C[0][0]=%0d (0x%08x)", t, act, act);
                    act = u_npu_top.tile_c_bus[t*`NPU_TILE_C_BITS + 63*32 +: 32];
                    $display("  [Tile#%0d] C[7][7]=%0d (0x%08x)", t, act, act);
                    
                    // 逐元素验证
                    for (ri = 0; ri < 8; ri = ri + 1) begin
                        for (ci = 0; ci < 8; ci = ci + 1) begin
                            elem = ri * 8 + ci;
                            // 期望值：Tile t 的第elem个元素 = (t*64 + elem + 1) & 0xFF
                            exp8 = (t * 64 + elem + 1) & 8'hFF;
                            
                            // 从tile_c_bus读取实际值
                            act = u_npu_top.tile_c_bus[t*`NPU_TILE_C_BITS + elem*32 +: 32];
                            
                            if (act !== exp8) begin
                                err = err + 1;
                                pass = 1'b0;
                                if (err <= 10) begin
                                    $display("    ❌ MISMATCH Tile#%0d C[%0d][%0d]=%0d (0x%08x) 期望=%0d (0x%02x)",
                                             t, ri, ci, act, act, exp8, exp8[7:0]);
                                end
                            end
                        end
                    end
                end
            end
            
            $display("  验证结果: 错误数=%0d", err);
        end
    endtask

    // ============================================================
    // SPLIT模式专用验证任务：通过tile_c_bus直接检查每个Tile的结果
    // SPLIT模式特点：dot_block只累加前4项（k=0,1,2,3）
    // 当B=I时：C[i][j] = A[i][j] if j<4 else 0
    // ============================================================
    task verify_all_tiles_cbus_split;
        input integer tile_count;  // 启用的Tile数量
        input [31:0] tile_mask;    // Tile使能掩码
        output reg pass;
        integer t;
        integer err;
        begin
            pass = 1'b1;
            err = 0;
            
            $display("\n[验证-SPLIT] 检查 %0d 个Tile的计算结果", tile_count);
            $display("[说明] SPLIT模式只使用前4列，期望：C[i][j]=A[i][j] (j<4), C[i][j]=0 (j>=4)");
            
            // 遍历所有32个Tile
            for (t = 0; t < 32; t = t + 1) begin
                // 只检查被启用的Tile
                if (tile_mask[t]) begin
                    // 打印样本点
                    act = u_npu_top.tile_c_bus[t*`NPU_TILE_C_BITS + 0*32 +: 32];
                    $display("  [Tile#%0d] C[0][0]=%0d (0x%08x)", t, act, act);
                    act = u_npu_top.tile_c_bus[t*`NPU_TILE_C_BITS + 63*32 +: 32];
                    $display("  [Tile#%0d] C[7][7]=%0d (0x%08x)", t, act, act);
                    
                    // 逐元素验证
                    for (ri = 0; ri < 8; ri = ri + 1) begin
                        for (ci = 0; ci < 8; ci = ci + 1) begin
                            elem = ri * 8 + ci;
                            
                            // SPLIT模式期望值计算
                            if (ci < 4) begin
                                // 前4列：C[i][j] = A[i][j]（因为B=I且j在0-3范围内）
                                exp8 = (t * 64 + elem + 1) & 8'hFF;
                            end else begin
                                // 后4列：C[i][j] = 0（因为k=j不在0-3范围内）
                                exp8 = 8'h00;
                            end
                            
                            // 从tile_c_bus读取实际值
                            act = u_npu_top.tile_c_bus[t*`NPU_TILE_C_BITS + elem*32 +: 32];
                            
                            if (act !== exp8) begin
                                err = err + 1;
                                pass = 1'b0;
                                if (err <= 10) begin
                                    $display("    ❌ MISMATCH Tile#%0d C[%0d][%0d]=%0d (0x%08x) 期望=%0d (0x%02x)",
                                             t, ri, ci, act, act, exp8, exp8[7:0]);
                                end
                            end
                        end
                    end
                    
                    if (err == 0) begin
                        $display("    ✓ Tile#%0d PASS", t);
                    end
                end
            end
            
            if (err > 0) begin
                $display("  验证结果: 错误数=%0d", err);
            end else begin
                $display("  ✓ 所有Tile验证通过！");
            end
        end
    endtask

    // ============================================================
    // 测试流程主程序
    // ============================================================

    initial begin
        test_num = 0;
        tests_passed = 0;
        tests_failed = 0;

        // ========================================
        // 初始化和复位
        // ========================================
        $display("\n========================================");
        $display("  NPU 32-Tile SPLIT模式全量测试");
        $display("  测试时间: %t", $time);
        $display("========================================\n");

        // 复位所有信号
        rst_n = 0;
        s_axi_awaddr = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;

        // 初始化内存数据
        init_memory_data();

        #20;
        rst_n = 1;
        $display("[%0t] 复位释放，系统就绪", $time);
        #20;

        // ========================================
        // TEST 1: 单Tile基准测试（Tile#0）
        // ========================================
        test_num = test_num + 1;
        $display("\n---- TEST %0d: 单Tile基准测试（Tile#0） ----", test_num);
        $display("期望: C = A (因为B=I)");

        axil_write(32'h04, {`NPU_MODE_SPLIT});            // reg_mode = SPLIT
        axil_write(32'h14, 32'd8);                       // reg_m = 8
        axil_write(32'h18, 32'd8);                       // reg_n = 8
        axil_write(32'h1C, 32'd8);                       // reg_k = 8
        axil_write(32'h08, 32'h00000100);                // reg_a_base = 0x100
        axil_write(32'h0C, 32'h00002000);                // reg_b_base = 0x2000
        axil_write(32'h10, 32'h00003000);                // reg_c_base = 0x3000（输出地址， unused in verification）
        axil_write(32'h20, 32'h00000001);                // reg_tile_mask = 仅Tile#0

        $display("[%0t] 启动计算...", $time);
        axil_write(32'h00, 32'h01);                      // reg_ctrl = start

        wait_for_done(100000);
        $display("[%0t] 计算完成: busy=%b done=%b error=%b", 
                 $time, npu_busy, npu_done, npu_error);

        #100;
        verify_all_tiles_cbus_split(1, 32'h00000001, pass_flag);
        if (!npu_error && pass_flag) begin
            $display("[PASS] TEST %0d", test_num);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] TEST %0d", test_num);
            tests_failed = tests_failed + 1;
        end

        #200;

        // ========================================
        // TEST 2: 4个Tile连续并行（Tile#0, #1, #2, #3）
        // ========================================
        test_num = test_num + 1;
        $display("\n---- TEST %0d: 4个Tile连续并行测试 ----", test_num);
        $display("启用: Tile#0, #1, #2, #3");
        $display("期望: 每个Tile的C等于对应的A");

        // tile_mask: Bit0, Bit1, Bit2, Bit3 = 0x0000000F
        axil_write(32'h04, {`NPU_MODE_SPLIT});            // reg_mode = SPLIT
        axil_write(32'h14, 32'd8);                       // reg_m = 8
        axil_write(32'h18, 32'd8);                       // reg_n = 8
        axil_write(32'h1C, 32'd8);                       // reg_k = 8
        axil_write(32'h08, 32'h00000100);                // reg_a_base = 0x100
        axil_write(32'h0C, 32'h00002000);                // reg_b_base = 0x2000
        axil_write(32'h10, 32'h00004000);                // reg_c_base = 0x4000
        axil_write(32'h20, 32'h0000000F);                // reg_tile_mask = Tile#0,1,2,3

        $display("[%0t] 启动计算...", $time);
        axil_write(32'h00, 32'h01);

        wait_for_done(500000);  // 4个Tile需要更长时间（约5ms）
        $display("[%0t] 计算完成: busy=%b done=%b error=%b", 
                 $time, npu_busy, npu_done, npu_error);

        #100;
        verify_all_tiles_cbus_split(4, 32'h0000000F, pass_flag);
        if (!npu_error && pass_flag) begin
            $display("[PASS] TEST %0d", test_num);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] TEST %0d", test_num);
            tests_failed = tests_failed + 1;
        end

        #200;

        // ========================================
        // TEST 3: 全部32个Tile同时启用（连续）
        // ========================================
        test_num = test_num + 1;
        $display("\n---- TEST %0d: 全部32-Tile并行测试 ----", test_num);
        $display("期望: 所有32个Tile的C都等于各自的A");

        axil_write(32'h04, {`NPU_MODE_SPLIT});            // reg_mode = SPLIT
        axil_write(32'h14, 32'd8);                       // reg_m = 8
        axil_write(32'h18, 32'd8);                       // reg_n = 8
        axil_write(32'h1C, 32'd8);                       // reg_k = 8
        axil_write(32'h08, 32'h00000100);                // reg_a_base = 0x100
        axil_write(32'h0C, 32'h00002000);                // reg_b_base = 0x2000
        axil_write(32'h10, 32'h00005000);                // reg_c_base = 0x5000
        axil_write(32'h20, 32'hFFFFFFFF);                // reg_tile_mask = 所有32个Tile（连续）

        $display("[%0t] 启动计算（32个Tile全开）...", $time);
        axil_write(32'h00, 32'h01);

        wait_for_done(200000);  // 更多Tile需要更长时间
        $display("[%0t] 计算完成: busy=%b done=%b error=%b", 
                 $time, npu_busy, npu_done, npu_error);

        #100;
        verify_all_tiles_cbus_split(32, 32'hFFFFFFFF, pass_flag);
        if (!npu_error && pass_flag) begin
            $display("[PASS] TEST %0d", test_num);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] TEST %0d", test_num);
            tests_failed = tests_failed + 1;
        end

        #200;

        // ========================================
        // TEST 4: 低16个Tile连续启用（Tile#0-15）
        // ========================================
        test_num = test_num + 1;
        $display("\n---- TEST %0d: 低位Tile块测试（Tile#0-15） ----", test_num);
        $display("启用: Tile#0-15（低16位连续）");
        $display("期望: 这16个Tile的C等于各自的A");

        axil_write(32'h04, {`NPU_MODE_SPLIT});            // reg_mode = SPLIT
        axil_write(32'h14, 32'd8);                       // reg_m = 8
        axil_write(32'h18, 32'd8);                       // reg_n = 8
        axil_write(32'h1C, 32'd8);                       // reg_k = 8
        axil_write(32'h08, 32'h00000100);                // reg_a_base = 0x100
        axil_write(32'h0C, 32'h00002000);                // reg_b_base = 0x2000
        axil_write(32'h10, 32'h00006000);                // reg_c_base = 0x6000
        axil_write(32'h20, 32'h0000FFFF);                // reg_tile_mask = Tile#0-15（连续）

        $display("[%0t] 启动计算（16个低位Tile）...", $time);
        axil_write(32'h00, 32'h01);

        wait_for_done(150000);
        $display("[%0t] 计算完成: busy=%b done=%b error=%b", 
                 $time, npu_busy, npu_done, npu_error);

        #100;
        verify_all_tiles_cbus_split(16, 32'h0000FFFF, pass_flag);
        if (!npu_error && pass_flag) begin
            $display("[PASS] TEST %0d", test_num);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] TEST %0d", test_num);
            tests_failed = tests_failed + 1;
        end

        #200;

        // ========================================
        // TEST 4: 仅高位Tile启用（Tile#16-31）
        // ========================================
        test_num = test_num + 1;
        $display("\n---- TEST %0d: 高位Tile块测试（Tile#16-31） ----", test_num);
        $display("启用: Tile#16-31（高16位）");
        $display("期望: 这16个Tile的C等于各自的A");

        axil_write(32'h04, {`NPU_MODE_SPLIT});            // reg_mode = SPLIT
        axil_write(32'h14, 32'd8);                       // reg_m = 8
        axil_write(32'h18, 32'd8);                       // reg_n = 8
        axil_write(32'h1C, 32'd8);                       // reg_k = 8
        axil_write(32'h08, 32'h00000100);                // reg_a_base = 0x100
        axil_write(32'h0C, 32'h00002000);                // reg_b_base = 0x2000
        axil_write(32'h10, 32'h00006000);                // reg_c_base = 0x6000
        axil_write(32'h20, 32'hFFFF0000);                // reg_tile_mask = Tile#16-31

        $display("[%0t] 启动计算（16个高位Tile）...", $time);
        axil_write(32'h00, 32'h01);

        wait_for_done(150000);
        $display("[%0t] 计算完成: busy=%b done=%b error=%b", 
                 $time, npu_busy, npu_done, npu_error);

        #100;
        verify_all_tiles_cbus_split(16, 32'hFFFF0000, pass_flag);
        if (!npu_error && pass_flag) begin
            $display("[PASS] TEST %0d", test_num);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] TEST %0d", test_num);
            tests_failed = tests_failed + 1;
        end

        #200;

        // ========================================
        // 测试总结
        // ========================================
        $display("\n========================================");
        $display("  测试总结");
        $display("========================================");
        $display("  总测试数: %0d", tests_passed + tests_failed);
        $display("  通过:     %0d", tests_passed);
        $display("  失败:     %0d", tests_failed);
        if ((tests_passed + tests_failed) > 0) begin
            $display("  通过率:   %0.1f%%", (tests_passed * 100.0) / (tests_passed + tests_failed));
        end
        $display("========================================\n");
        
        if (tests_failed == 0) begin
            $display("✓ 所有测试通过！32-Tile INDEP模式功能正常。");
        end else begin
            $display("✗ 存在失败的测试，请检查波形和日志。");
        end
        
        #1000;
        $finish;
    end

endmodule

// ============================================================
// AXI4 BRAM 存储器模型模块
// ============================================================
module axi4_bram_model (
    input wire clk,
    input wire rst_n,
    
    // Write Address Channel
    input wire [31:0] m_axi_awaddr,
    input wire m_axi_awvalid,
    output reg m_axi_awready,
    
    // Write Data Channel
    input wire [31:0] m_axi_wdata,
    input wire [3:0] m_axi_wstrb,
    input wire m_axi_wvalid,
    input wire m_axi_wlast,
    output reg m_axi_wready,
    
    // Write Response Channel
    output wire [1:0] m_axi_bresp,
    output wire m_axi_bvalid,
    input wire m_axi_bready,
    
    // Read Address Channel
    input wire [31:0] m_axi_araddr,
    input wire m_axi_arvalid,
    output reg m_axi_arready,
    
    // Read Data Channel
    output wire [31:0] m_axi_rdata,
    output wire [1:0] m_axi_rresp,
    output wire m_axi_rlast,
    output wire m_axi_rvalid,
    input wire m_axi_rready
);

    // Internal registers to drive output wires
    reg [31:0] m_axi_rdata_reg;
    reg m_axi_rvalid_reg;
    reg m_axi_bvalid_reg;

    assign m_axi_rdata = m_axi_rdata_reg;
    assign m_axi_rvalid = m_axi_rvalid_reg;
    assign m_axi_bvalid = m_axi_bvalid_reg;

    localparam integer MEM_WORDS = 65536;  // 256KB storage (32-bit words)
    reg [31:0] axi4_mem [0:MEM_WORDS-1];
    
    // Integer variables for initialization and logic
    integer i;
    integer idx;
    integer word_idx;
    integer byte_idx;
    
    reg [31:0] mem_addr_wr;
    reg [31:0] mem_addr_rd;
    reg aw_accepted;

    assign m_axi_bresp = 2'b00; // OKAY
    assign m_axi_rresp = 2'b00; // OKAY
    assign m_axi_rlast = 1'b1;  // Single beat transfer

    initial begin
        // 初始化存储器内容
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            axi4_mem[i] = 32'hDEADBEEF;  // 默认填充
        end
    end

    // ----------------------------------------
    // AXI4 写通道逻辑 (AW, W & B)
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 0;
            m_axi_wready  <= 0;
            m_axi_bvalid_reg <= 0;
            aw_accepted   <= 0;
            mem_addr_wr   <= 0;
        end else begin
            // AW Channel Handshake
            if (m_axi_awvalid && !aw_accepted) begin
                m_axi_awready <= 1;
                mem_addr_wr <= m_axi_awaddr[31:2]; // 锁存字地址
                aw_accepted <= 1;
            end else begin
                m_axi_awready <= 0;
            end

            // W Channel Handshake
            if (aw_accepted && m_axi_wvalid && !m_axi_wready) begin
                m_axi_wready <= 1;
                // 执行写入
                if (mem_addr_wr < MEM_WORDS) begin
                    axi4_mem[mem_addr_wr] <= m_axi_wdata;
                end
            end else begin
                m_axi_wready <= 0;
            end

            // B Channel Response
            if (m_axi_wready && m_axi_wvalid) begin
                m_axi_bvalid_reg <= 1;
                aw_accepted <= 0; 
            end 
            else if (m_axi_bvalid_reg && m_axi_bready) begin
                m_axi_bvalid_reg <= 0;
            end
        end
    end

    // ----------------------------------------
    // AXI4 读通道逻辑 (AR & R)
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 0;
            m_axi_rvalid_reg  <= 0;
            m_axi_rdata_reg   <= 0;
            mem_addr_rd       <= 0;
        end else begin
            // AR Channel Handshake
            if (m_axi_arvalid && !m_axi_rvalid_reg) begin
                m_axi_arready <= 1;
                mem_addr_rd <= m_axi_araddr[31:2];
                m_axi_rdata_reg <= axi4_mem[m_axi_araddr[31:2]];
                m_axi_rvalid_reg <= 1;
            end else begin
                m_axi_arready <= 0;
            end

            // R Channel Handshake
            if (m_axi_rvalid_reg && m_axi_rready) begin
                m_axi_rvalid_reg <= 0;
            end
        end
    end

endmodule
