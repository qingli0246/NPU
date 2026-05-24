`include "npu_defs.vh"

// ============================================================
// npu_data_mover - 数据搬运模块（DMA 版本）
//
// 数据通路：
// Load:   共享BRAM → AXI Master(Burst读) → 内部A/B Buffer → Mover分发 → Tile
// Store:  Tile结果 → Mover收集 → 内部C Buffer → AXI Master(Burst写) → 共享BRAM
//
// 状态机流程：
// IDLE → DMA_LOAD_A → DISTRIBUTE_A → DMA_LOAD_B → DISTRIBUTE_B
//      → COMPUTE_WAIT → COLLECT_C → DMA_STORE_C → DONE → IDLE
//
// DMA 阶段：dma_mode=1，AXI Master 控制 Buffer Port B
// Distribute/Collect 阶段：dma_mode=0，Mover 控制 Buffer Port B
// ============================================================
module npu_data_mover (clk, rst_n,
    cfg_mode, cfg_m, cfg_n, cfg_k, cfg_tile_mask,
    cfg_a_base_addr, cfg_b_base_addr, cfg_c_base_addr,
    load_start, store_start, load_done, store_done,
    // DMA 请求接口（→ npu_axi_master）
    dma_rd_req, dma_rd_addr, dma_rd_len, dma_buf_wr_addr, dma_rd_done,
    dma_wr_req, dma_wr_addr, dma_wr_total_len, dma_buf_rd_addr, dma_wr_done,
    dma_mode,
    // Mover Buffer 端口（→ npu_buffer_mgr，dma_mode=0 时激活）
    mover_buf_rd_en, mover_buf_rd_addr, mover_buf_rd_data, mover_buf_rd_valid,
    mover_buf_wr_en, mover_buf_wr_addr, mover_buf_wr_data, mover_buf_wr_strb,
    // Tile 接口
    tile_en, tile_a_data, tile_a_valid, tile_a_ready,
    tile_b_data, tile_b_valid, tile_b_ready,
    tile_c_data, tile_c_valid, tile_c_ready
);

    parameter ADDR_WIDTH  = `NPU_AXI_ADDR_WIDTH;
    parameter DATA_WIDTH  = `NPU_AXI_DATA_WIDTH;
    parameter TILE_COUNT  = `NPU_NUM_TILES;
    parameter K_MAX       = `NPU_K_MAX;
    parameter A_BUS_WIDTH = 8 * `NPU_NUM_TILES;
    parameter C_BUS_WIDTH = `NPU_TILE_C_BITS * `NPU_NUM_TILES;

    input  wire                       clk;
    input  wire                       rst_n;
    input  wire [1:0]                 cfg_mode;
    input  wire [5:0]                 cfg_m;
    input  wire [5:0]                 cfg_n;
    input  wire [5:0]                 cfg_k;
    input  wire [31:0]                cfg_tile_mask;
    input  wire [31:0]                cfg_a_base_addr;
    input  wire [31:0]                cfg_b_base_addr;
    input  wire [31:0]                cfg_c_base_addr;
    input  wire                       load_start;
    input  wire                       store_start;
    output reg                        load_done;
    output reg                        store_done;

    // DMA 请求接口
    output reg                        dma_rd_req;
    output reg  [31:0]                dma_rd_addr;
    output reg  [7:0]                 dma_rd_len;
    output reg  [15:0]                dma_buf_wr_addr;
    input  wire                       dma_rd_done;

    output reg                        dma_wr_req;
    output reg  [31:0]                dma_wr_addr;
    output reg  [11:0]                dma_wr_total_len;
    output reg  [15:0]                dma_buf_rd_addr;
    input  wire                       dma_wr_done;

    output wire                       dma_mode;

    // Mover Buffer 端口
    output reg                        mover_buf_rd_en;
    output reg  [ADDR_WIDTH-1:0]      mover_buf_rd_addr;
    input  wire [DATA_WIDTH-1:0]      mover_buf_rd_data;
    input  wire                       mover_buf_rd_valid;
    output reg                        mover_buf_wr_en;
    output reg  [ADDR_WIDTH-1:0]      mover_buf_wr_addr;
    output reg  [DATA_WIDTH-1:0]      mover_buf_wr_data;
    output reg  [3:0]                 mover_buf_wr_strb;

    // Tile 接口
    output wire [TILE_COUNT-1:0]      tile_en;
    output reg  [A_BUS_WIDTH-1:0]     tile_a_data;
    output reg                        tile_a_valid;
    input  wire [TILE_COUNT-1:0]      tile_a_ready;
    output reg  [A_BUS_WIDTH-1:0]     tile_b_data;
    output reg                        tile_b_valid;
    input  wire [TILE_COUNT-1:0]      tile_b_ready;
    input  wire [C_BUS_WIDTH-1:0]     tile_c_data;
    input  wire                       tile_c_valid;
    output reg                        tile_c_ready;

    // ========================================================
    //  常量
    // ========================================================
    wire is_merge = (cfg_mode == `NPU_MODE_MERGE);
    wire is_indep = (cfg_mode == `NPU_MODE_INDEP);

    // 计算启用的Tile数量的函数
    function [5:0] calc_enabled_tiles;
        input [31:0] tile_mask;
        integer i;
        begin
            calc_enabled_tiles = 6'd0;
            for (i = 0; i < 32; i = i + 1) begin
                calc_enabled_tiles = calc_enabled_tiles + tile_mask[i];
            end
        end
    endfunction

    // 每 Tile 的 A/B 数据量（32bit 字数）= 2*K
    wire [10:0] tile_a_words = {5'd0, cfg_k} << 1;
    wire [10:0] tile_b_words = {5'd0, cfg_k} << 1;

    // DMA Burst 长度（字数-1）= 2*K - 1
    wire [7:0]  dma_burst_len_ab = {2'd0, cfg_k, 1'b0} - 8'd1;

    // ========================================================
    //  状态定义（增加预读状态）
    // ========================================================
    localparam S_IDLE             = 5'd0;
    localparam S_DMA_LOAD_A       = 5'd1;
    localparam S_DMA_LOAD_A_WAIT  = 5'd2;
    localparam S_DISTRIBUTE_A_PRE = 5'd3;  // 【新增】Distribute A预读状态
    localparam S_DISTRIBUTE_A     = 5'd4;
    localparam S_DMA_LOAD_B       = 5'd5;
    localparam S_DMA_LOAD_B_WAIT  = 5'd6;
    localparam S_DISTRIBUTE_B_PRE = 5'd7;  // 【新增】Distribute B预读状态
    localparam S_DISTRIBUTE_B     = 5'd8;
    localparam S_COMPUTE_WAIT     = 5'd10;
    localparam S_COLLECT_C        = 5'd11;
    localparam S_DMA_STORE_C      = 5'd12;
    localparam S_DMA_STORE_C_WAIT = 5'd13;
    localparam S_DONE             = 5'd14;

    // ========================================================
    //  寄存器
    // ========================================================
    reg [4:0]  state;
    reg [4:0]  tile_idx;
    reg [10:0] word_cnt;
    reg [1:0]  byte_idx;
    reg [5:0]  store_word;
    reg [31:0] wr_data_buf;
    reg [TILE_COUNT-1:0] mover_tile_en;
    reg [TILE_COUNT-1:0] next_mover_tile_en;
    reg        mover_tile_w_done;

    // ========================================================
    //  计算启用的Tile数量的函数
    // ========================================================
    function [4:0] calc_enabled_tile_count;
        input [31:0] tile_mask;
        integer i;
        begin
            calc_enabled_tile_count = 5'd0;
            for (i = 0; i < 32; i = i + 1) begin
                if (tile_mask[i])
                    calc_enabled_tile_count = calc_enabled_tile_count + 5'd1;
            end
        end
    endfunction

    // ========================================================
    //  Tile 查找逻辑
    // ========================================================
    wire [5:0] next_tile_6bit = {1'b0, tile_idx} + 6'd1;
    wire [31:0] remaining_tiles_mask = (tile_idx == 5'd31) ? 32'd0 :
                                        (cfg_tile_mask & ~((32'h1 << next_tile_6bit) - 32'h1));
    wire is_last_enabled_tile = (remaining_tiles_mask == 32'd0);

    reg [4:0] next_tile_idx;
    reg       next_tile_found;
    integer ti_find;
    always @(*) begin
        next_tile_idx = 5'd0;
        next_tile_found = 1'b0;
        for (ti_find = 0; ti_find < 32; ti_find = ti_find + 1) begin
            if (remaining_tiles_mask[ti_find] && !next_tile_found) begin
                next_tile_idx = ti_find[4:0];
                next_tile_found = 1'b1;
            end
        end
    end

    reg [4:0] first_enabled_tile;
    reg       first_tile_found;
    integer ti_first;
    always @(*) begin
        first_enabled_tile = 5'd0;
        first_tile_found = 1'b0;
        for (ti_first = 0; ti_first < 32; ti_first = ti_first + 1) begin
            if (cfg_tile_mask[ti_first] && !first_tile_found) begin
                first_enabled_tile = ti_first[4:0];
                first_tile_found = 1'b1;
            end
        end
    end

    // Tile ready
    wire a_current_tile_ready = tile_a_ready[tile_idx];
    wire b_current_tile_ready = tile_b_ready[tile_idx];
    reg a_current_tile_ready_d;
    reg b_current_tile_ready_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_current_tile_ready_d <= 1'b0;
            b_current_tile_ready_d <= 1'b0;
        end else begin
            a_current_tile_ready_d <= a_current_tile_ready;
            b_current_tile_ready_d <= b_current_tile_ready;
        end
    end
    // ========================================================
    //  DMA 模式信号（更新以包含预读状态）
    // ========================================================
    assign dma_mode = (state == S_DMA_LOAD_A)      || (state == S_DMA_LOAD_A_WAIT) ||
                      (state == S_DMA_LOAD_B)      || (state == S_DMA_LOAD_B_WAIT) ||
                      (state == S_DMA_STORE_C)     || (state == S_DMA_STORE_C_WAIT);

    assign tile_en = mover_tile_en;

    // ========================================================
    //  每 Tile 外部 BRAM 字节偏移（需在 always 块外用寄存器版本）
    // ========================================================
    // 注意：tile_idx 是寄存器，这些是组合逻辑
    wire [15:0] tile_a_ext_bytes = tile_idx * tile_a_words * 4;
    wire [15:0] tile_b_ext_bytes = tile_idx * tile_b_words * 4;

    // ========================================================
    //  下一状态信号
    // ========================================================
    reg [4:0]  next_state;
    reg [4:0]  tile_idx_next;
    reg [10:0] word_cnt_next;
    reg [1:0]  byte_idx_next;
    reg [5:0]  store_word_next;
    reg [31:0] wr_data_buf_next;
    reg        mover_load_done;
    reg        mover_store_done;

    // ========================================================
    //  时序逻辑：状态寄存器更新
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            tile_idx        <= 5'd0;
            word_cnt        <= 11'd0;
            byte_idx        <= 2'd0;
            store_word      <= 6'd0;
            wr_data_buf     <= 32'd0;
            mover_tile_en   <= {TILE_COUNT{1'b0}};
            mover_tile_w_done <= 1'b0;
            load_done       <= 1'b0;
            store_done      <= 1'b0;
        end else begin
            state           <= next_state;
            tile_idx        <= tile_idx_next;
            word_cnt        <= word_cnt_next;
            byte_idx        <= byte_idx_next;
            store_word      <= store_word_next;
            wr_data_buf     <= wr_data_buf_next;
            mover_tile_en   <= next_mover_tile_en;
            mover_tile_w_done <= (state == S_DISTRIBUTE_A && byte_idx == 2'd3 &&
                                  word_cnt + 11'd1 >= tile_a_words && a_current_tile_ready) ||
                                 (state == S_DISTRIBUTE_B && byte_idx == 2'd3 &&
                                  word_cnt + 11'd1 >= tile_b_words && (b_current_tile_ready || is_merge));
            load_done       <= mover_load_done;
            store_done      <= mover_store_done;
        end
    end

    // ========================================================
    //  组合逻辑：下一状态
    // ========================================================
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (load_start)
                    next_state = S_DMA_LOAD_A;
                else if (store_start)
                    next_state = S_COLLECT_C;
            end
            S_DMA_LOAD_A:begin
                next_state = S_DMA_LOAD_A_WAIT;
            end     
                 
            S_DMA_LOAD_A_WAIT:begin
                if (dma_rd_done) next_state = S_DISTRIBUTE_A_PRE;
            end
            S_DISTRIBUTE_A_PRE:begin
                 next_state = S_DISTRIBUTE_A;
            end

            S_DISTRIBUTE_A: begin
                
                if (byte_idx == 2'd3 && word_cnt + 11'd1 >= tile_a_words && a_current_tile_ready) begin
                    if (is_merge )begin
                        next_state = S_DMA_LOAD_B;
                    end else if (is_indep) begin
                        if (is_last_enabled_tile) begin
                             next_state = S_DMA_LOAD_B;
                        end else begin
                             next_state = S_DMA_LOAD_A;
                        end
                    end
                end 
                
            end
            S_DMA_LOAD_B: begin
                next_state = S_DMA_LOAD_B_WAIT;
            end    
                 
            S_DMA_LOAD_B_WAIT:  begin
                 if (dma_rd_done) next_state = S_DISTRIBUTE_B_PRE;
            end
   
            S_DISTRIBUTE_B_PRE:begin
                 next_state = S_DISTRIBUTE_B;
            end

            S_DISTRIBUTE_B: begin
                if (is_merge) begin
                    // ----------------------------------------------------
                    // MERGE 模式：B 矩阵广播给所有 Tile
                    // - 只需加载一次 B 数据
                    // - 同时分发给所有启用的 Tile
                    // - 无需等待 Tile ready 信号
                    // ----------------------------------------------------
                    
                    // 检查是否完成当前字的最后一个字节
                    if (byte_idx == 2'd3 && word_cnt + 11'd1 >= tile_b_words) begin
                        // B 数据全部分发完毕，进入计算等待
                        next_state = S_COMPUTE_WAIT;
                    end
                    
                end else if (is_indep) begin
                    // ----------------------------------------------------
                    // INDEP 模式：每个 Tile 独立加载 B 数据
                    // - 需要为每个启用的 Tile 单独 DMA 读取
                    // - 必须等待当前 Tile 的 ready 信号
                    // - 逐个 Tile 处理
                    // ----------------------------------------------------
                    // 检查当前 Tile 的 B 数据是否分发完毕
                    if (byte_idx == 2'd3 && word_cnt + 11'd1 >= tile_b_words && b_current_tile_ready) begin
                        
                        if (is_last_enabled_tile) begin
                            // 最后一个启用的 Tile 完成，进入计算阶段
                            next_state = S_COMPUTE_WAIT;
                        end else begin
                            // 还有更多 Tile 需要处理，加载下一个 Tile 的 B 数据
                            next_state = S_DMA_LOAD_B;
                        end
                    end
                end

            end
            S_COMPUTE_WAIT:  begin
                if (store_start) next_state = S_COLLECT_C;
            end   
                
            S_COLLECT_C: begin
                if (tile_c_valid && store_word == 6'd63) begin
                    if (is_last_enabled_tile)
                        next_state = S_DMA_STORE_C;
                end
            end

            S_DMA_STORE_C:begin
                next_state = S_DMA_STORE_C_WAIT;
            end     
             

            S_DMA_STORE_C_WAIT: begin
                if (dma_wr_done) next_state = S_DONE;
            end
            S_DONE:             next_state = S_IDLE;

            default:            next_state = S_IDLE;
        endcase
    end

    // ========================================================
    //  组合逻辑：输出控制信号
    // ========================================================
    integer ti;

    always @(*) begin
        tile_idx_next      = tile_idx;
        word_cnt_next      = word_cnt;
        byte_idx_next      = byte_idx;
        store_word_next    = store_word;
        wr_data_buf_next   = wr_data_buf;
        next_mover_tile_en = mover_tile_en;
        mover_load_done    = 1'b0;
        mover_store_done   = 1'b0;

        // DMA 默认值
        dma_rd_req      = 1'b0;
        dma_rd_addr     = 32'd0;
        dma_rd_len      = 8'd0;
        dma_buf_wr_addr = 16'd0;
        dma_wr_req      = 1'b0;
        dma_wr_addr     = 32'd0;
        dma_wr_total_len      = 12'd0;
        dma_buf_rd_addr = 16'd0;

        // Mover Buffer 默认值
        mover_buf_rd_en   = 1'b0;
        mover_buf_rd_addr = {ADDR_WIDTH{1'b0}};
        mover_buf_wr_en   = 1'b0;
        mover_buf_wr_addr = {ADDR_WIDTH{1'b0}};
        mover_buf_wr_data = {DATA_WIDTH{1'b0}};
        mover_buf_wr_strb = 4'h0;

        // Tile 默认值
        tile_a_valid = 1'b0;
        tile_a_data  = {A_BUS_WIDTH{1'b0}};
        tile_b_valid = 1'b0;
        tile_b_data  = {A_BUS_WIDTH{1'b0}};
        tile_c_ready = 1'b0;

        case (state)
            // ------------------------------------------------
            S_IDLE: begin
                if (load_start) begin
                    tile_idx_next      = first_enabled_tile;
                    word_cnt_next      = 11'd0;
                    byte_idx_next      = 2'd0;
                    mover_tile_w_done  = 1'b0;
                    next_mover_tile_en = ({{(TILE_COUNT-1){1'b0}}, 1'b1} << first_enabled_tile) & cfg_tile_mask;
                end else if (store_start) begin
                    tile_idx_next   = first_enabled_tile;
                    store_word_next = 6'd0;
                end
            end

            // ------------------------------------------------
            // DMA Load A：发起读请求，AXI Master 将数据写入内部 A Buffer
            // ------------------------------------------------
            S_DMA_LOAD_A: begin
                dma_rd_req      = 1'b1;
                dma_rd_addr     = cfg_a_base_addr + {16'd0, tile_a_ext_bytes};
                dma_rd_len      = dma_burst_len_ab;
                dma_buf_wr_addr = `NPU_A_BUFFER_BASE + tile_idx * tile_a_words * 4;
            end

            S_DMA_LOAD_A_WAIT: begin

            
            end
            S_DISTRIBUTE_A_PRE:begin
                    mover_buf_rd_en   = 1'b1;
                    mover_buf_rd_addr = `NPU_A_BUFFER_BASE + tile_idx * tile_a_words * 4 + {5'd0, word_cnt, 2'b00};
            end
            // ------------------------------------------------
            // Distribute A：从内部 A Buffer 读数据，逐字节发给 Tile
            // ------------------------------------------------
            S_DISTRIBUTE_A: begin
                mover_buf_rd_en   = 1'b1;
                //mover_buf_rd_addr = `NPU_A_BUFFER_BASE + tile_idx * tile_a_words * 4 + {5'd0, word_cnt, 2'b00};
                tile_a_valid      = mover_buf_rd_valid;
                // 直接使用 mover_buf_rd_data，避免 wr_data_buf 的延迟问题
                tile_a_data[tile_idx*8 +: 8] = mover_buf_rd_data[byte_idx*8 +: 8];

                if(mover_buf_rd_valid&&a_current_tile_ready_d)begin


                    if (byte_idx == 2'd3) begin
                        byte_idx_next = 2'd0;
                        
                        if (word_cnt + 11'd1 >= tile_a_words) begin
                            // 当前 Tile 的 A 数据全部分发完成
                            if (is_indep) begin
                                if (is_last_enabled_tile) begin
                                    tile_idx_next = first_enabled_tile;
                                end else begin
                                    tile_idx_next = next_tile_idx;
                                end

                                next_mover_tile_en = ({{(TILE_COUNT-1){1'b0}}, 1'b1} << next_tile_idx) & cfg_tile_mask;
                            end
                            word_cnt_next = 11'd0;

                        end else begin
                            word_cnt_next = word_cnt + 11'd1;
                            mover_buf_rd_addr = `NPU_A_BUFFER_BASE + tile_idx * tile_a_words * 4 + {5'd0, word_cnt+11'd1, 2'b00};
                        end
                    end else begin
                        byte_idx_next = byte_idx + 2'd1;
                    end
                end
                if (mover_buf_rd_valid)
                    wr_data_buf_next = mover_buf_rd_data;

            end

            // ------------------------------------------------
            // DMA Load B
            // ------------------------------------------------
            S_DMA_LOAD_B: begin
                dma_rd_req      = 1'b1;
                dma_rd_addr     = cfg_b_base_addr + {16'd0, tile_b_ext_bytes};
                dma_rd_len      = dma_burst_len_ab;
                dma_buf_wr_addr = `NPU_B_BUFFER_BASE + tile_idx * tile_b_words * 4;
            end

            S_DMA_LOAD_B_WAIT: begin
                // 等待 dma_rd_done
            end

            S_DISTRIBUTE_B_PRE:begin
                    mover_buf_rd_en   = 1'b1;
                    if (is_merge) begin
                        mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {5'd0, word_cnt, 2'b00};
                    end else begin
                        mover_buf_rd_addr = `NPU_B_BUFFER_BASE + tile_idx * tile_b_words * 4 + {5'd0, word_cnt, 2'b00};
                    end
            end

            // ------------------------------------------------
            // Distribute B：从内部 B Buffer 读数据，广播或逐 Tile 发给 Tile
            // ------------------------------------------------
            S_DISTRIBUTE_B: begin
                // 1. 发起 Buffer 读取请求
                mover_buf_rd_en   = 1'b1;

                // 2. 计算读取地址（在PRE状态已设置，这里保持以确保持续读取或重新确认地址）
                if (is_merge) begin
                    // MERGE 模式：B 数据在 Buffer 起始位置（共享）
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {5'd0, word_cnt, 2'b00};
                end 
                    
                   
                

                // 3. 准备发送给 Tile 的数据
                // 直接使用 mover_buf_rd_data，避免 wr_data_buf 的延迟问题
                tile_b_valid = mover_buf_rd_valid;
                if (is_merge) begin
                    // MERGE 模式：广播给所有启用的 Tile
                    for (ti = 0; ti < TILE_COUNT; ti = ti + 1) begin
                        if (cfg_tile_mask[ti])
                            tile_b_data[ti*8 +: 8] = mover_buf_rd_data[byte_idx*8 +: 8];
                    end
                end else begin
                    // INDEP 模式：只发送给当前 Tile
                    tile_b_data[tile_idx*8 +: 8] = mover_buf_rd_data[byte_idx*8 +: 8];
                end

                // 4. 更新 Buffer 数据寄存器（在数据有效时锁存）
                if (mover_buf_rd_valid)
                    wr_data_buf_next = mover_buf_rd_data;

                // 5. 状态推进逻辑（计数器更新与状态跳转）
                if (is_merge) begin
                    // ----------------------------------------------------
                    // MERGE 模式推进逻辑
                    // - 无需等待 Tile ready，连续发送
                    // - 发送完所有字后进入 COMPUTE_WAIT
                    // ----------------------------------------------------
                    if (mover_buf_rd_valid && byte_idx == 2'd3) begin
                        byte_idx_next = 2'd0;
                        if (word_cnt + 11'd1 >= tile_b_words) begin
                            // 所有数据发送完毕，保持 word_cnt 不变，等待状态机跳转
                            word_cnt_next = word_cnt;
                        end else begin
                            word_cnt_next = word_cnt + 11'd1;
                        end
                    end else if (mover_buf_rd_valid) begin
                        byte_idx_next = byte_idx + 2'd1;
                        word_cnt_next = word_cnt;
                    end

                end else if (is_indep) begin
                    // ----------------------------------------------------
                    // INDEP 模式推进逻辑
                    // - 必须等待当前 Tile 的 ready 信号
                    // - 使用 b_current_tile_ready_d 进行同步（与 A 矩阵一致）
                    // - 当前 Tile 完成后，切换到下一个 Tile 或结束
                    // ----------------------------------------------------
                    if (b_current_tile_ready_d && mover_buf_rd_valid) begin
                        if (byte_idx == 2'd3) begin
                            byte_idx_next = 2'd0;

                            if (word_cnt + 11'd1 >= tile_b_words) begin
                                // 当前 Tile 的 B 数据全部分发完毕
                                if (is_last_enabled_tile) begin
                                    // 最后一个 Tile，准备进入计算阶段
                                    word_cnt_next = word_cnt;
                                    tile_idx_next = first_enabled_tile;
                                end else begin
                                    // 还有下一个 Tile，重置计数器并切换 Tile
                                    tile_idx_next = next_tile_idx;
                                    word_cnt_next = 11'd0;
                                    // 更新 Tile 使能掩码，点亮下一个 Tile
                                    next_mover_tile_en = ({{(TILE_COUNT-1){1'b0}}, 1'b1} << next_tile_idx) & cfg_tile_mask;
                                end
                            end else begin
                                // 继续发送当前 Tile 的下一个字
                                word_cnt_next = word_cnt + 11'd1;
                                mover_buf_rd_addr = `NPU_B_BUFFER_BASE + tile_idx * tile_b_words * 4 + {5'd0, word_cnt+11'd1, 2'b00};
                            end
                        end else begin
                            // 继续发送当前字的下一个字节
                            byte_idx_next = byte_idx + 2'd1;
                        end
                    end else begin
                        // Tile 未就绪，保持所有计数器不变（等待）
                        byte_idx_next = byte_idx;
                        word_cnt_next = word_cnt;
                    end
                end
            end

            // ------------------------------------------------
            // Compute Wait：通知 Scheduler 加载完成
            // ------------------------------------------------
            S_COMPUTE_WAIT: begin
                mover_load_done    = 1'b1;
                next_mover_tile_en = cfg_tile_mask[TILE_COUNT-1:0];
                tile_idx_next      = first_enabled_tile;
            end

            // ------------------------------------------------
            // Collect C：从 Tile 收集结果写入 C Buffer
            // ------------------------------------------------
            S_COLLECT_C: begin
                if (tile_c_valid) begin
                    mover_buf_wr_en   = 1'b1;
                    mover_buf_wr_strb = 4'hF;
                    mover_buf_wr_addr = `NPU_C_BUFFER_BASE + {1'd0, tile_idx, 8'd0} + {6'd0, store_word, 2'b00};
                    mover_buf_wr_data = tile_c_data[tile_idx * `NPU_TILE_C_BITS + store_word * 32 +: 32];
                    tile_c_ready      = 1'b1;

                    if (store_word == 6'd63) begin
                        store_word_next = 6'd0;
                        if (!is_last_enabled_tile)
                            tile_idx_next = next_tile_idx;
                    end else begin
                        store_word_next = store_word + 6'd1;
                    end
                end
            end

            // ------------------------------------------------
            // DMA Store C：发起写请求，AXI Master 从 C Buffer 读数据写回外部 BRAM
            // ------------------------------------------------
            S_DMA_STORE_C: begin
                dma_wr_req      = 1'b1;
                dma_wr_addr     = cfg_c_base_addr;
                // 根据启用的Tile数量计算传输长度：每个Tile有64个word（8x8矩阵）
                // AXI burst长度字段 = 总数据个数 - 1
                dma_wr_total_len      = calc_enabled_tiles(cfg_tile_mask) * 12'd64 - 12'd1;
                dma_buf_rd_addr = `NPU_C_BUFFER_BASE;
            end

            S_DMA_STORE_C_WAIT: begin
                // 等待 dma_wr_done
            end

            // ------------------------------------------------
            S_DONE: begin
                mover_store_done = 1'b1;
                tile_idx_next    = first_enabled_tile;
                word_cnt_next    = 11'd0;
                byte_idx_next    = 2'd0;
                store_word_next  = 6'd0;
            end

            default: ;
        endcase
    end

endmodule
