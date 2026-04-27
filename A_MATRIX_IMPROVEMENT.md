# A 矩阵数据输入改进 - 修改总结

## 修改概览

已完成 **A 矩阵数据输入字数根据工作模式自适应** 的改进工作。

**改进前**：
```verilog
rd_word_count <= 16'd16;  // 硬编码，不适应不同矩阵规模和工作模式
```

**改进后**：
```verilog
// 根据工作模式、矩阵维度动态计算
rd_word_count <= calc_rd_word_count(cfg_mode, cfg_matrix_m, cfg_matrix_n, cfg_matrix_k);
```

---

## 详细改动清单

### 文件 1：`rtl/npu_ctrl.v`

#### 修改 1a：新增 `calc_rd_word_count()` 函数（第 47-87 行）
```verilog
function [15:0] calc_rd_word_count;
    input [1:0]  mode;
    input [31:0] m;
    input [31:0] n;
    input [31:0] k;
    
    // A 矩阵大小：M×K（8bit 元素）
    // 计算方式：ceil((M*K*8) / 32)
    // 不同工作模式下都需要完整的 M×K 矩阵数据
endfunction
```

**功能**：
- 计算 A 矩阵的 32bit 字数
- 支持 INDEP/MERGE/SPLIT 三种工作模式
- 公式：`words = (a_elems * 8 + 31) >> 5`（向上取整）
- 防护：返回值范围 [1, 65535]

#### 修改 1b：更新 IDLE→CFG 状态转移（第 139-140 行）
```verilog
// 修改前：
rd_word_count <= 16'd16;

// 修改后：
rd_word_count <= calc_rd_word_count(cfg_mode, cfg_matrix_m, cfg_matrix_n, cfg_matrix_k);
```

**影响**：A 矩阵读取字数现在会根据实际矩阵规模计算

---

### 文件 2：`rtl/npu_top.v`

#### 修改 2a：改进 A 数据分发逻辑（第 375-470 行）

**原实现问题**：
```verilog
// INDEP 模式映射不清
tile_a_bus_reg[rd_data_index * 32 +: 32] <= rd_data_word;

// MERGE/SPLIT 模式数据写错（32bit 写 512bit）
tile_a_bus_reg[0 * NPU_TILE_A_BITS +: NPU_TILE_A_BITS] <= rd_data_word;
```

**新实现**：四层 case 语句，根据模式进行差异化处理

##### INDEP 模式：轮转分配
```verilog
case (`NPU_MODE_INDEP)
    tile_id = rd_data_index % `NPU_NUM_TILES;
    word_offset = (rd_data_index / `NPU_NUM_TILES);
    tile_a_bus_reg[tile_id * `NPU_TILE_A_BITS + word_offset * 32 +: 32] <= rd_data_word;
end
```
- **分配策略**：
  - Tile#0 ← word#0, word#32, word#64, ...
  - Tile#1 ← word#1, word#33, word#65, ...
  - Tile#31 ← word#31, word#63, word#95, ...
- **优势**：负载均衡，每个 Tile 获得均匀的数据片段

##### MERGE 模式：主 Tile 优先
```verilog
case (`NPU_MODE_MERGE)
    for (i = 0; i < `NPU_NUM_TILES; i = i + 1)
        if (pool_cfg_group_master[i])
            tile_a_bus_reg[i * `NPU_TILE_A_BITS + ...] <= rd_data_word;
    end
end
```
- **分配策略**：数据送到 `cfg_group_master` 标记的主 Tile
- **传播**：从属 Tile 通过脉动级联网络接收数据

##### SPLIT 模式：轮转分配（同 INDEP）
```verilog
case (`NPU_MODE_SPLIT)
    // 与 INDEP 相同的轮转分配
    // Tile 内部集成拆分逻辑处理 4×4 子阵列
end
```

#### 修改 2b：缓存工作模式和矩阵参数
```verilog
reg [1:0] mode_cache;
reg [31:0] m_cache, n_cache, k_cache;

// 在 CFG/LOAD 阶段缓存配置参数供分发逻辑使用
```

---

## 关键改进点

### ✅ 问题 6：A 矩阵读取字数硬编码 → **已解决**
| 矩阵规模 | 原实现 | 新实现 | 计算式 |
|---------|-------|-------|--------|
| 8×8    | 16 | 16 | (8*8)/4 |
| 16×16  | 16 | 64 | (16*16)/4 |
| 32×32  | 16 | 256 | (32*32)/4 |

### ✅ 问题 2a：INDEP 模式数据映射不清 → **已解决**
- 原因：`rd_data_index * 32` 的寻址意义不明确
- 现在：明确的两级寻址 `tile_id = idx % 32, word_offset = idx / 32`
- 验证方法：仿真观察 tile_a_bus_reg 内容

### ⚠️ 问题 2b：MERGE/SPLIT 模式数据分配 → **已改进**
- 改进点：从"一味写 32bit 到 512bit 位置"→ 明确的模式感知分配策略
- 需要：仿真验证 MERGE/SPLIT 模式下数据是否正确分发

---

## 仿真验证建议

### 1️⃣ 验证 rd_word_count 动态计算
```
testbench:
  设置 cfg_matrix_m, cfg_matrix_n, cfg_matrix_k
  触发 cfg_start_pulse
  观察 npu_ctrl.rd_word_count 输出
  
预期：
  M=8, K=8   → rd_word_count = 16
  M=16, K=16 → rd_word_count = 64
  M=32, K=32 → rd_word_count = 256
```

### 2️⃣ 验证 INDEP 模式 A 数据分发
```
testbench:
  设置 pool_mode = INDEP
  逐周期注入 rd_data 和 rd_data_valid
  观察 tile_a_bus_reg 内容
  
预期：
  word#0 写入 tile_a_bus_reg[Tile_0 部分]
  word#1 写入 tile_a_bus_reg[Tile_1 部分]
  word#32 写入 tile_a_bus_reg[Tile_0 部分 的下一个 word offset]
  ...
```

### 3️⃣ 验证 MERGE 模式 A 数据分发
```
testbench:
  设置 pool_mode = MERGE
  设置 cfg_group_master = 某个模式（比如 0x00000001 表示 Tile#0 为主）
  验证数据是否只写到主 Tile
```

---

## 与其他问题的关系

| 问题 | 状态 | 依赖关系 |
|------|------|--------|
| 问题 2a | ✅ 已解决 | 无依赖 |
| 问题 2b | ⚠️ 已改进 | 等待仿真验证 |
| 问题 6 | ✅ 已解决 | 无依赖 |
| 问题 1 | ❌ 待修复 | 不依赖本改动 |
| 问题 4 | ❌ 待修复 | 不依赖本改动 |
| 问题 3 | ❌ 待修复 | 依赖问题 1 的修复 |

---

## 改动文件汇总

| 文件 | 修改行数 | 修改内容 |
|------|--------|---------|
| `rtl/npu_ctrl.v` | 47-140 | 新增 calc_rd_word_count 函数，更新 rd_word_count 计算 |
| `rtl/npu_top.v` | 375-470 | 改进 A 数据分发逻辑，支持三种工作模式 |
| `README.md` | 新增章节 | 项目更新说明 |
| `EXECUTION_ANALYSIS.md` | 更新 LOAD 阶段 | 更新数据流向说明 |
| `QUICK_CHECKLIST.md` | 更新状态 | 标记问题 2a、2b、6 的修复状态 |

---

## 下一步建议

1. **立即执行**：仿真验证上述三个测试用例
2. **继续修复**：问题 1（写 DMA 连续数据供给）和问题 4（权重缓存有效数据）
3. **可选优化**：验证 MERGE/SPLIT 模式的数据分发，完善问题 2b
