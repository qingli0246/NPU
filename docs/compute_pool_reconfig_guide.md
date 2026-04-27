# npu_compute_pool 重构配置说明

本文说明 [rtl/npu_compute_pool.v](rtl/npu_compute_pool.v) 中各配置输入在不同取值下会形成什么排列。

## 1. Tile 编号与网格

- 计算池为 4 行 x 8 列，共 32 个 Tile
- 编号规则为行优先：
  - idx = row * 8 + col
  - row 取值 0..3，col 取值 0..7

例如：
- row=0,col=0 -> idx=0
- row=1,col=2 -> idx=10
- row=3,col=7 -> idx=31

## 2. 配置输入含义

- cfg_top_mode[1:0]
  - NPU_MODE_INDEP：独立模式
  - NPU_MODE_MERGE：合并模式（启用可配置级联）
  - NPU_MODE_SPLIT：拆分模式（每个 Tile 内部拆为 4 个 4x4）

- cfg_group_master[31:0]
  - 标记每个 Tile 是否为分组主 Tile
  - 在 MERGE 下，主 Tile 通常作为本地数据注入起点

- cfg_h_link_en[31:0]
  - 控制横向链路（左 -> 右）是否导通
  - 对 idx=i 的 Tile，若 i 不是行首列，且 cfg_h_link_en[i]=1，则
    - a_left[i] <- a_right[i-1]

- cfg_v_link_en[31:0]
  - 控制纵向链路（上 -> 下）是否导通
  - 对 idx=i 的 Tile，若 i>=8 且 cfg_v_link_en[i]=1，则
    - b_top[i] <- b_down[i-8]

## 3. 不同输入下的排列结果

### 3.1 INDEP（独立并行）

输入条件：
- cfg_top_mode = NPU_MODE_INDEP

结果：
- 所有级联链路被模式门控关闭
- 32 个 Tile 互不影响，分别计算各自 8x8 任务
- 性能侧重吞吐并行

### 3.2 MERGE（可重构合并）

输入条件：
- cfg_top_mode = NPU_MODE_MERGE
- cfg_h_link_en / cfg_v_link_en 按目标拓扑置位

结果：
- 由软件定义的链路导通后，Tile 形成更大脉动阵列
- 可实现行向拼接、列向拼接、2x2/2xN/NxM 分组拼接

示例 A：单行 1x4 合并（idx 0,1,2,3）
- cfg_h_link_en[1]=1, [2]=1, [3]=1
- cfg_v_link_en 全 0
- cfg_group_master[0]=1，其他可置 0

示例 B：2x2 合并（左上角 idx=t）
- 四个 Tile：t, t+1, t+8, t+9
- 横向：cfg_h_link_en[t+1]=1, cfg_h_link_en[t+9]=1
- 纵向：cfg_v_link_en[t+8]=1, cfg_v_link_en[t+9]=1
- 主 Tile：cfg_group_master[t]=1

### 3.3 SPLIT（Tile 内拆分）

输入条件：
- cfg_top_mode = NPU_MODE_SPLIT

结果：
- 跨 Tile 级联关闭
- 每个 Tile 内部拆为 4 个 4x4 子阵列
- 全池最大并行为 32 x 4 = 128 个 4x4 任务

## 4. 边界约束

- 每行首列 Tile 没有左邻居，a_left 固定为 0
- 第一行 Tile 没有上邻居，b_top 固定为 0
- 因此：
  - cfg_h_link_en 在行首列位上置 1 不会产生有效输入
  - cfg_v_link_en 在第一行位上置 1 不会产生有效输入

## 5. 软件侧配置建议

- 每次启动前先清零 cfg_h_link_en/cfg_v_link_en，再按目标拓扑逐位开启
- 每个合并组至少指定一个主 Tile（cfg_group_master=1）
- 对多组并行任务，建议按“组内连续编号、组间断开链路”方式配置，便于调试和定位
