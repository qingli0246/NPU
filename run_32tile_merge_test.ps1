# ============================================================================
# NPU 32-Tile MERGE模式全量测试运行脚本
# ============================================================================
# 功能：自动化编译、运行和日志记录MERGE模式的32-Tile测试
# 用法：.\run_32tile_merge_test.ps1 [-Clean]
#   -Clean: 清理旧的可执行文件和波形文件后再运行
# ============================================================================

param(
    [string]$Tool = "iverilog",  # 仿真工具：iverilog, modelsim, vivado
    [switch]$Waveform,           # 是否生成波形文件
    [switch]$Clean               # 是否清理旧文件
)

# 设置控制台编码为 UTF-8，解决中文乱码问题
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  NPU 32-Tile MERGE模式全量测试" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 设置工作目录
$ProjectRoot = $PSScriptRoot
$RTLDir = Join-Path $ProjectRoot "rtl"
$TBDir = Join-Path $ProjectRoot "TB"
$TestFile = Join-Path $TBDir "tb_npu_32tile_merge_test.v"
$OutputExe = Join-Path $ProjectRoot "tb_npu_32tile_merge_test.exe"
$WaveFile = Join-Path $ProjectRoot "TB\npu_32tile_merge_test.vcd"
$LogFile = Join-Path $ProjectRoot "TB\npu_32tile_merge_test.log"

# 清理旧文件
if ($Clean) {
    Write-Host "[清理] 删除旧的编译文件和波形文件..." -ForegroundColor Yellow
    if (Test-Path $OutputExe) {
        Remove-Item $OutputExe -Force
        Write-Host "  ✓ 已删除: $OutputExe" -ForegroundColor Green
    }
    if (Test-Path $WaveFile) {
        Remove-Item $WaveFile -Force
        Write-Host "  ✓ 已删除: $WaveFile" -ForegroundColor Green
    }
    if (Test-Path $LogFile) {
        Remove-Item $LogFile -Force
        Write-Host "  ✓ 已删除: $LogFile" -ForegroundColor Green
    }
    Write-Host ""
}

# 检查必要文件是否存在
Write-Host "[检查] 验证必要文件..." -ForegroundColor Yellow

$RequiredFiles = @(
    "TB\tb_npu_32tile_merge_test.v",
    "rtl\npu_top.v",
    "rtl\npu_ctrl.v",
    "rtl\npu_compute_pool.v",
    "rtl\npu_tile.v",
    "rtl\npu_dma_rd.v",
    "rtl\npu_dma_wr.v",
    "rtl\npu_weight_cache.v",
    "rtl\npu_axi4_bridge.v",
    "rtl\npu_defs.vh"
)

$AllFilesExist = $true
foreach ($file in $RequiredFiles) {
    $fullPath = Join-Path $ProjectRoot $file
    if (Test-Path $fullPath) {
        Write-Host "  ✓ $file" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $file (缺失)" -ForegroundColor Red
        $AllFilesExist = $false
    }
}

if (-not $AllFilesExist) {
    Write-Host ""
    Write-Host "错误: 缺少必要的源文件，无法继续测试。" -ForegroundColor Red
    exit 1
}

Write-Host ""

# 根据选择的工具进行编译和运行
switch ($Tool.ToLower()) {
    "iverilog" {
        Write-Host "[编译] 使用 Icarus Verilog 编译..." -ForegroundColor Cyan
        
        $CompileCmd = "iverilog -g2012 -o `"$OutputExe`" -I `"$RTLDir`" `"$(Join-Path $TBDir 'tb_npu_32tile_merge_test.v')`" `"$(Join-Path $RTLDir 'npu_top.v')`" `"$(Join-Path $RTLDir 'npu_ctrl.v')`" `"$(Join-Path $RTLDir 'npu_compute_pool.v')`" `"$(Join-Path $RTLDir 'npu_tile.v')`" `"$(Join-Path $RTLDir 'npu_dma_rd.v')`" `"$(Join-Path $RTLDir 'npu_dma_wr.v')`" `"$(Join-Path $RTLDir 'npu_weight_cache.v')`" `"$(Join-Path $RTLDir 'npu_axi4_bridge.v')`""
        
        Write-Host "执行命令: $CompileCmd" -ForegroundColor Gray
        Invoke-Expression $CompileCmd
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "错误: 编译失败！" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "✓ 编译成功" -ForegroundColor Green
        Write-Host ""
        
        Write-Host "[运行] 执行仿真测试..." -ForegroundColor Cyan
        Write-Host "提示: 测试可能需要几分钟时间，请耐心等待..." -ForegroundColor Yellow
        Write-Host "日志文件: $LogFile" -ForegroundColor Yellow
        Write-Host ""
        
        # 创建日志文件并开始记录
        $StartTime = Get-Date
        
        # 先清空日志文件（如果存在）
        if (Test-Path $LogFile) {
            Clear-Content -Path $LogFile
            Write-Host "[日志] 已清空旧日志文件: $LogFile" -ForegroundColor Cyan
        }
        
        Write-Host "[日志] 开始记录仿真输出到: $LogFile" -ForegroundColor Cyan
        
        # 使用 Tee-Object 同时输出到控制台和文件（覆盖模式）
        vvp $OutputExe | Tee-Object -FilePath $LogFile
        
        $EndTime = Get-Date
        $Duration = ($EndTime - $StartTime).TotalSeconds
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "错误: 仿真执行失败！" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "✓ 仿真完成 (耗时: $([math]::Round($Duration, 2)) 秒)" -ForegroundColor Green
        Write-Host "✓ 完整日志已保存到: $LogFile" -ForegroundColor Green
    }
    
    "modelsim" {
        Write-Host "[编译] 使用 ModelSim 编译..." -ForegroundColor Cyan
        Write-Host "注意: ModelSim 模式尚未完全实现，请使用 Icarus Verilog" -ForegroundColor Yellow
        exit 1
    }
    
    "vivado" {
        Write-Host "[编译] 使用 Vivado 编译..." -ForegroundColor Cyan
        Write-Host "注意: Vivado 模式尚未完全实现，请使用 Icarus Verilog" -ForegroundColor Yellow
        exit 1
    }
    
    default {
        Write-Host "错误: 不支持的仿真工具 '$Tool'" -ForegroundColor Red
        Write-Host "支持的选项: iverilog, modelsim, vivado" -ForegroundColor Yellow
        exit 1
    }
}

# 检查波形文件
Write-Host ""
Write-Host "[检查] 波形文件..." -ForegroundColor Cyan

if (Test-Path $WaveFile) {
    $FileSize = (Get-Item $WaveFile).Length / 1MB
    Write-Host "✓ 波形文件已生成: $WaveFile" -ForegroundColor Green
    Write-Host "  文件大小: $([math]::Round($FileSize, 2)) MB" -ForegroundColor Gray
    
    if ($Waveform) {
        Write-Host ""
        Write-Host "[提示] 使用以下命令查看波形:" -ForegroundColor Cyan
        Write-Host "gtkwave `"$WaveFile`"" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ 未找到波形文件" -ForegroundColor Yellow
    Write-Host "  可能原因: 测试中未启用 VCD 输出或仿真提前终止" -ForegroundColor Gray
}

# 检查日志文件
Write-Host ""
Write-Host "[检查] 日志文件..." -ForegroundColor Cyan

if (Test-Path $LogFile) {
    $LogSize = (Get-Item $LogFile).Length / 1KB
    Write-Host "✓ 日志文件已生成: $LogFile" -ForegroundColor Green
    Write-Host "  文件大小: $([math]::Round($LogSize, 2)) KB" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[提示] 查看完整日志:" -ForegroundColor Cyan
    Write-Host "  Get-Content `"$LogFile`"" -ForegroundColor Yellow
    Write-Host "  notepad `"$LogFile`"" -ForegroundColor Yellow
} else {
    Write-Host "⚠ 未找到日志文件" -ForegroundColor Yellow
}

# 显示测试总结
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  测试完成" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "测试结果已在上方输出中显示" -ForegroundColor White
Write-Host "完整日志文件: $LogFile" -ForegroundColor White
Write-Host ""
Write-Host "如需查看详细波形，请运行:" -ForegroundColor White
Write-Host "  gtkwave TB\npu_32tile_merge_test.vcd" -ForegroundColor Yellow
Write-Host ""
Write-Host "详细说明请参考: 32TILE_TEST_GUIDE.md" -ForegroundColor White
Write-Host ""










