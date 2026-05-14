`include "npu_defs.vh"

// ============================================================
// npu_data_mover - 数据搬运模块（标准FSM三分法重构）
// 从 A/B Buffer 读取数据分发到 Tile，收集 C 结果写回 C Buffer
// 支持 INDEP / MERGE / SPLIT 三种模式
// 
// FSM设计原则：
// 1. 时序逻辑块：状态寄存器和计数器
// 2. 组合逻辑块（下一状态）：计算next_state
// 3. 组合逻辑块（输出）：控制信号和数据输出
// ============================================================
module npu_data_mover (clk, rst_n,
    cfg_mode, cfg_m, cfg_n, cfg_k, cfg_tile_mask,
    load_start, store_start, load_done, store_done,
    buf_rd_en, buf_rd_addr, buf_rd_data, buf_rd_valid,
    buf_wr_en, buf_wr_addr, buf_wr_data, buf_wr_strb,
    tile_en, tile_a_data, tile_a_valid,
    tile_b_data, tile_b_valid,
    tile_c_data, tile_c_valid, tile_c_ready
);

    parameter ADDR_WIDTH  = `NPU_AXI_ADDR_WIDTH;
    parameter DATA_WIDTH  = `NPU_AXI_DATA_WIDTH;
    parameter TILE_COUNT  = `NPU_NUM_TILES;
    parameter K_MAX       = `NPU_K_MAX;
    parameter A_BUS_WIDTH = 8 * `NPU_NUM_TILES;
    parameter C_BUS_WIDTH = `NPU_TILE_C_BITS * `NPU_NUM_TILES;  // 2048 * 32 = 65536位

    input  wire                       clk;
    input  wire                       rst_n;
    input  wire [1:0]                 cfg_mode;
    input  wire [5:0]                 cfg_m;
    input  wire [5:0]                 cfg_n;
    input  wire [5:0]                 cfg_k;
    input  wire [31:0]                cfg_tile_mask;
    input  wire                       load_start;
    input  wire                       store_start;
    output reg                        load_done;
    output reg                        store_done;
    output reg                        buf_rd_en;
    output reg  [ADDR_WIDTH-1:0]      buf_rd_addr;
    input  wire [DATA_WIDTH-1:0]      buf_rd_data;
    input  wire                       buf_rd_valid;
    output reg                        buf_wr_en;
    output reg  [ADDR_WIDTH-1:0]      buf_wr_addr;
    output reg  [DATA_WIDTH-1:0]      buf_wr_data;
    output reg  [3:0]                 buf_wr_strb;
    output wire [TILE_COUNT-1:0]      tile_en;
    output reg  [A_BUS_WIDTH-1:0]     tile_a_data;
    output reg                        tile_a_valid;
    output reg  [A_BUS_WIDTH-1:0]     tile_b_data;
    output reg                        tile_b_valid;
    input  wire [C_BUS_WIDTH-1:0]     tile_c_data;
    input  wire                       tile_c_valid;
    output reg                        tile_c_ready;

    // ========================================================
    //  常量与模式检测（组合逻辑）
    // ========================================================
    wire [10:0] tile_a_words = {5'd0, cfg_k} << 1;   // 2*K words per tile (A)
    wire [10:0] tile_b_words = {5'd0, cfg_k} << 1;   // 2*K words per tile (INDEP/MERGE B)
    wire [10:0] split_b_group_words = {5'd0, cfg_k} >> 1; // K/4 words per column group

    wire is_merge = (cfg_mode == `NPU_MODE_MERGE);
    wire is_split = (cfg_mode == `NPU_MODE_SPLIT);

    // ========================================================
    //  状态定义
    // ========================================================
    localparam S_IDLE        = 5'd0;
    localparam S_LOAD_A      = 5'd1;
    localparam S_LOAD_A_WAIT = 5'd2;
    localparam S_UNPACK_A    = 5'd3;
    localparam S_LOAD_B      = 5'd4;
    localparam S_LOAD_B_WAIT = 5'd5;
    localparam S_UNPACK_B    = 5'd6;
    localparam S_SPLIT_LOAD_B      = 5'd7;
    localparam S_SPLIT_LOAD_B_WAIT = 5'd8;
    localparam S_SPLIT_UNPACK_B    = 5'd9;
    localparam S_COMPUTE_WAIT      = 5'd10;
    localparam S_STORE       = 5'd11;
    localparam S_STORE_WR    = 5'd12;
    localparam S_DONE        = 5'd13;

    // ========================================================
    //  状态机和计数器寄存器（时序逻辑块1）
    // ========================================================
    reg [4:0]  state;
    reg [4:0]  tile_idx;
    reg [10:0] word_cnt;
    reg [1:0]  byte_idx;
    reg [5:0]  store_word;
    reg [31:0] wr_data_buf;
    reg [2:0]  split_group_cnt;
    reg [13:0] split_b_buf;
    reg        is_load_op;  // ✅ 新增：标记当前是Load操作还是Store操作

    // ========================================================
    //  查找下一个启用的 Tile（组合逻辑）
    // ========================================================
    // 剩余未处理的 tile 掩码（tile_idx 之后的启用 tile）
    // 使用 6-bit 加法避免 tile_idx=31 时的 5-bit 溢出
    wire [5:0] next_tile_6bit = {1'b0, tile_idx} + 6'd1;
    wire [31:0] remaining_tiles_mask = (tile_idx == 5'd31) ? 32'd0 :
                                        (cfg_tile_mask & ~((32'h1 << next_tile_6bit) - 32'h1));


    // 检查当前 tile 是否是最后一个启用的 tile
    wire is_last_enabled_tile = (remaining_tiles_mask == 32'd0);

    // 优先编码器：查找 remaining_tiles_mask 中最低位的启用 tile
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

    // 查找第一个启用的 tile（用于 S_IDLE 初始化）
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

    // 下一状态信号声明
    reg [4:0]  next_state;
    reg [4:0]  tile_idx_next;
    reg [10:0] word_cnt_next;
    reg [1:0]  byte_idx_next;
    reg [5:0]  store_word_next;
    reg [31:0] wr_data_buf_next;
    reg [2:0]  split_group_cnt_next;
    reg [13:0] split_b_buf_next;

    // ---- 状态寄存器更新（时序）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            tile_idx        <= 5'd0;
            word_cnt        <= 11'd0;
            byte_idx        <= 2'd0;
            store_word      <= 6'd0;
            wr_data_buf     <= 32'd0;
            split_group_cnt <= 3'd0;
            split_b_buf     <= 14'd0;
            is_load_op      <= 1'b0;
        end else begin
            state           <= next_state;
            tile_idx        <= tile_idx_next;
            word_cnt        <= word_cnt_next;
            byte_idx        <= byte_idx_next;
            store_word      <= store_word_next;
            wr_data_buf     <= wr_data_buf_next;
            split_group_cnt <= split_group_cnt_next;
            split_b_buf     <= split_b_buf_next;
            // ✅ 在IDLE状态捕获操作类型
            if (state == S_IDLE) begin
                if (load_start)
                    is_load_op <= 1'b1;
                else if (store_start)
                    is_load_op <= 1'b0;
            end
        end
    end

    // ========================================================
    //  下一状态逻辑（组合逻辑块1）
    // ========================================================
    always @(*) begin
        // 默认值
        next_state          = state;

        case (state)
            S_IDLE: begin
                if (load_start) begin
                    next_state    = S_LOAD_A;
                end 
            end

            S_LOAD_A: begin
                next_state = S_LOAD_A_WAIT;
            end

            S_LOAD_A_WAIT: begin
                if (buf_rd_valid) begin
                    next_state       = S_UNPACK_A;
                end
            end

            S_UNPACK_A: begin
                //如果是最后一个启用的tile且当前tile的word_cnt已经大于等于tile_a_words，就进入LOAD_B，否则继续LOAD_A
                if (byte_idx == 2'd3) begin
                    if (word_cnt + 11'd1 >= tile_a_words) begin
                        if (is_merge) begin
                            if (is_last_enabled_tile) begin
                                next_state = S_LOAD_B;
                            end else begin
                                next_state = S_LOAD_A;
                            end
                        end else if (is_split) begin
                             if (is_last_enabled_tile) begin
                                next_state = S_SPLIT_LOAD_B;
                            end else begin
                                next_state = S_LOAD_A;
                            end   
                        end
                    end else begin
                        next_state    = S_LOAD_A;
                    end
                end else begin   
                    next_state    = S_LOAD_A;
                end

            end

            S_LOAD_B: begin
                next_state = S_LOAD_B_WAIT;
            end

            S_LOAD_B_WAIT: begin
                if (buf_rd_valid) begin
                    next_state       = S_UNPACK_B;
                end
            end

            S_UNPACK_B: begin

                // 状态转移逻辑
                if (byte_idx == 2'd3) begin  
                    // 当前字的4个字节都处理完了
                    if (word_cnt + 11'd1 >= tile_b_words) begin
                        // 当前 Tile 的 B 矩阵全部加载完成
                        if (is_merge) begin
                            next_state = S_COMPUTE_WAIT;  // ✅ 进入计算等待状态，等待Tile C的结果
                        end else if (is_split) begin
                             if (is_last_enabled_tile) begin
                                next_state = S_COMPUTE_WAIT;
                            end else begin
                                next_state = S_LOAD_B;
                            end   
                        end
                    end else begin
                        next_state = S_LOAD_B;  // 回到 LOAD_B 读取下一个字
                    end
                end 
            end

            S_SPLIT_LOAD_B: begin

                next_state = S_SPLIT_LOAD_B_WAIT;
            end

            S_SPLIT_LOAD_B_WAIT: begin
                if (buf_rd_valid) begin
                    next_state       = S_SPLIT_UNPACK_B;
                end
            end

            S_SPLIT_UNPACK_B: begin

            end
            S_COMPUTE_WAIT : begin
                if (store_start) begin
                    next_state      = S_STORE;
                end
            end
            S_STORE: begin
                if (tile_c_valid) begin
                    next_state      = S_STORE_WR;
                end
            end

            S_STORE_WR: begin
                if (store_word == 6'd63) begin
                    if (is_last_enabled_tile) begin
                        next_state = S_DONE;
                    end else begin
                        next_state      = S_STORE;
                    end
                end 
            end

            S_DONE: begin
                // ✅ 完成done信号后自动返回IDLE
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ========================================================
    //  输出信号生成（组合逻辑块2 - 中间信号）
    // ========================================================
    reg mover_load_done;           // ✅ 改为 reg
    reg mover_store_done;          // ✅ 改为 reg
    reg mover_buf_rd_en;           // ✅ 改为 reg
    reg [ADDR_WIDTH-1:0] mover_buf_rd_addr;   // ✅ 改为 reg
    reg mover_buf_wr_en;           // ✅ 改为 reg
    reg [ADDR_WIDTH-1:0] mover_buf_wr_addr;   // ✅ 改为 reg
    reg [DATA_WIDTH-1:0] mover_buf_wr_data;   // ✅ 改为 reg
    reg [3:0] mover_buf_wr_strb;   // ✅ 改为 reg
    reg [TILE_COUNT-1:0] mover_tile_en;       // ✅ 改为 reg
    reg [A_BUS_WIDTH-1:0] mover_tile_a_data;  // ✅ 改为 reg
    reg mover_tile_a_valid;        // ✅ 改为 reg
    reg [A_BUS_WIDTH-1:0] mover_tile_b_data;  // ✅ 改为 reg
    reg mover_tile_b_valid;        // ✅ 改为 reg
    reg mover_tile_c_ready;        // ✅ 改为 reg

    integer ti;
    wire [15:0] tile_offset_bytes = tile_idx * tile_a_words * 4;  // 字节偏移
    always @(*) begin
        // 默认值
        mover_load_done     = 1'b0;
        mover_store_done    = 1'b0;
        mover_buf_rd_en     = 1'b0;
        mover_buf_rd_addr   = {ADDR_WIDTH{1'b0}};
        mover_buf_wr_en     = 1'b0;
        mover_buf_wr_addr   = {ADDR_WIDTH{1'b0}};
        mover_buf_wr_data   = {DATA_WIDTH{1'b0}};
        mover_buf_wr_strb   = 4'h0;
        mover_tile_a_valid  = 1'b0;
        mover_tile_b_valid  = 1'b0;
        mover_tile_c_ready  = 1'b0;
        mover_tile_a_data   = {A_BUS_WIDTH{1'b0}};
        mover_tile_b_data   = {A_BUS_WIDTH{1'b0}};

        tile_idx_next       = tile_idx;
        word_cnt_next       = word_cnt;
        byte_idx_next       = byte_idx;
        store_word_next     = store_word;
        wr_data_buf_next    = wr_data_buf;
        split_group_cnt_next = split_group_cnt;
        split_b_buf_next    = split_b_buf;
        // ---- Tile 使能逻辑 ----
        if (state >= S_LOAD_A && state <= S_SPLIT_UNPACK_B) begin
            if (is_merge)
                mover_tile_en = cfg_tile_mask[TILE_COUNT-1:0];
            else
                mover_tile_en = ({{(TILE_COUNT-1){1'b0}}, 1'b1} << tile_idx) & cfg_tile_mask[TILE_COUNT-1:0];
        end else if (state >= S_STORE && state <= S_STORE_WR) begin
            mover_tile_en = ({{(TILE_COUNT-1){1'b0}}, 1'b1} << tile_idx) & cfg_tile_mask[TILE_COUNT-1:0];
        end else begin
            mover_tile_en = {TILE_COUNT{1'b0}};
        end

        case (state)
                S_IDLE: begin
                if (load_start) begin
                    tile_idx_next = first_enabled_tile;
                    word_cnt_next = 11'd0;
                    byte_idx_next = 2'd0;
                end else if (store_start) begin
                    tile_idx_next  = first_enabled_tile;
                    store_word_next= 6'd0;
                end
            end
            S_LOAD_A: begin
                mover_buf_rd_en = 1'b1;
                if (is_merge)
                    mover_buf_rd_addr = `NPU_A_BUFFER_BASE + tile_offset_bytes + {5'd0, word_cnt, 2'b00};
                else
                    mover_buf_rd_addr = `NPU_A_BUFFER_BASE + tile_offset_bytes + {5'd0, word_cnt, 2'b00};
            end

            S_LOAD_A_WAIT: begin
                //  保持读请求和地址，直到数据返回
                mover_buf_rd_en = 1'b1;
               if (buf_rd_valid) begin
                    wr_data_buf_next = buf_rd_data;
                end
                if (is_merge)
                    mover_buf_rd_addr = `NPU_A_BUFFER_BASE + tile_offset_bytes + {5'd0, word_cnt, 2'b00};
                else
                    mover_buf_rd_addr = `NPU_A_BUFFER_BASE + tile_offset_bytes + {5'd0, word_cnt, 2'b00};
            end

            S_UNPACK_A: begin
                mover_tile_a_valid = 1'b1;
                if (is_merge) begin
                     mover_tile_a_data[tile_idx*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
                end else begin  //对于其他工作模式，后面再修改
                    mover_tile_a_data[tile_idx*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
                end
                
                if (byte_idx == 2'd3) begin
                    byte_idx_next = 2'd0;
                    if (word_cnt + 11'd1 >= tile_a_words) begin
                        word_cnt_next = 11'd0;
                        if(is_merge)begin
                            if (is_last_enabled_tile) begin
                                tile_idx_next = first_enabled_tile;
                            end else begin
                                tile_idx_next = next_tile_idx;
                            end
                        end else if (is_split) begin
                             if (is_last_enabled_tile) begin
                                split_group_cnt_next = 3'd0;
                            end else begin
                                tile_idx_next = next_tile_idx;
                            end
                        end
                    end else begin
                        word_cnt_next = word_cnt + 11'd1;
                    end
                end else begin
                    byte_idx_next = byte_idx + 2'd1;
                end
            end

            S_LOAD_B: begin
                mover_buf_rd_en = 1'b1;
                if (is_merge)
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {5'd0, word_cnt, 2'b00};
                else
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {1'd0, tile_idx, 10'd0} + {5'd0, word_cnt, 2'b00};
            end

            S_LOAD_B_WAIT: begin
                // ✅ 保持读请求和地址，直到数据返回
                mover_buf_rd_en = 1'b1;
                if (buf_rd_valid) begin
                    wr_data_buf_next = buf_rd_data;
                end
                if (is_merge)
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {5'd0, word_cnt, 2'b00};
                else
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {1'd0, tile_idx, 10'd0} + {5'd0, word_cnt, 2'b00};
            end

            S_UNPACK_B: begin
                mover_tile_b_valid = 1'b1;
                if (is_merge) begin
                    for (ti = 0; ti < TILE_COUNT; ti = ti + 1)
                        mover_tile_b_data[ti*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
                end else begin
                    mover_tile_b_data[tile_idx*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
                end               
                
                if (byte_idx == 2'd3) begin
                    // 当前字的4个字节都处理完了
                    if (word_cnt + 11'd1 >= tile_b_words) begin
                        // 当前 Tile 的 B 矩阵全部加载完成
                        word_cnt_next = 11'd0;
                        if (is_merge) begin
                            if (is_last_enabled_tile) begin
                                tile_idx_next = first_enabled_tile;
                            end
                        end else if (is_split) begin
                            if (is_last_enabled_tile) begin
                                split_group_cnt_next = 3'd0;
                                tile_idx_next = first_enabled_tile;
                            end else begin
                                tile_idx_next = next_tile_idx;
                            end
                        end
                    end else begin
                        // 当前 Tile 还有更多字要加载
                        word_cnt_next = word_cnt + 11'd1;
                    end
                end else begin
                    // 当前字还有字节未处理
                    byte_idx_next = byte_idx + 2'd1;
                end
            end

            S_SPLIT_LOAD_B: begin
                mover_buf_rd_en = 1'b1;
                if (split_group_cnt == 3'd0 && word_cnt == 11'd0)
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {2'd0, tile_idx} * {5'd0, cfg_k, 3'b000} + {5'd0, word_cnt, 2'b00};
                else
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {2'd0, split_b_buf} + {5'd0, word_cnt, 2'b00};
            end

            S_SPLIT_LOAD_B_WAIT: begin
                // ✅ 保持读请求和地址，直到数据返回
                mover_buf_rd_en = 1'b1;
                if (buf_rd_valid) begin
                    wr_data_buf_next = buf_rd_data;
                end
                if (split_group_cnt == 3'd0 && word_cnt == 11'd0)
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {2'd0, tile_idx} * {5'd0, cfg_k, 3'b000} + {5'd0, word_cnt, 2'b00};
                else
                    mover_buf_rd_addr = `NPU_B_BUFFER_BASE + {2'd0, split_b_buf} + {5'd0, word_cnt, 2'b00};
            end

            S_SPLIT_UNPACK_B: begin
                mover_tile_b_valid = 1'b1;
                mover_tile_b_data[tile_idx*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
            end

            S_COMPUTE_WAIT: begin

            end
            S_STORE: begin
                if (tile_c_valid)
                    mover_tile_c_ready = 1'b1;
            end

            S_STORE_WR: begin
                mover_buf_wr_en   = 1'b1;
                mover_buf_wr_strb = 4'hF;
                mover_buf_wr_addr = `NPU_C_BUFFER_BASE + {1'd0, tile_idx, 8'd0} + {6'd0, store_word, 2'b00};
                mover_buf_wr_data = tile_c_data[(tile_idx*256 + store_word*32) +: 32];
                
                // [DEBUG] Store阶段监控 - 输出写入C Buffer的数据
                if (store_word == 6'd0) begin
                    $display("[STORE DBG] t=%0t Writing C Buffer for Tile %d, addr=0x%08X, data[0]=0x%08X",
                             $time, tile_idx, 
                             `NPU_C_BUFFER_BASE + {1'd0, tile_idx, 8'd0},
                             tile_c_data[(tile_idx*256 + 0*32) +: 32]);
                end
            end

            S_DONE: begin
                // ✅ 根据 is_load_op 标志位决定输出哪个 done 信号
                tile_idx_next = first_enabled_tile;
                word_cnt_next = 11'd0;
                byte_idx_next = 2'd0;
                store_word_next = 6'd0;
                split_group_cnt_next = 3'd0;
                if (is_load_op)
                    mover_load_done = 1'b1;
                else
                    mover_store_done = 1'b1;
            end

            default: ;
        endcase
    end

    // ========================================================
    //  输出信号赋值（时序驱动）
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_done       <= 1'b0;
            store_done      <= 1'b0;
            buf_rd_en       <= 1'b0;
            buf_rd_addr     <= {ADDR_WIDTH{1'b0}};
            buf_wr_en       <= 1'b0;
            buf_wr_addr     <= {ADDR_WIDTH{1'b0}};
            buf_wr_data     <= {DATA_WIDTH{1'b0}};
            buf_wr_strb     <= 4'h0;
            tile_a_valid    <= 1'b0;
            tile_b_valid    <= 1'b0;
            tile_c_ready    <= 1'b0;
            tile_a_data     <= {A_BUS_WIDTH{1'b0}};
            tile_b_data     <= {A_BUS_WIDTH{1'b0}};
        end else begin
            load_done    <= mover_load_done;
            store_done   <= mover_store_done;
            buf_rd_en    <= mover_buf_rd_en;
            buf_rd_addr  <= mover_buf_rd_addr;
            buf_wr_en    <= mover_buf_wr_en;
            buf_wr_addr  <= mover_buf_wr_addr;
            buf_wr_data  <= mover_buf_wr_data;
            buf_wr_strb  <= mover_buf_wr_strb;
            tile_a_valid <= mover_tile_a_valid;
            tile_b_valid <= mover_tile_b_valid;
            tile_c_ready <= mover_tile_c_ready;
            tile_a_data  <= mover_tile_a_data;
            tile_b_data  <= mover_tile_b_data;
        end
    end

    assign tile_en = mover_tile_en;

    // ========================================================
    //  调试输出（监控状态机）
    // ========================================================
    reg [4:0] prev_state;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            prev_state <= S_IDLE;
        else
            prev_state <= state;
    end
    
    always @(posedge clk) begin
        if (state != prev_state) begin
            case (state)
                S_IDLE:        $display("[t=%0t] STATE -> IDLE", $time);
                S_LOAD_A:      $display("[t=%0t] STATE -> LOAD_A", $time);
                S_LOAD_A_WAIT: $display("[t=%0t] STATE -> LOAD_A_WAIT", $time);
                S_UNPACK_A:    $display("[t=%0t] STATE -> UNPACK_A", $time);
                S_LOAD_B:      $display("[t=%0t] STATE -> LOAD_B", $time);
                S_LOAD_B_WAIT: $display("[t=%0t] STATE -> LOAD_B_WAIT", $time);
                S_UNPACK_B:    $display("[t=%0t] STATE -> UNPACK_B", $time);
                S_DONE:        $display("[t=%0t] STATE -> DONE", $time);
                default:       $display("[t=%0t] STATE -> %d", $time, state);
            endcase
        end
    end

endmodule