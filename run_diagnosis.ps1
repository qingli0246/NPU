# ============================================================
# NPU仿真诊断脚本 - 快速定位卡顿问题
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NPU Simulation Diagnostics" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$logFile = "diagnosis_log.txt"

Write-Host "[INFO] Starting diagnostics..." -ForegroundColor Green
Write-Host "[INFO] Log file: $logFile" -ForegroundColor Green
Write-Host ""

# 检查编译文件
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
        exit 1
    }
    
    Write-Host "[INFO] Compilation successful." -ForegroundColor Green
    Write-Host ""
}

Write-Host "[STEP 2] Running quick simulation (max 5 seconds)..." -ForegroundColor Cyan
Write-Host ""

# 运行仿真并设置超时
$job = Start-Job -ScriptBlock {
    Set-Location $args[0]
    & vvp npu_sim.exe 2>&1
} -ArgumentList $scriptDir

# 等待最多5秒
$completed = Wait-Job $job -Timeout 5

if ($completed) {
    $output = Receive-Job $job
    $output | Tee-Object -FilePath $logFile -Append
    
    Write-Host ""
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[SUCCESS] Simulation completed quickly!" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Simulation finished with errors." -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "[WARNING] Simulation is taking too long (>5 seconds)!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  1. Infinite loop in RTL code" -ForegroundColor Yellow
    Write-Host "  2. Deadlock in state machine" -ForegroundColor Yellow
    Write-Host "  3. DMA transfer not completing" -ForegroundColor Yellow
    Write-Host "  4. Clock not toggling properly" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Stopping simulation..." -ForegroundColor Cyan
    
    Stop-Job $job
    Remove-Job $job -Force
    
    Write-Host ""
    Write-Host "[INFO] Partial output saved to: $logFile" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
