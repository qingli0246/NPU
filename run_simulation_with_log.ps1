# ============================================================
# NPU仿真测试脚本 - 带日志输出
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NPU Simulation Test with Log" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$logFile = "simulation_log.txt"

Write-Host "[INFO] Starting simulation..." -ForegroundColor Green
Write-Host "[INFO] Log file: $logFile" -ForegroundColor Green
Write-Host ""

# 检查是否已编译
if (-not (Test-Path "npu_sim.exe")) {
    Write-Host "[STEP 1] Compiling..." -ForegroundColor Cyan
    
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
    
    & iverilog @sources 2>&1 | Tee-Object -FilePath $logFile
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[ERROR] Compilation failed!" -ForegroundColor Red
        Write-Host "Check $logFile for details." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "[INFO] Compilation successful." -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "[INFO] Using existing compiled file." -ForegroundColor Green
    Write-Host ""
}

Write-Host "[STEP 2] Running simulation..." -ForegroundColor Cyan
Write-Host "This may take a few minutes..." -ForegroundColor Yellow
Write-Host ""

# 运行仿真并记录日志
& vvp npu_sim.exe 2>&1 | Tee-Object -FilePath $logFile -Append

Write-Host ""
if ($LASTEXITCODE -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "[SUCCESS] Simulation completed!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "[ERROR] Simulation failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
}

Write-Host ""
Write-Host "Log saved to: $logFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
