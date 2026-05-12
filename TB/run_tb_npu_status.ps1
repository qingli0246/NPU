# ============================================================
#  NPU Status模块测试脚本
#  测试 npu_status 模块（联合npu_config）并保存结果到日志文件
# ============================================================

# 设置错误处理
$ErrorActionPreference = "Continue"

# 定义路径
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RTL_Dir = Join-Path $ScriptDir "..\rtl"
$TestFile = Join-Path $ScriptDir "tb_npu_status_test.v"
$OutputDir = Join-Path $ScriptDir "npu_status_test_output"
$LogFile = Join-Path $OutputDir "test_log.txt"

# 如果输出目录不存在则创建
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
    Write-Host "[信息] 已创建输出目录: $OutputDir" -ForegroundColor Green
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  NPU Status模块测试运行器" -ForegroundColor Cyan
Write-Host "  (联合npu_config测试)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查测试文件是否存在
if (-not (Test-Path $TestFile)) {
    Write-Host "[错误] 未找到测试文件: $TestFile" -ForegroundColor Red
    exit 1
}

# 检查Icarus Verilog是否可用
$iverilog_cmd = Get-Command "iverilog" -ErrorAction SilentlyContinue
$vvp_cmd = Get-Command "vvp" -ErrorAction SilentlyContinue

if (-not $iverilog_cmd -or -not $vvp_cmd) {
    Write-Host "[错误] 未找到Icarus Verilog。请先安装。" -ForegroundColor Red
    Write-Host "下载地址: http://iverilog.icarus.com/" -ForegroundColor Yellow
    exit 1
}

Write-Host "[信息] 开始编译..." -ForegroundColor Yellow
Write-Host "[信息] 测试文件: $TestFile" -ForegroundColor Gray
Write-Host "[信息] 输出目录: $OutputDir" -ForegroundColor Gray
Write-Host ""

# 使用Icarus Verilog编译测试平台
$compile_args = @(
    "-o", (Join-Path $OutputDir "tb_npu_status"),
    "-I", $RTL_Dir,
    $TestFile,
    (Join-Path $RTL_Dir "npu_status.v"),
    (Join-Path $RTL_Dir "npu_config.v")
)

$compile_output = & iverilog $compile_args 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 编译失败！" -ForegroundColor Red
    Write-Host $compile_output -ForegroundColor Red
    
    # 保存错误日志
    $compile_output | Out-File -FilePath $LogFile -Encoding UTF8
    Write-Host "[信息] 错误日志已保存到: $LogFile" -ForegroundColor Yellow
    exit 1
}

Write-Host "[成功] 编译完成！" -ForegroundColor Green
Write-Host ""

# 运行仿真
Write-Host "[信息] 开始仿真..." -ForegroundColor Yellow
Write-Host "[信息] 这可能需要几秒钟..." -ForegroundColor Gray
Write-Host ""

# 捕获仿真输出（直接写入文件）
$simulation_start = Get-Date
$simulation_exe = Join-Path $OutputDir "tb_npu_status"

# 创建临时文件来捕获输出
$TempOutputFile = Join-Path $OutputDir "temp_simulation_output.txt"
$TempErrorFile = Join-Path $OutputDir "temp_simulation_error.txt"

# 运行仿真并将输出重定向到临时文件
Start-Process -FilePath "vvp" -ArgumentList $simulation_exe -Wait -NoNewWindow -RedirectStandardOutput $TempOutputFile -RedirectStandardError $TempErrorFile

$simulation_end = Get-Date
$simulation_duration = ($simulation_end - $simulation_start).TotalSeconds

# 读取仿真输出（合并stdout和stderr）
$output_content = ""
if (Test-Path $TempOutputFile) {
    $output_content = Get-Content $TempOutputFile -Raw -Encoding UTF8
}
if (Test-Path $TempErrorFile) {
    $error_content = Get-Content $TempErrorFile -Raw -Encoding UTF8
    if ($error_content) {
        $output_content += "`n" + $error_content
    }
}
$simulation_output = $output_content

# 在终端显示仿真输出
Write-Host $simulation_output

# 保存日志文件
$log_content = @"
========================================
NPU Status模块测试日志
(联合npu_config测试)
========================================
测试时间: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
持续时间: ${simulation_duration} 秒
========================================

$simulation_output

========================================
测试日志结束
========================================
"@

$log_content | Out-File -FilePath $LogFile -Encoding UTF8

# 删除临时文件
if (Test-Path $TempOutputFile) {
    Remove-Item $TempOutputFile -Force
}
if (Test-Path $TempErrorFile) {
    Remove-Item $TempErrorFile -Force
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  测试执行完成" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[信息] 持续时间: ${simulation_duration} 秒" -ForegroundColor Gray
Write-Host "[信息] 日志文件已保存到: $LogFile" -ForegroundColor Green

# 检查日志中是否包含失败
if ($simulation_output -match "\[FAIL\]") {
    Write-Host "[警告] 检测到测试失败。请检查日志文件。" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "[成功] 所有测试通过！" -ForegroundColor Green
    exit 0
}