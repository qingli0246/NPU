# NPU 测试文件对比说明

## 📊 两个测试文件的对比

| 特性 | `tb_npu_top_test.v` (原始) | `tb_npu_complex_test.v` (新增) |
|------|---------------------------|------------------------------|
| **用途** | 单个 Tile 基础功能验证 | 多 Tile、多工作模式复杂功能 |
| **矩阵规模** | 8×8×8 单一规模 | 8×8×8 和 16×16×16 多种规模 |
| **Tile 配置** | Tile#0 仅 | Tile#0, #1, #2, #3, 全部(#0-31) |
| **工作模式** | INDEP 仅 | INDEP、MERGE、STATIC/DYNAMIC |
| **测试场景数** | 1 个 | 6 个 |
| **时间投入** | 短 (~200 μs) | 中等 (~1-2 ms) |
| **波形文件** | tb_npu_top_test.vcd | npu_complex_test.vcd |
| **验证深度** | 基础的 C 矩阵检查 | 详细的多任务并行性分析 |
| **权重模式** | 动态加载仅 | 静态加载/权重共享 |
| **多任务支持** | 无 (单任务) | 支持顺序执行 3+ 个任务 |

---

## 🔄 何时使用哪个测试？

### 使用 `tb_npu_top_test.v` 的场景：
- ✅ 快速功能验证（编译 + 仿真 < 1 分钟）
- ✅ 调试单个 Tile 的计算逻辑
- ✅ 验证基本的 AXI 接口握手
- ✅ 引入新的 Tile 设计时做冒烟测试
- ✅ 持续集成/快速反馈循环

### 使用 `tb_npu_complex_test.v` 的场景：
- ✅ 验证多 Tile 并行计算能力
- ✅ 测试不同的工作模式（INDEP、MERGE、SPLIT）
- ✅ 验证权重缓存和加载策略
- ✅ 测试多任务流程和状态管理
- ✅ 综合系统验证前的全面测试
- ✅ 性能基准测试（多 Tile 吞吐量）
- ✅ 大矩阵处理能力验证

---

## 📋 测试场景详解

### 原始测试 (tb_npu_top_test.v)

```
┌─────────────────────┐
│  Reset & Init       │
├─────────────────────┤
│  Config Tile#0      │
│  INDEP, 8x8x8       │
├─────────────────────┤
│  Start Computation  │
├─────────────────────┤
│  Wait for Done      │
├─────────────────────┤
│  Verify C[0][0]=1   │
└─────────────────────┘
  时间: ~200 μs
```

**输出场景**：
```
[Test] NPU Top Level Integration Test
[Mode] Single Tile (Tile#0) - 8x8 Matrix Multiply
[Step 2] Configure NPU via AXI-Lite
[Step 3] Start NPU Computation
[Step 4] Verify C Matrix Results
```

---

### 新增复杂测试 (tb_npu_complex_test.v)

```
┌─────────────────────┐
│  Reset & Init       │  初始化
│  Memory Preload     │  预加载矩阵数据到 BRAM
├─────────────────────┤
│ TEST 1: Tile#0      │  基准: 单 Tile
│ TEST 2: Tile#0,1    │  并行: 双 Tile  ───┐
│ TEST 3: Tile#0-3    │  并行: 四 Tile  ───┤ 相同时间
├─────────────────────┤                      ├─ 验证加速
│ TEST 4: Static Mode │  权重复用        ───┘
├─────────────────────┤
│ TEST 5: 3 Tasks     │  任务流程
│ Task1, Task2, Task3 │
├─────────────────────┤
│ TEST 6: 16x16x16    │  大矩阵
│ Merge Mode          │
├─────────────────────┤
│ Verify All Results  │
└─────────────────────┘
  时间: ~1-2 ms
```

**输出场景示例**：
```
TEST 1: Single Tile (INDEP Mode) - 8x8x8
TEST 2: Dual Tile (INDEP Mode) - Parallel 8x8x8
TEST 3: Quad Tile (INDEP Mode) - Parallel 8x8x8
TEST 4: Static Weight Mode (INDEP + STATIC)
TEST 5: Sequential Task Execution (3 tasks)
TEST 6: Large Matrix (16x16x16) - MERGE Mode

[Computation complete, busy=0 done=1 error=0]
[Verify] Reading and checking results
```

---

## 🎯 关键验证指标

### 原始测试验证的指标

| 指标 | 预期 | 验证方式 |
|------|------|--------|
| 单 Tile 功能 | ✓ 工作 | C[0][0]=1 |
| AXI-Lite 握手 | ✓ 正常 | awready/wready 信号 |
| 计算完成信号 | ✓ 拉高 | npu_done=1 |
| 错误信号 | ✓ 低 | npu_error=0 |

### 新增复杂测试的额外验证指标

| 指标 | 预期 | 验证方式 |
|------|------|--------|
| **并行加速** | TEST2 时间 ≈ TEST1 | 波形分析 busy 信号 |
| **四 Tile 吞吐** | TEST3 时间 ≈ TEST1 | 时间戳对比 |
| **权重缓存** | TEST4 与 TEST1 结果一致 | 比较输出矩阵 |
| **任务切换** | TEST5 顺序完成 | npu_done 脉冲计数 ≥ 3 |
| **大矩阵处理** | TEST6 16×16 正确计算 | MERGE 模式输出验证 |
| **无错误运行** | 所有测试 npu_error=0 | 波形中 error 信号监控 |

---

## 🔬 波形分析建议

### 在 GTKWave 中关注的关键时序点

#### TEST 1-3 对比（验证并行加速）

```
TEST1:        |--[busy]----------|  (~200 clk)
              |                  |
TEST2:        |--[busy]----------|  (~200 clk)  ← 时间相同！
              |                  |
TEST3:        |--[busy]----------|  (~200 clk)  ← 仍然相同！
              |                  |

结论: 4 个 Tile 同步工作，无时间增加
```

#### TEST 5（多任务检查）

```
Task1:  |---[busy]---|done|
                        
Task2:              |----[busy]-----|done|
                                      
Task3:                          |-----[busy]-----|done|

观察点:
- 每个 task 都有独立的 busy/done 脉冲
- 任务间无系统复位，状态正确转移
```

---

## 💾 文件结构

```
f:\complication-6\NPU\
├── TB/
│   ├── tb_npu_top_test.v          (原始单 Tile 测试)
│   ├── tb_npu_complex_test.v      ← (新增复杂测试) 
│   ├── npu_top_test.vcd           (原始测试波形)
│   └── npu_complex_test.vcd       ← (新增测试波形)
├── rtl/
│   ├── npu_defs.vh
│   ├── npu_top.v
│   └── ... (其他 RTL 文件)
├── TEST_GUIDE.md                  (原始测试指南)
├── COMPLEX_TEST_GUIDE.md          ← (新增测试指南)
├── quick_test.ps1                 (原始快速测试脚本)
└── run_complex_test.ps1           ← (新增复杂测试脚本)
```

---

## 🚀 推荐使用流程

### 开发阶段
```
1. 修改 RTL 代码
   ↓
2. 快速验证: run_quick_test.ps1      (1-2 min)
   ↓
3. 如果通过，继续开发
   如果失败，调试设计
   ↓
4. 定期运行: run_complex_test.ps1    (5-10 min)
   验证多 Tile、多模式功能
   ↓
5. 集成测试通过，准备上板
```

### 集成验证阶段
```
1. 同时运行两个测试
2. 比较波形 (tb_npu_top_test.vcd vs npu_complex_test.vcd)
3. 验证时序差异
4. 检查功耗和资源使用
5. 生成测试报告
```

---

## 📌 常见问题

### Q: 两个测试可以并行运行吗？
**A**: 不建议。它们都使用相同的编译目标和 BRAM 模型，建议顺序运行。

### Q: 新测试会影响原始测试吗？
**A**: 不会。两个测试文件独立，编译输出到不同的 .vvp 文件。

### Q: 测试数据用的是什么矩阵？
**A**: 
- **原始测试**: A=I(单位矩阵), B=0(全零)，结果 C=0
- **新增测试**: A=I, B=I，结果 C=I (对角线为 1)

### Q: 如何在实际项目中使用这些数据？
**A**: 请在 `init_memory_data()` 任务中修改矩阵初始化逻辑，使用实际的计算数据。

### Q: 测试失败如何调试？
**A**: 
1. 查看控制台输出的 npu_error 信号
2. 打开 GTKWave 查看时序波形
3. 追踪 AXI 握手信号是否正常
4. 检查配置寄存器值是否正确写入

