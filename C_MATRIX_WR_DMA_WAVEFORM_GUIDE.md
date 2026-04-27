# C矩阵数据收集与写DMA握手信号波形分析指南

## 文档说明

本文档描述了NPU在STORE阶段进行C矩阵数据收集和写回时，各个关键信号的**正常行为**。你可以对照实际仿真波形，检查是否存在异常。

**重要提示**：本文档仅描述"应该看到什么"，不直接指出问题所在。请根据波形自行判断。

---

## 一、正常情况下的信号时序关系

### 1. 计算完成阶段（RUN → STORE转换）

**关键信号：**
- `pool_done`：计算池完成信号，**单周期脉冲**
- `tile_done_mask[31:0]`：各Tile完成标志，在pool_done拉高时为全1
- `ctrl_state`：控制器状态，从`NPU_ST_RUN`跳转到`NPU_ST_STORE`

**时序要求：**
```
时钟周期：  N-1     N       N+1     N+2
-------------------------------------------
pool_done:   0    → 1      → 0      → 0
tile_done:   0    → 32'hFFFFFFFF → 0 → 0
ctrl_state:  RUN  → STORE   → STORE  → STORE
wr_start:    0    → 0      → 1(脉冲)→ 0
```

---

### 2. C矩阵数据收集阶段（c_wr_phase）

**进入条件：**
- `ctrl_state == NPU_ST_STORE`
- `wr_busy == 0`（DMA空闲）

**退出条件：**
- `c_wr_cnt >= wr_word_count`（收集完所有字）

**关键信号定义：**

| 信号 | 类型 | 含义 | 正常行为 |
|------|------|------|----------|
| `c_wr_phase` | reg | 收集阶段标志 | 进入STORE时置1，收集完成后清零 |
| `c_wr_cnt` | reg [15:0] | 已收集的字数计数器 | 从0递增到wr_word_count-1 |
| `wr_data_ready` | wire | DMA就绪信号 | 由npu_dma_wr驱动，表示可以接收新数据 |
| `wr_data_ready_prev` | reg | ready上升沿检测寄存器 | 延迟一拍用于边沿检测 |
| `wr_data_valid` | wire | 数据有效信号 | 在ready上升沿且数据准备好时拉高 |
| `wr_data_out` | wire [31:0] | 输出的32bit数据 | 当前周期的C矩阵数据字 |
| `wr_data_ready_flag` | reg | 数据准备就绪标志 | 标记当前数据已准备好供DMA读取 |

---

### 3. 数据收集与DMA握手的完整流程

**INDEP模式示例（假设M=8, N=8，wr_word_count=32）：**

```
周期 T0: c_wr_phase=1, c_wr_cnt=0
         - 从Tile#0提取第0个字：wr_data_buffer[0] = tile_c_bus[0*512 + 0*32 +: 32]
         - wr_data_ready_flag = 0 (等待DMA ready)

周期 T1: wr_data_ready=1, wr_data_ready_prev=0 (上升沿检测)
         - wr_data_valid = 1 (数据有效)
         - wr_data_out = wr_data_buffer[0]
         - c_wr_cnt = 1 (递增)
         - 准备下一个字：wr_tile_idx=0, wr_word_in_tile=1

周期 T2: wr_data_ready=1 (保持), wr_data_ready_prev=1 (非上升沿)
         - wr_data_valid = 0 (不再输出，等待DMA消费)
         - c_wr_cnt = 1 (保持不变)

周期 T3: wr_data_ready=0 (DMA忙碌), wr_data_ready_prev=1
         - wr_data_valid = 0
         - c_wr_cnt = 1 (保持不变)
         
周期 T4: wr_data_ready=1, wr_data_ready_prev=0 (新的上升沿)
         - wr_data_valid = 1 (输出下一个字)
         - wr_data_out = wr_data_buffer[1]
         - c_wr_cnt = 2
         ...
         
周期 T31: c_wr_cnt=31
          - 输出最后一个字
          
周期 T32: c_wr_cnt=32 >= wr_word_count(32)
          - c_wr_phase = 0 (退出收集阶段)
          - wr_data_valid = 0
```

**关键原则：**
1. **计数器只在ready上升沿递增**：`if (wr_data_ready && !wr_data_ready_prev) c_wr_cnt++`
2. **valid信号跟随ready上升沿**：确保每次DMA准备好时才提供新数据
3. **数据提前准备**：在每个周期预先从tile_c_bus提取数据到wr_data_buffer

---

### 4. npu_dma_wr内部状态机行为

**状态流转：**
```
ST_IDLE → ST_CMD → ST_WAIT → ST_DONE
           ↑         ↓
           └─────────┘ (循环直到wr_cnt达到word_count)
```

**ST_CMD状态（等待数据）：**
- 条件：`data_in_valid == 1 && cmd_ready == 1`
- 动作：
  - 发送AXI写命令：`cmd_addr = base_addr + {wr_cnt, 2'b00}`
  - 锁存数据：`cmd_wdata = data_in`
  - 递增计数器：`wr_cnt++`
  - 跳转到ST_WAIT

**ST_WAIT状态（等待写响应）：**
- 条件：`rsp_valid == 1`
- 动作：
  - 如果`wr_cnt < word_count`：返回ST_CMD，继续等待下一个数据
  - 如果`wr_cnt == word_count`：跳转到ST_DONE

**关键信号：**
- `wr_busy`：在ST_CMD和ST_WAIT期间为1，ST_IDLE和ST_DONE期间为0
- `wr_done`：进入ST_DONE时产生单周期脉冲
- `wr_cnt`：已成功写入的字数，从0递增到word_count

---

## 二、波形检查清单

### 检查点1：STORE阶段启动
- [ ] `ctrl_state` 从RUN变为STORE
- [ ] `wr_start` 产生单周期脉冲（在wr_busy==0时）
- [ ] `wr_busy` 从0变为1（DMA开始工作）

### 检查点2：C矩阵收集阶段激活
- [ ] `c_wr_phase` 在进入STORE后变为1
- [ ] `c_wr_cnt` 初始值为0
- [ ] `wr_word_count` 值正确（如M=8,N=8时应为32）

### 检查点3：数据收集循环
- [ ] `wr_data_ready` 和 `wr_data_ready_prev` 的上升沿检测正常工作
- [ ] 每次上升沿时：
  - [ ] `wr_data_valid` 拉高1个周期
  - [ ] `wr_data_out` 输出正确的32bit数据
  - [ ] `c_wr_cnt` 递增1
- [ ] `wr_data_valid` 不在非上升沿周期拉高
- [ ] `c_wr_cnt` 不在非上升沿周期递增

### 检查点4：DMA内部计数
- [ ] `wr_cnt`（DMA内部计数器）从0开始递增
- [ ] 每次`wr_data_valid`脉冲后，`wr_cnt`递增1
- [ ] `wr_cnt` 最终达到`wr_word_count`的值

### 检查点5：完成信号
- [ ] 当`c_wr_cnt >= wr_word_count`时，`c_wr_phase`变为0
- [ ] `wr_done` 产生单周期脉冲
- [ ] `wr_busy` 从1变为0
- [ ] `ctrl_state` 从STORE变为DONE

---

## 三、常见异常现象及可能原因

### 异常1：c_wr_cnt不递增
**现象**：`c_wr_cnt` 保持为0或某个固定值  
**可能原因**：
- `wr_data_ready` 始终为0（DMA未就绪）
- 上升沿检测逻辑错误（wr_data_ready_prev未正确更新）
- 条件判断顺序错误（先检查范围再检查精确条件）

**排查方法**：
- 观察`wr_data_ready`的实际波形
- 检查`wr_data_ready_prev`是否在每个时钟周期正确更新
- 确认`if (wr_data_ready && !wr_data_ready_prev)`条件能否满足

---

### 异常2：wr_data_valid持续拉高
**现象**：`wr_data_valid` 在多个连续周期保持为1  
**可能原因**：
- 未使用上升沿检测，直接使用电平信号
- valid信号未在数据被消费后清除

**影响**：
- DMA可能在ST_CMD状态重复接收同一数据
- `wr_cnt` 可能在不该递增时递增

**排查方法**：
- 确认valid只在ready上升沿时拉高
- 验证valid在非上升沿周期是否为0

---

### 异常3：c_wr_cnt提前达到目标值
**现象**：`c_wr_cnt` 快速递增到wr_word_count，但实际只输出了少量数据  
**可能原因**：
- 计数器在每个时钟周期都递增，而非仅在握手时递增
- 缺少`wr_data_ready`的门控

**排查方法**：
- 对比`c_wr_cnt`的递增速率与`wr_data_valid`的脉冲次数
- 两者应该完全一致（每次valid脉冲对应cnt+1）

---

### 异常4：DMA卡在ST_CMD状态
**现象**：`wr_busy` 保持为1，但`wr_cnt` 停止递增  
**可能原因**：
- `wr_data_valid` 过早变为0（只有1个周期脉冲）
- DMA期望连续数据流，但上层只提供单次脉冲

**这是问题1的核心症状！**

**排查方法**：
- 统计`wr_data_valid`的总脉冲数
- 对比预期值（wr_word_count）与实际值
- 如果实际值远小于预期，说明数据流中断

---

### 异常5：tile_c_bus数据无效
**现象**：`wr_data_out` 输出全0或不定态（X/Z）  
**可能原因**：
- Tile未完成计算，tile_c_bus无有效数据
- 数据提取索引错误（wr_tile_idx或wr_word_in_tile计算错误）
- tile_c_bus位宽或偏移量配置错误

**排查方法**：
- 在RUN阶段结束时检查`tile_c_bus`的实际值
- 验证数据提取公式：`tile_c_bus[wr_tile_idx * TILE_C_BITS + wr_word_in_tile * 32 +: 32]`
- 确认TILE_C_BITS的定义是否正确（应为512）

---

## 四、调试建议

### 1. 添加关键信号打印

在`npu_top.v`中添加以下调试输出：

```verilog
// 在C矩阵收集阶段的always块中
if (c_wr_phase && $time > 1000) begin  // 避免初期噪声
    if (wr_data_ready && !wr_data_ready_prev) begin
        $display("[%0t] [C_WR] cnt=%d, tile=%d, word=%d, data=%h", 
                 $time, c_wr_cnt, wr_tile_idx, wr_word_in_tile, wr_data_out);
    end
end

// 在退出收集阶段时
if (c_wr_phase && c_wr_cnt >= wr_word_count) begin
    $display("[%0t] [C_WR] Collection complete! Total words: %d", 
             $time, c_wr_cnt);
end
```

### 2. 波形查看重点

在GTKWave或ModelSim中重点关注：
- **时间窗口**：STORE阶段开始后的前100个周期
- **信号分组**：
  - 控制组：ctrl_state, c_wr_phase, wr_busy, wr_done
  - 计数组：c_wr_cnt, wr_cnt (DMA内部)
  - 握手组：wr_data_ready, wr_data_ready_prev, wr_data_valid
  - 数据组：wr_data_out, tile_c_bus (采样关键片段)

### 3. 分步验证策略

1. **第一步**：确认c_wr_phase能正确进入和退出
2. **第二步**：确认wr_data_ready有正常的上升沿
3. **第三步**：确认每次上升沿时wr_data_valid正确拉高
4. **第四步**：确认c_wr_cnt按预期递增
5. **第五步**：确认wr_data_out的数据内容正确
6. **第六步**：确认DMA内部wr_cnt同步递增

---

## 五、参考时序图

### 理想情况下的完整时序（简化版，仅显示关键信号）

```
clk:        ____    ____    ____    ____    ____    ____
            
c_wr_phase: _______██████████████████████████___________
            
wr_data_rdy:______↑_____↑_____↑_____↑_____↑_____________
              (T1)  (T4)  (T7)  (T10) (T13)
              
wr_data_val:______█_____█_____█_____█_____█_____________
              (T1)  (T4)  (T7)  (T10) (T13)
              
c_wr_cnt:   ___0_____1_____2_____3_____4_____5__________
            
wr_data_out:______D0____D1____D2____D3____D4____________
            
wr_busy:    _______████████████████████████████_________
            
wr_cnt:     ___0_____1_____2_____3_____4_____5__________
            
wr_done:    __________________________________█_________
                                            (T32)
```

**说明**：
- `wr_data_rdy` 的上升沿间隔不固定（取决于DMA内部处理速度）
- `wr_data_val` 严格跟随`wr_data_rdy`的上升沿
- `c_wr_cnt` 和 `wr_cnt` 应该完全同步
- 当`c_wr_cnt`达到目标值时，`c_wr_phase`退出，`wr_done`脉冲产生

---

## 六、总结

### 正常情况下应观察到：

1. ✅ `c_wr_phase` 在STORE阶段保持为1，直到收集完成
2. ✅ `wr_data_valid` 的脉冲总数 = `wr_word_count`
3. ✅ `c_wr_cnt` 从0递增到`wr_word_count`，每次递增对应一次valid脉冲
4. ✅ `wr_cnt`（DMA内部）与`c_wr_cnt` 同步递增
5. ✅ `wr_done` 在最后一个数据写入后产生脉冲
6. ✅ 整个过程中`wr_data_out` 输出有效的C矩阵数据（非0/X/Z）

**如果观察到异常，请对照"常见异常现象"章节进行排查。**

---

## 附录：相关代码位置参考

| 模块 | 文件 | 关键行号 | 功能 |
|------|------|---------|------|
| C矩阵收集逻辑 | `rtl/npu_top.v` | L720-L830 | 根据模式提取tile_c_bus数据 |
| 握手信号生成 | `rtl/npu_top.v` | L840-L845 | wr_data_valid和wr_data_out赋值 |
| DMA写状态机 | `rtl/npu_dma_wr.v` | L80-L180 | ST_CMD/ST_WAIT状态处理 |
| 控制器STORE阶段 | `rtl/npu_ctrl.v` | L325-L340 | STORE状态流转逻辑 |

**建议的波形观察顺序**：
1. 先看`ctrl_state`确认进入STORE
2. 再看`c_wr_phase`确认收集阶段激活
3. 然后观察`wr_data_ready`的上升沿模式
4. 接着验证`wr_data_valid`是否跟随上升沿
5. 最后对比`c_wr_cnt`和`wr_cnt`的同步性
