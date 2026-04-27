`ifndef NPU_DEFS_VH
`define NPU_DEFS_VH

// 基础参数：按你的 5 层架构做成可扩展骨架
`define NPU_NUM_TILES        32
`define NPU_TILE_ROWS        4
`define NPU_TILE_COLS        8
`define NPU_TILE_SIZE        8
`define NPU_SUB_TILE_SIZE    4

`define NPU_DATA_WIDTH       32
`define NPU_AXI_ADDR_WIDTH   32
`define NPU_AXI_DATA_WIDTH   32
`define NPU_AXI_STRB_WIDTH    4

// Tile 内部矩阵展开宽度
`define NPU_TILE_A_BITS     (8*8*8)
`define NPU_TILE_B_BITS     (8*8*8)
`define NPU_TILE_C_BITS     (8*8*16)
`define TILE_PORT_W         (8*8)

// 工作模式编码
`define NPU_MODE_INDEP       2'b00
`define NPU_MODE_MERGE       2'b01
`define NPU_MODE_SPLIT       2'b10

// 权重加载模式编码（reg_mode[3:2]位控制）
// reg_mode[2]: 动态/静态
`define NPU_WEIGHT_DYNAMIC   1'b0    // 动态权重：每次计算重新加载
`define NPU_WEIGHT_STATIC    1'b1    // 静态权重：预加载后复用

// reg_mode[3]: 权重共享/独立
`define NPU_WEIGHT_SHARED    1'b0    // 权重共享：所有Tile使用相同B矩阵
`define NPU_WEIGHT_INDEPENDENT 1'b1  // 独立权重：每个Tile使用不同B矩阵

// 组合模式示例：
// reg_mode[3:2] = 2'b00: 动态+权重共享
// reg_mode[3:2] = 2'b01: 动态+独立权重
// reg_mode[3:2] = 2'b10: 静态+权重共享
// reg_mode[3:2] = 2'b11: 静态+独立权重

// 全局状态机编码
`define NPU_ST_IDLE          4'd0
`define NPU_ST_CFG           4'd1
`define NPU_ST_LOAD          4'd2
`define NPU_ST_RUN           4'd3
`define NPU_ST_STORE         4'd4
`define NPU_ST_DONE          4'd5
`define NPU_ST_ERROR         4'd6

`endif