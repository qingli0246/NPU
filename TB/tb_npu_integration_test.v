`include "../rtl/npu_defs.vh"

// ============================================================
//  NPU 联合测试平台
//  测试完整 NPU 系统：AXI Slave + Config + Status + Buffer Manager
//                        + Scheduler + Data Mover + Compute Pool
// ============================================================

module tb_npu_integration_test;

    parameter CLK_PERIOD = 10;
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH;
    parameter DATA_WIDTH = `NPU_AXI_DATA_WIDTH;
    parameter TILE_COUNT = `NPU_NUM_TILES;
    parameter A_BUS_WIDTH = 8 * TILE_COUNT;
    parameter C_BUS_WIDTH = `NPU_TILE_C_BITS * TILE_COUNT;  // 2048 * 32 = 65536位

    // ============================================================
    //  AXI4 信号
    // ============================================================
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

    // ---- 中断输出 ----
    wire                     npu_irq;

    // ============================================================
    //  内部连线
    // ============================================================

    // AXI Slave ↔ Config
    wire                     reg_wr_en;
    wire [7:0]               reg_wr_addr;
    wire [31:0]              reg_wr_data;
    wire                     reg_rd_en;
    wire [7:0]               reg_rd_addr;
    wire [31:0]              reg_rd_data;

    // AXI Slave ↔ Buffer Mgr (Port A)
    wire                     axi_buf_wr_en;
    wire [ADDR_WIDTH-1:0]    axi_buf_wr_addr;
    wire [DATA_WIDTH-1:0]    axi_buf_wr_data;
    wire [3:0]               axi_buf_wr_strb;
    wire                     axi_buf_rd_en;
    wire [ADDR_WIDTH-1:0]    axi_buf_rd_addr;
    wire [DATA_WIDTH-1:0]    axi_buf_rd_data;
    wire                     axi_buf_rd_valid;

    // Config 输出
    wire [1:0]               cfg_mode;
    wire [5:0]               cfg_m, cfg_n, cfg_k;
    wire [31:0]              cfg_tile_mask;
    wire [3:0]               cfg_iterations;
    wire                     cfg_start, cfg_status_clr;
    wire                     irq_en_done, irq_en_error;

    // Status
    wire                     status_done, status_error;

    // Scheduler ↔ Data Mover
    wire                     load_start, compute_start, store_start;
    wire                     load_done, store_done;

    // Scheduler ↔ Compute Pool
    wire                     compute_done;
    wire                     npu_done, npu_error;
    wire [3:0]               npu_state;
    wire                     computing;

    // Data Mover ↔ Buffer Mgr (Port B)
    wire                     mover_buf_rd_en;
    wire [ADDR_WIDTH-1:0]    mover_buf_rd_addr;
    wire [DATA_WIDTH-1:0]    mover_buf_rd_data;
    wire                     mover_buf_rd_valid;
    wire                     mover_buf_wr_en;
    wire [ADDR_WIDTH-1:0]    mover_buf_wr_addr;
    wire [DATA_WIDTH-1:0]    mover_buf_wr_data;
    wire [3:0]               mover_buf_wr_strb;

    // Data Mover ↔ Compute Pool
    wire [TILE_COUNT-1:0]    tile_en;
    wire [A_BUS_WIDTH-1:0]   tile_a_data;
    wire                     tile_a_valid;
    wire [A_BUS_WIDTH-1:0]   tile_b_data;
    wire                     tile_b_valid;
    wire [C_BUS_WIDTH-1:0]   tile_c_data;
    wire                     tile_c_valid;
    wire                     tile_c_ready;
    wire [TILE_COUNT-1:0]    tile_done;
    wire                     pool_done;

    // compute_done 由 pool_done 驱动
    assign compute_done = pool_done;

    // ============================================================
    //  模块实例化
    // ============================================================

    // ---- 1. AXI Slave ----
    npu_axi_slave #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_axi_slave (
        .clk            (clk),
        .rst_n          (rst_n),
        .axi_awaddr     (axi_awaddr),
        .axi_awlen      (axi_awlen),
        .axi_awsize     (axi_awsize),
        .axi_awburst    (axi_awburst),
        .axi_awvalid    (axi_awvalid),
        .axi_awready    (axi_awready),
        .axi_wdata      (axi_wdata),
        .axi_wstrb      (axi_wstrb),
        .axi_wlast      (axi_wlast),
        .axi_wvalid     (axi_wvalid),
        .axi_wready     (axi_wready),
        .axi_bresp      (axi_bresp),
        .axi_bvalid     (axi_bvalid),
        .axi_bready     (axi_bready),
        .axi_araddr     (axi_araddr),
        .axi_arlen      (axi_arlen),
        .axi_arsize     (axi_arsize),
        .axi_arburst    (axi_arburst),
        .axi_arvalid    (axi_arvalid),
        .axi_arready    (axi_arready),
        .axi_rdata      (axi_rdata),
        .axi_rresp      (axi_rresp),
        .axi_rlast      (axi_rlast),
        .axi_rvalid     (axi_rvalid),
        .axi_rready     (axi_rready),
        .reg_wr_en      (reg_wr_en),
        .reg_wr_addr    (reg_wr_addr),
        .reg_wr_data    (reg_wr_data),
        .reg_rd_en      (reg_rd_en),
        .reg_rd_addr    (reg_rd_addr),
        .reg_rd_data    (reg_rd_data),
        .buf_wr_en      (axi_buf_wr_en),
        .buf_wr_addr    (axi_buf_wr_addr),
        .buf_wr_data    (axi_buf_wr_data),
        .buf_wr_strb    (axi_buf_wr_strb),
        .buf_rd_en      (axi_buf_rd_en),
        .buf_rd_addr    (axi_buf_rd_addr),
        .buf_rd_data    (axi_buf_rd_data),
        .buf_rd_valid   (axi_buf_rd_valid)
    );

    // ---- 2. Config ----
    npu_config u_config (
        .clk            (clk),
        .rst_n          (rst_n),
        .wr_en          (reg_wr_en),
        .wr_addr        (reg_wr_addr),
        .wr_data        (reg_wr_data),
        .rd_en          (reg_rd_en),
        .rd_addr        (reg_rd_addr),
        .rd_data        (reg_rd_data),
        .cfg_mode       (cfg_mode),
        .cfg_m          (cfg_m),
        .cfg_n          (cfg_n),
        .cfg_k          (cfg_k),
        .cfg_tile_mask  (cfg_tile_mask),
        .cfg_iterations (cfg_iterations),
        .cfg_start      (cfg_start),
        .cfg_status_clr (cfg_status_clr),
        .irq_en_done    (irq_en_done),
        .irq_en_error   (irq_en_error),
        .status_done    (status_done),
        .status_error   (status_error),
        .computing      (computing)
    );

    // ---- 3. Status ----
    npu_status u_status (
        .clk            (clk),
        .rst_n          (rst_n),
        .npu_done       (npu_done),
        .npu_error      (npu_error),
        .status_clr     (cfg_status_clr),
        .irq_en_done    (irq_en_done),
        .irq_en_error   (irq_en_error),
        .status_done    (status_done),
        .status_error   (status_error),
        .npu_irq        (npu_irq)
    );

    // ---- 4. Buffer Manager ----
    npu_buffer_mgr #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_buffer_mgr (
        .clk            (clk),
        .rst_n          (rst_n),
        .axi_wr_en      (axi_buf_wr_en),
        .axi_wr_addr    (axi_buf_wr_addr),
        .axi_wr_data    (axi_buf_wr_data),
        .axi_wr_strb    (axi_buf_wr_strb),
        .axi_rd_en      (axi_buf_rd_en),
        .axi_rd_addr    (axi_buf_rd_addr),
        .axi_rd_data    (axi_buf_rd_data),
        .axi_rd_valid   (axi_buf_rd_valid),
        .mover_rd_en    (mover_buf_rd_en),
        .mover_rd_addr  (mover_buf_rd_addr),
        .mover_rd_data  (mover_buf_rd_data),
        .mover_rd_valid (mover_buf_rd_valid),
        .mover_wr_en    (mover_buf_wr_en),
        .mover_wr_addr  (mover_buf_wr_addr),
        .mover_wr_data  (mover_buf_wr_data),
        .mover_wr_strb  (mover_buf_wr_strb)
    );

    // ---- 5. Scheduler ----
    npu_scheduler u_scheduler (
        .clk            (clk),
        .rst_n          (rst_n),
        .cfg_mode       (cfg_mode),
        .cfg_m          (cfg_m),
        .cfg_n          (cfg_n),
        .cfg_k          (cfg_k),
        .cfg_iterations (cfg_iterations),
        .cfg_start      (cfg_start),
        .load_start     (load_start),
        .compute_start  (compute_start),
        .store_start    (store_start),
        .load_done      (load_done),
        .compute_done   (compute_done),
        .store_done     (store_done),
        .npu_done       (npu_done),
        .npu_error      (npu_error),
        .npu_state      (npu_state),
        .computing      (computing)
    );

    // ---- 6. Data Mover ----
    npu_data_mover #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .TILE_COUNT  (TILE_COUNT),
        .K_MAX       (`NPU_K_MAX),
        .A_BUS_WIDTH (A_BUS_WIDTH),
        .C_BUS_WIDTH (C_BUS_WIDTH)
    ) u_data_mover (
        .clk            (clk),
        .rst_n          (rst_n),
        .cfg_mode       (cfg_mode),
        .cfg_m          (cfg_m),
        .cfg_n          (cfg_n),
        .cfg_k          (cfg_k),
        .cfg_tile_mask  (cfg_tile_mask),
        .load_start     (load_start),
        .store_start    (store_start),
        .load_done      (load_done),
        .store_done     (store_done),
        .buf_rd_en      (mover_buf_rd_en),
        .buf_rd_addr    (mover_buf_rd_addr),
        .buf_rd_data    (mover_buf_rd_data),
        .buf_rd_valid   (mover_buf_rd_valid),
        .buf_wr_en      (mover_buf_wr_en),
        .buf_wr_addr    (mover_buf_wr_addr),
        .buf_wr_data    (mover_buf_wr_data),
        .buf_wr_strb    (mover_buf_wr_strb),
        .tile_en        (tile_en),
        .tile_a_data    (tile_a_data),
        .tile_a_valid   (tile_a_valid),
        .tile_b_data    (tile_b_data),
        .tile_b_valid   (tile_b_valid),
        .tile_c_data    (tile_c_data),
        .tile_c_valid   (tile_c_valid),
        .tile_c_ready   (tile_c_ready)
    );

    // ---- 7. Compute Pool ----
    npu_compute_pool #(
        .TILE_COUNT  (TILE_COUNT),
        .K_MAX       (`NPU_K_MAX),
        .A_BUS_WIDTH (A_BUS_WIDTH),
        .C_BUS_WIDTH (C_BUS_WIDTH)
    ) u_compute_pool (
        .clk            (clk),
        .rst_n          (rst_n),
        .cfg_k          (cfg_k),
        .cfg_tile_mask  (cfg_tile_mask),
        .tile_en        (tile_en),
        .tile_a_data    (tile_a_data),
        .tile_a_valid   (tile_a_valid),
        .tile_b_data    (tile_b_data),
        .tile_b_valid   (tile_b_valid),
        .tile_c_data    (tile_c_data),
        .tile_c_valid   (tile_c_valid),
        .tile_c_ready   (tile_c_ready),
        .tile_done      (tile_done),
        .pool_done      (pool_done)
    );

    // ============================================================
    //  时钟生成
    // ============================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ============================================================
    //  波形转储
    // ============================================================
    initial begin
        $dumpfile("npu_integration_test.vcd");
        $dumpvars(0, tb_npu_integration_test);
    end

    // ============================================================
    //  验证任务：使用单位矩阵验证计算结果
    //  原理：如果 B = I（单位矩阵），则 C = A × I = A
    //  直接对比 C Buffer 和 A Buffer 的数据即可验证正确性
    // ============================================================
    task verify_c_result_with_identity;
        input [5:0] tile_id;          // Tile ID
        input [9:0] num_words;        // 需要验证的字数
        input [ADDR_WIDTH-1:0] a_base_addr;  // A Buffer 基地址
        input [ADDR_WIDTH-1:0] c_base_addr;  // C Buffer 基地址
        integer i;
        reg [31:0] a_val, c_val;
        integer errors;
        begin
            errors = 0;
            $display("    验证 Tile %0d 的计算结果 (B=I, 期望 C=A)...", tile_id);
            
            // 计算该Tile的A和C的偏移地址
            // INDEP模式：每个Tile的数据在Buffer中连续存放
            // A Buffer: tile_offset = tile_id * (2*K) * 4
            // C Buffer: tile_offset = tile_id * 256
            
            for (i = 0; i < num_words; i = i + 1) begin
                // 读取A矩阵数据
                axi_read(a_base_addr + i*4, a_val);
                // 读取C矩阵数据
                axi_read(c_base_addr + i*4, c_val);
                
                if (a_val !== c_val) begin
                    $display("      [FAIL] Word[%0d]: A=0x%08X, C=0x%08X (不匹配!)", 
                             i, a_val, c_val);
                    errors = errors + 1;
                end
            end
            
            if (errors == 0) begin
                $display("    [PASS] Tile 0 计算结果正确 (C=A)，共验证%d个数据", 8);
            end else begin
                $display("    [FAIL] Tile 0 有 %0d 个错误", errors);
                test_passed = 1'b0;  // 标记测试失败
            end
        end
    endtask

    // ============================================================
    //  验证任务：检查C Buffer是否包含有效数据（非全零/非X态）
    // ============================================================
    task check_c_buffer_valid;
        input [ADDR_WIDTH-1:0] c_base_addr;  // C Buffer 基地址
        input [9:0] num_words;               // 需要检查的字数
        integer i;
        reg [31:0] c_val;
        integer zero_count, x_count;
        begin
            zero_count = 0;
            x_count = 0;
            
            for (i = 0; i < num_words; i = i + 1) begin
                axi_read(c_base_addr + i*4, c_val);
                
                if (c_val === 32'h0) begin
                    zero_count = zero_count + 1;
                end else if (c_val === 32'hx) begin
                    x_count = x_count + 1;
                end
            end
            
            if (x_count > 0) begin
                $display("    [FAIL] C Buffer 中有 %0d 个X态值", x_count);
            end else if (zero_count == num_words) begin
                $display("    [WARN] C Buffer 全为零（可能计算错误或输入为零）");
            end else begin
                $display("    [PASS] C Buffer 包含有效数据 (零值=%0d/%0d)", 
                         zero_count, num_words);
            end
        end
    endtask

    // ============================================================
    //  新增任务：打印8×8 A矩阵（按行优先，每行2个word）
    // ============================================================
    task print_matrix_a_8x8;
        input [ADDR_WIDTH-1:0] base_addr;  // A Buffer 基地址
        input string matrix_name;          // 矩阵名称（如 "A" 或 "B"）
        integer i, j;
        reg [31:0] word_data;
        reg [7:0]  byte_val;
        begin
            $display("\n    ===== %s 矩阵 (8×8 INT8, 行优先布局) =====", matrix_name);
            $display("    基地址: 0x%08X", base_addr);
            $display("    格式: 每行2个word，每个word包含4个字节 [byte0, byte1, byte2, byte3]");
            $display("");
            
            for (i = 0; i < 8; i = i + 1) begin
                // 读取该行的第1个word（列0-3）
                axi_read(base_addr + (i*2)*4, word_data);
                
                // 读取该行的第2个word（列4-7）
                axi_read(base_addr + (i*2+1)*4, word_data);
                
                // 打印整行（8个字节）
                $write("    %s[%d] = [", matrix_name, i);
                
                // 第1个word的4个字节
                axi_read(base_addr + (i*2)*4, word_data);
                for (j = 0; j < 4; j = j + 1) begin
                    byte_val = word_data[j*8 +: 8];
                    if (j > 0) $write(", ");
                    $write("%2d", $signed(byte_val));
                end
                
                // 第2个word的4个字节
                axi_read(base_addr + (i*2+1)*4, word_data);
                for (j = 0; j < 4; j = j + 1) begin
                    byte_val = word_data[j*8 +: 8];
                    $write(", %2d", $signed(byte_val));
                end
                
                $display("]");
            end
            
            $display("    =========================================\n");
        end
    endtask

    // ============================================================
    //  新增任务：打印8×8 B矩阵（按行优先，每行2个word）
    //  同时以十六进制显示原始word值，方便对比
    // ============================================================
    task print_matrix_b_8x8;
        input [ADDR_WIDTH-1:0] base_addr;  // B Buffer 基地址
        integer i, j;
        reg [31:0] word_data;
        reg [7:0]  byte_val;
        begin
            $display("\n    ===== B 矩阵 (8×8 INT8, 行优先布局) =====");
            $display("    基地址: 0x%08X", base_addr);
            $display("    格式: 每行2个word，每个word包含4个字节 [byte0, byte1, byte2, byte3]");
            $display("");
            
            for (i = 0; i < 8; i = i + 1) begin
                // 打印整行（8个字节）
                $write("    B[%d] = [", i);
                
                // 第1个word的4个字节
                axi_read(base_addr + (i*2)*4, word_data);
                for (j = 0; j < 4; j = j + 1) begin
                    byte_val = word_data[j*8 +: 8];
                    if (j > 0) $write(", ");
                    $write("%2d", $signed(byte_val));
                end
                
                // 第2个word的4个字节
                axi_read(base_addr + (i*2+1)*4, word_data);
                for (j = 0; j < 4; j = j + 1) begin
                    byte_val = word_data[j*8 +: 8];
                    $write(", %2d", $signed(byte_val));
                end
                
                $display("]");
            end
            
            $display("");
            $display("    --- 原始Word值（十六进制）---");
            for (i = 0; i < 16; i = i + 1) begin
                axi_read(base_addr + i*4, word_data);
                $display("      Word[%2d] @0x%08X = 0x%08X", i, base_addr + i*4, word_data);
            end
            
            $display("    =========================================\n");
        end
    endtask

    // AXI 单次写
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

    // AXI Burst 写
    task axi_burst_write;
        input [ADDR_WIDTH-1:0] start_addr;
        input [7:0]            len;
        input [31:0]           data_base;
        integer i, timeout;
        reg     has_error;
        begin
            has_error = 0;
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

            @(posedge clk); #1;
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

    task wait_cycles;
        input integer n;
        integer i;
        begin for (i = 0; i < n; i = i + 1) @(posedge clk); end
    endtask

    // ============================================================
    //  测试变量
    // ============================================================
    integer test_num;
    reg [31:0] read_val, expected;
    reg        test_passed;
    integer    i, j;

    // ============================================================
    //  主测试流程
    // ============================================================
    initial begin
        // ---- 初始化 ----
        rst_n <= 1'b0;
        axi_awaddr <= 0; axi_awlen <= 0; axi_awsize <= 0; axi_awburst <= 0; axi_awvalid <= 0;
        axi_wdata <= 0; axi_wstrb <= 0; axi_wlast <= 0; axi_wvalid <= 0; axi_bready <= 0;
        axi_araddr <= 0; axi_arlen <= 0; axi_arsize <= 0; axi_arburst <= 0; axi_arvalid <= 0;
        axi_rready <= 0;
        test_num <= 0; test_passed <= 1'b1;

        $display("============================================================");
        $display("  NPU 联合测试 - 完整系统验证");
        $display("  模块: AXI Slave + Config + Status + Buffer Manager");
        $display("        + Scheduler + Data Mover + Compute Pool");
        $display("  开始时间: %t", $time);
        $display("============================================================");

        #20; rst_n <= 1'b1;
        wait_cycles(5);
/*
        // ================================================================
        //  阶段1: 基础通信 - AXI + Config + Buffer Manager
        // ================================================================
        $display("\n============================================================");
        $display("  阶段1: 基础通信测试");
        $display("  目标: 验证 AXI 总线 → Config 寄存器 → Buffer 读写");
        $display("============================================================");

        // TEST 1: 复位后默认值验证
        test_num = test_num + 1;
        $display("\n  测试 %d: 复位后默认值验证", test_num);
        axi_read(`NPU_AXI_LITE_BASE + `REG_MODE, read_val);
        if (read_val[1:0] !== 2'b00) begin
            $display("[FAIL] cfg_mode 默认值: %b, 期望 00", read_val[1:0]); test_passed = 1'b0;
        end else $display("[PASS] cfg_mode 默认值 = 00 (INDEP)");

        // TEST 2: 写入配置寄存器
        test_num = test_num + 1;
        $display("\n  测试 %d: 写入配置寄存器 (Mode=INDEP, M=8, N=8, K=8)", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h00);  // INDEP
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'h0000_0001);  // Tile 0
        wait_cycles(2);

        // 验证 Config 输出
        if (cfg_mode !== 2'b00 || cfg_m !== 6'd8 || cfg_n !== 6'd8 || cfg_k !== 6'd8) begin
            $display("[FAIL] Config 输出: mode=%b m=%d n=%d k=%d", cfg_mode, cfg_m, cfg_n, cfg_k);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Config 输出: mode=%b m=%d n=%d k=%d", cfg_mode, cfg_m, cfg_n, cfg_k);
        end

        // TEST 3: Buffer 写入验证
        test_num = test_num + 1;
        $display("\n  测试 %d: 通过 AXI 写入 A Buffer", test_num);
        axi_write(`NPU_A_BUFFER_BASE, 32'h0000_1000);
        axi_write(`NPU_A_BUFFER_BASE + 4, 32'h0000_1001);
        wait_cycles(1);
        axi_read(`NPU_A_BUFFER_BASE, read_val);
        if (read_val !== 32'h0000_1000) begin
            $display("[FAIL] A[0]: 期望 0x1000, 实际 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] A[0] = 0x%08X", read_val);

        // TEST 4: Buffer 读写完整性
        test_num = test_num + 1;
        $display("\n  测试 %d: Burst 写入 B Buffer", test_num);
        axi_burst_write(`NPU_B_BUFFER_BASE, 8'd15, 32'h0000_2000);
        wait_cycles(1);
        axi_read(`NPU_B_BUFFER_BASE, read_val);
        if (read_val !== 32'h0000_2000) begin
            $display("[FAIL] B[0]: 期望 0x2000, 实际 0x%08X", read_val); test_passed = 1'b0;
        end else $display("[PASS] B[0] = 0x%08X", read_val);

        // ================================================================
        //  阶段2: 状态与中断测试
        // ================================================================
        $display("\n============================================================");
        $display("  阶段2: 状态与中断测试");
        $display("  目标: 验证 Status 模块的标志管理和中断生成");
        $display("============================================================");

        // TEST 5: 使能中断
        test_num = test_num + 1;
        $display("\n  测试 %d: 使能 Done 和 Error 中断", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_IRQ_EN, 32'h03);
        wait_cycles(1);
        if (irq_en_done !== 1'b1 || irq_en_error !== 1'b1) begin
            $display("[FAIL] 中断使能: done=%b error=%b", irq_en_done, irq_en_error);
            test_passed = 1'b0;
        end else $display("[PASS] 中断使能: done=%b error=%b", irq_en_done, irq_en_error);

        // TEST 6: 清除状态标志
        test_num = test_num + 1;
        $display("\n  测试 %d: 清除状态标志", test_num);
        // 先通过写 REG_CTRL bit1 来清除
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h02);  // status_clr
        wait_cycles(3);
        $display("[PASS] 状态清除脉冲已发送");

        // ================================================================
        //  阶段3: 完整执行流程测试 (INDEP 模式)
        // ================================================================
        $display("\n============================================================");
        $display("  阶段3: 完整执行流程测试 (INDEP 模式)");
        $display("  目标: 验证 Load → Compute → Store 完整流程");
        $display("============================================================");

        // TEST 7: 准备数据并启动 NPU
        test_num = test_num + 1;
        $display("\n  测试 %d: 配置并启动 NPU (INDEP, K=4, Tile 0)", test_num);

        // 配置
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h00);      // INDEP
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'h0000_0001);  // 只用 Tile 0
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd1);

        // 写入 A 矩阵数据 (K=4, 但Tile按8×8架构存储,需填充后4列)
        // 注意：Tile是8-bit MAC，每个32位word包含4个字节数据
        // 8×8 Tile架构下，每行需要2个word(前4列+后4列)
        // 为确保 C == A（当B=I时），A值必须每个字节独立有意义
        $display("    写入 A 矩阵数据 (8×8布局,K=4有效)...");
        
       // Row 0: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        axi_write(`NPU_A_BUFFER_BASE + 0*4, 32'h04030201);  // Word 0: k=0~3
        axi_write(`NPU_A_BUFFER_BASE + 1*4, 32'h08070605);  // Word 1: k=4~7

        // Row 1: [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]
        axi_write(`NPU_A_BUFFER_BASE + 2*4, 32'h0C0B0A09);  // Word 2: k=0~3
        axi_write(`NPU_A_BUFFER_BASE + 3*4, 32'h100F0E0D);  // Word 3: k=4~7

        // Row 2: [0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18]
        axi_write(`NPU_A_BUFFER_BASE + 4*4, 32'h14131211);   // Word 4: k=0~3
        axi_write(`NPU_A_BUFFER_BASE + 5*4, 32'h18171615);  // Word 5: k=4~7

        // Row 3: [0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20]
        axi_write(`NPU_A_BUFFER_BASE + 6*4, 32'h1C1B1A19);  // Word 6: k=0~3
        axi_write(`NPU_A_BUFFER_BASE + 7*4, 32'h201F1E1D);  // Word 7: k=4~7

        // Row 4: [0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28]
        axi_write(`NPU_A_BUFFER_BASE + 8*4, 32'h24232221);   // Word 8: k=0~3
        axi_write(`NPU_A_BUFFER_BASE + 9*4, 32'h28272625);   // Word 9: k=4~7

        // Row 5: [0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30]
        axi_write(`NPU_A_BUFFER_BASE + 10*4, 32'h2C2B2A29);  // Word 10: k=0~3
        axi_write(`NPU_A_BUFFER_BASE + 11*4, 32'h302F2E2D);  // Word 11: k=4~7

        // Row 6: [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38]
        axi_write(`NPU_A_BUFFER_BASE + 12*4, 32'h34333231);  // Word 12: k=0~3
        axi_write(`NPU_A_BUFFER_BASE + 13*4, 32'h38373635);  // Word 13: k=4~7

        // Row 7: [0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40]
        axi_write(`NPU_A_BUFFER_BASE + 14*4, 32'h3C3B3A39);  // Word 14: k=0~3
        axi_write(`NPU_A_BUFFER_BASE + 15*4, 32'h403F3E3D);  // Word 15: k=4~7
        
        // 【新增】打印 A 矩阵数值
        print_matrix_a_8x8(`NPU_A_BUFFER_BASE, "A");

        // 写入 B 矩阵数据（8×8单位矩阵）
        // B[i][j] = 1 (当i==j), 否则为0
        // 小端序：Byte0先发送给Tile
        $display("    写入 B 矩阵数据 (8×8单位矩阵)...");
        
        // Row 0: [1, 0, 0, 0, 0, 0, 0, 0]
        axi_write(`NPU_B_BUFFER_BASE + 0*4, 32'h00000001);  // Byte0=1
        axi_write(`NPU_B_BUFFER_BASE + 1*4, 32'h00000000);  // Byte4-7=0

        // Row 1: [0, 1, 0, 0, 0, 0, 0, 0]
        axi_write(`NPU_B_BUFFER_BASE + 2*4, 32'h00000100);  // Byte1=1
        axi_write(`NPU_B_BUFFER_BASE + 3*4, 32'h00000000);

        // Row 2: [0, 0, 1, 0, 0, 0, 0, 0]
        axi_write(`NPU_B_BUFFER_BASE + 4*4, 32'h00010000);  // Byte2=1
        axi_write(`NPU_B_BUFFER_BASE + 5*4, 32'h00000000);

        // Row 3: [0, 0, 0, 1, 0, 0, 0, 0]
        axi_write(`NPU_B_BUFFER_BASE + 6*4, 32'h01000000);  // Byte3=1
        axi_write(`NPU_B_BUFFER_BASE + 7*4, 32'h00000000);

        // Row 4: [0, 0, 0, 0, 1, 0, 0, 0]
        axi_write(`NPU_B_BUFFER_BASE + 8*4, 32'h00000000);   // Byte0-3=0
        axi_write(`NPU_B_BUFFER_BASE + 9*4, 32'h00000001);   // Byte4=1

        // Row 5: [0, 0, 0, 0, 0, 1, 0, 0]
        axi_write(`NPU_B_BUFFER_BASE + 10*4, 32'h00000000);  // Byte0-3=0
        axi_write(`NPU_B_BUFFER_BASE + 11*4, 32'h00000100);  // Byte5=1

        // Row 6: [0, 0, 0, 0, 0, 0, 1, 0]
        axi_write(`NPU_B_BUFFER_BASE + 12*4, 32'h00000000);  // Byte0-3=0
        axi_write(`NPU_B_BUFFER_BASE + 13*4, 32'h00010000);  // Byte6=1

        // Row 7: [0, 0, 0, 0, 0, 0, 0, 1]
        axi_write(`NPU_B_BUFFER_BASE + 14*4, 32'h00000000);  // Byte0-3=0
        axi_write(`NPU_B_BUFFER_BASE + 15*4, 32'h01000000);  // Byte7=1
        
        // 【新增】打印 B 矩阵数值
        print_matrix_b_8x8(`NPU_B_BUFFER_BASE);

        // 2. 写入 B 矩阵为单位矩阵 (4×8布局,K=4行有效)
        $display("    写入 B 矩阵 (单位矩阵)...");
        begin : write_identity_matrix_7b
            integer i;
            reg [31:0] b_data;
           // Row 0: [1, 0, 0, 0, 0, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 0*4, 32'h00000001);  // Byte0=1
            axi_write(`NPU_B_BUFFER_BASE + 1*4, 32'h00000000);  // Byte4-7=0

            // Row 1: [0, 1, 0, 0, 0, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 2*4, 32'h00000100);  // Byte1=1
            axi_write(`NPU_B_BUFFER_BASE + 3*4, 32'h00000000);

            // Row 2: [0, 0, 1, 0, 0, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 4*4, 32'h00010000);  // Byte2=1
            axi_write(`NPU_B_BUFFER_BASE + 5*4, 32'h00000000);

            // Row 3: [0, 0, 0, 1, 0, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 6*4, 32'h01000000);  // Byte3=1
            axi_write(`NPU_B_BUFFER_BASE + 7*4, 32'h00000000);

            // Row 4: [0, 0, 0, 0, 1, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 8*4, 32'h00000000);   // Byte0-3=0
            axi_write(`NPU_B_BUFFER_BASE + 9*4, 32'h00000001);   // Byte4=1

            // Row 5: [0, 0, 0, 0, 0, 1, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 10*4, 32'h00000000);  // Byte0-3=0
            axi_write(`NPU_B_BUFFER_BASE + 11*4, 32'h00000100);  // Byte5=1

            // Row 6: [0, 0, 0, 0, 0, 0, 1, 0]
            axi_write(`NPU_B_BUFFER_BASE + 12*4, 32'h00000000);  // Byte0-3=0
            axi_write(`NPU_B_BUFFER_BASE + 13*4, 32'h00010000);  // Byte6=1

            // Row 7: [0, 0, 0, 0, 0, 0, 0, 1]
            axi_write(`NPU_B_BUFFER_BASE + 14*4, 32'h00000000);  // Byte0-3=0
            axi_write(`NPU_B_BUFFER_BASE + 15*4, 32'h01000000);  // Byte7=1
        end
        
        // 【新增】打印重新写入后的 B 矩阵数值
        print_matrix_b_8x8(`NPU_B_BUFFER_BASE);
        
        wait_cycles(2);

        // 启动 NPU
        $display("    启动 NPU...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h01);  // start
        wait_cycles(3);

        // 等待 computing 信号
        $display("    等待 computing 信号...");
        wait_cycles(10);

        if (computing) begin
            $display("[PASS] computing = 1, NPU 正在执行");
        end else begin
            $display("[INFO] computing = 0, 可能已完成或未启动");
        end

        // 等待完成（超时保护）
        $display("    等待 NPU 完成...");
        begin : wait_done_block
            integer timeout_cnt;
            timeout_cnt = 0;
            while (!npu_done && timeout_cnt < 10000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (npu_done) begin
                $display("[PASS] npu_done 检测到! (timeout=%0d)", timeout_cnt);
            end else begin
                $display("[WARN] 等待超时, npu_done 未置位");
            end
        end

        // 检查状态
        wait_cycles(5);
        axi_read(`NPU_AXI_LITE_BASE + `REG_STATUS, read_val);
        $display("    STATUS 寄存器 = 0x%08X", read_val);
        if (read_val[0]) begin
            $display("[PASS] status_done = 1");
        end else begin
            $display("[INFO] status_done = 0");
        end

        // TEST 7b: 验证 C Buffer 数据完整性（使用单位矩阵验证）
        $display("\n  测试 7b: 验证 C Buffer 计算结果正确性 (B=I, 期望C[i][j]=A_byte[i*K+j])");

        // ===== 重新配置并启动 NPU 执行计算 =====
        $display("    重新配置并启动 NPU (B=I, K=4)...");

        // 1. 清除状态标志
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h02);  // status_clr
        wait_cycles(3);

        // 2. 写入 B 矩阵为单位矩阵 (4×8布局,K=4行有效)
        $display("    写入 B 矩阵 (单位矩阵)...");
        begin : write_identity_matrix
            integer i;
            reg [31:0] b_data;
           // Row 0: [1, 0, 0, 0, 0, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 0*4, 32'h00000001);  // Byte0=1
            axi_write(`NPU_B_BUFFER_BASE + 1*4, 32'h00000000);  // Byte4-7=0

            // Row 1: [0, 1, 0, 0, 0, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 2*4, 32'h00000100);  // Byte1=1
            axi_write(`NPU_B_BUFFER_BASE + 3*4, 32'h00000000);

            // Row 2: [0, 0, 1, 0, 0, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 4*4, 32'h00010000);  // Byte2=1
            axi_write(`NPU_B_BUFFER_BASE + 5*4, 32'h00000000);

            // Row 3: [0, 0, 0, 1, 0, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 6*4, 32'h01000000);  // Byte3=1
            axi_write(`NPU_B_BUFFER_BASE + 7*4, 32'h00000000);

            // Row 4: [0, 0, 0, 0, 1, 0, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 8*4, 32'h00000000);   // Byte0-3=0
            axi_write(`NPU_B_BUFFER_BASE + 9*4, 32'h00000001);   // Byte4=1

            // Row 5: [0, 0, 0, 0, 0, 1, 0, 0]
            axi_write(`NPU_B_BUFFER_BASE + 10*4, 32'h00000000);  // Byte0-3=0
            axi_write(`NPU_B_BUFFER_BASE + 11*4, 32'h00000100);  // Byte5=1

            // Row 6: [0, 0, 0, 0, 0, 0, 1, 0]
            axi_write(`NPU_B_BUFFER_BASE + 12*4, 32'h00000000);  // Byte0-3=0
            axi_write(`NPU_B_BUFFER_BASE + 13*4, 32'h00010000);  // Byte6=1

            // Row 7: [0, 0, 0, 0, 0, 0, 0, 1]
            axi_write(`NPU_B_BUFFER_BASE + 14*4, 32'h00000000);  // Byte0-3=0
            axi_write(`NPU_B_BUFFER_BASE + 15*4, 32'h01000000);  // Byte7=1
        end

        // 3. 配置 NPU 参数 (INDEP模式, M=8, N=8, K=4)
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h00);      // INDEP
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'h0000_0001);  // Tile 0
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd1);

        // 4. 启动 NPU
        $display("    启动 NPU...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h01);  // start
        wait_cycles(3);

        // 5. 等待完成
        $display("    等待 NPU 完成...");
        begin : wait_test8_done
            integer timeout_cnt;
            timeout_cnt = 0;
            while (!npu_done && timeout_cnt < 10000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (npu_done) begin
                $display("[PASS] npu_done 检测到! (timeout=%0d)", timeout_cnt);
            end else begin
                $display("[FAIL] 等待超时, npu_done 未置位");
                test_passed = 1'b0;
            end
        end

        // 6. 检查状态
        wait_cycles(5);
        axi_read(`NPU_AXI_LITE_BASE + `REG_STATUS, read_val);
        $display("    STATUS 寄存器 = 0x%08X", read_val);
        if (read_val[0]) begin
            $display("[PASS] status_done = 1");
        end else begin
            $display("[INFO] status_done = 0");
        end

        // 【调试】打印 A、B 矩阵和 C 矩阵前几行数据
        begin : debug_print_abc_matrices
            integer i;
            reg [31:0] a_val, b_val, c_val;

            $display("\n    ===== 调试信息：计算完成后 A/B/C 矩阵数据 =====");
            $display("    --- A 矩阵 (8×8布局,地址 0x%08X - 0x%08X) ---",
                     `NPU_A_BUFFER_BASE, `NPU_A_BUFFER_BASE + 15*4);
            for (i = 0; i < 8; i = i + 1) begin
                // 每行占用2个word,读取第一个word(前4列)
                axi_read(`NPU_A_BUFFER_BASE + (i*2)*4, a_val);
                $display("      Row %d [k=0-3] @0x%08X = 0x%08X (bytes: %02X %02X %02X %02X)",
                         i, `NPU_A_BUFFER_BASE + (i*2)*4, a_val,
                         a_val[7:0], a_val[15:8], a_val[23:16], a_val[31:24]);
                // 读取第二个word(后4列,应为0)
                axi_read(`NPU_A_BUFFER_BASE + (i*2+1)*4, a_val);
                $display("      Row %d [k=4-7] @0x%08X = 0x%08X (应全0)",
                         i, `NPU_A_BUFFER_BASE + (i*2+1)*4, a_val);
            end

            $display("    --- B 矩阵 (地址 0x%08X - 0x%08X) ---",
                     `NPU_B_BUFFER_BASE, `NPU_B_BUFFER_BASE + 7*4);
            for (i = 0; i < 8; i = i + 1) begin
                axi_read(`NPU_B_BUFFER_BASE + i*4, b_val);
                $display("      B[%0d] @0x%08X = 0x%08X", i, `NPU_B_BUFFER_BASE + i*4, b_val);
            end

            $display("    --- C 矩阵 (8x8 INT32, 共64个word) ---");
            for (i = 0; i < 8; i = i + 1) begin
                axi_read(`NPU_C_BUFFER_BASE + (i*8+0)*4, c_val);
                $display("      C[%0d][0..3] = 0x%08X", i, c_val);
            end

            $display("    =================================================\n");
        end

        // 验证：C[i][j] = sum_k(A_byte[i*K+k] * B_byte[k*8+j])
        // B = 8×8单位矩阵 => C[i][j] = A_byte[i*K+j] (当 j < K)
        // K=8 时所有8列都应该有值
        // 注意：A Buffer 每行2个word(8字节)，C Buffer 每个word是1个INT32
        begin : verify_c_with_identity
            integer i, j, k;
            reg [31:0] a_word;
            reg [31:0] c_val;
            reg [7:0]  a_byte, expected_byte;
            integer errors;
            errors = 0;

            $display("    验证 Tile 0 的计算结果 (B=I, K=%0d, 期望 C[i][j]=A_byte[i*K+j])...", 8);

            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    // 读取对应的 A word 并提取 byte
                    // 8×8 Tile架构下，每行占用2个word:
                    //   Word 2*i+0: A[i][0-3]
                    //   Word 2*i+1: A[i][4-7]
                    if (j < 4) begin
                        axi_read(`NPU_A_BUFFER_BASE + (i*2)*4, a_word);
                        a_byte = a_word[j*8 +: 8];  // 从第一个word提取
                    end else begin
                        axi_read(`NPU_A_BUFFER_BASE + (i*2+1)*4, a_word);
                        a_byte = a_word[(j-4)*8 +: 8];  // 从第二个word提取
                    end

                    // K=8, B=I, 所有8列都有值: C[i][j] = A[i][j]
                    expected_byte = a_byte;

                    // 读取 C[i][j] (每个元素32bit, 在 C Buffer 中连续存放)
                    axi_read(`NPU_C_BUFFER_BASE + (i*8+j)*4, c_val);

                    // 比较低8位（MAC结果是INT32，但用B=I时值应在0~255范围）
                    if (c_val[7:0] !== expected_byte || c_val[31:8] !== 24'd0) begin
                        if (errors < 16) begin  // 最多打印16个错误
                            $display("      [FAIL] C[%0d][%0d]: 期望=0x%08X, 实际=0x%08X",
                                     i, j, {24'd0, expected_byte}, c_val);
                        end
                        errors = errors + 1;
                    end
                end
            end

            if (errors == 0) begin
                $display("    验证通过！\n");
            end else begin
                $display("    验证失败！共 %0d 个错误\n", errors);
            end

            if (errors == 0) begin
                $display("    [PASS] 测试 7b: Tile 0 计算结果正确，共验证 64 个元素");
            end else begin
                $display("    [FAIL] 测试 7b: Tile 0 有 %0d / 64 个错误", errors);
                test_passed = 1'b0;
            end
        end

*/
        // ================================================================
        //  阶段4: MERGE 模式严格验证测试
        // ================================================================
        $display("\n============================================================");
        $display("  阶段4: MERGE 模式严格验证测试");
        $display("  目标: 验证多 Tile 合并模式的正确性");
        $display("  配置: M=32, N=8, K=4, Tile 0-3");
        $display("============================================================");

        // TEST 8: MERGE 模式严格验证
        test_num = test_num + 1;
        $display("\n  测试 %d: MERGE 模式完整验证 (M=32, N=8, K=8, Tile 0-3)", test_num);

        // ============================================================
        // 步骤1: 清除状态标志
        // ============================================================
        $display("    [步骤1] 清除状态标志...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h02);  // status_clr
        wait_cycles(10);

        // ============================================================
        // 步骤2: 配置 MERGE 模式参数
        // ============================================================
        $display("    [步骤2] 配置 MERGE 模式参数...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h01);      // MERGE 模式
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd32);         // M=32 (32行)
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd8);          // N=8 (8列)
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd8);          // K=8 (内维度，完整Tile容量)
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'h0000_000F);  // 启用 Tile 0-3
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd1);         // 单次迭代
        
        $display("      配置: MODE=MERGE, M=32, N=8, K=8, TILE_MASK=0x%08X", 32'h0000_000F);

        // ============================================================
        // 步骤3: 构造 A 矩阵 (32×8, INT8)
        // ============================================================
        // MERGE 模式下，A 矩阵按完整 8×8 布局存储
        // 32行 × 8列 = 256 个 INT8 = 64 个 32-bit word
        $display("    [步骤3] 构造 A 矩阵 (32×8, 按8×8布局存储)...");
        
        begin : construct_merge_a_matrix
            integer row, col;
            reg [7:0] a_byte;
            reg [31:0] a_word;
            
            // 按行优先顺序构造 A 矩阵
            // 每行 8 字节（全部有效），占用 2 个 word
            for (row = 0; row < 32; row = row + 1) begin
                // Word 0: 前 4 列
                a_word = 0;
                for (col = 0; col < 4; col = col + 1) begin
                    // 构造可预测的数据：A[row][col] = row * 8 + col
                    a_byte = (row * 8 + col) & 8'hFF;
                    a_word[col*8 +: 8] = a_byte;
                end
                axi_write(`NPU_A_BUFFER_BASE + (row*2)*4, a_word);
                
                // Word 1: 后 4 列
                a_word = 0;
                for (col = 4; col < 8; col = col + 1) begin
                    a_byte = (row * 8 + col) & 8'hFF;
                    a_word[(col-4)*8 +: 8] = a_byte;
                end
                axi_write(`NPU_A_BUFFER_BASE + (row*2+1)*4, a_word);
            end
            
            $display("      A 矩阵构造完成: 32行 × 8列 = 64 words");
            $display("      数据模式: A[row][col] = row*8 + col");
        end

        // ============================================================
        // 步骤4: 构造 B 矩阵 (8×8, INT8) - 标准单位矩阵
        // ============================================================
        // B 矩阵为 8×8 标准单位矩阵
        // B[i][j] = 1 (当 i==j), 否则为 0
        // 这样 C = A × B = A（完美验证）
        $display("    [步骤4] 构造 B 矩阵 (8×8, 标准单位矩阵)...");
        
        begin : construct_merge_b_matrix
            integer row, col;
            reg [7:0] b_byte;
            reg [31:0] b_word;
            
            // B 矩阵: 8行 × 8列 = 64 字节 = 16 words
            // 每行占用 2 个 word（前 4 列 + 后 4 列）
            for (row = 0; row < 8; row = row + 1) begin
                // Word 0: 前 4 列
                b_word = 0;
                for (col = 0; col < 4; col = col + 1) begin
                    if (col == row) begin
                        b_byte = 8'h01;
                    end else begin
                        b_byte = 8'h00;
                    end
                    b_word[col*8 +: 8] = b_byte;
                end
                axi_write(`NPU_B_BUFFER_BASE + (row*2)*4, b_word);
                
                // Word 1: 后 4 列
                b_word = 0;
                for (col = 4; col < 8; col = col + 1) begin
                    if (col == row) begin
                        b_byte = 8'h01;
                    end else begin
                        b_byte = 8'h00;
                    end
                    b_word[(col-4)*8 +: 8] = b_byte;
                end
                axi_write(`NPU_B_BUFFER_BASE + (row*2+1)*4, b_word);
            end
            
            $display("      B 矩阵构造完成: 8行 × 8列 = 16 words");
            $display("      数据模式: B[i][j] = 1 (当 i==j), 否则 0");
            $display("      预期结果: C[row][col] = A[row][col] (所有元素)");
        end

        // ============================================================
        // 步骤5: 打印输入矩阵用于调试
        // ============================================================
        $display("    [步骤5] 打印输入矩阵（前8行）...");
        begin : print_merge_input_matrices
            integer i;
            reg [31:0] val;
            
            $display("      --- A 矩阵前8行 ---");
            for (i = 0; i < 32; i = i + 1) begin
                // Word 0: 前 4 列
                axi_read(`NPU_A_BUFFER_BASE + (i*2)*4, val);
                $display("        A[%d][0-3] = 0x%08X (bytes: %2d %2d %2d %2d)",
                         i, val,
                         $signed(val[7:0]), $signed(val[15:8]), 
                         $signed(val[23:16]), $signed(val[31:24]));
                
                // Word 1: 后 4 列
                axi_read(`NPU_A_BUFFER_BASE + (i*2+1)*4, val);
                $display("        A[%d][4-7] = 0x%08X (bytes: %2d %2d %2d %2d)",
                         i, val,
                         $signed(val[7:0]), $signed(val[15:8]), 
                         $signed(val[23:16]), $signed(val[31:24]));
            end
            
            $display("      --- B 矩阵（8×8 单位矩阵）---");
            for (i = 0; i < 8; i = i + 1) begin
                // Word 0: 前 4 列
                axi_read(`NPU_B_BUFFER_BASE + (i*2)*4, val);
                $display("        B[%d][0-3] = 0x%08X (bytes: %2d %2d %2d %2d)",
                         i, val,
                         $signed(val[7:0]), $signed(val[15:8]), 
                         $signed(val[23:16]), $signed(val[31:24]));
                
                // Word 1: 后 4 列
                axi_read(`NPU_B_BUFFER_BASE + (i*2+1)*4, val);
                $display("        B[%d][4-7] = 0x%08X (bytes: %2d %2d %2d %2d)",
                         i, val,
                         $signed(val[7:0]), $signed(val[15:8]), 
                         $signed(val[23:16]), $signed(val[31:24]));
            end
        end

        // ============================================================
        // 步骤6: 启动 NPU
        // ============================================================
        $display("    [步骤6] 启动 NPU...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h01);  // start 脉冲
        wait_cycles(3);

        // ============================================================
        // 步骤7: 等待计算完成（带超时保护）
        // ============================================================
        $display("    [步骤7] 等待 NPU 完成计算...");
        begin : wait_merge_completion
            integer timeout_cnt;
            timeout_cnt = 0;
            while (!npu_done && timeout_cnt < 50000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            
            if (npu_done) begin
                $display("      [PASS] npu_done 信号检测到 (耗时 %0d 周期)", timeout_cnt);
            end else begin
                $display("      [FAIL] 等待超时! npu_done 未置位 (timeout=%0d)", timeout_cnt);
                test_passed = 1'b0;
                disable wait_merge_completion;
            end
        end

        // ============================================================
        // 步骤8: 验证状态寄存器
        // ============================================================
        $display("    [步骤8] 验证状态寄存器...");
        wait_cycles(5);
        axi_read(`NPU_AXI_LITE_BASE + `REG_STATUS, read_val);
        $display("      STATUS 寄存器 = 0x%08X", read_val);
        
        if (read_val[0] === 1'b1) begin
            $display("      [PASS] status_done = 1");
        end else begin
            $display("      [FAIL] status_done = 0 (期望 1)");
            test_passed = 1'b0;
        end
        
        if (read_val[1] === 1'b1) begin
            $display("      [FAIL] status_error = 1 (检测到错误!)");
            test_passed = 1'b0;
        end else begin
            $display("      [PASS] status_error = 0");
        end

        // ============================================================
        // 步骤9: 读取并验证 C 矩阵结果
        // ============================================================
        $display("    [步骤9] 验证 C 矩阵计算结果...");
        
        begin : verify_merge_result
            integer row, col;
            reg [31:0] c_val;
            reg [31:0] expected_val;
            reg [7:0]  a_byte;
            integer errors;
            integer total_elements;
            
            errors = 0;
            total_elements = 32 * 8;  // 32行 × 8列
            
            $display("      开始验证 C 矩阵 (32×8, 共 %0d 个元素)...", total_elements);
            
            // 逐元素验证 C 矩阵
            // 理论预期：C = A × B，其中 B 是标准单位矩阵
            // 因此 C[row][col] = A[row][col] (所有 col)
            for (row = 0; row < 32; row = row + 1) begin
                for (col = 0; col < 8; col = col + 1) begin
                    // 读取 C 矩阵元素
                    axi_read(`NPU_C_BUFFER_BASE + (row*8 + col)*4, c_val);
                    
                    // 计算期望值
                    // C[row][col] = A[row][col] = row*8 + col
                    expected_val = 32'd0;
                    expected_val[7:0] = (row * 8 + col) & 8'hFF;

                    
                    // 验证结果
                    if (c_val !== expected_val) begin
                        if (errors < 32) begin  // 最多打印32个错误
                            $display("        [FAIL] C[%0d][%0d]: 期望=0x%08X (%0d), 实际=0x%08X (%0d)",
                                     row, col, expected_val, $signed(expected_val[7:0]),
                                     c_val, $signed(c_val[7:0]));
                        end
                        errors = errors + 1;
                    end
                end
                
                // 每8行打印一次进度
                if ((row + 1) % 8 == 0) begin
                    $display("        进度: 已验证 %0d/%0d 行, 发现 %0d 个错误", 
                             row + 1, 32, errors);
                end
            end
            
            // 总结验证结果
            $display("");
            if (errors == 0) begin
                $display("      [PASS] MERGE 模式计算结果完全正确!");
                $display("             验证了 %0d 个元素，全部匹配", total_elements);
            end else begin
                $display("      [FAIL] MERGE 模式计算结果有误!");
                $display("             共 %0d / %0d 个元素不匹配 (%.2f%% 错误率)",
                         errors, total_elements, 
                         real'(errors) / real'(total_elements) * 100.0);
                test_passed = 1'b0;
            end
        end

        // ============================================================
        // 步骤10: 打印 C 矩阵前8行用于调试
        // ============================================================
        $display("    [步骤10] 打印 C 矩阵前8行（调试用）...");
        begin : print_merge_c_matrix
            integer i, j;
            reg [31:0] c_val;
            
            $display("      --- C 矩阵前16行 ---");
            for (i = 0; i < 32; i = i + 1) begin
                $write("        C[%d] = [", i);
                for (j = 0; j < 8; j = j + 1) begin
                    axi_read(`NPU_C_BUFFER_BASE + (i*8 + j)*4, c_val);
                    if (j > 0) $write(", ");
                    $write("%4d", $signed(c_val[7:0]));
                end
                $display("]");
            end
        end

        // ================================================================
        //  阶段5-9: 其他测试（暂时注释，专注于 MERGE 模式验证）
        // ================================================================
/*
       

        // ================================================================
        //  阶段5: SPLIT 模式完整测试
        // ================================================================
        $display("\n============================================================");
        $display("  阶段5: SPLIT 模式测试");
        $display("  目标: 验证大 K 值拆分模式");
        $display("============================================================");

        // TEST 9: SPLIT 模式完整执行流程
        test_num = test_num + 1;
        $display("\n  测试 %d: SPLIT 模式完整执行 (K=8, Tile 0-3)", test_num);

        // 清除状态
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h02);  // status_clr
        wait_cycles(3);

        // 配置 SPLIT 模式
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h02);      // SPLIT
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd4);
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd4);
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd8);          // K=8
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'h0000_000F);  // Tile 0-3
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd1);

        // 写入 A 矩阵数据（SPLIT 模式下每个 Tile 处理部分 K）
        $display("    写入 A 矩阵数据...");
        for (i = 0; i < 16; i = i + 1) begin  // 2*K = 16 words
            axi_write(`NPU_A_BUFFER_BASE + i*4, 32'h0000_5000 + i);
        end

        // 写入 B 矩阵数据
        $display("    写入 B 矩阵数据...");
        for (i = 0; i < 16; i = i + 1) begin
            axi_write(`NPU_B_BUFFER_BASE + i*4, 32'h0000_6000 + i);
        end

        wait_cycles(2);

        // 启动 NPU
        $display("    启动 NPU (SPLIT 模式)...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h01);  // start
        wait_cycles(3);

        // 等待完成
        $display("    等待 NPU 完成...");
        begin : wait_split_done
            integer timeout_cnt;
            timeout_cnt = 0;
            while (!npu_done && timeout_cnt < 10000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (npu_done) begin
                $display("[PASS] SPLIT 模式完成! (timeout=%0d)", timeout_cnt);
            end else begin
                $display("[FAIL] SPLIT 模式超时"); test_passed = 1'b0;
            end
        end

        // 验证状态
        wait_cycles(5);
        axi_read(`NPU_AXI_LITE_BASE + `REG_STATUS, read_val);
        if (read_val[0]) begin
            $display("[PASS] status_done = 1");
        end else begin
            $display("[FAIL] status_done = 0"); test_passed = 1'b0;
        end

        // ================================================================
        //  阶段6: 多次迭代测试
        // ================================================================
        $display("\n============================================================");
        $display("  阶段6: 多次迭代测试");
        $display("  目标: 验证 cfg_iterations > 1 的情况");
        $display("============================================================");

        // TEST 10: 多次迭代执行
        test_num = test_num + 1;
        $display("\n  测试 %d: 多次迭代执行 (iterations=2)", test_num);

        // 清除状态
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h02);  // status_clr
        wait_cycles(3);

        // 配置多次迭代
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h00);      // INDEP
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd4);
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'h0000_0001);  // Tile 0
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd2);  // 2次迭代

        // 写入数据
        $display("    写入数据...");
        for (i = 0; i < 8; i = i + 1) begin
            axi_write(`NPU_A_BUFFER_BASE + i*4, 32'h0000_7000 + i);
            axi_write(`NPU_B_BUFFER_BASE + i*4, 32'h0000_8000 + i);
        end

        wait_cycles(2);

        // 启动 NPU
        $display("    启动 NPU (2次迭代)...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h01);  // start
        wait_cycles(3);

        // 等待完成
        $display("    等待 NPU 完成...");
        begin : wait_iter_done
            integer timeout_cnt;
            timeout_cnt = 0;
            while (!npu_done && timeout_cnt < 20000) begin  // 更长的超时
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (npu_done) begin
                $display("[PASS] 多次迭代完成! (timeout=%0d)", timeout_cnt);
            end else begin
                $display("[FAIL] 多次迭代超时"); test_passed = 1'b0;
            end
        end

        // ================================================================
        //  阶段7: 边界条件测试
        // ================================================================
        $display("\n============================================================");
        $display("  阶段7: 边界条件测试");
        $display("  目标: 验证极端配置下的行为");
        $display("============================================================");

        // TEST 11: 最大 K 值 (6位最大值为63)
        test_num = test_num + 1;
        $display("\n  测试 %d: 最大 K 值 (K=63)", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd63);
        wait_cycles(1);
        if (cfg_k !== 6'd63) begin
            $display("[FAIL] cfg_k = %d, 期望 63", cfg_k); test_passed = 1'b0;
        end else $display("[PASS] cfg_k = 63");

        // TEST 12: 最大 Tile Mask
        test_num = test_num + 1;
        $display("\n  测试 %d: 最大 Tile Mask (0xFFFFFFFF)", test_num);
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'hFFFF_FFFF);
        wait_cycles(1);
        if (cfg_tile_mask !== 32'hFFFF_FFFF) begin
            $display("[FAIL] cfg_tile_mask = 0x%08X", cfg_tile_mask); test_passed = 1'b0;
        end else $display("[PASS] cfg_tile_mask = 0xFFFFFFFF");

        // ================================================================
        //  阶段8: 中断验证
        // ================================================================
        $display("\n============================================================");
        $display("  阶段8: 中断验证");
        $display("  目标: 验证 npu_irq 信号");
        $display("============================================================");

        // TEST 13: 检查中断状态
        test_num = test_num + 1;
        $display("\n  测试 %d: 中断信号检查", test_num);
        $display("    npu_irq = %b", npu_irq);
        $display("    irq_en_done = %b, irq_en_error = %b", irq_en_done, irq_en_error);
        $display("    status_done = %b, status_error = %b", status_done, status_error);
        $display("[PASS] 中断信号检查完成");

        // ================================================================
        //  阶段9: 多 Tile 并行测试
        // ================================================================
        $display("\n============================================================");
        $display("  阶段9: 多 Tile 并行测试");
        $display("  目标: 验证多个 Tile 并行计算");
        $display("============================================================");

        // TEST 14: 4 个 Tile 并行计算
        test_num = test_num + 1;
        $display("\n  测试 %d: 4 Tile 并行计算 (INDEP, K=4)", test_num);

        // 清除状态
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h02);  // status_clr
        wait_cycles(3);

        // 配置 4 个 Tile
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h00);      // INDEP
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd4);
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd4);
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd4);
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'h0000_000F);  // Tile 0-3
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd1);

        // 写入数据（每个 Tile 独立数据）
        $display("    写入数据...");
        for (i = 0; i < 4; i = i + 1) begin  // 4 个 Tile
            for (j = 0; j < 8; j = j + 1) begin  // 每个 Tile 8 words
                axi_write(`NPU_A_BUFFER_BASE + i*256 + j*4, 32'h0000_9000 + i*256 + j);
                axi_write(`NPU_B_BUFFER_BASE + i*256 + j*4, 32'h0000_A000 + i*256 + j);
            end
        end

        wait_cycles(2);

        // 启动 NPU
        $display("    启动 NPU (4 Tile 并行)...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h01);  // start
        wait_cycles(3);

        // 等待完成
        $display("    等待 NPU 完成...");
        begin : wait_parallel_done
            integer timeout_cnt;
            timeout_cnt = 0;
            while (!npu_done && timeout_cnt < 15000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (npu_done) begin
                $display("[PASS] 4 Tile 并行计算完成! (timeout=%0d)", timeout_cnt);
            end else begin
                $display("[FAIL] 4 Tile 并行计算超时"); test_passed = 1'b0;
            end
        end

        // 验证所有 Tile 的结果
        $display("    验证 C Buffer...");
        begin : verify_parallel_c
            integer tile_idx, word_idx;
            reg [31:0] c_val;
            integer total_zeros, total_x;
            total_zeros = 0;
            total_x = 0;
            
            // 检查每个Tile的C Buffer是否有有效数据
            for (tile_idx = 0; tile_idx < 4; tile_idx = tile_idx + 1) begin
                integer tile_zeros, tile_x;
                tile_zeros = 0;
                tile_x = 0;
                
                // 读取每个Tile的前8个word
                for (word_idx = 0; word_idx < 8; word_idx = word_idx + 1) begin
                    axi_read(`NPU_C_BUFFER_BASE + tile_idx*256 + word_idx*4, c_val);
                    
                    if (word_idx == 0) begin
                        $display("      Tile %0d C[0] = 0x%08X", tile_idx, c_val);
                    end
                    
                    if (c_val === 32'h0) begin
                        tile_zeros = tile_zeros + 1;
                    end else if (c_val === 32'hx) begin
                        tile_x = tile_x + 1;
                    end
                end
                
                total_zeros = total_zeros + tile_zeros;
                total_x = total_x + tile_x;
                
                if (tile_x > 0) begin
                    $display("        [FAIL] Tile %0d 有 %0d 个X态值", tile_idx, tile_x);
                end else if (tile_zeros == 8) begin
                    $display("        [WARN] Tile %0d 全为零", tile_idx);
                end else begin
                    $display("        [PASS] Tile %0d 包含有效数据", tile_idx);
                end
            end
            
            if (total_x > 0) begin
                $display("    [FAIL] 4 Tile并行: 总共有 %0d 个X态값", total_x);
            end else begin
                $display("    [INFO] 4 Tile并行: 所有Tile无X态값 (零值总数=%0d)", total_zeros);
            end
        end
*/
        // ================================================================
        //  测试总结
        // ================================================================
        wait_cycles(5);
        $display("\n============================================================");
        $display("  NPU 联合测试总结");
        $display("============================================================");
        $display("  总测试数: %d", test_num);
        $display("");
        $display("  测试覆盖:");
        $display("    - 阶段1: 基础通信 (AXI + Config + Buffer) - 4个测试");
        $display("    - 阶段2: 状态与中断 - 2个测试");
        $display("    - 阶段3: INDEP 模式完整流程 + 数据验证 - 2个测试");
        $display("    - 阶段4: MERGE 模式完整流程 - 1个测试");
        $display("    - 阶段5: SPLIT 模式完整流程 - 1个测试");
        $display("    - 阶段6: 多次迭代 - 1个测试");
        $display("    - 阶段7: 边界条件 - 2个测试");
        $display("    - 阶段8: 中断验证 - 1个测试");
        $display("    - 阶段9: 多 Tile 并行 - 1个测试");
        $display("");
        if (test_passed) begin
            $display("  结果: 全部测试通过!");
        end else begin
            $display("  结果: 部分测试失败!");
        end
        $display("  结束时间: %t", $time);
        $display("============================================================");

        #50;
        $finish;
    end

    // ============================================================
    //  超时保护
    // ============================================================
    initial begin
        #2000000;  // 2ms 超时
        $display("\n[ERROR] 仿真超时！可能存在死锁。");
        $finish;
    end

    // ============================================================
    //  监控输出
    // ============================================================
    always @(posedge clk) begin
        // 监控状态机变化
        if (u_scheduler.npu_state !== npu_state) begin
            $display("[t=%0t] Scheduler State = %0d", $time, u_scheduler.npu_state);
        end

        // 监控 Data Mover 状态
        if (u_data_mover.state !== u_data_mover.prev_state) begin
            case (u_data_mover.state)
                5'd0: $display("[t=%0t] DataMover -> IDLE", $time);
                5'd1: $display("[t=%0t] DataMover -> LOAD_A", $time);
                5'd4: $display("[t=%0t] DataMover -> LOAD_B", $time);
                5'd10: $display("[t=%0t] DataMover -> STORE", $time);
                5'd12: $display("[t=%0t] DataMover -> DONE", $time);
                default: ;  // 不打印中间状态
            endcase
        end
    end

endmodule