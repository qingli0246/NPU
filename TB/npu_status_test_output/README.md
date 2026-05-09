# NPU Status模块测试

## 概述
本目录包含用于测试 `npu_status.v` 模块的测试平台和脚本。该测试联合了 `npu_config` 模块，因为 `npu_status` 依赖 config 提供的控制信号（`status_clr`、`irq_en_done`、`irq_en_error`）。

## 文件说明
- **tb_npu_status_test.v**: Verilog测试平台，包含20个综合测试用例
- **run_tb_npu_status.ps1**: 编译和运行测试的PowerShell脚本
- **npu_status_test_output/**: 生成文件的目录
  - `tb_npu_status`: 编译后的仿真可执行文件
  - `test_log.txt`: 完整的测试执行日志
  - `README.md`: 测试文档（本文件）

## 被测模块功能
`npu_status` 模块负责：
- **状态标志管理**：维护 `status_done` 和 `status_error` 标志
- **置位保持机制**：标志一旦置位就保持，直到被清除
- **清除控制**：通过 `status_clr` 信号清除标志
- **中断生成**：基于使能和边沿检测生成 `npu_irq` 中断
- **异步复位**：支持异步复位将所有状态清零

## 模块依赖关系
```
npu_config (提供控制信号)
    ↓ cfg_status_clr → status_clr
    ↓ irq_en_done → irq_en_done
    ↓ irq_en_error → irq_en_error
    
npu_status (被测模块)
    ← npu_done, npu_error (外部输入)
    → status_done, status_error (输出到config)
    → npu_irq (中断输出)
```

## 测试用例

### 测试1：复位后默认值检查
验证所有状态在复位后为0：
- `status_done = 0`
- `status_error = 0`
- `npu_irq = 0`
- REG_STATUS读取值为0x00000000

### 测试2：Done标志置位与保持
验证done标志的行为：
- 施加单周期 `npu_done` 脉冲
- 下一周期 `status_done` 置位为1
- 持续多个周期验证标志保持特性
- REG_STATUS正确反映done状态

### 测试3：Error标志置位与保持
验证error标志的行为：
- 先清除done标志
- 施加单周期 `npu_error` 脉冲
- 验证 `status_error` 置位并保持
- REG_STATUS正确反映error状态

### 测试4：双标志同时置位
验证done和error可以同时存在：
- 清除两个标志
- 同时施加 `npu_done` 和 `npu_error` 脉冲
- 验证两个标志都置位
- REG_STATUS = 0x00000003（bit0=done, bit1=error）

### 测试5：通过REG_CTRL清除状态
验证清除机制：
- 设置两个标志
- 写入 REG_CTRL bit1=1 产生 `status_clr` 脉冲
- 验证两个标志都被清除
- REG_STATUS恢复为0

### 测试6：仅Done中断生成
验证done中断的触发条件：
- 使能done中断（IRQ_EN bit0=1）
- 触发 `npu_done` 脉冲
- 验证 `npu_irq` 在上升沿产生单周期脉冲
- 验证中断自动返回0

### 测试7：仅Error中断生成
验证error中断的触发条件：
- 清除状态
- 使能error中断（IRQ_EN bit1=1）
- 触发 `npu_error` 脉冲
- 验证 `npu_irq` 正确生成

### 测试8：双中断使能
验证两个中断都可以工作时：
- 使能done和error中断（IRQ_EN=0x03）
- 依次触发done和error事件
- 验证每次都能生成对应的中断

### 测试9：中断禁用时不触发
验证中断使能控制的有效性：
- 禁用所有中断（IRQ_EN=0x00）
- 触发done和error事件
- 验证 `npu_irq` 始终为0

### 测试10：边沿检测 - 无重复触发
验证中断是边沿敏感而非电平敏感：
- 使能done中断
- 将 `npu_done` 持续拉高多个周期
- 第一个上升沿产生中断
- 后续周期（信号仍为高）不产生中断
- 证明是边沿检测而非电平检测

**关键时序说明**：
- 边沿检测需要一个周期的延迟来比较前后值
- Time=T: `npu_done` 从0变1，但中断还未产生
- Time=T+1: 检测到上升沿，`npu_irq=1`
- Time=T+2: 信号仍为高，但无新边沿，`npu_irq=0`

### 测试11：多次Done脉冲
验证连续事件的响应：
- 使能done中断
- 生成3次独立的 `npu_done` 脉冲
- 验证每次脉冲都产生对应的中断
- 验证脉冲间隔期间中断正确返回0

### 测试12：状态寄存器动态更新
验证REG_STATUS实时反映状态变化：
- 清除状态
- 设置done → 读取REG_STATUS=0x01
- 再设置error → 读取REG_STATUS=0x03
- 清除后只设置error → 读取REG_STATUS=0x02
- 验证寄存器值随状态动态变化

### 测试13：异步复位行为
验证异步复位的即时响应：
- 设置done和error标志
- 拉低 `rst_n`（不等待时钟边沿）
- 立即检查所有标志清零
- 释放复位后验证标志保持为0

### 测试14：中断re-trigger测试
验证清除后重新触发中断的能力：
- 使能done中断
- 触发 `npu_done`，生成第一次中断
- 通过 REG_CTRL 清除状态
- 再次触发 `npu_done`
- 验证第二次中断正确生成
- **关键发现**：支持多次独立的中断事件

### 测试15：连续error脉冲边沿触发验证
验证error信号的边沿检测特性：
- 使能error中断
- 连续施加多个 `npu_error` 脉冲
- 验证每个脉冲都产生对应的中断
- 验证脉冲间隔期间中断正确返回0
- 确认与done脉冲行为一致
- **关键发现**：error中断也是边沿敏感

### 测试16：事件发生后再使能中断
验证中断使能的时序要求：
- 先触发 `npu_done` 事件（此时中断禁用）
- 验证无中断产生
- 随后使能done中断
- 验证不会 retroactively 产生中断
- **关键发现**：中断只在使能后的新边沿触发

### 测试17：REG_CTRL=0x03同时start+clear验证
验证配置模块与状态模块的协同工作：
- 写入 REG_CTRL=0x03
- 验证 `cfg_start` 脉冲生成
- 验证 `cfg_status_clr` 脉冲生成
- 验证两个脉冲同时有效
- 验证下一周期都返回0
- **关键发现**：双脉冲机制正常工作

### 测试18：竞态条件 - status_clr与npu_done同周期
验证清除信号与事件信号同时到达的行为：
- 在同一周期施加 `status_clr=1` 和 `npu_done=1`
- 观察 `status_done` 的最终值
- 验证无 X/Z 不定态出现
- 验证信号值确定且有效
- **关键发现**：优先级逻辑清晰，无竞争冒险

### 测试19：连续status_clr脉冲幂等性
验证重复清除操作的安全性：
- 设置done和error标志
- 连续施加多个 `status_clr` 脉冲
- 验证第一次清除后状态归零
- 验证后续清除不产生副作用
- 验证系统保持稳定
- **关键发现**：清除操作具有幂等性

### 测试20：中断使能在事件期间切换
验证中断使能动态变化的安全性：
- 触发 `npu_done` 事件
- 在事件持续期间切换 `irq_en_done`
- 验证 `npu_irq` 输出无毛刺
- 验证状态转换平滑
- 验证最终状态有效且确定
- **关键发现**：使能切换不会引入瞬态错误

## 如何运行

### 前置条件
- 已安装Icarus Verilog并添加到PATH
- 可用的PowerShell环境

### 执行命令
``powershell
cd TB
.\run_tb_npu_status.ps1
```

脚本将执行以下操作：
1. 使用 `iverilog` 编译测试平台（同时编译npu_status和npu_config）
2. 使用 `vvp` 运行仿真
3. 将所有输出保存到 `npu_status_test_output/test_log.txt`
4. 在终端中显示结果，带有颜色编码的通过/失败指示

## 预期结果
所有20个测试应该通过，显示消息：
```
结果: 所有测试通过 ✓
```

## 注意事项
- 测试平台联合实例化了 `npu_config` 和 `npu_status` 两个模块
- `computing` 信号固定为0，不测试锁定功能
- 边沿检测有一个周期的延迟，这是正常的设计行为
- 所有测试都在约2.0微秒内完成（随测试用例增加略有延长）

## 测试覆盖的功能点

### 状态标志管理
- ✅ 默认值初始化
- ✅ Done标志置位与保持
- ✅ Error标志置位与保持
- ✅ 双标志同时置位
- ✅ 动态状态更新

### 清除机制
- ✅ 通过REG_CTRL清除
- ✅ status_clr脉冲生成
- ✅ 清除后状态归零
- ✅ 连续清除幂等性
- ✅ 竞态条件处理

### 中断系统
- ✅ Done中断生成
- ✅ Error中断生成
- ✅ 双中断使能
- ✅ 中断禁用验证
- ✅ 边沿检测（非电平敏感）
- ✅ 单周期脉冲特性
- ✅ 多次事件响应
- ✅ 中断re-trigger能力
- ✅ 使能时序要求
- ✅ 使能动态切换安全性

### 边界条件
- ✅ 异步复位
- ✅ 边沿检测延迟
- ✅ 连续脉冲处理
- ✅ 同周期信号竞争
- ✅ 无X/Z不定态

### 模块协同
- ✅ REG_CTRL双脉冲生成
- ✅ config与status信号交互
- ✅ 跨模块时序协调

## 测试输出说明

### 终端显示
- 实时显示仿真进度
- 使用颜色区分不同类型消息：
  - 青色：标题和总结
  - 黄色：信息和警告
  - 绿色：成功消息
  - 红色：错误消息
  - 灰色：辅助信息
- 保留原始换行格式，便于阅读
- 监控信号：`npu_done`, `npu_error`, `status_done`, `status_error`, `npu_irq`, `cfg_status_clr`

### 日志文件
- 位置：`npu_status_test_output/test_log.txt`
- 包含完整的仿真输出（带换行符）
- 包含测试时间戳和持续时间
- 可用于后续分析和归档

## 常见问题

### Q1: 编译失败
**原因**: Icarus Verilog未安装或不在PATH中  
**解决**: 安装Icarus Verilog并确保`iverilog`和`vvp`命令可用

### Q2: TEST 10边沿检测失败
**可能原因**: 不理解边沿检测需要延迟一个周期  
**解释**: 
- 边沿检测器使用前一个周期的值和当前值比较
- 第一个周期捕获当前值，第二个周期才检测到变化
- 这是正确的设计，不是bug

### Q3: 中断没有立即产生
**原因**: 边沿检测的固有延迟  
**解决**: 理解中断会在信号变化的第二个周期产生，而不是第一个

### Q4: 状态标志没有清除
**可能原因**: 
- `status_clr` 脉冲宽度不够
- REG_CTRL写入时机不对

**解决**: 确保写入REG_CTRL bit1=1后等待至少1个周期