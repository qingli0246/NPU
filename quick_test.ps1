# ============================================================
# NPU快速测试脚本（PowerShell）- 使用Icarus Verilog进行基本功能验证
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NPU Quick Test (Icarus Verilog)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查iverilog是否安装
try {
    $null = Get-Command iverilog -ErrorAction Stop
    Write-Host "[INFO] Icarus Verilog found." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Icarus Verilog not found!" -ForegroundColor Red
    Write-Host "Please install Icarus Verilog from: http://iverilog.icarus.com/" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Or use other tools:" -ForegroundColor Yellow
    Write-Host "  .\run_test.ps1 -Tool modelsim" -ForegroundColor White
    Write-Host "  .\run_test.ps1 -Tool vivado" -ForegroundColor White
    Write-Host ""
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host ""

# 检查文件是否存在
if (-not (Test-Path "rtl\npu_top.v")) {
    Write-Host "[ERROR] rtl\npu_top.v not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

if (-not (Test-Path "tb_npu_top.v")) {
    Write-Host "[ERROR] tb_npu_top.v not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "[STEP 1] Compiling all modules..." -ForegroundColor Cyan
Write-Host ""

# 编译所有文件
$sources = @(
    "-Irtl",
    "rtl\npu_defs.vh",
    "rtl\npu_tile.v",
    "rtl\npu_compute_pool.v",
    "rtl\npu_weight_cache.v",
    "rtl\npu_ctrl.v",
    "rtl\npu_dma_rd.v",
    "rtl\npu_dma_wr.v",
    "rtl\npu_axi4_bridge.v",
    "rtl\npu_top.v",
    "tb_memory_model.v",
    "tb_npu_top.v"
)

& iverilog -o npu_sim.exe @sources

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] Compilation failed! Check the errors above." -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "[INFO] Compilation successful." -ForegroundColor Green
Write-Host ""

Write-Host "[STEP 2] Running simulation..." -ForegroundColor Cyan
Write-Host "This may take a few minutes..." -ForegroundColor Yellow
Write-Host ""

& vvp npu_sim.exe

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] Simulation failed!" -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "[SUCCESS] Test completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "To view waveforms (if generated):" -ForegroundColor Yellow
    Write-Host "  gtkwave dump.vcd" -ForegroundColor White
}

Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
