# 快速检查清单：执行有效计算需要的修复

## 问题优先级与执行流程的对应关系

```
████████████████████════════════════════════
执行流程：CFG → LOAD → RUN → STORE → DONE
问题分布：       ✅2a   ✓   ❌1    
          ❌4    ✓    ✓   ❌3
              ✅6(动态)
```

---

## 🔴 关键阻塞（必须修复才能跑通）

### 问题 1：STORE 阶段写DMA卡死
- **现象**：`data_in_valid = |tile_done_mask`（1周期脉冲），但DMA需要32次脉冲
- **后果**：STORE卡死，计算永不完成
- **修复方案**：
  - [ ] 方案A：在npu_top中增加写回FIFO（推荐简单方案）
  - [ ] 方案B：改造计算池输出接口，自动分周期输出C数据
  - [ ] 方案C：改造写DMA，自动从pool_done后逐字提取数据
- **估计工作量**：2-4小时（含仿真验证）

### 问题 4：权重缓存无有效数据（CFG阶段）
- **现象**：`cache_wdata = {512{1'b0}}`，B矩阵全为0
- **后果**：所有计算结果都是0（B矩阵为0的矩阵乘法）
- **修复方案**：
  - [ ] 方案①：CPU通过AXI-Lite分多次写入B矩阵到权重缓存
  - [ ] 方案②：DMA在LOAD阶段读B矩阵，写入权重缓存，再读A矩阵
  - [ ] 方案③：简化方案 - 直接从tile_b_bus提供数据（跳过缓存）
- **估计工作量**：3-6小时（涉及控制流修改）

---

## 🟠 高风险问题（影响数据正确性）

### ✅ 问题 2a：A矩阵INDEP模式映射不清（已修复）
- **原因**：32bit数据写入512bit总线，映射关系模糊
- **修复方案**：✅ 已实现轮转分配：Tile#i 接收 word#i, word#(i+32), word#(i+64), ...
- **验证方法**：仿真观察 tile_a_bus_reg 的内容分配是否正确

### ✅ 问题 6：A矩阵读取字数硬编码（已修复）
- **原因**：`rd_word_count = 16'd16`，不根据M/N/K计算
- **修复方案**：✅ 新增 calc_rd_word_count() 函数
  ```verilog
  rd_word_count = calc_rd_word_count(cfg_mode, cfg_matrix_m, cfg_matrix_n, cfg_matrix_k)
  ```
  计算：ceil((M*K*8) / 32) = ceil(M*K/4)
- **验证方法**：对比不同M/N/K的rd_word_count值是否随矩阵大小变化

### ⚠️ 问题 2b：A矩阵MERGE/SPLIT模式分发（需验证）
- **现象**：已改进分发逻辑，但需要验证
- **修复方案**：
  - [ ] MERGE模式：优先分发给cfg_group_master标记的作为主Tile
  - [ ] SPLIT模式：轮转分配，与INDEP相同
- **验证方法**：仿真观察MERGE/SPLIT模式下的数据分发

---

## 执行顺序建议

### ✅ 第 0 步：修复 A 矩阵数据输入（已完成）
- ✅ 实现 `calc_rd_word_count()` 函数
  - 根据工作模式和矩阵维度动态计算 `rd_word_count`
  - 替代硬编码的 `16'd16`
  
- ✅ 改进 npu_top 中的 A 数据分发逻辑
  - **INDEP 模式**：轮转分配，Tile#i 接收 word#i, #(i+32), #(i+64), ...
  - **MERGE 模式**：优先分发到 cfg_group_master 标记的主 Tile
  - **SPLIT 模式**：轮转分配（与 INDEP 相同），Tile 内部拆分处理
  
- 说明：这解决了原来的 **问题 2a 和问题 6**

### 第 1 步：快速验证测试（1小时）
- 写个简单testbench，验证当前代码的问题1、2、4确实存在
- 确认理解无误

### 第 2 步：修复问题4（权重缓存）
- 选择方案③（最简单）：绕过缓存，从tile_b_bus直接提供
- 或选择方案①（可扩展）：CPU写入固定的B矩阵

### 第 3 步：修复问题2（A数据映射）
- 先在INDEP模式下明确映射规则
- 再推广到MERGE/SPLIT模式

### 第 4 步：修复问题1（写DMA卡死）
- **关键修复**，必须在第3步之后
- 选择方案A（FIFO）并仿真验证

### 第 5 步：修复问题3和6
- 问题6简单，先做
- 问题3依赖问题1，可在之后完善

---

## 最快路径（验证单个8×8矩阵计算）

如果只想快速验证一个8×8矩阵的端到端计算，最少修复：

| 修复 | 优先级 | 说明 | 状态 |
|------|-------|------|------|
| 问题4 | 必须 | 否则计算全0 | ❌ 未修复 |
| 问题2a/6 | 必须 | INDEP模式数据正确加载 | ✅ 已修复 |
| 问题1 | 必须 | STORE不卡死 | ❌ 未修复 |
| 问题3 | 可选 | 仅验证低32bit结果（临时方案） | ⚠️ 需改进 |

**最少工作量**：从6-10小时降低到 **4-8小时**（问题2a/6已修复，只需修复问题1和4）

---

## 修复检验标准

| 问题 | 检验方法 | 成功标志 |
|------|--------|---------|
| 1 | testbench观察写DMA状态 | wr_cnt从0计数到32 |
| 2a | 观察tile_a_bus内容 | 各Tile收到正确的A数据片段 |
| 4 | 观察tile_b_bus或cache内容 | B矩阵数据非零 |
| 3 | 观察写AXI总线 | 完整32个32bit字数据 |
| 6 | 对比不同M/N的rd_word_count | 值随矩阵大小变化 |

---

## 参考资源

- 完整分析：[EXECUTION_ANALYSIS.md](EXECUTION_ANALYSIS.md)
- 现有文档：
  - [docs/npu_top_review_and_guide.md](docs/npu_top_review_and_guide.md) - 顶层检查
  - [docs/npu_axi4_bridge_guide.md](docs/npu_axi4_bridge_guide.md) - AXI桥说明
  - [docs/compute_pool_reconfig_guide.md](docs/compute_pool_reconfig_guide.md) - 计算池配置
