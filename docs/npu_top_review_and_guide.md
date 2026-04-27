# npu_top 程序检查与说明

本文针对当前版本 [rtl/npu_top.v](rtl/npu_top.v) 做两件事：
- 结构与接口说明（便于继续开发）
- 风险点检查（便于快速修正）

## 1. 顶层功能概览

当前 [rtl/npu_top.v](rtl/npu_top.v) 已具备以下主链路：
- AXI-Lite 控制寄存器读写（CPU 配置入口）
- 全局控制器 `npu_ctrl` 驱动启动流程
- 计算池 `npu_compute_pool` 接入重构配置（mode/master/h/v link）
- 读 DMA + AXI4 bridge（从外部存储读取）
- 写 DMA + AXI4 bridge（向外部存储写回）
- 权重缓存 `npu_weight_cache`（B 矩阵缓存入口）

## 2. AXI-Lite 寄存器映射（当前实现）

地址按 `s_axi_*addr[7:2]` 解码：
- 0x00: `reg_ctrl`（bit0 触发 start）
- 0x01: `reg_mode`
- 0x02: `reg_a_base`
- 0x03: `reg_b_base`
- 0x04: `reg_c_base`
- 0x05: `reg_m`
- 0x06: `reg_n`
- 0x07: `reg_k`
- 0x08: `reg_tile_mask`
- 0x09: `reg_h_link_en`
- 0x0A: `reg_v_link_en`
- 0x0B: `reg_group_master`
- 0x10: status（busy/done/error）

## 3. 配置到计算池的映射

当前在 [rtl/npu_top.v](rtl/npu_top.v) 中，配置映射如下：
- `pool_cfg_group_master = reg_group_master[31:0]`
- `pool_cfg_h_link_en = reg_h_link_en[31:0]`
- `pool_cfg_v_link_en = reg_v_link_en[31:0]`
- `cfg_top_mode` 由 `npu_ctrl.pool_mode` 输出到计算池

即：软件写入 0x09/0x0A/0x0B 后，直接决定第二层互联拓扑。

## 4. 当前数据路径说明

### 4.1 A 数据
- 读 DMA 返回 `rd_data_word`
- 写入 `tile_a_bus_reg`
- `tile_a_bus = tile_a_bus_reg`

当前写入策略：
- INDEP：`tile_a_bus_reg[rd_data_index*32 +: 32] <= rd_data_word`
- 非 INDEP（MERGE/SPLIT）：写到第 0 号 Tile 的 A 区段

### 4.2 B 数据
- 当前直接将 `cache_rdata` 广播到所有 Tile：
  - `tile_b_bus_reg <= {NPU_NUM_TILES{cache_rdata}}`

### 4.3 C 数据
- 写 DMA 当前仅取 `tile_c_bus[31:0]` 作为写回输入

## 5. 检查发现的关键风险

### 已修复项 1：`pool_done/pool_busy` 已连接

当前源码已经把 `npu_compute_pool` 的 `pool_busy/pool_done` 接回顶层，并连到 `npu_ctrl`。
这意味着控制器现在可以根据计算池状态从 RUN 正常切到 STORE。

### 风险 2（高）：写 DMA 数据有效脉冲可能不足以支撑多字写回

位置：
- [rtl/npu_top.v](rtl/npu_top.v#L289)

现象：
- `data_in_valid` 使用 `|tile_done_mask`，通常是短脉冲。
- 但 `npu_ctrl` 配置 `wr_word_count=32`，写 DMA 需要连续多次 `data_in_valid` 才能完成。
- 可能在第一个字后停在等待数据状态，导致 STORE 卡住。

建议：
- 引入写回 FIFO 或写回计数器，确保 `data_in_valid` 在完整 `wr_word_count` 周期内按需提供。

### 风险 3（中）：MERGE 路径下 A 数据写入位宽不匹配语义

位置：
- [rtl/npu_top.v](rtl/npu_top.v#L391)

现象：
- 将 32 位 `rd_data_word` 写入 `NPU_TILE_A_BITS`（512 位）切片。
- 语法可通过，但只会有效更新低位，无法形成完整 Tile A 矩阵加载。

建议：
- 改为按 32 位分片写入（增加 Tile 内偏移地址计数），或定义明确 pack/unpack 格式。

### 风险 4（中）：INDEP 注释与实际行为不一致

位置：
- [rtl/npu_top.v](rtl/npu_top.v#L388)

现象：
- 注释写“分发到所有 tile”，但当前是按全局线性偏移写入单一大总线。
- 未体现按 Tile 独立装载的调度策略。

建议：
- 引入 `tile_id + tile_word_offset` 两级地址，明确数据分发到哪个 Tile。

## 6. 建议的最小修复优先级

1. 先修 `pool_done/pool_busy` 连接，避免状态机卡死。  
2. 再修写 DMA 连续数据供给，避免 STORE 卡死。  
3. 最后完善 A/B/C 数据 pack/unpack，提升功能完整性。

## 7. 当前可用结论

- 架构连线已基本成型，配置面可通过 AXI-Lite 下发。
- 互联配置寄存器已接入计算池。
- 仍属于“可综合骨架 + 部分数据路径占位”，用于联调框架是可行的；用于完整矩阵任务还需补上第 5 节风险修复。
