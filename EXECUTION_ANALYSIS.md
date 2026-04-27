# NPU 执行一次有效计算的完整流程分析

## 概览：控制状态机与数据流的交互

一次完整的矩阵计算执行流程如下：
```
CPU → AXI-Lite 寄存器 → npu_ctrl 状态机 → {计算池，DMA读，DMA写} → 外部存储
```

---

## 第 1 阶段：IDLE → CFG（初始化）

### 控制信号
| 信号 | 来源 | 含义 |
|------|------|------|
| `cfg_start_pulse` | AXI-Lite (写reg_ctrl[0]) | CPU启动信号 |
| `pool_tile_start_mask` | npu_ctrl | 拉高所有32个Tile的启动 |
| `pool_tile_clk_en_mask` | npu_ctrl | 使能所有Tile的时钟 |

### 数据变化
```
npu_ctrl 锁存以下配置参数：
  - cfg_mode (INDEP/MERGE/SPLIT)
  - cfg_a_base, cfg_c_base  (DMA基地址)
  - cfg_matrix_m, n, k      (矩阵尺寸)
  
计算得出：
  - rd_word_count = 16'd16            (硬编码！问题6)
  - wr_word_count = calc_wr_word_count(m,n,k)
```

### 问题点
- ❌ **问题 6**：`rd_word_count` 硬编码为16，未根据实际矩阵大小计算
  - 假设所有Tile的A矩阵都是8x8x8bit = 512bit
  - 512bit ÷ 32bit = 16个字，这个假设在所有模式下都成立吗？

---

## 第 2 阶段：CFG（权重配置）- 只有1个周期

### 权重缓存写入（当前实现）
```verilog
if (cfg_tile_mask_lo != 5'd0 || cfg_tile_mask_hi != 5'd0) begin
    cache_we    <= 1'b1;
    cache_waddr <= cfg_tile_mask_lo;
    cache_wdata <= {`NPU_TILE_B_BITS{1'b0}};  // 全零！
end
```

### 关键问题
- ❌ **问题 4**：B矩阵始终写全零
  - 权重缓存应该包含B矩阵数据（8x8x8bit = 512bit）
  - 当前代码 `cache_wdata` 是全零，没有真实数据来源
  
- ❌ **时序问题**：CFG状态只有1个周期
  - 即使有B矩阵数据，也只能写入一个Tile（512bit）
  - 其他31个Tile的权重缓存无法写入
  
- 建议方案：从DMA在LOAD阶段读取B矩阵，或CPU通过AXI-Lite提前配置

---

## 第 3 阶段：LOAD（读矩阵A）

### 读 DMA 的执行流程

```
npu_ctrl.rd_start = 1'b1  （1个周期脉冲）
            ↓
npu_dma_rd 从 ST_IDLE → ST_CMD
            ↓
ST_CMD: 发出读命令到AXI桥
        cmd_addr = rd_base_addr + {rd_cnt, 2'b00}
        每个周期递增rd_cnt (0→1→2→...→word_count-1)
            ↓
ST_WAIT: 等待AXI桥返回数据
        当 rsp_valid=1 时，输出 data_valid=1, data_word, data_index
            ↓
完读所有16个字 → ST_DONE → rd_done=1'b1（1周期脉冲）
            ↓
npu_ctrl 看到 !rd_busy，跳转到RUN状态
```

### 数据流向

读 DMA 返回的 `rd_data_word (32bit)` 会根据当前工作模式被分发到不同的 Tile：
```
INDEP 模式：
  Tile#0 receive: word#0, word#32, word#64, ...
  Tile#1 receive: word#1, word#33, word#65, ...
  Tile#2 receive: word#2, word#34, word#66, ...
  ...
  Tile#31 receive: word#31, word#63, word#95, ...
  （轮转分配，每个 Tile 接收均匀分布的片段）

MERGE 模式：
  优先分发到 cfg_group_master 标记的主 Tile
  其他数据通过级联网络传播

SPLIT 模式：
  与 INDEP 类似的轮转分配
  Tile 内部进行 4x4 子阵列拆分处理
```

### A 矩阵输入字数的计算

新增了 `calc_rd_word_count()` 函数，根据：
- 工作模式 (cfg_mode)：INDEP / MERGE / SPLIT
- 矩阵维度 (M, N, K)

动态计算需要读取的 A 矩阵字数：
```
A 矩阵大小：M × K × 8bit 元素
转换为 32bit 字：ceil((M*K*8) / 32) = ceil(M*K/4)

示例：
  M=8, N=8, K=8 → rd_word_count = ceil(64*8/32) = 16
  M=16, N=16, K=16 → rd_word_count = ceil(256*8/32) = 64
  M=32, N=32, K=32 → rd_word_count = ceil(1024*8/32) = 256
```

所有工作模式在当前实现中都需要完整的 M×K 矩阵，但分发策略不同。

### 关键问题修复状态

- ✅ **问题 6 已修复**：rd_word_count 不再硬编码，而是根据 M*K 动态计算
- ✅ **问题 2a 已部分修复**：INDEP 模式现在使用轮转分配，映射清晰化
- ⚠️ **问题 2b 仍需验证**：MERGE/SPLIT 模式的数据分发逻辑已改进，但需要仿真验证

---

## 第 4 阶段：RUN（计算）

### 计算池启动流程

```
npu_ctrl LOAD→RUN 转移时，继续保持：
  - pool_tile_start_mask = 32'hFFFFFFFF
  - pool_tile_clk_en_mask = 32'hFFFFFFFF

npu_compute_pool 接收：
  - tile_a_bus (512*32 = 16384 bits)
  - tile_b_bus (512*32 = 16384 bits)
  
每个Tile在 start=1, clk_en=1 时：
  Tile#i 状态机：ST_IDLE → ST_RUN → ST_DONE → ST_IDLE
                   ↓           ↓           ↓
             锁存输入    计算8x8乘法   输出done=1(1周期)
```

### Tile内部计算的时序

```
时钟周期：  N      N+1     N+2
-----------------------------------------
start:    1      0       0
state:    IDLE → RUN   → DONE → IDLE
busy:     0    → 1     → 0
done:     0      0     → 1    → 0
c_flat:   X      计算中   结果  结果
```

**关键：Tile的done信号只持续1个周期！**

### 计算池完成信号
```
pool_done = &tile_done_mask  (所有32个Tile的done都拉高)
```

如果某个Tile的数据为0（比如MERGE/SPLIT模式下数据未正确加载），
该Tile仍然会计算（结果为0），done照样拉高。

---

## 第 5 阶段：STORE（写回结果）- 🔴 这里出现死锁 🔴

### 写 DMA 的执行流程

```
npu_ctrl.wr_start = 1'b1  （1个周期脉冲）
            ↓
npu_dma_wr 从 ST_IDLE → ST_CMD
            ↓
ST_CMD: 等待 data_in_valid=1
        当收到 data_in_valid=1 AND cmd_ready=1 时：
        - cmd_addr = wr_base_addr + {wr_cnt, 2'b00}
        - cmd_wdata = data_in
        - wr_cnt += 1
        - 跳转到 ST_WAIT
        
        如果 data_in_valid=0，卡在ST_CMD，等待数据
            ↓
ST_WAIT: 等待 rsp_valid=1 (AXI写响应)
        当收到 rsp_valid=1 时：
        - 如果 wr_cnt < word_count，返回ST_CMD，继续等待下一个数据
        - 如果 wr_cnt == word_count，跳转到ST_DONE
            ↓
完成 word_count 次写入 → ST_DONE
```

### 数据来源与有效信号

```verilog
// 在 npu_top.v 中
.data_in       (tile_c_bus[31:0]),
.data_in_valid (|tile_done_mask),
```

**时序问题：**
```
时钟周期：  N       N+1     N+2     N+3     ...
-------------------------------------------------
pool_done: 0    → 1      → 0       → 0
done_mask: 0    → 32'hFFFFFFFF
                        → 0
data_in_valid: 0 → 1    → 0       → 0    (只有1个周期!)

npu_dma_wr:
  当 data_in_valid=1 时，wr_dma 在 ST_CMD 接收一个word
  当 data_in_valid=0 时，wr_dma 卡在 ST_CMD 等待
  
期望的 wr_word_count = 32（或其他值）
实际收到的有效脉冲 = 只有1个周期
```

### 💀 死锁原因分析

```
假设 M=8, N=8, K=8
wr_word_count = calc_wr_word_count(mode, 8, 8, 8)
              = (8*8 + 1) >> 1       (C矩阵: 8x8x16bit, 每32bit装2个元素)
              = (64 + 1) >> 1
              = 32

但 data_in_valid 只有1个周期的脉冲！

时序过程：
  周期 N+1：data_in_valid=1, wr_dma 接收第1个word (wr_cnt=1)
  周期 N+2：data_in_valid=0, wr_dma 在ST_WAIT等待rsp_valid
           (假设rsp在N+3返回) wr_cnt=1, 需要继续到32
  周期 N+3：wr_dma 看到 rsp_valid，回到ST_CMD
           但 data_in_valid=0 (已经结束了！)
           wr_dma 卡在 ST_CMD，永远等不到 data_in_valid
           
结果：npu_ctrl 在STORE状态卡死！
```

### ⚠️ 解决方案

有两个方向：

**方案A：改造npu_top的数据提供**
- 在计算池完成时，建立一个数据缓冲（FIFO或寄存器堆）
- 从tile_c_bus中逐字（32bit）提取数据，产生32个周期的data_in_valid脉冲

**方案B：改造计算池的输出接口**
- 计算池完成后，自动逐周期输出C矩阵的各个字
- 持续产生data_in_valid直到所有数据都被写回DMA

**方案C：改造写DMA的数据接收逻辑**
- 允许写DMA在pool_done后，自动从tile_c_bus中逐字提取数据
- 不依赖外部的data_in_valid脉冲

---

## 第 6 阶段：DONE

```
npu_ctrl.wr_start = 1'b0
            ↓
npu_ctrl 看到 !wr_busy，跳转到DONE状态
            ↓
npu_ctrl.global_done = 1'b1（1个周期脉冲）
            ↓
CPU读取状态寄存器 (0x10)，看到 npu_done=1，得知计算完成
            ↓
返回IDLE状态，可以进行下一次计算
```

---

## 完整的时序问题列表

| 优先级 | 问题 | 阶段 | 影响 | 修复复杂度 |
|-------|------|------|------|-----------|
| 🔴 高 | 问题1：写DMA数据脉冲不足 | STORE | 死锁 | 中 |
| 🔴 高 | 问题2a：A数据INDEP映射不清 | LOAD | 错误 | 中 |
| 🔴 高 | 问题2b：A数据MERGE/SPLIT写错 | LOAD | 错误 | 中 |
| 🔴 高 | 问题4：权重缓存全零 | CFG | 错误 | 高 |
| 🟠 中 | 问题3：C数据只写32bit | STORE | 错误 | 中 |
| 🟠 中 | 问题6：rd_word_count硬编码 | IDLE→CFG | 错误 | 低 |

---

## 最小执行方案（能否跑通单个8x8矩阵）

假设简化场景：
- MatrixSize: 8×8  (M=8, N=8, K=8)
- Mode: INDEP（所有Tile独立计算）
- 目标：验证一个Tile能否完成矩阵乘法并写回

### 执行检查清单

- [ ] 问题1修复：写回FIFO或计数器产生32周期的data_in_valid
- [ ] 问题2a修复（对INDEP）：明确A数据如何分配到各Tile
- [ ] 问题4修复：权重缓存能否提前由CPU写入（或DMA读取）
- [ ] 问题6修复（可选）：对于8x8固定大小，rd_word_count=16在INDEP下成立
- [ ] 测试：用仿真验证A/B数据能否正确加载到Tile
- [ ] 测试：Tile计算输出c_flat的数据是否正确
- [ ] 测试：C数据能否通过FIFO完整写回到存储器

如果以上条件都满足，**单个8x8矩阵的一次计算**可以成功执行。

---

## 进阶问题（不影响单个计算的成功，但影响功能完整性）

- 多Tile并行计算的负载均衡
- MERGE/SPLIT模式下的级联数据流
- 不同矩阵规模(M/N/K变化)的自适应
- AXI4桥的Burst支持和性能优化
