`ifndef NPU_DEFS_VH
`define NPU_DEFS_VH

// ============================================================
//  NPU 全局参数定义
// ============================================================

// Tile 配置
`define NPU_NUM_TILES        32       // 计算单元数量
`define NPU_TILE_SIZE        8        // 8x8 MAC 阵列
`define NPU_K_MAX            64       // 最大 K 维度（A 列数 = B 行数）

// AXI 接口参数
`define NPU_AXI_ADDR_WIDTH   16      // 64KB 内部地址空间
`define NPU_AXI_DATA_WIDTH   32      // 32bit 数据宽度
`define NPU_AXI_STRB_WIDTH   4       // 4bit WSTRB

// Tile 内部矩阵展开宽度
`define NPU_TILE_A_BITS     (8*8*8)
`define NPU_TILE_B_BITS     (8*8*8)
`define NPU_TILE_C_BITS     (8*8*32)
`define TILE_PORT_W         (8*8)

// ============================================================
//  AXI 地址空间规划
// ============================================================

// 区域基地址（内部偏移地址）
`define NPU_AXI_LITE_BASE   16'h0000   // AXI-Lite 寄存器区
`define NPU_A_BUFFER_BASE   16'h0100   // A 矩阵数据区
`define NPU_B_BUFFER_BASE   16'h4000   // B 矩阵数据区
`define NPU_C_BUFFER_BASE   16'h8000   // C 结果数据区

// 区域大小
`define NPU_AXI_LITE_SIZE   256        // 256 字节
`define NPU_A_BUFFER_SIZE   (16*1024)  // 16 KB
`define NPU_B_BUFFER_SIZE   (16*1024)  // 16 KB
`define NPU_C_BUFFER_SIZE   (8*1024)   // 8 KB

// Buffer 深度（32bit 字数）
`define NPU_A_BUF_DEPTH     (`NPU_A_BUFFER_SIZE / 4)   // 4096 words
`define NPU_B_BUF_DEPTH     (`NPU_B_BUFFER_SIZE / 4)   // 4096 words
`define NPU_C_BUF_DEPTH     (`NPU_C_BUFFER_SIZE / 4)   // 2048 words

// ============================================================
//  AXI-Lite 寄存器地址映射
// ============================================================

`define REG_CTRL            8'h00   // 控制寄存器（bit0:start, bit1:status_clr）
`define REG_STATUS          8'h04   // 状态寄存器（bit0:done, bit1:error）
`define REG_MODE            8'h08   // 工作模式
`define REG_M               8'h0C   // M 维度
`define REG_N               8'h10   // N 维度
`define REG_K               8'h14   // K 维度
`define REG_TILE_MASK       8'h18   // Tile 使能掩码
`define REG_ITERATIONS      8'h1C   // 迭代次数
`define REG_IRQ_EN          8'h20   // 中断使能

// ============================================================
//  工作模式编码
// ============================================================

`define NPU_MODE_INDEP       2'b00
`define NPU_MODE_MERGE       2'b01


// 权重加载模式编码（reg_mode[3:2]位控制）
`define NPU_WEIGHT_DYNAMIC   1'b0
`define NPU_WEIGHT_STATIC    1'b1
`define NPU_WEIGHT_SHARED    1'b0
`define NPU_WEIGHT_INDEPENDENT 1'b1

// ============================================================
//  全局状态机编码
// ============================================================

`define NPU_ST_IDLE          4'd0
`define NPU_ST_CFG           4'd1
`define NPU_ST_LOAD          4'd2
`define NPU_ST_RUN           4'd3
`define NPU_ST_STORE         4'd4
`define NPU_ST_DONE          4'd5
`define NPU_ST_ERROR         4'd6

// Tile 内部状态机
`define TILE_IDLE            3'd0
`define TILE_LOAD            3'd1
`define TILE_COMPUTE         3'd2
`define TILE_DONE            3'd3
// 异步加载状态
`define TILE_LOAD_A          3'd4
`define TILE_LOAD_B          3'd5

// ============================================================
//  AXI 响应编码
// ============================================================

`define AXI_RESP_OKAY        2'b00
`define AXI_RESP_EXOKAY      2'b01
`define AXI_RESP_SLVERR      2'b10
`define AXI_RESP_DECERR      2'b11

`endif