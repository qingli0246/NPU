# ============================================================
# NPU快速测试脚本（PowerShell）- 当前唯一仿真入口
# ============================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$outputFile = "TB\npu_top_integrated.vvp"
$testbench = "TB\tb_npu_top_test.v"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NPU Quick Test (Icarus Verilog)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    $null = Get-Command iverilog -ErrorAction Stop
    $null = Get-Command vvp -ErrorAction Stop
} catch {
    Write-Host "[ERROR] Icarus Verilog or vvp not found." -ForegroundColor Red
    Write-Host "Install Icarus Verilog first, then rerun this script." -ForegroundColor Yellow
    exit 1
}

foreach ($file in @(
    "TB\tb_npu_top_test.v",
    "rtl\npu_top.v",
    "rtl\npu_ctrl.v",
    "rtl\npu_compute_pool.v",
    "rtl\npu_tile.v",
    "rtl\npu_dma_rd.v",
    "rtl\npu_dma_wr.v",
    "rtl\npu_weight_cache.v",
    "rtl\npu_axi4_bridge.v",
    "rtl\npu_defs.vh"
)) {
    if (-not (Test-Path $file)) {
        Write-Host "[ERROR] Missing file: $file" -ForegroundColor Red
        exit 1
    }
}

Remove-Item $outputFile, "TB\npu_top_test.vcd" -ErrorAction SilentlyContinue

Write-Host "[STEP 1] Compiling current integrated testbench..." -ForegroundColor Cyan
Write-Host ""

$compileArgs = @(
    "-g2012",
    "-Irtl",
    "-o", $outputFile,
    $testbench,
    "rtl\npu_top.v",
    "rtl\npu_ctrl.v",
    "rtl\npu_compute_pool.v",
    "rtl\npu_tile.v",
    "rtl\npu_dma_rd.v",
    "rtl\npu_dma_wr.v",
    "rtl\npu_weight_cache.v",
    "rtl\npu_axi4_bridge.v"
)

& iverilog @compileArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] Compilation failed." -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Compilation successful: $outputFile" -ForegroundColor Green
Write-Host ""
Write-Host "[STEP 2] Running simulation..." -ForegroundColor Cyan
Write-Host ""

& vvp $outputFile

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] Simulation failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "[SUCCESS] Simulation completed." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
