`include "../rtl/npu_defs.vh"

// ============================================================
//  npu_axi_slave + npu_buffer_mgr 测试平台
//  测试 AXI4 Slave 接口、寄存器访问、Burst 传输、Buffer 读写
// ============================================================

module tb_npu_axi_slave_test;

    parameter CLK_PERIOD = 10;
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH;
    parameter DATA_WIDTH = `NPU_AXI_DATA_WIDTH;

    // ---- AXI4 Signals ----
    reg                      clk;
    reg                      rst_n;
    reg  [ADDR_WIDTH-1:0]    axi_awaddr;
    reg  [7:0]               axi_awlen;
    reg  [2:0]               axi_awsize;
    reg  [1:0]               axi_awburst;
    reg                      axi_awvalid;
    wire                     axi_awready;
    reg  [DATA_WIDTH-1:0]    axi_wdata;
    reg  [DATA_WIDTH/8-1:0]  axi_wstrb;
    reg                      axi_wlast;
    reg                      axi_wvalid;
    wire                     axi_wready;
    wire [1:0]               axi_bresp;
    wire                     axi_bvalid;
    reg                      axi_bready;
    reg  [ADDR_WIDTH-1:0]    axi_araddr;
    reg  [7:0]               axi_arlen;
    reg  [2:0]               axi_arsize;
    reg  [1:0]               axi_arburst;
    reg                      axi_arvalid;
    wire                     axi_arready;
    wire [DATA_WIDTH-1:0]    axi_rdata;
    wire [1:0]               axi_rresp;
    wire                     axi_rlast;
    wire                     axi_rvalid;
    reg                      axi_rready;

    // ---- Internal wires: AXI Slave ↔ Config ----
    wire                     reg_wr_en;
    wire [7:0]               reg_wr_addr;
    wire [31:0]              reg_wr_data;
    wire                     reg_rd_en;
    wire [7:0]               reg_rd_addr;
    wire [31:0]              reg_rd_data;

    // ---- Internal wires: AXI Slave ↔ Buffer Mgr (Port A) ----
    wire                     buf_wr_en;
    wire [ADDR_WIDTH-1:0]    buf_wr_addr;
    wire [DATA_WIDTH-1:0]    buf_wr_data;
    wire [3:0]               buf_wr_strb;
    wire                     buf_rd_en;
    wire [ADDR_WIDTH-1:0]    buf_rd_addr;
    wire [DATA_WIDTH-1:0]    buf_rd_data;
    wire                     buf_rd_valid;

    // ---- Config outputs ----
    wire [1:0]               cfg_mode;
    wire [5:0]               cfg_m, cfg_n, cfg_k;
    wire [31:0]              cfg_tile_mask;
    wire [3:0]               cfg_iterations;
    wire                     cfg_start, cfg_status_clr;
    wire                     irq_en_done, irq_en_error;
    reg                      status_done, status_error;

    // ---- DUT: AXI Slave ----
    npu_axi_slave #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut_axi (
        .clk(clk), .rst_n(rst_n),
        .axi_awaddr(axi_awaddr), .axi_awlen(axi_awlen), .axi_awsize(axi_awsize),
        .axi_awburst(axi_awburst), .axi_awvalid(axi_awvalid), .axi_awready(axi_awready),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wlast(axi_wlast),
        .axi_wvalid(axi_wvalid), .axi_wready(axi_wready),
        .axi_bresp(axi_bresp), .axi_bvalid(axi_bvalid), .axi_bready(axi_bready),
        .axi_araddr(axi_araddr), .axi_arlen(axi_arlen), .axi_arsize(axi_arsize),
        .axi_arburst(axi_arburst), .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rdata(axi_rdata), .axi_rresp(axi_rresp), .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid), .axi_rready(axi_rready),
        .reg_wr_en(reg_wr_en), .reg_wr_addr(reg_wr_addr), .reg_wr_data(reg_wr_data),
        .reg_rd_en(reg_rd_en), .reg_rd_addr(reg_rd_addr), .reg_rd_data(reg_rd_data),
        .buf_wr_en(buf_wr_en), .buf_wr_addr(buf_wr_addr), .buf_wr_data(buf_wr_data),
        .buf_wr_strb(buf_wr_strb),
        .buf_rd_en(buf_rd_en), .buf_rd_addr(buf_rd_addr),
        .buf_rd_data(buf_rd_data), .buf_rd_valid(buf_rd_valid)
    );

    // ---- DUT: Config ----
    npu_config dut_cfg (
        .clk(clk), .rst_n(rst_n),
        .wr_en(reg_wr_en), .wr_addr(reg_wr_addr), .wr_data(reg_wr_data),
        .rd_en(reg_rd_en), .rd_addr(reg_rd_addr), .rd_data(reg_rd_data),
        .cfg_mode(cfg_mode), .cfg_m(cfg_m), .cfg_n(cfg_n), .cfg_k(cfg_k),
        .cfg_tile_mask(cfg_tile_mask), .cfg_iterations(cfg_iterations),
        .cfg_start(cfg_start), .cfg_status_clr(cfg_status_clr),
        .irq_en_done(irq_en_done), .irq_en_error(irq_en_error),
        .status_done(status_done), .status_error(status_error), .computing(1'b0)
    );

    // ---- DUT: Buffer Manager (Port A connected to AXI Slave) ----
    npu_buffer_mgr #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut_buf (
        .clk(clk), .rst_n(rst_n),
        .axi_wr_en(buf_wr_en), .axi_wr_addr(buf_wr_addr), .axi_wr_data(buf_wr_data),
        .axi_wr_strb(buf_wr_strb),
        .axi_rd_en(buf_rd_en), .axi_rd_addr(buf_rd_addr),
        .axi_rd_data(buf_rd_data), .axi_rd_valid(buf_rd_valid),
        // Port B: not connected (tied off)
        .mover_rd_en(1'b0), .mover_rd_addr({ADDR_WIDTH{1'b0}}),
        .mover_rd_data(), .mover_rd_valid(),
        .mover_wr_en(1'b0), .mover_wr_addr({ADDR_WIDTH{1'b0}}),
        .mover_wr_data({DATA_WIDTH{1'b0}}), .mover_wr_strb(4'h0)
    );

    // ---- Clock ----
    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    // ============================================================
    //  波形转储 (VCD格式) - 先生成在当前目录，后续由脚本移动
    // ============================================================
    initial begin
        $dumpfile("npu_axi_slave_test.vcd");
        $dumpvars(0, tb_npu_axi_slave_test);  // 记录所有信号
        // 或者只记录关键信号以减少文件大小:
        // $dumpvars(1, dut_axi, dut_cfg, dut_buf);
    end

    // ============================================================
    //  辅助任务
    // ============================================================

    // AXI 单次写 (AW+W 同时进行)
    task axi_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        integer timeout;
        begin
            @(posedge clk); #1;
            axi_awaddr <= addr; axi_awlen <= 8'd0; axi_awsize <= 3'd2;
            axi_awburst <= 2'd1; axi_awvalid <= 1'b1;
            axi_wdata <= data; axi_wstrb <= 4'hF; axi_wlast <= 1'b1; axi_wvalid <= 1'b1;
            timeout = 0;
            while (!axi_awready || !axi_wready) begin
                @(posedge clk); timeout = timeout + 1;
                if (timeout > 50) begin
                    $display("[ERROR] Write timeout @0x%04X", addr);
                    axi_awvalid <= 1'b0; axi_wvalid <= 1'b0; axi_wlast <= 1'b0; #1;
                    disable axi_write;
                end
            end
            @(posedge clk); #1;
            axi_awvalid <= 1'b0; axi_wvalid <= 1'b0; axi_wlast <= 1'b0;
            // Wait for slave to enter W_RESP
            @(posedge clk); #1;
            axi_bready <= 1'b1;
            timeout = 0;
            while (!axi_bvalid) begin
                @(posedge clk); timeout = timeout + 1;
                if (timeout > 50) begin
                    $display("[ERROR] B timeout @0x%04X", addr);
                    axi_bready <= 1'b0; #1;
                    disable axi_write;
                end
            end
            @(posedge clk); #1;
            axi_bready <= 1'b0;
        end
    endtask

    // AXI 单次读
    task axi_read;
        input  [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] data;
        integer timeout;
        begin
            data = 32'h0;
            @(posedge clk); #1;
            axi_araddr <= addr; axi_arlen <= 8'd0; axi_arsize <= 3'd2;
            axi_arburst <= 2'd1; axi_arvalid <= 1'b1;
            timeout = 0;
            while (!axi_arready) begin
                @(posedge clk); timeout = timeout + 1;
                if (timeout > 50) begin
                    $display("[ERROR] AR timeout @0x%04X", addr);
                    axi_arvalid <= 1'b0; #1; disable axi_read;
                end
            end
            @(posedge clk); #1;
            axi_arvalid <= 1'b0; axi_rready <= 1'b1;
            timeout = 0;
            while (!axi_rvalid) begin
                @(posedge clk); timeout = timeout + 1;
                if (timeout > 50) begin
                    $display("[ERROR] R timeout @0x%04X", addr);
                    axi_rready <= 1'b0; #1; disable axi_read;
                end
            end
            data = axi_rdata;
            @(posedge clk); #1;
            axi_rready <= 1'b0;
        end
    endtask

    // AXI Burst 写 (len+1 个节拍)
    task axi_burst_write;
        input [ADDR_WIDTH-1:0] start_addr;
        input [7:0]            len;
        input [31:0]           data_base;
        integer i, timeout;
        reg     has_error;
        begin
            has_error = 0;
            // AW phase
            @(posedge clk); #1;
            axi_awaddr <= start_addr; axi_awlen <= len; axi_awsize <= 3'd2;
            axi_awburst <= 2'd1; axi_awvalid <= 1'b1;
            timeout = 0;
            while (!axi_awready) begin
                @(posedge clk); timeout = timeout + 1;
                if (timeout > 50) begin $display("[ERROR] Burst AW timeout"); has_error = 1; end
                if (has_error) begin axi_awvalid <= 1'b0; #1; disable axi_burst_write; end
            end
            @(posedge clk); #1;
            axi_awvalid <= 1'b0;

            // W phase: send len+1 beats
            for (i = 0; i <= len; i = i + 1) begin
                axi_wdata <= data_base + i;
                axi_wstrb <= 4'hF;
                axi_wlast <= (i == len);
                axi_wvalid <= 1'b1;
                timeout = 0;
                while (!axi_wready) begin
                    @(posedge clk); timeout = timeout + 1;
                    if (timeout > 50) begin $display("[ERROR] Burst W timeout beat %d", i); has_error = 1; end
                    if (has_error) begin axi_wvalid <= 1'b0; axi_wlast <= 1'b0; #1; disable axi_burst_write; end
                end
                @(posedge clk); #1;
            end
            axi_wvalid <= 1'b0; axi_wlast <= 1'b0;

            // Wait one cycle for slave to transition to W_RESP
            @(posedge clk); #1;

            // B phase: always execute to prevent slave stuck in W_RESP
            axi_bready <= 1'b1;
            timeout = 0;
            while (!axi_bvalid) begin
                @(posedge clk); timeout = timeout + 1;
                if (timeout > 50) begin $display("[ERROR] Burst B timeout"); end
                if (timeout > 52) begin axi_bready <= 1'b0; #1; disable axi_burst_write; end
            end
            @(posedge clk); #1;
            axi_bready <= 1'b0;
        end
    endtask

    // AXI Burst 读 (len+1 个节拍)
    task axi_burst_read;
        input  [ADDR_WIDTH-1:0] start_addr;
        input  [7:0]            len;
        output [31:0]           first_data;
        integer i, timeout;
        begin
            first_data = 32'h0;
            // AR phase
            @(posedge clk); #1;
            axi_araddr <= start_addr; axi_arlen <= len; axi_arsize <= 3'd2;
            axi_arburst <= 2'd1; axi_arvalid <= 1'b1;
            timeout = 0;
            while (!axi_arready) begin
                @(posedge clk); timeout = timeout + 1;
                if (timeout > 50) begin $display("[ERROR] Burst AR timeout"); disable axi_burst_read; end
            end
            @(posedge clk); #1;
            axi_arvalid <= 1'b0;
            // Keep rready high for entire burst
            axi_rready <= 1'b1;

            // R phase: wait for rvalid, capture, assert rready, wait for handshake
            for (i = 0; i <= len; i = i + 1) begin
                timeout = 0;
                while (!axi_rvalid) begin
                    @(posedge clk); timeout = timeout + 1;
                    if (timeout > 50) begin $display("[ERROR] Burst R timeout beat %d", i); axi_rready <= 1'b0; disable axi_burst_read; end
                end
                if (i == 0) first_data = axi_rdata;
                // Assert rready to complete handshake
                axi_rready <= 1'b1;
                @(posedge clk); #1;
                // Wait for slave to process beat (rready seen at this posedge)
                // Slave transitions to R_WAIT, then R_WAIT2, then R_DATA with next beat
                @(posedge clk); #1;
            end
            $display("[BURST_RD] loop done, rready=%b rvalid=%b", axi_rready, axi_rvalid);
            axi_rready <= 1'b0;
        end
    endtask

    task wait_cycles;
        input integer n;
        integer i;
        begin for (i = 0; i < n; i = i + 1) @(posedge clk); end
    endtask

    // ============================================================
    //  测试序列
    // ============================================================
    integer test_num;
    reg [31:0] read_val, expected;
    reg        test_passed;
    integer    i;

    initial begin
        // Init
        rst_n <= 1'b0;
        axi_awaddr <= 0; axi_awlen <= 0; axi_awsize <= 0; axi_awburst <= 0; axi_awvalid <= 0;
        axi_wdata <= 0; axi_wstrb <= 0; axi_wlast <= 0; axi_wvalid <= 0; axi_bready <= 0;
        axi_araddr <= 0; axi_arlen <= 0; axi_arsize <= 0; axi_arburst <= 0; axi_arvalid <= 0;
        axi_rready <= 0;
        status_done <= 0; status_error <= 0;
        test_num <= 0; test_passed <= 1'b1;

        $display("========================================");
        $display("  NPU AXI Slave + Buffer Manager 测试");
        $display("  开始时间: %t", $time);
        $display("========================================");

        #20; rst_n <= 1'b1;
        wait_cycles(2);

        // ================================================
        //  第一部分: 寄存器访问 (通过 AXI)
        // ================================================
        $display("\n======== 第一部分: 寄存器访问 ========");

        // TEST 1: Write/Read REG_M
        test_num = test_num + 1;
        $display("\n  测试 %d: 通过 AXI 读写 REG_M", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd16);
        wait_cycles(1);
        axi_read(`NPU_AXI_LITE_BASE + `REG_M, read_val);
        if (read_val !== 32'd16) begin
            $display("[FAIL] REG_M: expected 16, got %d", read_val); test_passed = 1'b0;
        end else $display("[PASS] REG_M = %d", read_val);

        // TEST 2: Write/Read REG_N, REG_K
        test_num = test_num + 1;
        $display("\n  测试 %d: 读写 REG_N, REG_K", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd32);
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd16);
        wait_cycles(1);
        if (cfg_n !== 6'd32 || cfg_k !== 6'd16) begin
            $display("[FAIL] cfg_n=%d, cfg_k=%d", cfg_n, cfg_k); test_passed = 1'b0;
        end else $display("[PASS] cfg_n=%d, cfg_k=%d", cfg_n, cfg_k);

        // TEST 3: REG_MODE
        test_num = test_num + 1;
        $display("\n  测试 %d: REG_MODE 读写", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h01);  // MERGE
        wait_cycles(1);
        if (cfg_mode !== 2'b01) begin
            $display("[FAIL] cfg_mode=%b, expected 01", cfg_mode); test_passed = 1'b0;
        end else $display("[PASS] cfg_mode=%b (MERGE)", cfg_mode);

        // TEST 4: REG_CTRL start pulse
        test_num = test_num + 1;
        $display("\n  测试 %d: REG_CTRL 启动脉冲", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h01);
        wait_cycles(2);
        axi_read(`NPU_AXI_LITE_BASE + `REG_CTRL, read_val);
        if (read_val[0] !== 1'b1) begin
            $display("[FAIL] REG_CTRL[0]=%b", read_val[0]); test_passed = 1'b0;
        end else $display("[PASS] REG_CTRL[0] set (start pulse generated)");

        // TEST 5: REG_IRQ_EN
        test_num = test_num + 1;
        $display("\n  测试 %d: REG_IRQ_EN", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_IRQ_EN, 32'h03);
        wait_cycles(1);
        if (irq_en_done !== 1'b1 || irq_en_error !== 1'b1) begin
            $display("[FAIL] irq_en done=%b error=%b", irq_en_done, irq_en_error); test_passed = 1'b0;
        end else $display("[PASS] IRQ enable: done=%b, error=%b", irq_en_done, irq_en_error);

        // TEST 6: REG_TILE_MASK + ITERATIONS
        test_num = test_num + 1;
        $display("\n  测试 %d: TILE_MASK + ITERATIONS", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'hFFFF0000);
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd8);
        wait_cycles(1);
        if (cfg_tile_mask !== 32'hFFFF0000 || cfg_iterations !== 4'd8) begin
            $display("[FAIL] mask=0x%08X iter=%d", cfg_tile_mask, cfg_iterations); test_passed = 1'b0;
        end else $display("[PASS] mask=0x%08X, iter=%d", cfg_tile_mask, cfg_iterations);

        // ================================================
        //  第二部分: Burst 写入 A Buffer
        // ================================================
        $display("\n======== 第二部分: Burst 写入 A Buffer ========");

        // TEST 7: Burst write 16 beats to A Buffer
        test_num = test_num + 1;
        $display("\n  测试 %d: Burst 写入 16 个节拍到 A Buffer", test_num);
        axi_burst_write(`NPU_A_BUFFER_BASE, 8'd15, 32'h0000_0100);
        // Writes: 0x100, 0x101, 0x102, ... 0x10F to A_BUFFER_BASE+0..+60
        $display("[PASS] Burst write 16 beats completed");

        // TEST 8: Read back A Buffer (single reads to verify)
        test_num = test_num + 1;
        $display("\n  测试 %d: 回读 A Buffer (验证 burst 数据)", test_num);
        axi_read(`NPU_A_BUFFER_BASE, read_val);
        if (read_val !== 32'h0000_0100) begin
            $display("[FAIL] A[0]: expected 0x100, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] A[0] = 0x%08X", read_val);

        axi_read(`NPU_A_BUFFER_BASE + 4, read_val);
        if (read_val !== 32'h0000_0101) begin
            $display("[FAIL] A[1]: expected 0x101, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] A[1] = 0x%08X", read_val);

        axi_read(`NPU_A_BUFFER_BASE + 60, read_val);
        if (read_val !== 32'h0000_010F) begin
            $display("[FAIL] A[15]: expected 0x10F, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] A[15] = 0x%08X", read_val);

        // ================================================
        //  第三部分: Burst 写入 B Buffer
        // ================================================
        $display("\n======== 第三部分: Burst 写入 B Buffer ========");

        // TEST 9: Burst write to B Buffer
        test_num = test_num + 1;
        $display("\n  测试 %d: Burst 写入 8 个节拍到 B Buffer", test_num);
        axi_burst_write(`NPU_B_BUFFER_BASE, 8'd7, 32'h0000_0200);
        $display("[PASS] Burst write 8 beats to B completed");

        // TEST 10: Read back B Buffer
        test_num = test_num + 1;
        $display("\n  测试 %d: 回读 B Buffer", test_num);
        axi_read(`NPU_B_BUFFER_BASE, read_val);
        if (read_val !== 32'h0000_0200) begin
            $display("[FAIL] B[0]: expected 0x200, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] B[0] = 0x%08X", read_val);

        axi_read(`NPU_B_BUFFER_BASE + 28, read_val);
        if (read_val !== 32'h0000_0207) begin
            $display("[FAIL] B[7]: expected 0x207, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] B[7] = 0x%08X", read_val);

        // ================================================
        //  第四部分: C Buffer 写入 + Burst 读取
        // ================================================
        $display("\n======== 第四部分: C Buffer 写入 + Burst 读取 ========");

        // TEST 11: Write to C Buffer then burst read back
        test_num = test_num + 1;
        $display("\n  测试 %d: 写入 C Buffer 然后 burst 读取", test_num);
        // Write 4 values to C Buffer
        axi_write(`NPU_C_BUFFER_BASE,      32'hCAFE_0001);
        axi_write(`NPU_C_BUFFER_BASE + 4,  32'hCAFE_0002);
        axi_write(`NPU_C_BUFFER_BASE + 8,  32'hCAFE_0003);
        axi_write(`NPU_C_BUFFER_BASE + 12, 32'hCAFE_0004);
        wait_cycles(1);

        // Burst read 4 beats from C Buffer
        axi_burst_read(`NPU_C_BUFFER_BASE, 8'd3, read_val);
        if (read_val !== 32'hCAFE_0001) begin
            $display("[FAIL] C[0]: expected 0xCAFE0001, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] C[0] = 0x%08X (burst read first beat)", read_val);

        // ================================================
        //  第五部分: 地址边界测试
        // ================================================
        $display("\n======== 第五部分: 地址边界 ========");

        wait_cycles(5);  // Ensure AXI slave is idle

        // TEST 12: Last register address vs first buffer address
        test_num = test_num + 1;
        $display("\n  测试 %d: 寄存器/Buffer 边界", test_num);
        $display("[DEBUG] Before Part 5: rvalid=%b rlast=%b rdata=0x%08X rready=%b arvalid=%b",
            axi_rvalid, axi_rlast, axi_rdata, axi_rready, axi_arvalid);
        axi_write(`NPU_AXI_LITE_BASE + `REG_IRQ_EN, 32'h01);
        axi_write(`NPU_A_BUFFER_BASE, 32'hAAAA_BBBB);
        wait_cycles(1);
        axi_read(`NPU_AXI_LITE_BASE + `REG_IRQ_EN, read_val);
        if (read_val !== 32'h01) begin
            $display("[FAIL] IRQ_EN corrupted: 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] IRQ_EN=0x%08X (not corrupted by buffer write)", read_val);

        axi_read(`NPU_A_BUFFER_BASE, read_val);
        if (read_val !== 32'hAAAA_BBBB) begin
            $display("[FAIL] A[0] corrupted: 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] A[0]=0x%08X (not corrupted by register write)", read_val);

        // TEST 13: A Buffer end vs B Buffer start boundary
        test_num = test_num + 1;
        $display("\n  测试 %d: A/B Buffer 边界", test_num);
        // Write to last word of A Buffer and first word of B Buffer
        axi_write(`NPU_A_BUFFER_BASE + `NPU_A_BUFFER_SIZE - 4, 32'hAAAA_0001);
        axi_write(`NPU_B_BUFFER_BASE, 32'hBBBB_0001);
        wait_cycles(1);
        axi_read(`NPU_A_BUFFER_BASE + `NPU_A_BUFFER_SIZE - 4, read_val);
        if (read_val !== 32'hAAAA_0001) begin
            $display("[FAIL] A last word: 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] A last word = 0x%08X", read_val);

        axi_read(`NPU_B_BUFFER_BASE, read_val);
        if (read_val !== 32'hBBBB_0001) begin
            $display("[FAIL] B[0]: 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] B[0] = 0x%08X", read_val);

        // TEST 14: B/C Buffer boundary
        test_num = test_num + 1;
        $display("\n  测试 %d: B/C Buffer 边界", test_num);
        axi_write(`NPU_B_BUFFER_BASE + `NPU_B_BUFFER_SIZE - 4, 32'hBBBB_0002);
        axi_write(`NPU_C_BUFFER_BASE, 32'hCCCC_0001);
        wait_cycles(1);
        axi_read(`NPU_B_BUFFER_BASE + `NPU_B_BUFFER_SIZE - 4, read_val);
        if (read_val !== 32'hBBBB_0002) begin
            $display("[FAIL] B last word: 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] B last word = 0x%08X", read_val);

        axi_read(`NPU_C_BUFFER_BASE, read_val);
        if (read_val !== 32'hCCCC_0001) begin
            $display("[FAIL] C[0]: 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] C[0] = 0x%08X", read_val);

        // ================================================
        //  第六部分: 大型 Burst (64 个节拍)
        // ================================================
        $display("\n======== 第六部分: 大型 Burst 传输 ========");

        // TEST 15: 64-beat burst write to A Buffer
        test_num = test_num + 1;
        $display("\n  测试 %d: 64 个节拍 burst 写入 A Buffer", test_num);
        axi_burst_write(`NPU_A_BUFFER_BASE + 256, 8'd63, 32'h0000_1000);
        $display("[PASS] 64-beat burst write completed");

        // TEST 16: Verify random samples from 64-beat burst
        test_num = test_num + 1;
        $display("\n  测试 %d: 验证 64 个节拍 burst 数据", test_num);
        axi_read(`NPU_A_BUFFER_BASE + 256, read_val);
        if (read_val !== 32'h0000_1000) begin
            $display("[FAIL] beat[0]: expected 0x1000, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] beat[0] = 0x%08X", read_val);

        axi_read(`NPU_A_BUFFER_BASE + 256 + 63*4, read_val);
        if (read_val !== 32'h0000_103F) begin
            $display("[FAIL] beat[63]: expected 0x103F, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] beat[63] = 0x%08X", read_val);

        axi_read(`NPU_A_BUFFER_BASE + 256 + 32*4, read_val);
        if (read_val !== 32'h0000_1020) begin
            $display("[FAIL] beat[32]: expected 0x1020, got 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] beat[32] = 0x%08X", read_val);

        // ================================================
        //  总结
        // ================================================
        wait_cycles(5);
        $display("\n========================================");
        $display("  测试总结");
        $display("========================================");
        $display("  总测试数: %d", test_num);
        if (test_passed) begin
            $display("  结果: 全部测试通过 ✓");
        end else begin
            $display("  结果: 部分测试失败 ✗");
        end
        $display("  结束时间: %t", $time);
        $display("========================================\n");
        #50; $finish;
    end

    initial begin
        $monitor("Time=%t | AW:addr=0x%04X len=%d v=%b r=%b | W:data=0x%08X v=%b r=%b | B:v=%b | AR:addr=0x%04X v=%b r=%b | R:data=0x%08X v=%b last=%b",
            $time, axi_awaddr, axi_awlen, axi_awvalid, axi_awready,
            axi_wdata, axi_wvalid, axi_wready,
            axi_bvalid,
            axi_araddr, axi_arvalid, axi_arready,
            axi_rdata, axi_rvalid, axi_rlast);
    end

endmodule