# NPU Simulation Script
# Usage: .\run_sim.ps1 [test_name]
# Example: .\run_sim.ps1 burst_simple
#          .\run_sim.ps1 burst_test
#          .\run_sim.ps1 npu_32tile_test

param(
    [string]$TestName = "burst_simple"
)

# Set encoding to UTF-8 for Chinese characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

# Set paths
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TBDir = Join-Path $ProjectRoot "TB"
$RTLDir = Join-Path $ProjectRoot "rtl"
$OutputDir = Join-Path $TBDir "output"

# Create output directory if not exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   NPU Simulation Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Test Name: $TestName" -ForegroundColor Yellow
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Yellow
Write-Host ""

# Check if test file exists
$TestFile = Join-Path $TBDir "tb_$TestName.v"
if (-not (Test-Path $TestFile)) {
    Write-Host "ERROR: Test file not found: $TestFile" -ForegroundColor Red
    exit 1
}

# Get all RTL files
$RTLFiles = Get-ChildItem -Path $RTLDir -Filter "*.v" | ForEach-Object { $_.FullName }
$RTLFiles += Get-ChildItem -Path $RTLDir -Filter "*.vh" | ForEach-Object { $_.FullName }

Write-Host "RTL Files:" -ForegroundColor Green
foreach ($file in $RTLFiles) {
    Write-Host "  - $(Split-Path $file -Leaf)" -ForegroundColor Gray
}
Write-Host ""

# Step 1: Compile
Write-Host "[Step 1/3] Compiling..." -ForegroundColor Yellow
$CompileCmd = "iverilog -o `"$OutputDir\$TestName`" -I`"$RTLDir`" `"$TestFile`" $($RTLFiles -join ' ')"
Write-Host "Command: $CompileCmd" -ForegroundColor Gray

try {
    Invoke-Expression $CompileCmd
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed"
    }
    Write-Host "Compilation successful!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Compilation failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 2: Run simulation
Write-Host "[Step 2/3] Running simulation..." -ForegroundColor Yellow
$RunCmd = "vvp `"$OutputDir\$TestName`""
Write-Host "Command: $RunCmd" -ForegroundColor Gray

Push-Location $TBDir
try {
    Invoke-Expression $RunCmd
    if ($LASTEXITCODE -ne 0) {
        throw "Simulation failed"
    }
    Write-Host ""
    Write-Host "Simulation completed!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Simulation failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host ""

# Step 3: Check waveform
$VCDFile = Join-Path $TBDir "$TestName.vcd"
if (Test-Path $VCDFile) {
    Write-Host "[Step 3/3] Waveform generated:" -ForegroundColor Yellow
    Write-Host "  $VCDFile" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Open with GTKWave: gtkwave `"$VCDFile`"" -ForegroundColor Gray
} else {
    Write-Host "[Step 3/3] No waveform file generated" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Done!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
