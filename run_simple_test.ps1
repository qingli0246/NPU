# ============================================================
# NPU最简单测试脚本（PowerShell）- 直接编译运行
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NPU Simulation Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 获取脚本所在目录
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

Write-Host "[INFO] Current directory: $(Get-Location)" -ForegroundColor Green
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

Write-Host "[STEP 1] Compiling..." -ForegroundColor Cyan
Write-Host ""

# 编译所有RTL文件和testbench
$sources = @(
    "-Irtl",
    "-o",
    "npu_sim.exe",
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

& iverilog @sources

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] Compilation failed!" -ForegroundColor Red
    Write-Host "Please check the error messages above." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "[INFO] Compilation successful!" -ForegroundColor Green
Write-Host ""

Write-Host "[STEP 2] Running simulation..." -ForegroundColor Cyan
Write-Host "This may take a while..." -ForegroundColor Yellow
Write-Host ""

& vvp npu_sim.exe

Write-Host ""
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Simulation failed!" -ForegroundColor Red
} else {
    Write-Host "[SUCCESS] Simulation completed!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
