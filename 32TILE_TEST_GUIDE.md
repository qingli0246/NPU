# NPU 32-Tile 全量并行计算测试指南

## 📋 测试概述

本测试套件专门用于验证 NPU 的 **32 个 Tile 完整并行计算能力**，重点测试 `cfg_tile_mask` 扩展为 32 位后的功能正确性。

### 测试目标

1. ✅ 验证 `cfg_tile_mask` 能够正确控制所有 32 个 Tile
2. ✅ 确认高位 Tile（Tile#10-31）能够被正确启用和计算
3. ✅ 验证 `calc_rd_word_count` 函数能准确统计启用的 Tile 数量
4. ✅ 检查 `pool_tile_start_mask` 与配置值完全一致
5. ✅ 测试不同 Tile 组合模式下的并行计算能力

---

## 🧪 测试场景

### Test 1: 单 Tile 启用（Tile#0）- 基准测试

**目的**: 建立基准，验证基本功能正常

**配置**:
- `reg_tile_mask = 32'h00000001` (仅 Bit0)
- 矩阵规模: M=N=K=8
- 工作模式: INDEP + 静态权重

**预期结果**: 
- ✓ NPU 正常完成计算
- ✓ 无错误标志

---

### Test 2: 多 Tile 分散启用

**目的**: 测试非连续 Tile 的启用能力

**配置**:
- `reg_tile_mask = 32'h40808081`
- 启用 Tile: #0, #5, #10, #15, #20, #25, #30 (共 7 个)
- 矩阵规模: M=N=K=8

**预期结果**:
- ✓ 7 个分散的 Tile 同时工作
- ✓ A 矩阵读取字数 = 7 × (单个 Tile 所需字数)

---

### Test 3: 全部 32 个 Tile 同时启用 ⭐

**目的**: 验证最大并行度下的系统稳定性

**配置**:
- `reg_tile_mask = 32'hFFFFFFFF` (所有位)
- 启用 Tile: #0-#31 (全部 32 个)
- 矩阵规模: M=N=K=8

**预期结果**:
- ✓ 32 个 Tile 全部启动
- ✓ A 矩阵读取字数 = 32 × (单个 Tile 所需字数)
- ✓ 计算时间合理（不应超时）

---

### Test 4: 仅高位 Tile 启用（Tile#31）⭐⭐

**目的**: **关键测试** - 验证最高位 Tile 能否被正确启用

**配置**:
- `reg_tile_mask = 32'h80000000` (仅 Bit31)
- 启用 Tile: #31 (最高位)
- 矩阵规模: M=N=K=8

**预期结果**:
- ✓ Tile#31 成功启动并计算
- ✓ **如果失败，说明 cfg_tile_mask 高位未正确传递**

**重要性**: 
- 这是验证 Bug 修复的关键测试
- 如果此测试失败，说明之前的 10 位限制问题仍然存在

---

### Test 5: 连续高位 Tile 块（Tile#16-31）

**目的**: 测试高 16 位 Tile 的批量启用

**配置**:
- `reg_tile_mask = 32'hFFFF0000` (高 16 位)
- 启用 Tile: #16-#31 (共 16 个)
- 矩阵规模: M=N=K=8

**预期结果**:
- ✓ 16 个高位 Tile 正常工作
- ✓ A 矩阵读取字数 = 16 × (单个 Tile 所需字数)

---

### Test 6: 大矩阵 32-Tile 并行计算

**目的**: 验证大规模计算下的 32-Tile 性能

**配置**:
- `reg_tile_mask = 32'hFFFFFFFF` (所有位)
- 矩阵规模: M=N=K=16 (比之前大一倍)
- 启用 Tile: #0-#31 (全部 32 个)

**预期结果**:
- ✓ 32 个 Tile 处理更大矩阵
- ✓ 计算时间在合理范围内
- ✓ 无溢出或超时错误

---

## 🔧 运行方法

### 方法 1: 使用 PowerShell 脚本（推荐）

```powershell
.\run_32tile_test.ps1
```

### 方法 2: 手动编译和运行

```powershell
# 编译
iverilog -g2012 -o tb_npu_32tile_test.exe -I rtl `
    TB/tb_npu_32tile_test.v `
    rtl/npu_top.v `
    rtl/npu_ctrl.v `
    rtl/npu_compute_pool.v `
    rtl/npu_tile.v `
    rtl/npu_dma_rd.v `
    rtl/npu_dma_wr.v `
    rtl/npu_weight_cache.v `
    rtl/npu_axi4_bridge.v

# 运行
vvp tb_npu_32tile_test.exe
```

### 方法 3: 查看波形

```powershell
# 使用 GTKWave 打开波形文件
gtkwave tb_npu_32tile_test.vcd
```

---

## 📊 关键信号监控

在波形分析时，重点关注以下信号：

### 1. 配置阶段（CFG State）

| 信号 | 位置 | 说明 |
|------|------|------|
| `u_npu_top.reg_tile_mask` | npu_top | 检查写入的完整 32 位值 |
| `u_npu_top.u_npu_ctrl.cfg_tile_mask_lo` | npu_ctrl | 应为 reg_tile_mask[4:0] |
| `u_npu_top.u_npu_ctrl.cfg_tile_mask_hi` | npu_ctrl | 应为 reg_tile_mask[9:5] |
| **⚠️ 待修复**: `u_npu_top.u_npu_ctrl.cfg_tile_mask` | npu_ctrl | 应直接接收 32 位 |

### 2. 计算阶段（RUN State）

| 信号 | 位置 | 说明 |
|------|------|------|
| `u_npu_top.u_npu_ctrl.tile_start_mask_value` | npu_ctrl | 应与 reg_tile_mask 一致 |
| `u_npu_top.pool_tile_start_mask` | npu_top | 应传递给 compute_pool |
| `u_npu_top.u_npu_ctrl.rd_word_count` | npu_ctrl | 应根据启用 Tile 数计算 |

### 3. Tile 状态

| 信号 | 位置 | 说明 |
|------|------|------|
| `u_npu_top.u_compute_pool.tile_start[i]` | compute_pool | i=0~31，检查哪些 Tile 启动 |
| `u_npu_top.u_compute_pool.tile_busy[i]` | compute_pool | 检查 Tile 是否忙碌 |
| `u_npu_top.u_compute_pool.tile_done[i]` | compute_pool | 检查 Tile 是否完成 |

---

## ✅ 验证标准

### 通过条件

所有测试必须满足：
1. ✓ `npu_done == 1` (计算完成)
2. ✓ `npu_error == 0` (无错误)
3. ✓ 未发生超时
4. ✓ 波形中 `pool_tile_start_mask` 与配置的 `reg_tile_mask` 一致

### 特别验证点（Test 4）

**Test 4 是核心验证测试**，必须确认：
- ✓ `reg_tile_mask[31]` 能够正确传递到控制器
- ✓ `tile_start_mask_value[31]` 被置为 1
- ✓ `pool_tile_start_mask[31]` 产生启动脉冲
- ✓ Tile#31 的 `tile_start` 信号被激活

---

## 🐛 常见问题排查

### 问题 1: Test 4 失败（Tile#31 未启动）

**可能原因**: `cfg_tile_mask` 仍为 10 位，高位被截断

**排查步骤**:
1. 检查 `npu_ctrl.v` 端口定义是否为 `[4:0]`
2. 检查 `npu_top.v` 实例化是否只传递了 `[9:0]`
3. 查看波形中 `cfg_tile_mask_hi` 和 `cfg_tile_mask_lo` 的值

**解决方案**: 按照之前提供的方案修改为 32 位端口

---

### 问题 2: rd_word_count 计算错误

**可能原因**: `calc_rd_word_count` 函数接收的 tile_mask 只有 10 位

**排查步骤**:
1. 在波形中观察 `rd_word_count` 的值
2. 计算预期值：`enabled_tiles × ceil(8×K×8/32)`
3. 对比实际值与预期值

**示例**:
- 启用 32 个 Tile，K=8
- 预期: `32 × ceil(8×8×8/32) = 32 × 16 = 512`
- 如果实际值为 `10 × 16 = 160`，说明只统计了 10 个 Tile

---

### 问题 3: 仿真超时

**可能原因**: 
- Tile 数量过多导致计算时间过长
- 某些 Tile 卡死未完成

**排查步骤**:
1. 增加 `wait_for_done` 的超时时间
2. 检查哪些 Tile 的 `tile_done` 信号未拉高
3. 查看 Tile 内部状态机是否卡住

---

## 📈 性能预期

| 测试场景 | Tile 数量 | 预期相对时间 |
|---------|----------|-------------|
| Test 1 (单 Tile) | 1 | 1x (基准) |
| Test 2 (7 Tile) | 7 | ~1x (并行) |
| Test 3 (32 Tile) | 32 | ~1x (并行) |
| Test 4 (单高位) | 1 | ~1x (基准) |
| Test 5 (16 Tile) | 16 | ~1x (并行) |
| Test 6 (32 Tile, 大矩阵) | 32 | ~2x (数据量大) |

**注意**: 由于 Tile 并行工作，增加 Tile 数量不应显著增加总计算时间（除非受限于 DMA 带宽）。

---

## 🔍 调试技巧

### 1. 添加调试输出

在 `npu_ctrl.v` 的 CFG 阶段添加：

```verilog
$display("[CFG] reg_tile_mask = 0x%h", reg_tile_mask);
$display("[CFG] enabled_tile_count = %d", enabled_count);
$display("[CFG] rd_word_count = %d", rd_word_count);
```

### 2. 波形筛选技巧

在 GTKWave 中：
- 搜索 "tile_mask" 快速定位相关信号
- 搜索 "tile_start" 查看所有 Tile 的启动状态
- 使用 "Data Format" → "Binary" 查看位掩码

### 3. 逐步验证策略

如果 Test 3-6 失败：
1. 先确保 Test 1 和 Test 4 通过
2. 逐步增加 Tile 数量：1 → 2 → 4 → 8 → 16 → 32
3. 每次增加后检查波形确认

---

## 📝 测试记录模板

```
测试日期: ___________
测试人员: ___________

Test 1: □ PASS  □ FAIL  备注: ________________
Test 2: □ PASS  □ FAIL  备注: ________________
Test 3: □ PASS  □ FAIL  备注: ________________
Test 4: □ PASS  □ FAIL  备注: ________________
Test 5: □ PASS  □ FAIL  备注: ________________
Test 6: □ PASS  □ FAIL  备注: ________________

关键发现:
_________________________________________________
_________________________________________________

修复建议:
_________________________________________________
_________________________________________________
```

---

## 🎯 下一步行动

根据测试结果：

### 如果所有测试通过
- ✅ `cfg_tile_mask` 32 位扩展成功
- ✅ 可以继续使用完整的 32-Tile 并行能力
- ✅ 建议添加更多边界测试（如奇数 Tile 数量）

### 如果 Test 4 失败
- ❌ 需要立即修复 `cfg_tile_mask` 位宽问题
- ❌ 参考之前提供的修改方案
- ❌ 修复后重新运行全部测试

### 如果其他测试失败
- ⚠️ 检查具体失败的 Tile 编号
- ⚠️ 分析是否为特定 Tile 的硬件问题
- ⚠️ 可能需要检查 compute_pool 的 Tile 实例化

---

## 📚 相关文档

- [NPU 项目 README](../README.md)
- [复杂测试指南](../COMPLEX_TEST_GUIDE.md)
- [测试对比分析](../TEST_COMPARISON.md)

---

**最后更新**: 2026-05-07  
**版本**: 1.0  
**作者**: NPU 开发团队
