# NPU Complex Functionality Test Runner
# 运行复杂功能测试的 PowerShell 脚本

param(
    [switch]$Compile = $true,
    [switch]$Run = $true,
    [switch]$ViewWave = $false,
    [string]$TestName = "tb_npu_complex_test"
)

# 颜色定义
$colors = @{
    'Success' = 'Green'
    'Error'   = 'Red'
    'Warning' = 'Yellow'
    'Info'    = 'Cyan'
    'Debug'   = 'Gray'
}

function Write-Status {
    param([string]$Message, [string]$Level = 'Info')
    $color = $colors[$Level]
    Write-Host $Message -ForegroundColor $color
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Title.PadRight(59)) ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# 检查当前目录
Write-Status "Checking workspace..." 'Info'
if (-not (Test-Path "rtl")) {
    Write-Status "ERROR: rtl/ directory not found. Please run this script from the NPU project root." 'Error'
    exit 1
}
if (-not (Test-Path "TB")) {
    Write-Status "ERROR: TB/ directory not found. Please run this script from the NPU project root." 'Error'
    exit 1
}

Write-Status "✓ Workspace structure verified" 'Success'

# ============================================================
# 编译部分
# ============================================================

if ($Compile) {
    Write-Section "COMPILATION PHASE"
    
    Write-Status "Preparing compilation for: $TestName" 'Info'
    
    $vvpOutput = "TB\$($TestName).vvp"
    $testFile = "TB\$($TestName).v"
    
    # 检查测试文件是否存在
    if (-not (Test-Path $testFile)) {
        Write-Status "ERROR: Test file $testFile not found!" 'Error'
        exit 1
    }
    
    Write-Status "Test file verified: $testFile" 'Success'
    Write-Host ""
    
    # RTL 文件列表
    $rtlFiles = @(
        "rtl\npu_defs.vh",
        "rtl\npu_top.v",
        "rtl\npu_ctrl.v",
        "rtl\npu_compute_pool.v",
        "rtl\npu_tile.v",
        "rtl\npu_dma_rd.v",
        "rtl\npu_dma_wr.v",
        "rtl\npu_weight_cache.v",
        "rtl\npu_axi4_bridge.v"
    )
    
    # 验证所有 RTL 文件
    $missingFiles = @()
    foreach ($file in $rtlFiles) {
        if (-not (Test-Path $file)) {
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-Status "ERROR: Missing RTL files:" 'Error'
        foreach ($file in $missingFiles) {
            Write-Status "  - $file" 'Error'
        }
        exit 1
    }
    
    Write-Status "✓ All RTL files verified" 'Success'
    Write-Host ""
    Write-Status "Compiling with iverilog..." 'Info'
    
    # 编译命令
    $compileCmd = @(
        "iverilog",
        "-g2012",
        "-I", "rtl",
        "-o", $vvpOutput
    ) + $testFile + $rtlFiles
    
    # 执行编译
    $startTime = Get-Date
    & iverilog -g2012 -I rtl -o $vvpOutput $testFile $rtlFiles 2>&1 | ForEach-Object {
        if ($_ -match "error" -or $_ -match "ERROR") {
            Write-Status $_ 'Error'
        } else {
            Write-Status $_ 'Debug'
        }
    }
    
    $compileStatus = $LASTEXITCODE
    $compileTime = (Get-Date) - $startTime
    
    Write-Host ""
    if ($compileStatus -eq 0) {
        Write-Status "✓ Compilation successful! (${compileTime})" 'Success'
        Write-Status "  Output: $vvpOutput" 'Info'
    } else {
        Write-Status "✗ Compilation FAILED!" 'Error'
        Write-Status "  Exit code: $compileStatus" 'Error'
        exit 1
    }
}

# ============================================================
# 仿真部分
# ============================================================

if ($Run) {
    Write-Section "SIMULATION PHASE"
    
    $vvpOutput = "TB\$($TestName).vvp"
    
    if (-not (Test-Path $vvpOutput)) {
        Write-Status "ERROR: Compiled VVP file not found: $vvpOutput" 'Error'
        Write-Status "Please compile first with -Compile flag" 'Info'
        exit 1
    }
    
    Write-Status "Running simulation: $vvpOutput" 'Info'
    Write-Host ""
    
    $startTime = Get-Date
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    # 运行仿真
    & vvp $vvpOutput 2>&1
    
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    $simStatus = $LASTEXITCODE
    $simTime = (Get-Date) - $startTime
    
    Write-Host ""
    if ($simStatus -eq 0) {
        Write-Status "✓ Simulation completed successfully (${simTime})" 'Success'
    } else {
        Write-Status "⚠ Simulation finished with exit code: $simStatus" 'Warning'
    }
}

# ============================================================
# 波形查看部分
# ============================================================

if ($ViewWave) {
    Write-Section "WAVEFORM VIEWING"
    
    $vcdFile = "TB\$($TestName).vcd"
    
    if (-not (Test-Path $vcdFile)) {
        Write-Status "ERROR: VCD waveform file not found: $vcdFile" 'Error'
        Write-Status "Simulation may have failed or VCD dumping is disabled" 'Info'
        exit 1
    }
    
    Write-Status "Opening waveform with GTKWave: $vcdFile" 'Info'
    
    # 尝试启动 GTKWave
    try {
        Start-Process -FilePath "gtkwave" -ArgumentList $vcdFile -NoNewWindow
        Write-Status "✓ GTKWave launched" 'Success'
    } catch {
        Write-Status "WARNING: Could not launch GTKWave. Please open manually:" 'Warning'
        Write-Status "  gtkwave $vcdFile" 'Info'
    }
}

# ============================================================
# 最终总结
# ============================================================

Write-Section "TEST SUMMARY"

Write-Host "Test Name:   $TestName" -ForegroundColor Gray
Write-Host "Test File:   TB\$($TestName).v" -ForegroundColor Gray
Write-Host "Compiled:    TB\$($TestName).vvp" -ForegroundColor Gray
Write-Host "Waveform:    TB\$($TestName).vcd" -ForegroundColor Gray
Write-Host ""

$testGuidePath = "COMPLEX_TEST_GUIDE.md"
if (Test-Path $testGuidePath) {
    Write-Status "For detailed test information, see: $testGuidePath" 'Info'
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. View waveform:   gtkwave TB\$($TestName).vcd" -ForegroundColor Gray
Write-Host "  2. Check results:   grep -i 'PASS\|FAIL' console output" -ForegroundColor Gray
Write-Host "  3. Analyze logs:    Review simulation console output above" -ForegroundColor Gray
Write-Host ""

Write-Status "✓ Test execution completed" 'Success'
