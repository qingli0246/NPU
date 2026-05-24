# ============================================================
# NPU MERGE模式测试运行脚本
# 测试完整 NPU 系统（MERGE工作模式）
# ============================================================

$ErrorActionPreference = "Stop"

# 设置控制台编码为 UTF-8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 配置路径
$TEST_FILE = "F:\complication-6\NPU\TB\tb_npu_merge_mode_test.v"
$OUTPUT_DIR = "F:\complication-6\NPU\TB\npu_merge_mode_test_output"
$RTL_DIR = "F:\complication-6\NPU\rtl"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  NPU MERGE模式测试运行器" -ForegroundColor Cyan
Write-Host "  测试: AXI Slave + Config + Status + Buffer Manager" -ForegroundColor Cyan
Write-Host "        + Scheduler + Data Mover + Compute Pool" -ForegroundColor Cyan
Write-Host "        + MERGE工作模式验证" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 创建输出目录
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null
    Write-Host "[信息] 创建输出目录: $OUTPUT_DIR" -ForegroundColor Green
}

Write-Host "[信息] 开始编译..." -ForegroundColor Yellow
Write-Host "[信息] 测试文件: $TEST_FILE" -ForegroundColor Gray
Write-Host "[信息] 输出目录: $OUTPUT_DIR" -ForegroundColor Gray
Write-Host ""

# 编译命令 - 需要包含所有 RTL 文件
$compile_args = @(
    "-g2012",
    "-pfileline=1",  # 启用零延迟振荡检测，打印行号
    "-o", "$OUTPUT_DIR\tb_npu_merge_mode.exe",
    "-I", "$RTL_DIR",
    "$TEST_FILE",
    "$RTL_DIR\npu_top.v",
    "$RTL_DIR\npu_axi_slave.v",
    "$RTL_DIR\npu_axi_master.v",
    "$RTL_DIR\npu_config.v",
    "$RTL_DIR\npu_status.v",
    "$RTL_DIR\npu_buffer_mgr.v",
    "$RTL_DIR\npu_scheduler.v",
    "$RTL_DIR\npu_data_mover.v",
    "$RTL_DIR\npu_compute_pool.v",
    "$RTL_DIR\npu_tile.v",
    "$RTL_DIR\npu_clock_gate.v",
    "$RTL_DIR\npu_defs.vh"
)

try {
    # 执行编译
    Write-Host "[信息] 编译命令:" -ForegroundColor Gray
    Write-Host "iverilog $($compile_args -join ' ')" -ForegroundColor DarkGray
    Write-Host ""

    & iverilog @compile_args 2>&1 | Tee-Object -FilePath "$OUTPUT_DIR\compile_log.txt" -Append

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 编译失败！" -ForegroundColor Red
        Get-Content "$OUTPUT_DIR\compile_log.txt" | Write-Host -ForegroundColor Red

        # 保存错误日志
        Write-Host "[信息] 错误日志已保存到: $OUTPUT_DIR\compile_log.txt" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "[成功] 编译完成" -ForegroundColor Green
    Write-Host ""

    # 运行仿真
    Write-Host "[信息] 开始仿真..." -ForegroundColor Yellow
    Write-Host ""

    # 清空旧日志文件
    if (Test-Path "$OUTPUT_DIR\test_log.txt") {
        Clear-Content "$OUTPUT_DIR\test_log.txt"
    }

    # 【关键修复】设置环境变量强制vvp使用UTF-8输出
    $env:LANG = "en_US.UTF-8"
    $env:LC_ALL = "en_US.UTF-8"
    
    # 执行仿真
    $process = Start-Process -FilePath "vvp" -ArgumentList "`"$OUTPUT_DIR\tb_npu_merge_mode.exe`"" -RedirectStandardOutput "$OUTPUT_DIR\test_log.txt" -PassThru -NoNewWindow -Wait

    # 等待进程结束
    $process.WaitForExit()

    # 显示日志文件内容
    Write-Host "[信息] 仿真输出：" -ForegroundColor Gray
    Write-Host "----------------------------------------" -ForegroundColor Gray

    Get-Content "$OUTPUT_DIR\test_log.txt" -Encoding UTF8 | ForEach-Object {
        Write-Host $_ -ForegroundColor White
    }

    # 获取退出码
    $exit_code = $LASTEXITCODE

    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[成功] 仿真完成" -ForegroundColor Green
    Write-Host "[信息] 测试日志已保存到: $OUTPUT_DIR\test_log.txt" -ForegroundColor Yellow

    # 移动波形文件到输出目录
    $vcd_file = "npu_merge_mode_test.vcd"
    if (Test-Path $vcd_file) {
        Move-Item -Path $vcd_file -Destination "$OUTPUT_DIR\$vcd_file" -Force
        Write-Host "[成功] 波形文件已移动到: $OUTPUT_DIR\$vcd_file" -ForegroundColor Green
    } else {
        Write-Host "[警告] 未找到波形文件: $vcd_file" -ForegroundColor Yellow
    }

    Write-Host ""

    # 检查测试结果
    $log_content = Get-Content "$OUTPUT_DIR\test_log.txt" -Raw -Encoding UTF8
    if ($log_content -match "\[FAIL\]") {
        Write-Host "[警告] 检测到测试失败，请查看日志详情" -ForegroundColor Red
        exit 1
    } elseif ($exit_code -ne 0) {
        Write-Host "[错误] 仿真执行失败（退出码: $exit_code）" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "[成功] 所有测试通过！" -ForegroundColor Green
    }

} catch {
    Write-Host "[错误] 执行失败: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  MERGE模式测试运行结束" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan