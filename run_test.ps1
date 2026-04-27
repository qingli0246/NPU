# ============================================================
# NPU仿真测试运行脚本（PowerShell）
# 支持多种仿真工具
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("iverilog", "modelsim", "vivado", "help")]
    [string]$Tool = "help"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NPU Simulation Test Runner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$RTL_DIR = "rtl"
$TB_FILE = "tb_npu_top.v"
$WORK_LIB = "work"

if ($Tool -eq "help") {
    Write-Host "Usage: .\run_test.ps1 [-Tool <tool>]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Available tools:" -ForegroundColor Yellow
    Write-Host "  iverilog   - Icarus Verilog (free, recommended for quick tests)" -ForegroundColor White
    Write-Host "  modelsim   - ModelSim/QuestaSim" -ForegroundColor White
    Write-Host "  vivado     - Xilinx Vivado Simulator" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\run_test.ps1 -Tool iverilog" -ForegroundColor White
    Write-Host "  .\run_test.ps1 -Tool modelsim" -ForegroundColor White
    Write-Host "  .\run_test.ps1 -Tool vivado" -ForegroundColor White
    exit
}

Write-Host "[INFO] Using tool: $Tool" -ForegroundColor Green
Write-Host ""

switch ($Tool) {
    "iverilog" {
        Write-Host "[INFO] Running with Icarus Verilog..." -ForegroundColor Green
        Write-Host ""
        
        # 检查iverilog是否安装
        try {
            $null = Get-Command iverilog -ErrorAction Stop
        } catch {
            Write-Host "[ERROR] Icarus Verilog not found!" -ForegroundColor Red
            Write-Host "Please install Icarus Verilog from: http://iverilog.icarus.com/" -ForegroundColor Yellow
            exit 1
        }
        
        # 编译
        Write-Host "[STEP 1] Compiling..." -ForegroundColor Cyan
        
        $sources = @(
            "$RTL_DIR\npu_defs.vh",
            "$RTL_DIR\npu_tile.v",
            "$RTL_DIR\npu_compute_pool.v",
            "$RTL_DIR\npu_weight_cache.v",
            "$RTL_DIR\npu_ctrl.v",
            "$RTL_DIR\npu_dma_rd.v",
            "$RTL_DIR\npu_dma_wr.v",
            "$RTL_DIR\npu_axi4_bridge.v",
            "$RTL_DIR\npu_top.v",
            "tb_memory_model.v",
            $TB_FILE
        )
        
        $compileArgs = @("-I$RTL_DIR", "-o", "npu_sim.exe") + $sources
        
        & iverilog @compileArgs
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "[ERROR] Compilation failed!" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "[INFO] Compilation successful." -ForegroundColor Green
        Write-Host ""
        
        # 运行仿真
        Write-Host "[STEP 2] Running simulation..." -ForegroundColor Cyan
        Write-Host "This may take a few minutes..." -ForegroundColor Yellow
        Write-Host ""
        
        & vvp npu_sim.exe
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "[ERROR] Simulation failed!" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "[SUCCESS] Icarus Verilog test completed!" -ForegroundColor Green
    }
    
    "modelsim" {
        Write-Host "[INFO] Running with ModelSim/QuestaSim..." -ForegroundColor Green
        Write-Host ""
        
        # 清理旧库
        if (Test-Path $WORK_LIB) {
            Remove-Item -Recurse -Force $WORK_LIB
        }
        
        # 创建库
        Write-Host "[STEP 1] Creating library..." -ForegroundColor Cyan
        & vlib $WORK_LIB
        & vmap work $WORK_LIB
        Write-Host ""
        
        # 编译
        Write-Host "[STEP 2] Compiling..." -ForegroundColor Cyan
        
        $sources = @(
            "+incdir+$RTL_DIR",
            "$RTL_DIR\npu_defs.vh",
            "$RTL_DIR\npu_tile.v",
            "$RTL_DIR\npu_compute_pool.v",
            "$RTL_DIR\npu_weight_cache.v",
            "$RTL_DIR\npu_ctrl.v",
            "$RTL_DIR\npu_dma_rd.v",
            "$RTL_DIR\npu_dma_wr.v",
            "$RTL_DIR\npu_axi4_bridge.v",
            "$RTL_DIR\npu_top.v",
            "tb_memory_model.v",
            $TB_FILE
        )
        
        & vlog -work work @sources
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "[ERROR] Compilation failed!" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "[INFO] Compilation successful." -ForegroundColor Green
        Write-Host ""
        
        # 运行仿真
        Write-Host "[STEP 3] Running simulation..." -ForegroundColor Cyan
        & vsim -c work.tb_npu_top -do "run -all; quit"
        
        Write-Host ""
        Write-Host "[SUCCESS] ModelSim test completed!" -ForegroundColor Green
    }
    
    "vivado" {
        Write-Host "[INFO] Running with Vivado Simulator..." -ForegroundColor Green
        Write-Host ""
        
        # 创建Tcl脚本
        $tclContent = @"
create_project -force npu_test ./npu_test_proj -part xc7k325tffg900-2
add_files -fileset sources_1 $RTL_DIR/npu_defs.vh
add_files -fileset sources_1 $RTL_DIR/npu_tile.v
add_files -fileset sources_1 $RTL_DIR/npu_compute_pool.v
add_files -fileset sources_1 $RTL_DIR/npu_weight_cache.v
add_files -fileset sources_1 $RTL_DIR/npu_ctrl.v
add_files -fileset sources_1 $RTL_DIR/npu_dma_rd.v
add_files -fileset sources_1 $RTL_DIR/npu_dma_wr.v
add_files -fileset sources_1 $RTL_DIR/npu_axi4_bridge.v
add_files -fileset sources_1 $RTL_DIR/npu_top.v
add_files -fileset sources_1 tb_memory_model.v
add_files -fileset sim_1 $TB_FILE
set_property top tb_npu_top [current_fileset -simset]
launch_simulation
run all
"@
        
        $tclContent | Out-File -FilePath "vivado_run.tcl" -Encoding ASCII
        
        Write-Host "[STEP 1] Running Vivado simulation..." -ForegroundColor Cyan
        & vivado -mode batch -source vivado_run.tcl
        
        Write-Host ""
        Write-Host "[SUCCESS] Vivado test completed!" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
