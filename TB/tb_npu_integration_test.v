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
    
    // 每个 Tile 在 Buffer 中的偏移量 (基于 8x8 INT8 输入, 8x8 INT32 输出)
    // A/B Buffer: 8*8 bytes = 64 bytes = 16 words
    // C Buffer: 8*8 * 4 bytes = 256 bytes = 64 words
    parameter TILE_A_OFFSET_WORDS = 16; 
    parameter TILE_B_OFFSET_WORDS = 16;
    parameter TILE_C_OFFSET_WORDS = 64;

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
    wire [TILE_COUNT-1:0]    tile_a_ready;
    wire [A_BUS_WIDTH-1:0]   tile_b_data;
    wire                     tile_b_valid;
    wire [TILE_COUNT-1:0]    tile_b_ready;
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
        .tile_a_ready   (tile_a_ready),
        .tile_b_data    (tile_b_data),
        .tile_b_valid   (tile_b_valid),
        .tile_b_ready   (tile_b_ready),
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
        .tile_a_ready   (tile_a_ready),
        .tile_b_data    (tile_b_data),
        .tile_b_valid   (tile_b_valid),
        .tile_b_ready   (tile_b_ready),
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
    reg [ADDR_WIDTH-1:0] b_tile_base;
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
*/
/*  
               // ================================================================
        //  阶段3: 完整执行流程测试 (INDEP 模式, K=8, 32 Tiles)
        // ================================================================
        $display("\n============================================================");
        $display("  阶段3: 全量 Tile 压力测试 (INDEP, K=8, 32 Tiles)");
        $display("  目标: 验证所有 32 个 Tile 的并行计算正确性");
        $display("  策略: 随机数据 + 在线软件比对 (On-the-fly Verification)");
        $display("============================================================");

        test_num = test_num + 1;
        $display("\n  测试 %d: 32-Tile 并行计算验证", test_num);

        // 1. 清除状态 & 配置
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h02); wait_cycles(3);
        
        $display("    [步骤1] 配置 NPU (Mode=INDEP, M=N=K=8, Mask=0xFFFFFFFF)...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_MODE, 32'h00);
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd8);
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'hFFFF_FFFF); // Enable All 32 Tiles
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd1);

        // 3. 写入 A 矩阵数据 (为每个Tile写入不同的数据)
        $display("    [步骤2] 写入 A 矩阵数据");
        
        // ===== Tile 0 数据 (offset 0x000 - 0x03C) =====
  
        for (i = 0; i < 512; i = i + 1) begin
            axi_write(`NPU_A_BUFFER_BASE + i*4, i+1);
        end


        // 4. 写入 B 矩阵数据（8×8单位矩阵，所有Tile共享）
        $display("    [步骤3] 写入 B 矩阵数据 (8×8单位矩阵)...");
        
       for (i = 0; i < 32; i = i + 1) begin
            // 计算当前 Tile 的 B 矩阵基地址
            // 假设 B Buffer 中 Tile 是连续排列的，每个 Tile 占 16 words (64 bytes)
            b_tile_base = `NPU_B_BUFFER_BASE + (i * 16 * 4);

            // Row 0: [1, 0, 0, 0, 0, 0, 0, 0]
            axi_write(b_tile_base + 0*4, 32'h00000001);
            axi_write(b_tile_base + 1*4, 32'h00000000);

            // Row 1: [0, 1, 0, 0, 0, 0, 0, 0]
            axi_write(b_tile_base + 2*4, 32'h00000100);
            axi_write(b_tile_base + 3*4, 32'h00000000);

            // Row 2: [0, 0, 1, 0, 0, 0, 0, 0]
            axi_write(b_tile_base + 4*4, 32'h00010000);
            axi_write(b_tile_base + 5*4, 32'h00000000);

            // Row 3: [0, 0, 0, 1, 0, 0, 0, 0]
            axi_write(b_tile_base + 6*4, 32'h01000000);
            axi_write(b_tile_base + 7*4, 32'h00000000);
            
            // Row 0: [1, 0, 0, 0, 0, 0, 0, 0]
            axi_write(b_tile_base + 8*4, 32'h00000000);
            axi_write(b_tile_base + 9*4, 32'h00000001);

            // Row 1: [0, 1, 0, 0, 0, 0, 0, 0]
            axi_write(b_tile_base + 10*4, 32'h00000000);
            axi_write(b_tile_base + 11*4, 32'h00000100);

            // Row 2: [0, 0, 1, 0, 0, 0, 0, 0]
            axi_write(b_tile_base + 12*4, 32'h00000000);
            axi_write(b_tile_base + 13*4, 32'h00010000);


            // Row 3: [0, 0, 0, 1, 0, 0, 0, 0]
            axi_write(b_tile_base + 14*4, 32'h00000000);
            axi_write(b_tile_base + 15*4, 32'h01000000);

            
            $display("      Tile %d B Matrix Written to Base 0x%08X", i, b_tile_base);
        end
        // 打印 B 矩阵数值
        print_matrix_b_8x8(`NPU_B_BUFFER_BASE);
        
        wait_cycles(2);

        // 5. 启动 NPU
        $display("    [步骤4] 启动 NPU...");
        axi_write(`NPU_AXI_LITE_BASE + `REG_CTRL, 32'h01);  // start
        wait_cycles(3);

        // 等待 computing 信号
        $display("    [步骤5] 等待 computing 信号...");
        wait_cycles(10);

        if (computing) begin
            $display("[PASS] computing = 1, NPU 正在执行");
        end else begin
            $display("[INFO] computing = 0, 可能已完成或未启动");
        end

        // 等待完成（超时保护）
        $display("    [步骤6] 等待 NPU 完成...");
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
                $display("[FAIL] 等待超时, npu_done 未置位");
                test_passed = 1'b0;
            end
        end

        // 检查状态
        wait_cycles(5);
        axi_read(`NPU_AXI_LITE_BASE + `REG_STATUS, read_val);
        $display("    STATUS 寄存器 = 0x%08X", read_val);
        if (read_val[0]) begin
            $display("[PASS] status_done = 1");
        end else begin
            $display("[FAIL] status_done = 0");
            test_passed = 1'b0;
        end

        // 【调试】打印 C 矩阵数据（仅显示每个Tile的第0行）
        begin : debug_print_c_matrices
            integer tile_id;
            reg [31:0] c_val;

            $display("\n    ===== 调试信息：计算完成后 C 矩阵数据 =====");
            for (tile_id = 0; tile_id < 4; tile_id = tile_id + 1) begin
                $display("    --- Tile %d C矩阵 (第0行) ---", tile_id);
                axi_read(`NPU_C_BUFFER_BASE + (tile_id*64+0)*4, c_val);
                $display("      C[%d][0][0..3] = 0x%08X", tile_id, c_val);
            end
            $display("    =================================================\n");
        end

        // 验证：对每个Tile验证 C[i][j] = A[i][j] (当 B=I 且 j<K=4)
        // Tile 0: A[0][j] = j+1
        // Tile 1: A[0][j] = j+11
        // Tile 2: A[0][j] = j+21
        // Tile 3: A[0][j] = j+31
                    begin : verify_all_tiles_correct
            integer tile_id;
            integer row, col; // 使用行列索引更清晰
            reg [31:0] word_a; // A 的一个打包 Word
            reg [31:0] word_c; // C 的一个单值 Word
            reg signed [7:0] byte_a; // A 的单个字节
            reg signed [31:0] expected_c; // 期望的 C 值 (符号扩展后)
            integer errors;
            integer total_errors;
            reg [ADDR_WIDTH-1:0] addr_a_word, addr_c_word;

            total_errors = 0;
            $display("    [步骤7] 验证 Tile 0-31 的计算结果 (C == A, 考虑位宽转换)...");

            for (tile_id = 0; tile_id < 32; tile_id = tile_id + 1) begin
                errors = 0;
                
                // 遍历 8x8 矩阵的每一个元素
                for (row = 0; row < 8; row = row + 1) begin
                    for (col = 0; col < 8; col = col + 1) begin
                        
                        // 1. 计算 A 的地址 (按 Word 访问)
                        // A 的布局: 每行 2 个 Word. 
                        // Word Index in Tile = row * 2 + (col / 4)
                        // Byte Index in Word = col % 4
                        addr_a_word = `NPU_A_BUFFER_BASE + 
                                      (tile_id * TILE_A_OFFSET_WORDS + row * 2 + (col / 4)) * 4;
                        
                        // 2. 计算 C 的地址 (按 Word 访问)
                        // C 的布局: 每行 8 个 Word (每个元素一个 Word)
                        // Word Index in Tile = row * 8 + col
                        addr_c_word = `NPU_C_BUFFER_BASE + 
                                      (tile_id * TILE_C_OFFSET_WORDS + row * 8 + col) * 4;

                        // 3. 读取数据
                        axi_read(addr_a_word, word_a);
                        axi_read(addr_c_word, word_c);

                        // 4. 从 A 的 Word 中提取对应的 8-bit 字节
                        // Little-Endian: Byte 0 is LSB
                        byte_a = word_a[(col % 4) * 8 +: 8];

                        // 5. 将 A 的 8-bit 数据符号扩展为 32-bit 作为期望值
                        // $signed 会自动处理符号扩展
                        expected_c = $signed(byte_a);

                        // 6. 比对
                        if (word_c !== expected_c) begin
                            if (errors < 5) begin 
                                $display("        [FAIL] Tile %0d C[%d][%d]: Exp(A_ext)=%0d (0x%08X), Act(C)=%0d (0x%08X)", 
                                         tile_id, row, col, expected_c, expected_c, word_c, word_c);
                            end
                            errors = errors + 1;
                        end
                    end
                end

                if (errors == 0) begin
                    $display("        [PASS] Tile %0d Verified", tile_id);
                end else begin
                    $display("        [FAIL] Tile %0d has %0d errors", tile_id, errors);
                    total_errors = total_errors + errors;
                end
            end

            if (total_errors == 0) begin
                $display("    [PASS] Test %d: All 32 Tiles Passed!", test_num);
            end else begin
                $display("    [FAIL] Test %d: Total %0d Errors", test_num, total_errors);
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
        axi_write(`NPU_AXI_LITE_BASE + `REG_M, 32'd256);         // M=32 (32行)
        axi_write(`NPU_AXI_LITE_BASE + `REG_N, 32'd8);          // N=8 (8列)
        axi_write(`NPU_AXI_LITE_BASE + `REG_K, 32'd8);          // K=8 (内维度，完整Tile容量)
        axi_write(`NPU_AXI_LITE_BASE + `REG_TILE_MASK, 32'hffff_ffff);  // 启用 Tile 0-3
        axi_write(`NPU_AXI_LITE_BASE + `REG_ITERATIONS, 32'd1);         // 单次迭代
        
        $display("      配置: MODE=MERGE, M=32, N=8, K=8, TILE_MASK=0x%08X", 32'hffff_ffff);

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
            for (row = 0; row < 256; row = row + 1) begin
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
            reg [7:0] temp_byte;
            errors = 0;
            total_elements = 256 * 8;  // 256行 × 8列
            
            $display("      开始验证 C 矩阵 (256×8, 共 %0d 个元素)...", total_elements);
            
            // 逐元素验证 C 矩阵
            // 理论预期：C = A × B，其中 B 是标准单位矩阵
            // 因此 C[row][col] = A[row][col] (所有 col)
            for (row = 0; row < 256; row = row + 1) begin
                for (col = 0; col < 8; col = col + 1) begin
                    // 读取 C 矩阵元素
                    axi_read(`NPU_C_BUFFER_BASE + (row*8 + col)*4, c_val);
                    
                    // 计算期望值
                    // C[row][col] = A[row][col] = row*8 + col
                    // 修改后：强制进行符号扩展

                    temp_byte = (row * 8 + col) & 8'hFF;
                    expected_val = $signed(temp_byte); // $signed 会将 8-bit 有符号数扩展为 32-bit 有符号数

                    
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
                             row + 1, 256, errors);
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
            
            $display("      --- C 矩阵前256行 ---");
            for (i = 0; i < 256; i = i + 1) begin
                $write("        C[%d] = [", i);
                for (j = 0; j < 8; j = j + 1) begin
                    axi_read(`NPU_C_BUFFER_BASE + (i*8 + j)*4, c_val);
                    if (j > 0) $write(", ");
                    $write("%4d", $signed(c_val[7:0]));
                end
                $display("]");
            end
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
/*
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
*/
endmodule