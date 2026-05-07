# NPU 复杂功能测试运行指南

## 📌 新建测试文件说明

### 文件名
- `TB/tb_npu_complex_test.v` - 复杂功能仿真测试平台

### 测试覆盖场景

#### TEST 1: 单个 Tile (INDEP 模式) - 参考基准
- **配置**：INDEP 模式，Tile#0 仅
- **矩阵**：8×8×8 (A、B 均为单位矩阵)
- **预期结果**：C = I × I = I (单位矩阵)
- **用途**：建立基准，验证单 tile 功能正常

#### TEST 2: 双 Tile 并行 (INDEP 模式)
- **配置**：INDEP 模式，Tile#0 和 Tile#1 同时运行
- **矩阵**：8×8×8，两个 tile 独立计算
- **预期结果**：两个 tile 的输出位置不同 (0x400)，均为单位矩阵
- **用途**：验证多 tile 并行计算

#### TEST 3: 四 Tile 并行 (INDEP 模式)
- **配置**：INDEP 模式，Tile#0-3 同时运行
- **矩阵**：8×8×8，四个 tile 独立计算
- **预期结果**：四个 tile 并行执行，结果正确
- **用途**：验证大规模并行能力

#### TEST 4: 静态权重加载模式
- **配置**：STATIC + SHARED 模式 (reg_mode[3:2] = 2'b10)
- **矩阵**：8×8×8
- **预期结果**：权重预加载，复用于多次计算
- **用途**：验证权重缓存功能

#### TEST 5: 多任务顺序执行
- **配置**：三个任务依次执行，无系统复位
- **任务1**：1 个 tile (0x700)
- **任务2**：2 个 tile (0x800)
- **任务3**：4 个 tile (0x900)
- **用途**：验证状态管理和任务流程

#### TEST 6: 大矩阵计算 (MERGE 模式)
- **配置**：MERGE 模式，所有 32 个 tile 协作
- **矩阵**：16×16×16 (更大的矩阵)
- **预期结果**：多 tile 协作计算大矩阵
- **用途**：验证 MERGE 模式和可扩展性

---

## 🔧 运行方式

### 方式 1：使用编译脚本（推荐）

创建 PowerShell 脚本 `run_complex_test.ps1`：

```powershell
# 编译
Write-Host "Compiling NPU Complex Functional Test..." -ForegroundColor Cyan
$compileCmd = @(
    "iverilog",
    "-g2012",
    "-I", "rtl",
    "-o", "TB\npu_complex_test.vvp",
    "TB\tb_npu_complex_test.v",
    "rtl\npu_top.v",
    "rtl\npu_ctrl.v",
    "rtl\npu_compute_pool.v",
    "rtl\npu_tile.v",
    "rtl\npu_dma_rd.v",
    "rtl\npu_dma_wr.v",
    "rtl\npu_weight_cache.v",
    "rtl\npu_axi4_bridge.v"
)

& $compileCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "Compilation failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Compilation successful!" -ForegroundColor Green

# 仿真
Write-Host "`nRunning simulation..." -ForegroundColor Cyan
vvp TB\npu_complex_test.vvp

Write-Host "`nSimulation completed!" -ForegroundColor Green
Write-Host "Waveform file: TB\npu_complex_test.vcd" -ForegroundColor Yellow
```

运行：
```powershell
cd f:\complication-6\NPU
.\run_complex_test.ps1
```

### 方式 2：手动编译和运行

```powershell
cd f:\complication-6\NPU

# 编译
iverilog -g2012 -I rtl -o TB\npu_complex_test.vvp `
    TB\tb_npu_complex_test.v `
    rtl\npu_top.v rtl\npu_ctrl.v rtl\npu_compute_pool.v rtl\npu_tile.v `
    rtl\npu_dma_rd.v rtl\npu_dma_wr.v rtl\npu_weight_cache.v rtl\npu_axi4_bridge.v

# 运行
vvp TB\npu_complex_test.vvp

# 查看波形（使用 GTKWave）
gtkwave TB\npu_complex_test.vcd
```

---

## 📊 验证预期输出

运行仿真后，应该看到：

```
╔════════════════════════════════════════════════════════╗
║     NPU COMPLEX FUNCTIONALITY TEST PLATFORM            ║
║     Multiple Tile Computation & Advanced Modes         ║
╚════════════════════════════════════════════════════════╝

[Reset released, system ready]

┌────────────────────────────────────────────────────────┐
│ TEST 1: Single Tile (INDEP Mode) - 8x8x8              │
│ Expected: C = A * B = I * I = I (Identity Matrix)     │
└────────────────────────────────────────────────────────┘

[Configuration complete, starting computation...]
[Computation complete, busy=0 done=1 error=0]
[Verify] Reading and checking results
...

[TEST EXECUTION COMPLETED]
```

---

## 🎯 关键观察点

### 信号监控
在 GTKWave 中重点观察：

1. **时序信号**
   - `clk` - 100 MHz 系统时钟 (10 ns 周期)
   - `rst_n` - 复位信号 (20 ns 后释放)

2. **控制接口**
   - `s_axi_awvalid / s_axi_awready` - 写地址握手
   - `s_axi_wvalid / s_axi_wready` - 写数据握手
   - `s_axi_arvalid / s_axi_arready` - 读地址握手
   - `s_axi_rvalid / s_axi_rready` - 读数据握手

3. **计算状态**
   - `npu_busy` - NPU 正在计算（应在启动后立即拉高）
   - `npu_done` - 计算完成标志（应在任务完成时拉高）
   - `npu_error` - 错误标志（正常应保持低电平）
   - `npu_irq` - 中断信号（可选，取决于设计）

4. **数据通路**
   - `m_axi_araddr / m_axi_arvalid` - 读地址发出
   - `m_axi_rdata / m_axi_rvalid` - 读数据返回
   - `m_axi_awaddr / m_axi_awvalid` - 写地址发出
   - `m_axi_wdata / m_axi_wvalid` - 写数据发出

---

## ✅ 测试通过标准

1. **编译无错误** - iverilog 编译成功
2. **仿真完成** - vvp 正常结束，无 fatal 错误
3. **状态转移正确**
   - `npu_done` 在每个任务完成时拉高
   - `npu_error` 保持低电平
   - `npu_busy` 反映计算状态
4. **数据路径正常**
   - AXI-Lite 写读握手成功
   - AXI4 数据接口 BRAM 存储器通信正常
5. **多 Tile 并行执行** - TEST 2-3 在相同时间内完成

---

## 🐛 故障排查

### 编译错误
- 检查 Verilog 语法（特别是宏定义使用）
- 验证 `rtl/npu_defs.vh` 中的宏定义格式
- 确认所有 `.v` 文件都在 `rtl/` 目录中

### 仿真错误
- `npu_done` 从未拉高 → 检查 npu_ctrl 状态机
- `npu_error` 被拉高 → 检查配置参数和内存初始化
- AXI 握手无响应 → 检查 BRAM 模型实现

### 波形分析
```powershell
# 生成波形 (需要 GTKWave 安装)
gtkwave TB\npu_complex_test.vcd

# 或使用其他波形查看器（如 ModelSim）
```

---

## 📌 后续扩展

可以进一步扩展的测试场景：

1. **功能测试** - 实际矩阵计算验证（而非单位矩阵）
2. **性能测试** - 吞吐量和延迟测量
3. **压力测试** - 长时间连续计算
4. **错误注入** - 测试错误检测机制
5. **功耗分析** - 不同工作模式的功耗对比

