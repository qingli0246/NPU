# NPU 测试平台总览

## 📋 目录说明

本目录包含 NPU 各子模块的完整验证环境，包括测试平台、测试用例和相关文档。

```
TB/
├── tb_npu_axi_slave_test.v          # AXI Slave 测试平台 ✅
├── tb_npu_config_test.v             # Config 模块测试平台 ✅
├── tb_npu_status_test.v             # Status 模块测试平台 ✅
├── tb_npu_data_mover_test.v         # Data Mover 测试平台 ✅
├── README.md                         # 本文档（测试总览）
├── run_tb_npu_data_mover.ps1        # Data Mover 自动化测试脚本
├── run_tb_npu_config.ps1            # Config 自动化测试脚本
└── run_tb_npu_status.ps1            # Status 自动化测试脚本
│
├── npu_axi_slave_test_output/       # AXI Slave 测试输出 ✅
│   ├── test_log.txt                  # 详细测试日志
│   ├── npu_axi_slave_test.vcd        # 波形文件
│   └── README.md                     # 详细测试报告（16个测试用例）
│
├── npu_config_test_output/          # Config 测试输出 ✅
│   ├── test_log.txt                  # 详细测试日志
│   ├── tb_npu_config.vcd             # 波形文件
│   └── README.md                     # 详细测试报告（20个测试用例）
│
├── npu_status_test_output/          # Status 测试输出 ✅
│   ├── test_log.txt                  # 详细测试日志
│   ├── tb_npu_status.vcd             # 波形文件
│   └── README.md                     # 详细测试报告（20个测试用例）
│
└── npu_data_mover_test_output/      # Data Mover 测试输出 ✅
    ├── test_log.txt                  # 详细测试日志
    ├── tb_npu_data_mover_test.vcd    # 波形文件
    └── README.md                     # 详细测试报告（9个测试用例）
```

---

## 🎯 测试目标

验证 NPU 各子模块的功能正确性：

### 已完成测试的模块

#### 1. NPU AXI Slave 模块 ✅
- **被测模块**: `npu_axi_slave`, `npu_config`, `npu_buffer_mgr`
- **测试用例**: 16个
- **通过率**: 100%
- **详细说明**: [npu_axi_slave_test_output/README.md](./npu_axi_slave_test_output/README.md)

#### 2. NPU Config 模块 ✅
- **被测模块**: `npu_config`
- **测试用例**: 20个
- **通过率**: 100%
- **核心功能**: 配置寄存器管理、启动脉冲生成、计算锁定机制
- **详细说明**: [npu_config_test_output/README.md](./npu_config_test_output/README.md)

#### 3. NPU Status 模块 ✅
- **被测模块**: `npu_status` (联合测试 `npu_config`)
- **测试用例**: 20个
- **通过率**: 100%
- **核心功能**: 状态标志管理、中断生成、边沿检测
- **详细说明**: [npu_status_test_output/README.md](./npu_status_test_output/README.md)

#### 4. NPU Data Mover 模块 ✅
- **被测模块**: `npu_data_mover`
- **测试用例**: 9个
- **通过率**: 100%
- **详细说明**: [npu_data_mover_test_output/README.md](./npu_data_mover_test_output/README.md)

### 待测试的模块

#### 5. NPU Scheduler 模块 ⏳
- **状态**: 待创建测试平台

#### 6. NPU Compute Pool 模块 ⏳
- **状态**: 待创建测试平台

#### 7. NPU Tile 控制器 ⏳
- **状态**: 待创建测试平台

---

## 🚀 快速开始

### 环境要求
- **仿真器**: Icarus Verilog (iverilog)
- **SystemVerilog 支持**: `-g2012` 选项
- **波形查看器**: GTKWave (可选)
- **PowerShell**: Windows 10+ 或 PowerShell Core

### 运行测试

#### 方法1: 使用自动化脚本（推荐）

```bash
# 进入测试目录
cd TB

# 运行各个模块的测试
pwsh -ExecutionPolicy Bypass -File .\run_tb_npu_config.ps1
pwsh -ExecutionPolicy Bypass -File .\run_tb_npu_status.ps1
pwsh -ExecutionPolicy Bypass -File .\run_tb_npu_data_mover.ps1
```

#### 方法2: 手动编译运行

```bash
# 编译 Config 测试
iverilog -g2012 -o config_test.exe \
  -I ../rtl \
  tb_npu_config_test.v \
  ../rtl/npu_config.v \
  ../rtl/npu_defs.vh

# 运行仿真
vvp config_test.exe

# 查看波形
gtkwave tb_npu_config.vcd
```

### 预期输出
- **控制台**: 显示测试进度和结果摘要
- **日志文件**: 各模块测试输出目录下的 `test_log.txt`
- **波形文件**: 各模块测试输出目录下的 `.vcd` 文件

---

## 📊 测试结果概览

### 总体统计

| 模块 | 测试用例数 | 通过数 | 失败数 | 通过率 | 状态 |
|------|-----------|--------|--------|--------|------|
| AXI Slave | 16 | 16 | 0 | 100% | ✅ |
| Config | 20 | 20 | 0 | 100% | ✅ |
| Status | 20 | 20 | 0 | 100% | ✅ |
| Data Mover | 9 | 9 | 0 | 100% | ✅ |
| **总计** | **65** | **65** | **0** | **100%** | **✅** |

### 测试分类

#### AXI Slave 测试（16个用例）
- 寄存器访问测试: 6个
- A/B/C Buffer 读写测试: 5个
- 边界与压力测试: 5个

#### Config 测试（20个用例）
- 基础寄存器测试: 8个
- 脉冲生成测试: 4个
- 锁定机制测试: 3个
- 边界条件测试: 3个
- 鲁棒性测试: 2个

#### Status 测试（20个用例）
- 状态标志管理: 5个
- 清除机制: 4个
- 中断系统: 7个
- 边界条件: 3个
- 模块协同: 1个

#### Data Mover 测试（9个用例）
- INDEP 模式测试: 3个
- MERGE 模式测试: 3个
- SPLIT 模式测试: 1个
- 大K值测试: 1个
- 最大Tile数测试: 1个

---

## 🔍 各模块测试详细说明

### 1. AXI Slave 模块测试

**详细说明**: [npu_axi_slave_test_output/README.md](./npu_axi_slave_test_output/README.md)

**核心功能验证**:
- ✅ AXI4-Lite 寄存器读写
- ✅ AXI4 Burst 数据传输
- ✅ 多端口 Buffer 管理
- ✅ 地址解码与边界检查
- ✅ 状态机时序正确性

### 2. Config 模块测试

**详细说明**: [npu_config_test_output/README.md](./npu_config_test_output/README.md)

**核心功能验证**:
- ✅ 默认值初始化与复位恢复
- ✅ 寄存器读写回环验证
- ✅ 启动/清除脉冲生成（单周期宽度）
- ✅ 计算锁定机制（computing=1时保护关键寄存器）
- ✅ 三种工作模式配置（INDEP/MERGE/SPLIT）
- ✅ 位宽截断处理（M/N/K为6位，iterations为4位）
- ✅ 异步复位即时响应
- ✅ 非法地址安全处理
- ✅ 总线毛刺容忍
- ✅ 背靠背连续脉冲生成
- ✅ 只读寄存器写保护

**关键特性**:
- **脉冲生成**: REG_CTRL写入bit0产生cfg_start脉冲，写入bit1产生cfg_status_clr脉冲
- **锁定机制**: computing=1时，REG_M/N/K/MODE被锁定，但REG_TILE_MASK/ITERATIONS/IRQ_EN仍可写
- **位宽截断**: 寄存器存储32位完整值，输出端口截断为指定位宽
- **鲁棒性**: 非法地址访问不影响系统，多周期wr_en毛刺被过滤

### 3. Status 模块测试

**详细说明**: [npu_status_test_output/README.md](./npu_status_test_output/README.md)

**核心功能验证**:
- ✅ 状态标志置位与保持（status_done/status_error）
- ✅ 双标志同时置位
- ✅ 通过REG_CTRL清除状态
- ✅ Done/Error中断生成（边沿敏感）
- ✅ 中断使能控制（irq_en_done/irq_en_error）
- ✅ 中断禁用验证
- ✅ 边沿检测特性（非电平敏感）
- ✅ 多次事件响应与re-trigger能力
- ✅ 异步复位行为
- ✅ 竞态条件处理（status_clr与npu_done同周期）
- ✅ 连续清除幂等性
- ✅ 中断使能动态切换安全性

**关键特性**:
- **置位保持**: 标志一旦置位就保持，直到被清除
- **边沿检测**: 中断在信号上升沿产生，有一个周期的延迟
- **中断使能**: 只有使能后的新边沿才会触发中断，不会retroactively产生
- **模块协同**: 与npu_config联合测试，验证跨模块信号交互

**模块依赖关系**:
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

### 4. Data Mover 模块测试

**详细说明**: [npu_data_mover_test_output/README.md](./npu_data_mover_test_output/README.md)

**核心功能验证**:
- ✅ INDEP 模式：独立处理单个Tile
- ✅ MERGE 模式：合并多个Tile数据
- ✅ SPLIT 模式：拆分大K值矩阵
- ✅ Load/Store 操作时序
- ✅ 最大32个Tile支持
- ✅ 最大K=32支持

---

## 🏗️ 架构概览

### 模块层次结构

```
NPU Top Level
├── npu_axi_slave (AXI接口层) ✅ 已测试
│   ├── npu_config (配置管理) ✅ 已测试
│   └── npu_buffer_mgr (Buffer管理)
│
├── npu_status (状态管理) ✅ 已测试
│   ├── 状态标志 (done/error)
│   └── 中断生成 (npu_irq)
│
├── npu_data_mover (数据搬运) ✅ 已测试
│   ├── Load 引擎 (A/B矩阵读取)
│   └── Store 引擎 (C矩阵写入)
│
├── npu_scheduler (调度器) ⏳ 待测试
├── npu_compute_pool (计算池) ⏳ 待测试
├── npu_tile (Tile控制器) ⏳ 待测试
└── npu_clock_gate (时钟门控) ⏳ 待测试
```

### AXI 接口规范
- **写通道**: AW (地址) + W (数据) → B (响应)
- **读通道**: AR (地址) → R (数据+响应)
- **支持的传输类型**: SINGLE, INCR (Burst)
- **数据宽度**: 32-bit
- **地址宽度**: 32-bit (字节地址)

---

## 📝 关键设计特性

### 1. 三段式状态机设计
- **时序逻辑**: 状态寄存器更新
- **组合逻辑**: 下一状态计算
- **组合逻辑**: 输出信号生成

### 2. 地址解码机制
- 基于地址范围自动选择目标模块
- 支持字节地址到字地址转换 (`addr[31:2]`)
- 严格的边界检查防止越界访问

### 3. Buffer 读取优化
- **BRAM 读延迟**: 1 拍时钟周期
- **握手信号保持**: 在WAIT状态保持读请求有效
- **总延迟**: 从读请求到数据返回约 2 拍

### 4. Burst 传输支持
- 最大支持 256 beats (len=255)
- 自动地址递增（每次 +4 字节）
- rlast 信号正确标记最后一拍

### 5. 配置寄存器管理
- **脉冲生成**: 单周期脉冲用于启动和清除
- **锁定机制**: 计算期间保护关键参数
- **位宽截断**: 寄存器存储完整值，输出截断

### 6. 状态与中断系统
- **置位保持**: 标志一旦置位持续保持
- **边沿检测**: 中断对上升沿敏感
- **使能控制**: 灵活的中断使能配置

---

## ⚠️ 注意事项

### 时序约束
- **时钟频率**: 测试使用 10ns 周期 (100 MHz)
- **握手时序**: valid/ready 必须遵循 AXI 协议规范
- **数据稳定性**: 输出数据在 valid 有效期间保持稳定

### 地址对齐
- 所有访问必须是 4 字节对齐
- 非对齐访问可能导致未定义行为

### 复位要求
- 异步低电平复位 (`rst_n`)
- 复位后所有状态机回到 IDLE
- 连续测试之间需确保状态完全清理

### 边沿检测延迟
- Status模块的中断生成有一个周期延迟
- 这是正常的边沿检测行为，不是bug
- Time=T: 信号变化，Time=T+1: 检测到边沿并产生中断

---

## 🛠️ 调试技巧

### 波形分析关键点

1. **AXI 握手验证**
   - 观察 `axi_arvalid/axi_arready` 配对
   - 检查 `axi_rvalid/axi_rready` 时序
   - 确认 `axi_awvalid/axi_wvalid/axi_bready` 协调

2. **状态机跟踪**
   - 监控状态寄存器变化
   - 验证状态转换条件
   - 检查计数器递增

3. **Buffer 接口**
   - `buf_rd_en` / `buf_rd_valid` 时序关系
   - `buf_rd_addr` 地址正确性
   - `buf_wr_en` / `buf_wr_data` 写入时序

4. **Config 寄存器**
   - 验证脉冲宽度（应为单周期）
   - 检查锁定机制生效时机
   - 观察位宽截断是否正确

5. **Status 中断**
   - 观察边沿检测延迟（1个周期）
   - 验证中断使能控制
   - 检查清除信号的幂等性

6. **数据一致性**
   - 对比写入值和读取值
   - 验证 Burst 传输的数据顺序
   - 检查边界地址的数据完整性

### 常见问题排查

| 问题现象 | 可能原因 | 检查点 |
|---------|---------|--------|
| 读取返回全0 | 地址错误或 Buffer 未初始化 | buf_rd_addr, buf_rd_en |
| 读取返回全Z | 端口未赋值或高阻态 | assign 语句, 端口连接 |
| 握手超时 | valid/ready 不匹配 | 状态机卡死, 条件判断错误 |
| 数据错位 | 地址递增错误 | 地址计算逻辑 |
| 状态机死锁 | WAIT状态信号未保持 | buf_rd_en 在WAIT状态的值 |
| 脉冲宽度异常 | 脉冲生成逻辑错误 | cfg_start/cfg_status_clr持续时间 |
| 中断未产生 | 边沿检测延迟理解错误 | 等待额外1个周期 |
| 锁定失效 | computing信号未正确设置 | 检查锁定条件判断 |

---

## 📈 测试覆盖率

### 功能覆盖
- ✅ AXI Slave: 100% (16/16 用例通过)
- ✅ Config: 100% (20/20 用例通过)
- ✅ Status: 100% (20/20 用例通过)
- ✅ Data Mover: 100% (9/9 用例通过)
- ⏳ Scheduler: 待完善
- ⏳ Compute Pool: 待完善

### 代码覆盖
- **AXI Slave FSM**: 所有状态和转换路径已验证
- **Buffer Manager**: A/B/C 三端口全部测试
- **Config 寄存器**: 所有寄存器访问路径覆盖
- **Status 标志**: 置位/保持/清除全流程验证
- **Data Mover FSM**: INDEP/MERGE/SPLIT 三种模式全覆盖

---

## 🔄 版本历史

### v1.2 (2026-05-10)
- ✅ 新增 Config 模块测试（20个测试用例）
- ✅ 新增 Status 模块测试（20个测试用例）
- ✅ 更新测试总览文档，整合所有模块测试结果
- ✅ 添加模块依赖关系说明

### v1.1 (2026-05-10)
- ✅ 新增 Data Mover 模块测试（9个测试用例）
- ✅ 修复 Data Mover LOAD_WAIT 状态握手时序问题
- ✅ 更新测试总览文档

### v1.0 (2026-05-09)
- ✅ 完成 AXI Slave 基础功能验证（16个测试用例）
- ✅ 修复 axi_rdata 时序问题（改为组合逻辑输出）
- ✅ 优化 Buffer Manager 读地址保持逻辑
- ✅ 完善测试文档和调试指南

---

## 📚 相关文档

- **AXI Slave 详细报告**: [npu_axi_slave_test_output/README.md](./npu_axi_slave_test_output/README.md)
- **Config 详细报告**: [npu_config_test_output/README.md](./npu_config_test_output/README.md)
- **Status 详细报告**: [npu_status_test_output/README.md](./npu_status_test_output/README.md)
- **Data Mover 详细报告**: [npu_data_mover_test_output/README.md](./npu_data_mover_test_output/README.md)
- **RTL 源码**: `../rtl/` 目录
- **设计规范**: 参考项目根目录的设计文档

---

## 💡 扩展建议

如需增加新的测试用例，建议：

1. **增量测试策略**: 从小到大逐个添加，每次验证一个功能点
2. **清理旧文件**: 新增测试前清理对应输出目录
3. **宏控制**: 使用 `ENABLE_TESTx` 宏选择性启用测试
4. **波形保存**: 为关键测试单独保存 VCD 文件便于对比
5. **自动化脚本**: 为新模块创建类似的 PowerShell 测试脚本
6. **联合测试**: 考虑创建模块间的集成测试（如Config+Status已实现）

---

## 📞 技术支持

如有问题或建议，请：
1. 查看详细测试报告了解具体测试步骤
2. 分析波形文件定位时序问题
3. 参考调试技巧章节进行问题排查
4. 特别注意边沿检测的1周期延迟特性

---

**最后更新**: 2026-05-10  
**测试状态**: ✅ 65/65 全部通过  
**文档版本**: v1.2