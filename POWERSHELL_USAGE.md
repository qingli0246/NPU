# PowerShell 测试脚本使用说明

## 📋 概述

项目现已提供完整的PowerShell测试脚本，相比CMD脚本具有以下优势：
- ✅ **彩色输出**：更清晰的日志显示
- ✅ **参数化调用**：灵活选择仿真工具
- ✅ **更好的错误处理**：详细的错误提示
- ✅ **现代语法**：符合Windows最佳实践

---

## 🚀 快速开始

### 方法1：快速测试（推荐）

在PowerShell中运行：
```powershell
.\quick_test.ps1
```

这将：
1. 自动检测Icarus Verilog是否安装
2. 编译所有RTL文件和testbench
3. 运行仿真测试
4. 显示测试结果

---

### 方法2：选择仿真工具

```powershell
# 使用Icarus Verilog
.\run_test.ps1 -Tool iverilog

# 使用ModelSim
.\run_test.ps1 -Tool modelsim

# 使用Vivado
.\run_test.ps1 -Tool vivado

# 查看帮助
.\run_test.ps1 -Tool help
```

---

### 方法3：最简单测试

```powershell
.\run_simple_test.ps1
```

这个脚本最简洁，适合快速验证。

---

## 🔧 首次使用准备

### 1. 允许执行PowerShell脚本

如果首次运行遇到权限问题，需要设置执行策略：

```powershell
# 以管理员身份运行PowerShell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

或者临时绕过：
```powershell
powershell -ExecutionPolicy Bypass -File .\quick_test.ps1
```

---

### 2. 安装Icarus Verilog（如果未安装）

**下载地址**：http://bleyer.org/icarus/

**验证安装**：
```powershell
iverilog -version
```

应该看到类似输出：
```
Icarus Verilog version 11.0 (stable) (...)
```

---

## 📊 脚本对比

| 特性 | quick_test.ps1 | run_test.ps1 | run_simple_test.ps1 |
|------|----------------|--------------|---------------------|
| **复杂度** | 中等 | 高 | 低 |
| **工具选择** | ❌ 仅iverilog | ✅ 三种工具 | ❌ 仅iverilog |
| **彩色输出** | ✅ | ✅ | ✅ |
| **文件检查** | ✅ | ✅ | ✅ |
| **适用场景** | 日常测试 | 多工具切换 | 快速验证 |

---

## 🎨 输出示例

### 成功编译
```
========================================
NPU Quick Test (Icarus Verilog)
========================================

[INFO] Icarus Verilog found.

[STEP 1] Compiling all modules...

[INFO] Compilation successful.

[STEP 2] Running simulation...
This may take a few minutes...

[Test 1] Dynamic + Weight Shared Mode - 8x8 Matrix Multiply
[TB] AXI-L Write: addr=0x00000004, data=0x00000000
...

========================================
[SUCCESS] Test completed successfully!
========================================
```

### 编译失败
```
[ERROR] Compilation failed! Check the errors above.
```

### 工具未找到
```
[ERROR] Icarus Verilog not found!
Please install Icarus Verilog from: http://iverilog.icarus.com/
```

---

## ⚙️ 高级用法

### 自定义编译选项

编辑 `quick_test.ps1`，修改编译参数：

```powershell
# 添加调试信息
$sources = @(
    "-g2012",        # 启用SystemVerilog 2012支持
    "-DDEBUG",       # 定义DEBUG宏
    "-Irtl",
    ...
)
```

### 生成波形文件

在testbench中添加VCD导出：

```verilog
initial begin
    $dumpfile("npu_wave.vcd");
    $dumpvars(0, tb_npu_top);
end
```

然后运行：
```powershell
.\quick_test.ps1
gtkwave npu_wave.vcd
```

---

## 🐛 常见问题

### Q1: 无法识别"iverilog"命令

**原因**：Icarus Verilog未安装或未添加到PATH

**解决**：
1. 确认已安装Icarus Verilog
2. 将安装目录添加到系统PATH
3. 重启PowerShell

---

### Q2: 权限被禁止

**错误信息**：
```
无法加载文件 xxx.ps1，因为在此系统上禁止运行脚本
```

**解决**：
```powershell
# 方法1：临时绕过
powershell -ExecutionPolicy Bypass -File .\quick_test.ps1

# 方法2：永久设置（需要管理员权限）
Set-ExecutionPolicy RemoteSigned
```

---

### Q3: 编译错误

**常见原因**：
- 文件路径错误
- 缺少依赖文件
- 语法错误

**解决**：
1. 检查错误信息中的行号
2. 确认所有文件存在
3. 参考TEST_GUIDE.md的调试技巧

---

### Q4: 仿真卡住不动

**可能原因**：
- 时钟未正确生成
- 死锁状态
- 等待条件永不满足

**解决**：
1. Ctrl+C终止仿真
2. 检查testbench的时钟生成代码
3. 添加超时机制

---

## 📝 CMD vs PowerShell 对比

### CMD脚本（旧版）
```cmd
quick_test.bat
run_test.bat iverilog
```

**缺点**：
- ❌ 无彩色输出
- ❌ 错误处理简单
- ❌ 参数传递复杂
- ❌ 字符串处理困难

---

### PowerShell脚本（新版）
```powershell
.\quick_test.ps1
.\run_test.ps1 -Tool iverilog
```

**优点**：
- ✅ 彩色输出（Write-Host -ForegroundColor）
- ✅ 强大的错误处理（try-catch）
- ✅ 灵活的参数系统（param）
- ✅ 丰富的内置命令
- ✅ 更好的对象支持

---

## 🎯 推荐使用流程

### 日常开发
```powershell
# 每次修改RTL后快速验证
.\quick_test.ps1
```

### 多工具测试
```powershell
# 在不同仿真工具间切换
.\run_test.ps1 -Tool iverilog
.\run_test.ps1 -Tool modelsim
.\run_test.ps1 -Tool vivado
```

### 持续集成
```powershell
# 自动化测试脚本
if (.\quick_test.ps1) {
    Write-Host "Test passed!" -ForegroundColor Green
} else {
    Write-Host "Test failed!" -ForegroundColor Red
    exit 1
}
```

---

## 📚 相关文档

- **[TEST_GUIDE.md](TEST_GUIDE.md)** - 详细测试指南
- **[README.md](README.md)** - 项目总览
- **[EXECUTION_ANALYSIS.md](EXECUTION_ANALYSIS.md)** - 执行流程分析

---

## 💡 提示

1. **首次使用建议**：先运行 `.\quick_test.ps1` 验证环境配置
2. **遇到问题**：查看控制台输出的错误信息
3. **深入学习**：阅读PowerShell官方文档了解高级功能
4. **贡献代码**：欢迎提交改进建议和bug报告

---

**祝您使用愉快！** 🚀