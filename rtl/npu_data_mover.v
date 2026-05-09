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
    parameter C_BUS_WIDTH = 256 * `NPU_NUM_TILES;

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
    output reg  [TILE_COUNT-1:0]      tile_en;
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
    localparam S_STORE       = 5'd10;
    localparam S_STORE_WR    = 5'd11;
    localparam S_DONE        = 5'd12;

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
        end else begin
            state           <= next_state;
            tile_idx        <= tile_idx_next;
            word_cnt        <= word_cnt_next;
            byte_idx        <= byte_idx_next;
            store_word      <= store_word_next;
            wr_data_buf     <= wr_data_buf_next;
            split_group_cnt <= split_group_cnt_next;
            split_b_buf     <= split_b_buf_next;
        end
    end

    // ========================================================
    //  下一状态逻辑（组合逻辑块1）
    // ========================================================
    wire [4:0]  next_state;
    wire [4:0]  tile_idx_next;
    wire [10:0] word_cnt_next;
    wire [1:0]  byte_idx_next;
    wire [5:0]  store_word_next;
    wire [31:0] wr_data_buf_next;
    wire [2:0]  split_group_cnt_next;
    wire [13:0] split_b_buf_next;

    always @(*) begin
        // 默认值
        next_state          = state;
        tile_idx_next       = tile_idx;
        word_cnt_next       = word_cnt;
        byte_idx_next       = byte_idx;
        store_word_next     = store_word;
        wr_data_buf_next    = wr_data_buf;
        split_group_cnt_next= split_group_cnt;
        split_b_buf_next    = split_b_buf;

        case (state)
            S_IDLE: begin
                if (load_start) begin
                    next_state    = S_LOAD_A;
                    tile_idx_next = 5'd0;
                    word_cnt_next = 11'd0;
                    byte_idx_next = 2'd0;
                end else if (store_start) begin
                    next_state     = S_STORE;
                    tile_idx_next  = 5'd0;
                    store_word_next= 6'd0;
                end
            end

            S_LOAD_A: begin
                next_state = S_LOAD_A_WAIT;
            end

            S_LOAD_A_WAIT: begin
                if (buf_rd_valid) begin
                    next_state       = S_UNPACK_A;
                    wr_data_buf_next = buf_rd_data;
                    byte_idx_next    = 2'd0;
                end
            end

            S_UNPACK_A: begin
                if (byte_idx == 2'd3) begin
                    if (word_cnt + 11'd1 >= tile_a_words) begin
                        if (is_merge || tile_idx == 5'd31) begin
                            word_cnt_next = 11'd0;
                            tile_idx_next = 5'd0;
                            if (is_split) begin
                                split_group_cnt_next = 3'd0;
                                next_state = S_SPLIT_LOAD_B;
                            end else begin
                                next_state = S_LOAD_B;
                            end
                        end else begin
                            tile_idx_next = tile_idx + 5'd1;
                            word_cnt_next = 11'd0;
                            next_state    = S_LOAD_A;
                        end
                    end else begin
                        word_cnt_next = word_cnt + 11'd1;
                        next_state    = S_LOAD_A;
                    end
                end else begin
                    byte_idx_next = byte_idx + 2'd1;
                end
            end

            S_LOAD_B: begin
                next_state = S_LOAD_B_WAIT;
            end

            S_LOAD_B_WAIT: begin
                if (buf_rd_valid) begin
                    next_state       = S_UNPACK_B;
                    wr_data_buf_next = buf_rd_data;
                    byte_idx_next    = 2'd0;
                end
            end

            S_UNPACK_B: begin
                if (byte_idx == 2'd3) begin
                    if (word_cnt + 11'd1 >= tile_b_words) begin
                        if (is_merge || tile_idx == 5'd31) begin
                            next_state = S_DONE;
                        end else begin
                            tile_idx_next = tile_idx + 5'd1;
                            word_cnt_next = 11'd0;
                            next_state    = S_LOAD_B;
                        end
                    end else begin
                        word_cnt_next = word_cnt + 11'd1;
                        next_state    = S_LOAD_B;
                    end
                end else begin
                    byte_idx_next = byte_idx + 2'd1;
                end
            end

            S_SPLIT_LOAD_B: begin
                if (split_group_cnt == 3'd0 && word_cnt == 11'd0) begin
                    split_b_buf_next = {3'd0, tile_idx} * {5'd0, cfg_k, 3'b000};
                end
                next_state = S_SPLIT_LOAD_B_WAIT;
            end

            S_SPLIT_LOAD_B_WAIT: begin
                if (buf_rd_valid) begin
                    next_state       = S_SPLIT_UNPACK_B;
                    wr_data_buf_next = buf_rd_data;
                    byte_idx_next    = 2'd0;
                end
            end

            S_SPLIT_UNPACK_B: begin
                if (byte_idx == 2'd3) begin
                    if (word_cnt + 11'd1 >= split_b_group_words) begin
                        if (split_group_cnt == 3'd7) begin
                            if (tile_idx == 5'd31) begin
                                next_state = S_DONE;
                            end else begin
                                tile_idx_next         = tile_idx + 5'd1;
                                word_cnt_next         = 11'd0;
                                split_group_cnt_next  = 3'd0;
                                split_b_buf_next      = split_b_buf + {5'd0, cfg_k, 3'b000};
                                next_state            = S_SPLIT_LOAD_B;
                            end
                        end else begin
                            split_group_cnt_next = split_group_cnt + 3'd1;
                            word_cnt_next        = 11'd0;
                            split_b_buf_next     = split_b_buf + {8'd0, cfg_k};
                            next_state           = S_SPLIT_LOAD_B;
                        end
                    end else begin
                        word_cnt_next = word_cnt + 11'd1;
                        next_state    = S_SPLIT_LOAD_B;
                    end
                end else begin
                    byte_idx_next = byte_idx + 2'd1;
                end
            end

            S_STORE: begin
                if (tile_c_valid) begin
                    next_state      = S_STORE_WR;
                    store_word_next = 6'd0;
                end
            end

            S_STORE_WR: begin
                if (store_word == 6'd63) begin
                    if (tile_idx == 5'd31) begin
                        next_state = S_DONE;
                    end else begin
                        tile_idx_next   = tile_idx + 5'd1;
                        store_word_next = 6'd0;
                        next_state      = S_STORE;
                    end
                end else begin
                    store_word_next = store_word + 6'd1;
                end
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ========================================================
    //  输出逻辑（组合逻辑块2）
    // ========================================================
    wire mover_load_done;
    wire mover_store_done;
    wire mover_buf_rd_en;
    wire [ADDR_WIDTH-1:0] mover_buf_rd_addr;
    wire mover_buf_wr_en;
    wire [ADDR_WIDTH-1:0] mover_buf_wr_addr;
    wire [DATA_WIDTH-1:0] mover_buf_wr_data;
    wire [3:0] mover_buf_wr_strb;
    wire [TILE_COUNT-1:0] mover_tile_en;
    wire [A_BUS_WIDTH-1:0] mover_tile_a_data;
    wire mover_tile_a_valid;
    wire [A_BUS_WIDTH-1:0] mover_tile_b_data;
    wire mover_tile_b_valid;
    wire mover_tile_c_ready;

    integer ti;

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
            S_LOAD_A: begin
                mover_buf_rd_en = 1'b1;
                if (is_merge)
                    mover_buf_rd_addr = `NPU_A_BUFFER_BASE + {5'd0, word_cnt, 2'b00};
                else
                    mover_buf_rd_addr = `NPU_A_BUFFER_BASE + {1'd0, tile_idx, 10'd0} + {5'd0, word_cnt, 2'b00};
            end

            S_LOAD_A_WAIT: begin
                // 等待数据
            end

            S_UNPACK_A: begin
                mover_tile_a_valid = 1'b1;
                if (is_merge) begin
                    for (ti = 0; ti < TILE_COUNT; ti = ti + 1)
                        mover_tile_a_data[ti*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
                end else begin
                    mover_tile_a_data[tile_idx*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
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
                // 等待数据
            end

            S_UNPACK_B: begin
                mover_tile_b_valid = 1'b1;
                if (is_merge) begin
                    for (ti = 0; ti < TILE_COUNT; ti = ti + 1)
                        mover_tile_b_data[ti*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
                end else begin
                    mover_tile_b_data[tile_idx*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
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
                // 等待数据
            end

            S_SPLIT_UNPACK_B: begin
                mover_tile_b_valid = 1'b1;
                mover_tile_b_data[tile_idx*8 +: 8] = wr_data_buf[byte_idx*8 +: 8];
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
            end

            S_DONE: begin
                if (load_start)
                    mover_load_done = 1'b1;
                if (store_start)
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

endmodule