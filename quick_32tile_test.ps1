# NPU 32-Tile 测试 - 快速验证脚本
# 功能：仅运行 Test 1（单 Tile）进行快速验证

# 设置控制台编码为 UTF-8，解决中文乱码问题
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  NPU 32-Tile 测试 - 快速验证" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ProjectRoot = $PSScriptRoot
$OutputExe = Join-Path $ProjectRoot "tb_npu_32tile_test.exe"

# 检查可执行文件是否存在
if (-not (Test-Path $OutputExe)) {
    Write-Host "[编译] 首次运行，正在编译..." -ForegroundColor Yellow
    
    $CompileCmd = "iverilog -g2012 -o `"$OutputExe`" -I `"$ProjectRoot\rtl`" `"$(Join-Path $ProjectRoot 'TB' 'tb_npu_32tile_test.v')`" `"$(Join-Path $ProjectRoot 'rtl' 'npu_top.v')`" `"$(Join-Path $ProjectRoot 'rtl' 'npu_ctrl.v')`" `"$(Join-Path $ProjectRoot 'rtl' 'npu_compute_pool.v')`" `"$(Join-Path $ProjectRoot 'rtl' 'npu_tile.v')`" `"$(Join-Path $ProjectRoot 'rtl' 'npu_dma_rd.v')`" `"$(Join-Path $ProjectRoot 'rtl' 'npu_dma_wr.v')`" `"$(Join-Path $ProjectRoot 'rtl' 'npu_weight_cache.v')`" `"$(Join-Path $ProjectRoot 'rtl' 'npu_axi4_bridge.v')`""
    
    Invoke-Expression $CompileCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "错误: 编译失败！" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ 编译成功" -ForegroundColor Green
    Write-Host ""
}

Write-Host "[运行] 执行仿真测试..." -ForegroundColor Cyan
Write-Host "注意: 如果测试超时，说明 cfg_tile_mask 需要修复为 32 位" -ForegroundColor Yellow
Write-Host ""

vvp $OutputExe | Select-Object -Last 30

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "提示:" -ForegroundColor Cyan
Write-Host "- 如果看到 'Timeout' 错误，需要先修复 cfg_tile_mask 位宽问题" -ForegroundColor Yellow
Write-Host "- 修复后重新运行此脚本进行验证" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
