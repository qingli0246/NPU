`include "npu_defs.vh"

// ============================================================
// npu_top - NPU 系统顶层模块（标准FSM三分法重构）
// 实例化并连接所有子模块，对外暴露 AXI4 Slave 接口
// 
// FSM设计原则：
// 1. 时序逻辑块：无（顶层主要是模块实例化）
// 2. 组合逻辑块1：内部信号连接
// 3. 组合逻辑块2：模块间信号路由
// ============================================================
module npu_top (axi_aclk, axi_aresetn,
    axi_awaddr, axi_awlen, axi_awsize, axi_awburst, axi_awvalid, axi_awready,
    axi_wdata, axi_wstrb, axi_wlast, axi_wvalid, axi_wready,
    axi_bresp, axi_bvalid, axi_bready,
    axi_araddr, axi_arlen, axi_arsize, axi_arburst, axi_arvalid, axi_arready,
    axi_rdata, axi_rresp, axi_rlast, axi_rvalid, axi_rready,
    npu_irq
);

    parameter ADDR_WIDTH  = `NPU_AXI_ADDR_WIDTH;
    parameter DATA_WIDTH  = `NPU_AXI_DATA_WIDTH;
    parameter TILE_COUNT  = `NPU_NUM_TILES;
    parameter K_MAX       = `NPU_K_MAX;
    parameter A_BUS_WIDTH = 8 * `NPU_NUM_TILES;
    parameter C_BUS_WIDTH = `NPU_TILE_C_BITS * `NPU_NUM_TILES;  // 2048 * 32 = 65536位

    // ---- AXI4 Slave 接口 ----
    input  wire                    axi_aclk;
    input  wire                    axi_aresetn;
    input  wire [ADDR_WIDTH-1:0]   axi_awaddr;
    input  wire [7:0]              axi_awlen;
    input  wire [2:0]              axi_awsize;
    input  wire [1:0]              axi_awburst;
    input  wire                    axi_awvalid;
    output wire                    axi_awready;
    input  wire [DATA_WIDTH-1:0]   axi_wdata;
    input  wire [DATA_WIDTH/8-1:0] axi_wstrb;
    input  wire                    axi_wlast;
    input  wire                    axi_wvalid;
    output wire                    axi_wready;
    output wire [1:0]              axi_bresp;
    output wire                    axi_bvalid;
    input  wire                    axi_bready;
    input  wire [ADDR_WIDTH-1:0]   axi_araddr;
    input  wire [7:0]              axi_arlen;
    input  wire [2:0]              axi_arsize;
    input  wire [1:0]              axi_arburst;
    input  wire                    axi_arvalid;
    output wire                    axi_arready;
    output wire [DATA_WIDTH-1:0]   axi_rdata;
    output wire [1:0]              axi_rresp;
    output wire                    axi_rlast;
    output wire                    axi_rvalid;
    input  wire                    axi_rready;
    output wire                    npu_irq;

    // ========================================================
    //  内部连线（组合逻辑块1：信号定义）
    // ========================================================

    // AXI Slave ↔ Config
    wire        reg_wr_en;
    wire [7:0]  reg_wr_addr;
    wire [31:0] reg_wr_data;
    wire        reg_rd_en;
    wire [7:0]  reg_rd_addr;
    wire [31:0] reg_rd_data;

    // AXI Slave ↔ Buffer Mgr (Port A)
    wire        axi_buf_wr_en;
    wire [ADDR_WIDTH-1:0] axi_buf_wr_addr;
    wire [DATA_WIDTH-1:0] axi_buf_wr_data;
    wire [3:0]  axi_buf_wr_strb;
    wire        axi_buf_rd_en;
    wire [ADDR_WIDTH-1:0] axi_buf_rd_addr;
    wire [DATA_WIDTH-1:0] axi_buf_rd_data;
    wire        axi_buf_rd_valid;

    // Config 输出
    wire [1:0]  cfg_mode;
    wire [5:0]  cfg_m, cfg_n, cfg_k;
    wire [31:0] cfg_tile_mask;
    wire [3:0]  cfg_iterations;
    wire        cfg_start;
    wire        cfg_status_clr;
    wire        irq_en_done, irq_en_error;

    // Status
    wire        status_done, status_error;

    // Scheduler ↔ Data Mover
    wire        load_start, compute_start, store_start;
    wire        load_done, store_done;

    // Scheduler ↔ Compute Pool
    wire        compute_done;
    wire        npu_done, npu_error;
    wire [3:0]  npu_state;
    wire        computing;

    // Data Mover ↔ Buffer Mgr (Port B)
    wire        mover_buf_rd_en;
    wire [ADDR_WIDTH-1:0] mover_buf_rd_addr;
    wire [DATA_WIDTH-1:0] mover_buf_rd_data;
    wire        mover_buf_rd_valid;
    wire        mover_buf_wr_en;
    wire [ADDR_WIDTH-1:0] mover_buf_wr_addr;
    wire [DATA_WIDTH-1:0] mover_buf_wr_data;
    wire [3:0]  mover_buf_wr_strb;

    // Data Mover ↔ Compute Pool（打包总线）
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

    // ========================================================
    //  模块间信号路由（组合逻辑块2：信号连接）
    // ========================================================
    
    // compute_done 由 pool_done 驱动
    assign compute_done = pool_done;

    // ========================================================
    //  子模块实例化（时序逻辑块1：模块阵列）
    // ========================================================

    // ---- 1. AXI Slave ----
    npu_axi_slave #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_axi_slave (
        .clk            (axi_aclk),
        .rst_n          (axi_aresetn),
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
        .clk            (axi_aclk),
        .rst_n          (axi_aresetn),
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
        .clk            (axi_aclk),
        .rst_n          (axi_aresetn),
        .npu_done       (npu_done),
        .npu_error      (npu_error),
        .status_clr     (cfg_status_clr),
        .irq_en_done    (irq_en_done),
        .irq_en_error   (irq_en_error),
        .status_done    (status_done),
        .status_error   (status_error),
        .npu_irq        (npu_irq)
    );

    // ---- 4. Buffer Mgr ----
    npu_buffer_mgr #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_buffer_mgr (
        .clk            (axi_aclk),
        .rst_n          (axi_aresetn),
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
        .clk            (axi_aclk),
        .rst_n          (axi_aresetn),
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
        .clk            (axi_aclk),
        .rst_n          (axi_aresetn),
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
        .clk            (axi_aclk),
        .rst_n          (axi_aresetn),
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

endmodule
