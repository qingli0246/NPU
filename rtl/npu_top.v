`timescale 1ns/1ps
`include "npu_defs.vh"

module npu_top (
    input  wire                     clk,
    input  wire                     rst_n,

    // AXI-Lite 控制接口
    input  wire [31:0]              s_axi_awaddr,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,
    input  wire [31:0]              s_axi_wdata,
    input  wire [3:0]               s_axi_wstrb,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,
    input  wire [31:0]              s_axi_araddr,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,
    output reg  [31:0]              s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    // AXI4 数据接口：作为主设备连接 BRAM / 存储控制器
    output wire [31:0]              m_axi_awaddr,
    output wire                     m_axi_awvalid,
    input  wire                     m_axi_awready,
    output wire [31:0]              m_axi_wdata,
    output wire [3:0]               m_axi_wstrb,
    output wire                     m_axi_wvalid,
    input  wire                     m_axi_wready,
    input  wire                     m_axi_bvalid,
    output wire                     m_axi_bready,
    output wire [31:0]              m_axi_araddr,
    output wire                     m_axi_arvalid,
    input  wire                     m_axi_arready,
    input  wire [31:0]              m_axi_rdata,
    input  wire                     m_axi_rvalid,
    output wire                     m_axi_rready,

    // 对外状态与中断
    output wire                     npu_busy,
    output wire                     npu_done,
    output wire                     npu_error,
    output wire                     npu_irq
);

    // ----------------------------
    // AXI-Lite 寄存器组 (全局唯一配置源)
    // ----------------------------
    reg [31:0] reg_ctrl;
    reg [31:0] reg_mode;
    reg [31:0] reg_a_base;
    reg [31:0] reg_b_base;
    reg [31:0] reg_c_base;
    reg [31:0] reg_m;
    reg [31:0] reg_n;
    reg [31:0] reg_k;
    reg [31:0] reg_tile_mask;
    reg [31:0] reg_h_link_en;
    reg [31:0] reg_v_link_en;
    reg [31:0] reg_group_master;

    reg cfg_start_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            s_axi_bvalid    <= 1'b0;
            s_axi_arready   <= 1'b0;
            s_axi_rdata     <= 32'd0;
            s_axi_rresp     <= 2'b00;
            s_axi_rvalid    <= 1'b0;

            reg_ctrl        <= 32'd0;
            reg_mode        <= 32'd0;
            reg_a_base      <= 32'd0;
            reg_b_base      <= 32'd0;
            reg_c_base      <= 32'd0;
            reg_m           <= 32'd0;
            reg_n           <= 32'd0;
            reg_k           <= 32'd0;
            reg_tile_mask   <= 32'd0;
            reg_h_link_en   <= 32'd0;
            reg_v_link_en   <= 32'd0;
            reg_group_master<= 32'd0;

            cfg_start_pulse <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_arready <= 1'b0;

            if (s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                case (s_axi_awaddr[7:2])
                    6'h00: begin
                        reg_ctrl <= s_axi_wdata;
                        if (s_axi_wdata[0]) cfg_start_pulse <= 1'b1;
                    end
                    6'h01: reg_mode        <= s_axi_wdata;
                    6'h02: reg_a_base      <= s_axi_wdata;
                    6'h03: reg_b_base      <= s_axi_wdata;
                    6'h04: reg_c_base      <= s_axi_wdata;
                    6'h05: reg_m           <= s_axi_wdata;
                    6'h06: reg_n           <= s_axi_wdata;
                    6'h07: reg_k           <= s_axi_wdata;
                    6'h08: reg_tile_mask   <= s_axi_wdata;
                    6'h09: reg_h_link_en   <= s_axi_wdata;
                    6'h0A: reg_v_link_en   <= s_axi_wdata;
                    6'h0B: reg_group_master<= s_axi_wdata;
                    default: begin end
                endcase
            end else begin
                if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            end

            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rdata   <= axi_rdata_comb;
                s_axi_rresp <= 2'b00;
            end else begin
                if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            end

            if (npu_busy) cfg_start_pulse <= 1'b0;
        end
    end

    // ----------------------------
    // 全局连线
    // ----------------------------
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
    wire ctrl_busy;
    wire ctrl_done;
    wire ctrl_error;
    wire pool_busy;
    wire pool_done;

    // ----------------------------
    // 计算池阵列互联配置（全局统一）
    // ----------------------------
    wire [`NPU_NUM_TILES-1:0] pool_cfg_group_master = reg_group_master[`NPU_NUM_TILES-1:0];
    wire [`NPU_NUM_TILES-1:0] pool_cfg_h_link_en    = reg_h_link_en[`NPU_NUM_TILES-1:0];
    wire [`NPU_NUM_TILES-1:0] pool_cfg_v_link_en    = reg_v_link_en[`NPU_NUM_TILES-1:0];

    // ----------------------------
    // 数据总线
    // ----------------------------
    wire [`NPU_NUM_TILES*`NPU_TILE_A_BITS-1:0] tile_a_bus;
    wire [`NPU_NUM_TILES*`NPU_TILE_B_BITS-1:0] tile_b_bus;
    wire [`NPU_NUM_TILES*`NPU_TILE_C_BITS-1:0] tile_c_bus;
    wire [`NPU_NUM_TILES-1:0] tile_busy_mask;
    wire [`NPU_NUM_TILES-1:0] tile_done_mask;

    // ----------------------------
    // 权重缓存 B matrix
    // ----------------------------
    wire [`NPU_TILE_B_BITS-1:0] cache_rdata;
    wire [`NPU_NUM_TILES-1:0] cache_valid_bits;
    
    // 新增：B矩阵加载时的缓存写入控制信号（在npu_top中直接控制）
    reg cache_we_top;
    reg [4:0] cache_waddr_top;
    reg [`NPU_TILE_B_BITS-1:0] cache_wdata_top;
    
    // 多路选择器：选择缓存写入信号的来源
    // - CFG阶段：使用ctrl的信号（当前是全零，保留兼容性）
    // - LOAD阶段（B矩阵加载）：使用top的信号（真实数据）
    wire cache_we_final;
    wire [4:0] cache_waddr_final;
    wire [`NPU_TILE_B_BITS-1:0] cache_wdata_final;
    
    assign cache_we_final = b_load_phase ? cache_we_top : cache_we;
    assign cache_waddr_final = b_load_phase ? cache_waddr_top : cache_waddr;
    assign cache_wdata_final = b_load_phase ? cache_wdata_top : cache_wdata;
    
    // 多端口读取输出（用于独立权重模式 - 优化版）
    // 分组宽总线：4组×8Tile，总宽度 = 4 * 512 = 2048 bits
    // rdata_group[group_id*512 +: 512] 对应第group_id组的权重
    wire [4*`NPU_TILE_B_BITS-1:0] cache_rdata_group;
    
    npu_weight_cache u_cache (
        .clk            (clk),
        .rst_n          (rst_n),
        .we             (cache_we_final),
        .waddr          (cache_waddr_final),
        .wdata          (cache_wdata_final),
        .raddr          (reg_tile_mask[4:0]),
        .rdata          (cache_rdata),
        .rdata_group    (cache_rdata_group),  // 新增：分组多端口输出
        .valid_bits     (cache_valid_bits)
    );

    // ==========================================================
    // 计算池（已正确连接全局配置 + 脉动级联）
    // ==========================================================
    npu_compute_pool u_pool (
        .clk              (clk),
        .rst_n            (rst_n),
        .clk_en           (1'b1),
        .tile_start_mask   (pool_tile_start_mask),
        .tile_clk_en_mask  (pool_tile_clk_en_mask),
        .cfg_top_mode     (pool_mode),
        .cfg_group_master (pool_cfg_group_master),
        .cfg_h_link_en    (pool_cfg_h_link_en),
        .cfg_v_link_en    (pool_cfg_v_link_en),
        .tile_a_bus       (tile_a_bus),
        .tile_b_bus       (tile_b_bus),
        .tile_c_bus       (tile_c_bus),
        .tile_busy_mask   (tile_busy_mask),
        .tile_done_mask   (tile_done_mask),
        .pool_busy        (pool_busy),
        .pool_done        (pool_done),
        .merge_link_active(),
        .split_link_active(),
        .indep_link_active()
    );

    // ----------------------------
    // DMA 读
    // ----------------------------
    wire rd_busy;
    wire rd_done;
    wire rd_cmd_valid;
    wire rd_cmd_ready;
    wire rd_cmd_write;
    wire [31:0] rd_cmd_addr;
    wire [31:0] rd_cmd_wdata;
    wire [3:0] rd_cmd_wstrb;
    wire rd_rsp_valid;
    wire [31:0] rd_rsp_rdata;
    wire rd_data_valid;
    wire [31:0] rd_data_word;
    wire [15:0] rd_data_index;

    npu_dma_rd u_rd_dma (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (rd_start),
        .base_addr  (rd_base_addr),
        .word_count (rd_word_count),
        .busy       (rd_busy),
        .done       (rd_done),
        .cmd_valid  (rd_cmd_valid),
        .cmd_write  (rd_cmd_write),
        .cmd_addr   (rd_cmd_addr),
        .cmd_wdata  (rd_cmd_wdata),
        .cmd_wstrb  (rd_cmd_wstrb),
        .cmd_ready  (rd_cmd_ready),
        .rsp_valid  (rd_rsp_valid),
        .rsp_rdata  (rd_rsp_rdata),
        .data_valid (rd_data_valid),
        .data_word  (rd_data_word),
        .data_index (rd_data_index)
    );

    // ----------------------------
    // DMA 写
    // ----------------------------
    wire wr_busy;
    wire wr_done;
    wire wr_cmd_valid;
    wire wr_cmd_ready;
    wire wr_cmd_write;
    wire [31:0] wr_cmd_addr;
    wire [31:0] wr_cmd_wdata;
    wire [3:0] wr_cmd_wstrb;
    wire wr_rsp_valid;
    wire wr_data_ready;  // DMA写就绪信号（用于握手协议）
    // C矩阵写回数据信号（必须在DMA实例化之前声明，避免隐式声明冲突）
    wire wr_data_valid;
    wire [31:0] wr_data_out;


    npu_dma_wr u_wr_dma (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (wr_start),
        .base_addr     (wr_base_addr),
        .word_count    (wr_word_count),
        .data_in       (wr_data_out),      // 使用C矩阵收集后的数据
        .data_in_valid (wr_data_valid),    // 使用握手信号
        .data_in_ready (wr_data_ready),    // DMA就绪信号（用于握手）
        .busy          (wr_busy),
        .done          (wr_done),
        .cmd_valid     (wr_cmd_valid),
        .cmd_write     (wr_cmd_write),
        .cmd_addr      (wr_cmd_addr),
        .cmd_wdata     (wr_cmd_wdata),
        .cmd_wstrb     (wr_cmd_wstrb),
        .cmd_ready     (wr_cmd_ready),
        .rsp_valid     (wr_rsp_valid),
        .rsp_rdata     ()
    );

    // ----------------------------
    // AXI 桥
    // ----------------------------
    npu_axi4_bridge u_bridge (
        .clk          (clk),
        .rst_n        (rst_n),
        .rd_cmd_valid (rd_cmd_valid),
        .rd_cmd_ready (rd_cmd_ready),
        .rd_cmd_addr  (rd_cmd_addr),
        .rd_rsp_valid (rd_rsp_valid),
        .rd_rsp_rdata (rd_rsp_rdata),
        .wr_cmd_valid (wr_cmd_valid),
        .wr_cmd_ready (wr_cmd_ready),
        .wr_cmd_addr  (wr_cmd_addr),
        .wr_cmd_wdata (wr_cmd_wdata),
        .wr_cmd_wstrb (wr_cmd_wstrb),
        .wr_rsp_valid (wr_rsp_valid),
        .m_axi_awaddr (m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata  (m_axi_wdata),
        .m_axi_wstrb  (m_axi_wstrb),
        .m_axi_wvalid (m_axi_wvalid),
        .m_axi_wready (m_axi_wready),
        .m_axi_bvalid (m_axi_bvalid),
        .m_axi_bready (m_axi_bready),
        .m_axi_araddr (m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata  (m_axi_rdata),
        .m_axi_rvalid (m_axi_rvalid),
        .m_axi_rready (m_axi_rready)
    );

    // ----------------------------
    // 全局控制器
    // ----------------------------
    npu_ctrl u_ctrl (
        .clk                  (clk),
        .rst_n                (rst_n),
        .cfg_start_pulse      (cfg_start_pulse),
        .cfg_mode             (reg_mode[1:0]),
        .cfg_b_static         (reg_mode[2]),      // B矩阵静态权重标志
        .cfg_b_independent    (reg_mode[3]),      // B矩阵独立权重标志
        .cfg_tile_mask_lo     (reg_tile_mask[4:0]),
        .cfg_tile_mask_hi     (reg_tile_mask[9:5]),
        .cfg_a_base           (reg_a_base),
        .cfg_b_base           (reg_b_base),
        .cfg_c_base           (reg_c_base),
        .cfg_matrix_m         (reg_m),
        .cfg_matrix_n         (reg_n),
        .cfg_matrix_k         (reg_k),
        .pool_busy            (pool_busy),      // 添加pool_busy连接
        .pool_done            (pool_done),      // 添加pool_done连接
        .rd_busy              (rd_busy),
        .rd_done              (rd_done),
        .wr_busy              (wr_busy),
        .wr_done              (wr_done),
        .pool_tile_start_mask (pool_tile_start_mask),
        .pool_tile_clk_en_mask(pool_tile_clk_en_mask),
        .pool_mode            (pool_mode),
        .rd_start             (rd_start),
        .wr_start             (wr_start),
        .rd_base_addr         (rd_base_addr),
        .wr_base_addr         (wr_base_addr),
        .rd_word_count        (rd_word_count),
        .wr_word_count        (wr_word_count),
        .cache_we             (cache_we),
        .cache_waddr          (cache_waddr),
        .cache_wdata          (cache_wdata),
        .global_busy          (ctrl_busy),
        .global_done          (ctrl_done),
        .global_error         (ctrl_error),
        .global_state         ()
    );

    // ==========================================================
    // DMA → 计算池 数据真正连接
    // A 数据分发策略取决于工作模式：
    //   - INDEP：A 矩阵线性分发到所有 Tile（轮转分配）
    //   - MERGE：A 矩阵分发到主 Tile，通过级联网络传播
    //   - SPLIT：A 矩阵分发后由 Tile 内部拆分处理
    // 
    // B 数据处理策略：
    //   - 动态权重模式（reg_mode[2]=0）：通过DMA读取B矩阵并写入权重缓存
    //   - 静态权重模式（reg_mode[2]=1）：直接使用缓存中的预加载值
    // ==========================================================
    reg [`NPU_NUM_TILES*`NPU_TILE_A_BITS-1:0] tile_a_bus_reg;
    reg [`NPU_NUM_TILES*`NPU_TILE_B_BITS-1:0] tile_b_bus_reg;

    // 工作模式和矩阵参数的缓存（用于计算目标位置）
    reg [1:0] mode_cache;
    reg [31:0] m_cache, n_cache, k_cache;
    reg b_static_cache;       // B矩阵是否为静态权重
    reg b_independent_cache;  // B矩阵是否为独立权重（每个Tile不同）

    // B矩阵加载状态管理
    reg b_load_phase;        // 是否处于B矩阵加载阶段
    reg [15:0] b_load_cnt;   // B矩阵加载计数器
    reg [15:0] b_expected_words;  // 新增：B矩阵预期加载字数（动态计算）
    reg [4:0]  b_tile_idx;   // 当前正在加载的Tile索引
    reg [3:0]  b_word_idx;   // Tile内字的索引（0-15，共16个字）
    
    // A矩阵加载完成标志（从控制器同步）
    reg a_load_complete;
    
    // B矩阵缓存写入缓冲（用于累积一个字的所有32bit片段）
    reg [`NPU_TILE_B_BITS-1:0] cache_wdata_buffer;
    reg [3:0] cache_word_cnt;  // 当前Tile内已接收的字数（0-15）
    
    // 独立权重模式：当前正在加载的Tile索引（0-31）
    reg [4:0] current_tile_for_weight;
    
    // 临时变量声明（用于A/B矩阵数据分发计算）
    integer tile_id_temp;
    integer word_offset_temp;
    integer i_temp;
    integer tile_idx_temp;
    integer word_in_tile_temp;
    integer group_i;          // 用于B矩阵组遍历
    integer tile_in_group;    // 用于B矩阵组内Tile遍历
    reg break_found;          // 用于在for循环中模拟break语句
    
    // C矩阵写回相关寄存器
    reg c_wr_phase;           // C矩阵写回阶段标志
    reg [15:0] c_wr_cnt;      // C矩阵写回计数器
    reg [31:0] wr_data_word;  // 当前要写入的字（32 bits）
    reg wr_data_ready_flag;   // 数据准备好标志
    reg [4:0] wr_tile_idx;    // 当前正在收集的Tile索引
    reg [4:0] wr_word_in_tile; // Tile内字的索引
    reg wr_data_ready_prev;   // wr_data_ready上一周期状态（用于上升沿检测）

    // ============================================================
    // 信号连接：将内部寄存器连接到输出总线
    // ============================================================
    assign tile_a_bus = tile_a_bus_reg;
    assign tile_b_bus = tile_b_bus_reg;

    // wr_data_ready 上升沿检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_data_ready_prev <= 1'b0;
        end else begin
            wr_data_ready_prev <= wr_data_ready;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tile_a_bus_reg <= 'b0;
            tile_b_bus_reg <= 'b0;
            mode_cache <= `NPU_MODE_INDEP;
            m_cache <= 32'd0;
            n_cache <= 32'd0;
            k_cache <= 32'd0;
            b_static_cache <= 1'b0;
            b_independent_cache <= 1'b0;
            b_load_phase <= 1'b0;
            b_load_cnt <= 16'd0;
            b_tile_idx <= 5'd0;
            b_word_idx <= 4'd0;
            a_load_complete <= 1'b0;
            cache_we_top <= 1'b0;
            cache_waddr_top <= 5'd0;
            cache_wdata_top <= {`NPU_TILE_B_BITS{1'b0}};
            cache_wdata_buffer <= {`NPU_TILE_B_BITS{1'b0}};
            cache_word_cnt <= 4'd0;
            current_tile_for_weight <= 5'd0;
            
            // C矩阵写回寄存器初始化
            c_wr_phase <= 1'b0;
            c_wr_cnt <= 16'd0;
            wr_data_word <= 32'd0;
            wr_data_ready_flag <= 1'b0;
            wr_tile_idx <= 5'd0;
            wr_word_in_tile <= 5'd0;
            break_found <= 1'b0;
        end else begin
            // 缓存当前模式和矩阵参数，供A数据分发逻辑使用
            if (ctrl_busy && !rd_busy && !b_load_phase) begin  // CFG或LOAD阶段开始
                mode_cache <= pool_mode;
                m_cache <= reg_m;
                n_cache <= reg_n;
                k_cache <= reg_k;
                b_static_cache <= reg_mode[2];  // 缓存B矩阵静态标志
                b_independent_cache <= reg_mode[3];  // 缓存B矩阵独立权重标志
            end

            // ================================================================
            // 阶段判断：A矩阵加载 vs B矩阵加载
            // ================================================================
            
            // 检测A矩阵加载完成的信号
            // 当DMA读取完成(rd_done)且当前不在B矩阵加载阶段时，标记A加载完成
            if (rd_done && !b_load_phase && !b_static_cache) begin
                a_load_complete <= 1'b1;
            end
            
            // 当A矩阵加载完成且收到新的有效数据时，切换到B矩阵加载阶段
            if (a_load_complete && !b_load_phase && rd_data_valid) begin
                b_load_phase <= 1'b1;
                b_load_cnt <= 16'd0;
                 b_expected_words <= rd_word_count;  // 缓存B矩阵的预期字数
                current_tile_for_weight <= 5'd0;  // 重置组索引，准备加载第0组权重
                a_load_complete <= 1'b0;
            end
            
            // B矩阵加载完成后，重置阶段标志
            // 使用动态计算的字数判断加载是否完成（支持任意规模的矩阵）
            if (b_load_phase && b_load_cnt >= b_expected_words) begin
                b_load_phase <= 1'b0;
                b_load_cnt <= 16'd0;
                b_expected_words <= 16'd0;  // 清除预期字数
                current_tile_for_weight <= 5'd0;  // 重置组索引，为下次计算做准备
            end

            if (rd_data_valid) begin
                if (!b_load_phase) begin
                    // ============================================================
                    // A 矩阵加载阶段
                    // ============================================================
                    case (mode_cache)
                        `NPU_MODE_INDEP: begin
                            // INDEP 模式：A 矩阵均匀分配到所有 32 个 Tile
                            // 轮转分配：word#j 分配到 Tile#(j % 32) 的位置 (j / 32) * 32
                            tile_id_temp = rd_data_index % `NPU_NUM_TILES;
                            word_offset_temp = (rd_data_index / `NPU_NUM_TILES);
                            // A 矩阵每个 Tile 部分占 NPU_TILE_A_BITS = 512 bit
                            // 对应 16 个 32bit 字
                            tile_a_bus_reg[tile_id_temp * `NPU_TILE_A_BITS + word_offset_temp * 32 +: 32] <= rd_data_word;
                        end

                        `NPU_MODE_MERGE: begin
                            // MERGE 模式：A 矩阵分散到主 Tile，通过脉动级联传播
                            // 简化方案：分发到所有标记为 group_master 的 Tile
                            for (i_temp = 0; i_temp < `NPU_NUM_TILES; i_temp = i_temp + 1) begin
                                if (pool_cfg_group_master[i_temp]) begin
                                    // 这是一个主 Tile，分发数据给它
                                    tile_a_bus_reg[i_temp * `NPU_TILE_A_BITS + (rd_data_index % 16) * 32 +: 32] <= rd_data_word;
                                end
                            end
                        end

                        `NPU_MODE_SPLIT: begin
                            // SPLIT 模式：每个 Tile 内部拆分为 4 个 4x4 子阵列
                            // A 数据分发策略与 INDEP 类似，但 Tile 内部会做拆分处理
                            tile_id_temp = rd_data_index % `NPU_NUM_TILES;
                            word_offset_temp = (rd_data_index / `NPU_NUM_TILES);
                            tile_a_bus_reg[tile_id_temp * `NPU_TILE_A_BITS + word_offset_temp * 32 +: 32] <= rd_data_word;
                        end

                        default: begin
                            // 默认按 INDEP 处理
                            tile_id_temp = rd_data_index % `NPU_NUM_TILES;
                            word_offset_temp = (rd_data_index / `NPU_NUM_TILES);
                            tile_a_bus_reg[tile_id_temp * `NPU_TILE_A_BITS + word_offset_temp * 32 +: 32] <= rd_data_word;
                        end
                    endcase
                end else begin
                    // ============================================================
                    // B 矩阵加载阶段（仅在动态权重模式下）
                    // ============================================================
                    // 将读取的数据写入权重缓存和tile_b_bus_reg
                    // 
                    // 支持两种模式：
                    // 1. 权重共享模式（b_independent_cache=0）：
                    //    - 所有Tile使用相同的B矩阵
                    //    - 只加载一次B矩阵到cache[0]
                    //    - 然后广播到所有Tile
                    //
                    // 2. 独立权重模式（b_independent_cache=1，优化版）：
                    //    - 32个Tile分为4组，每组8个Tile共享相同权重
                    //    - 依次加载4个B矩阵到cache[0, 8, 16, 24]
                    //    - 每组内的Tile从对应的cache条目读取
                    
                    // 计算当前是第几个字（0-15，对应一个8x8矩阵的16个32bit字）
                    word_in_tile_temp = b_load_cnt % 16;
                    
                    // 累积B矩阵数据到缓冲区
                    cache_wdata_buffer[word_in_tile_temp * 32 +: 32] <= rd_data_word;
                    cache_word_cnt <= cache_word_cnt + 1;
                    
                    // 每接收16个字（一个完整的8x8矩阵），写入缓存
                    if (cache_word_cnt == 4'd15) begin
                        if (!b_independent_cache) begin
                            // 权重共享模式：写入cache[0]，所有Tile共享
                            cache_we_top <= 1'b1;
                            cache_waddr_top <= 5'd0;
                            cache_wdata_top <= cache_wdata_buffer;
                            
                            // 同时更新tile_b_bus_reg，广播到所有Tile
                            tile_b_bus_reg <= {`NPU_NUM_TILES{cache_wdata_buffer}};
                        end else begin
                            // 独立权重模式（优化版）：写入当前组对应的cache条目
                            // Group 0 → cache[0], Group 1 → cache[8], 
                            // Group 2 → cache[16], Group 3 → cache[24]
                            cache_we_top <= 1'b1;
                            cache_waddr_top <= current_tile_for_weight * 8;  // 每组间隔8个条目
                            cache_wdata_top <= cache_wdata_buffer;
                            
                            // 更新当前组的所有Tile的tile_b_bus
                            begin
                                for (i_temp = 0; i_temp < 8; i_temp = i_temp + 1) begin
                                    tile_id_temp = current_tile_for_weight * 8 + i_temp;
                                    tile_b_bus_reg[tile_id_temp * `NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] <= cache_wdata_buffer;
                                end
                            end
                            
                            // 切换到下一个组（0→1→2→3）
                            if (current_tile_for_weight < 3) begin
                                current_tile_for_weight <= current_tile_for_weight + 1;
                            end
                        end
                        
                        // 重置计数器
                        cache_word_cnt <= 4'd0;
                        cache_wdata_buffer <= {`NPU_TILE_B_BITS{1'b0}};
                    end else begin
                        // 还未收集完16个字，保持缓存写信号关闭
                        cache_we_top <= 1'b0;
                    end
                    
                    b_load_cnt <= b_load_cnt + 1;
                end
            end

            // ================================================================
            // B 数据输出：根据静态/动态模式和共享/独立模式选择不同策略
            // ================================================================
            // 
            // 注意：静态权重模式（b_static_cache=1）下，权重缓存中的数据来自：
            // 1. 首次使用：需要以动态模式运行一次，将权重加载到缓存
            // 2. 后续使用：缓存保持之前的值，无需重新加载
            // 
            // 如果缓存未初始化，cache_rdata为全零，计算结果也会是全零
            
            if (b_independent_cache) begin
                // 独立权重模式（优化版）：分组共享策略
                // 将32个Tile分为4组，每组8个Tile共享相同的权重
                // Group 0: Tile[0-7]   → 使用 cache_rdata_group[0*512 +: 512]
                // Group 1: Tile[8-15]  → 使用 cache_rdata_group[1*512 +: 512]
                // Group 2: Tile[16-23] → 使用 cache_rdata_group[2*512 +: 512]
                // Group 3: Tile[24-31] → 使用 cache_rdata_group[3*512 +: 512]
                
                // 遍历4个组
                for (i_temp = 0; i_temp < 4; i_temp = i_temp + 1) begin
                    // 获取当前组的权重数据
                    // 每个组内的8个Tile共享相同的权重
                    for (tile_idx_temp = 0; tile_idx_temp < 8; tile_idx_temp = tile_idx_temp + 1) begin
                        tile_id_temp = i_temp * 8 + tile_idx_temp;
                        
                        // 将当前组的权重分配给组内所有Tile
                        tile_b_bus_reg[tile_id_temp * `NPU_TILE_B_BITS +: `NPU_TILE_B_BITS] <= 
                            cache_rdata_group[i_temp * `NPU_TILE_B_BITS +: `NPU_TILE_B_BITS];
                    end
                end
            end else begin
                // 权重共享模式：所有Tile使用相同的B矩阵
                if (b_static_cache) begin
                    // 静态权重模式：直接使用缓存中的值，广播到所有Tile
                    tile_b_bus_reg <= {`NPU_NUM_TILES{cache_rdata}};
                end else if (b_load_phase) begin
                    // 动态权重模式，B矩阵正在加载中
                    // 保持之前的值，等待加载完成
                    tile_b_bus_reg <= tile_b_bus_reg;
                end else if (!b_load_phase && b_load_cnt > 0) begin
                    // 动态权重模式，B矩阵已加载完成
                    // 从缓存读取并广播到所有Tile
                    tile_b_bus_reg <= {`NPU_NUM_TILES{cache_rdata}};
                end else begin
                    // 默认情况：使用缓存数据（可能是全零）
                    tile_b_bus_reg <= {`NPU_NUM_TILES{cache_rdata}};
                end
            end
            
            // 清除缓存写信号（只在需要时拉高一个周期）
            if (cache_we_top) begin
                cache_we_top <= 1'b0;
            end
            
            // ================================================================
            // C 矩阵数据收集：从 Tile 输出到 DMA 写缓冲
            // ================================================================
            // C 矩阵是计算结果，需要从32个Tile收集并打包为DMA可识别的格式
            // 
            // 收集策略根据工作模式不同：
            // - INDEP模式：轮转收集所有Tile的结果
            // - MERGE模式：从主Tile收集级联后的结果
            // - SPLIT模式：收集拆分后的子结果
            
            // 检测wr_start信号，开始C矩阵收集阶段
            // 注意：只在wr_start时启动，避免pool_done导致的重复启动
            if (wr_start && !c_wr_phase) begin
                c_wr_phase <= 1'b1;
                c_wr_cnt <= 16'd0;
                wr_tile_idx <= 5'd0;
                wr_word_in_tile <= 5'd0;
                wr_data_word <= 32'd0;
                wr_data_ready_flag <= 1'b0;
                $display("[%0t] [NPU_TOP] C matrix collection started! wr_start=%b, wr_word_count=%d", 
                         $time, wr_start, wr_word_count);
            end
            
            // C矩阵收集完成后，重置阶段标志
            if (c_wr_phase && c_wr_cnt >= wr_word_count) begin
                c_wr_phase <= 1'b0;
                c_wr_cnt <= 16'd0;
                $display("[%0t] [NPU_TOP] C matrix collection completed! c_wr_cnt=%d", $time, c_wr_cnt);
            end
            
            // 在C矩阵收集阶段，从tile_c_bus收集数据并输出到DMA（带握手协议）
            // 注意：不需要检查tile_done_mask，因为计算结果已经在tile_c_bus上了
            if (c_wr_phase) begin
                case (mode_cache)
                    `NPU_MODE_INDEP: begin
                        // INDEP模式：轮转收集所有Tile的结果
                        // 计算当前应该从哪个Tile的哪个位置读取数据
                        wr_tile_idx = c_wr_cnt / 32;  // Tile索引（假设每Tile最多32字）
                        wr_word_in_tile = c_wr_cnt % 32;  // Tile内字的索引
                        
                        // 只有当DMA准备好接收数据时，才提供新数据
                        // 使用上升沿检测，确保每次DMA准备好接收时只递增一次
                        if (wr_data_ready && !wr_data_ready_prev && wr_tile_idx < `NPU_NUM_TILES && wr_word_in_tile < 32) begin
                            // 从对应Tile读取一个字（32bit）
                            wr_data_word <= tile_c_bus[wr_tile_idx * `NPU_TILE_C_BITS + wr_word_in_tile * 32 +: 32];
                            wr_data_ready_flag <= 1'b1;
                            c_wr_cnt <= c_wr_cnt + 1;  // 只在上升沿递增一次
                            // 调试输出
                            if (c_wr_cnt < 3) begin
                                $display("[%0t] [NPU_TOP] INDEP: wr_tile_idx=%d, wr_word_in_tile=%d, tile_c_bus_slice=%h", 
                                         $time, wr_tile_idx, wr_word_in_tile, 
                                         tile_c_bus[wr_tile_idx * `NPU_TILE_C_BITS + wr_word_in_tile * 32 +: 32]);
                            end
                        end else if (!wr_data_ready) begin
                            // DMA未就绪，保持数据和标志不变
                            wr_data_ready_flag <= wr_data_ready_flag;
                            c_wr_cnt <= c_wr_cnt;  // 计数器保持不变
                        end else begin
                            // 超出范围或无上升沿，清除标志
                            wr_data_ready_flag <= 1'b0;
                        end
                    end

                    `NPU_MODE_MERGE: begin
                        // MERGE模式：从主Tile收集级联后的结果
                        // 简化实现：从第一个标记为group_master的Tile顺序读取
                        // 使用上升沿检测，确保每次DMA准备好接收时只递增一次
                        if (wr_data_ready && !wr_data_ready_prev) begin
                            break_found <= 1'b0;
                            for (i_temp = 0; i_temp < `NPU_NUM_TILES; i_temp = i_temp + 1) begin
                                if (pool_cfg_group_master[i_temp] && !break_found) begin
                                    wr_data_word <= tile_c_bus[i_temp * `NPU_TILE_C_BITS + (c_wr_cnt % 32) * 32 +: 32];
                                    wr_data_ready_flag <= 1'b1;
                                    c_wr_cnt <= c_wr_cnt + 1;
                                    break_found <= 1'b1;  // 设置标志，后续迭代不再执行
                                end
                            end
                            if (!break_found) begin
                                wr_data_ready_flag <= 1'b0;
                            end
                        end else begin
                            wr_data_ready_flag <= wr_data_ready_flag;
                            c_wr_cnt <= c_wr_cnt;
                        end
                    end

                    `NPU_MODE_SPLIT: begin
                        // SPLIT模式：收集拆分后的子结果
                        // 与INDEP类似，使用上升沿检测
                        wr_tile_idx = c_wr_cnt / 32;
                        wr_word_in_tile = c_wr_cnt % 32;
                        
                        if (wr_data_ready && !wr_data_ready_prev && wr_tile_idx < `NPU_NUM_TILES && wr_word_in_tile < 32) begin
                            wr_data_word <= tile_c_bus[wr_tile_idx * `NPU_TILE_C_BITS + wr_word_in_tile * 32 +: 32];
                            wr_data_ready_flag <= 1'b1;
                            c_wr_cnt <= c_wr_cnt + 1;
                        end else if (!wr_data_ready) begin
                            wr_data_ready_flag <= wr_data_ready_flag;
                            c_wr_cnt <= c_wr_cnt;
                        end else begin
                            wr_data_ready_flag <= 1'b0;
                        end
                    end

                    default: begin
                        // 默认按INDEP处理，使用上升沿检测
                        wr_tile_idx = c_wr_cnt / 32;
                        wr_word_in_tile = c_wr_cnt % 32;
                        
                        if (wr_data_ready && !wr_data_ready_prev && wr_tile_idx < `NPU_NUM_TILES && wr_word_in_tile < 32) begin
                            wr_data_word <= tile_c_bus[wr_tile_idx * `NPU_TILE_C_BITS + wr_word_in_tile * 32 +: 32];
                            wr_data_ready_flag <= 1'b1;
                            c_wr_cnt <= c_wr_cnt + 1;

                            if (c_wr_cnt < 3) begin
                                $display("[%0t] [NPU_TOP] INDEP: wr_tile_idx=%d, wr_word_in_tile=%d, tile_c_bus_slice=%h", 
                                         $time, wr_tile_idx, wr_word_in_tile, 
                                         tile_c_bus[wr_tile_idx * `NPU_TILE_C_BITS + wr_word_in_tile * 32 +: 32]);
                            end
                        end else if (!wr_data_ready) begin
                            wr_data_ready_flag <= wr_data_ready_flag;
                            c_wr_cnt <= c_wr_cnt;
                        end else begin
                            wr_data_ready_flag <= 1'b0;
                        end
                    end
                endcase
            end else begin
                // 不在收集阶段或Tile未完成时，清除ready标志
                wr_data_ready_flag <= 1'b0;
            end
        end
    end

    // ================================================================
    // DMA 写数据输出：将收集的C矩阵数据传递给写DMA
    // ================================================================
  
    // 当数据准备好时，拉高valid信号
    assign wr_data_valid = wr_data_ready_flag;
    assign wr_data_out = wr_data_word;

    // AXI-Lite 读数据组合逻辑（确保数据立即有效）
    wire [31:0] axi_rdata_comb;
    
    // 使用组合逻辑always块实现多路选择器
    reg [31:0] axi_rdata_reg;
    always @(*) begin
        if (s_axi_arvalid && !s_axi_rvalid) begin
            case(s_axi_araddr[7:2])
                6'h00: axi_rdata_reg = reg_ctrl;
                6'h01: axi_rdata_reg = reg_mode;
                6'h02: axi_rdata_reg = reg_a_base;
                6'h03: axi_rdata_reg = reg_b_base;
                6'h04: axi_rdata_reg = reg_c_base;
                6'h05: axi_rdata_reg = reg_m;
                6'h06: axi_rdata_reg = reg_n;
                6'h07: axi_rdata_reg = reg_k;
                6'h08: axi_rdata_reg = reg_tile_mask;
                6'h09: axi_rdata_reg = reg_h_link_en;
                6'h0A: axi_rdata_reg = reg_v_link_en;
                6'h0B: axi_rdata_reg = reg_group_master;
                6'h10: axi_rdata_reg = {28'd0, npu_error, npu_done, npu_busy, 1'b0};
                default: axi_rdata_reg = 32'd0;
            endcase
        end else begin
            axi_rdata_reg = 32'd0;
        end
    end
    
    assign axi_rdata_comb = axi_rdata_reg;

    // ================================================================
    // 输出信号赋值：将内部状态映射到外部端口
    // ================================================================
    assign npu_busy  = ctrl_busy;   // NPU忙碌状态
    assign npu_done  = ctrl_done;   // NPU完成标志
    assign npu_error = ctrl_error;  // NPU错误标志
    assign npu_irq   = 1'b0;        // 中断信号（暂未实现）

    // ----------------------------
    // AXI-Lite 控制逻辑
    // ----------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            s_axi_bvalid    <= 1'b0;
            s_axi_arready   <= 1'b0;
            s_axi_rdata     <= 32'd0;
            s_axi_rresp     <= 2'b00;
            s_axi_rvalid    <= 1'b0;

            reg_ctrl        <= 32'd0;
            reg_mode        <= 32'd0;
            reg_a_base      <= 32'd0;
            reg_b_base      <= 32'd0;
            reg_c_base      <= 32'd0;
            reg_m           <= 32'd0;
            reg_n           <= 32'd0;
            reg_k           <= 32'd0;
            reg_tile_mask   <= 32'd0;
            reg_h_link_en   <= 32'd0;
            reg_v_link_en   <= 32'd0;
            reg_group_master<= 32'd0;

            cfg_start_pulse <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_arready <= 1'b0;

            if (s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                case (s_axi_awaddr[7:2])
                    6'h00: begin
                        reg_ctrl <= s_axi_wdata;
                        if (s_axi_wdata[0]) cfg_start_pulse <= 1'b1;
                    end
                    6'h01: reg_mode        <= s_axi_wdata;
                    6'h02: reg_a_base      <= s_axi_wdata;
                    6'h03: reg_b_base      <= s_axi_wdata;
                    6'h04: reg_c_base      <= s_axi_wdata;
                    6'h05: reg_m           <= s_axi_wdata;
                    6'h06: reg_n           <= s_axi_wdata;
                    6'h07: reg_k           <= s_axi_wdata;
                    6'h08: reg_tile_mask   <= s_axi_wdata;
                    6'h09: reg_h_link_en   <= s_axi_wdata;
                    6'h0A: reg_v_link_en   <= s_axi_wdata;
                    6'h0B: reg_group_master<= s_axi_wdata;
                    default: begin end
                endcase
            end else begin
                if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            end

            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rdata   <= axi_rdata_comb;
                s_axi_rresp <= 2'b00;
            end else begin
                if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            end

            if (npu_busy) cfg_start_pulse <= 1'b0;
        end
    end

    // ==========================================================
    // 调试监控：每1000个周期输出一次关键状态
    // ==========================================================
    reg [31:0] debug_cycle_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debug_cycle_counter <= 32'd0;
        end else begin
            debug_cycle_counter <= debug_cycle_counter + 1;
            
            // 每1000个周期输出一次状态（仅在busy时）
            if (npu_busy && (debug_cycle_counter[9:0] == 10'd0)) begin
                $display("[%0t] [NPU_TOP] ctrl_state=%d rd_busy=%b wr_busy=%b pool_busy=%b tile_start_mask=0x%h",
                         $time, u_ctrl.state, rd_busy, wr_busy, pool_busy, u_npu_top.pool_tile_start_mask);
            end
        end
    end

endmodule
