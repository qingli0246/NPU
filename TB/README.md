# NPU AXI Slave 测试平台总览

## 📋 目录说明

本目录包含 NPU AXI Slave 模块的完整验证环境，包括测试平台、测试用例和相关文档。

```
TB/
├── tb_npu_axi_slave_test.v          # 主测试平台文件
├── README.md                         # 本文档（测试总览）
└── npu_axi_slave_test_output/       # 测试输出目录
    ├── test_log.txt                  # 详细测试日志
    ├── npu_axi_slave_test.vcd        # 波形文件
    └── README.md                     # 详细测试报告（16个测试用例详解）
```

---

## 🎯 测试目标

验证 **NPU AXI Slave** 模块及其配套组件的功能正确性：

### 被测模块
1. **npu_axi_slave**: AXI4/AXI4-Lite 从设备控制器
2. **npu_config**: 配置寄存器管理模块
3. **npu_buffer_mgr**: A/B/C 三端口 Buffer 管理器

### 核心功能验证
- ✅ AXI4-Lite 寄存器读写
- ✅ AXI4 Burst 数据传输
- ✅ 多端口 Buffer 管理
- ✅ 地址解码与边界检查
- ✅ 状态机时序正确性

---

## 🚀 快速开始

### 环境要求
- **仿真器**: Icarus Verilog (iverilog)
- **SystemVerilog 支持**: `-g2012` 选项
- **波形查看器**: GTKWave (可选)

### 编译与运行

```bash
# 进入测试目录
cd TB

# 编译测试平台
iverilog -g2012 -o npu_axi_slave_test.exe \
  -I ../rtl \
  tb_npu_axi_slave_test.v \
  ../rtl/npu_axi_slave.v \
  ../rtl/npu_config.v \
  ../rtl/npu_buffer_mgr.v \
  ../rtl/npu_defs.vh

# 运行仿真
vvp npu_axi_slave_test.exe

# 查看波形（可选）
gtkwave npu_axi_slave_test.vcd
```

### 预期输出
- **控制台**: 显示测试进度和结果摘要
- **日志文件**: `npu_axi_slave_test_output/test_log.txt`
- **波形文件**: `npu_axi_slave_test.vcd`

---

## 📊 测试结果概览

### 总体统计
- **测试用例总数**: 16 个
- **通过数量**: 16 个 ✅
- **失败数量**: 0 个
- **通过率**: 100%
- **仿真时间**: 3395 ns

### 测试分类

| 类别 | 测试编号 | 数量 | 状态 |
|------|---------|------|------|
| 寄存器访问 | 测试 1-6 | 6 | ✅ 全部通过 |
| A Buffer 读写 | 测试 7-8 | 2 | ✅ 全部通过 |
| B Buffer 读写 | 测试 9-10 | 2 | ✅ 全部通过 |
| C Buffer 读写 | 测试 11 | 1 | ✅ 通过 |
| 边界与压力测试 | 测试 12-16 | 5 | ✅ 全部通过 |

---

## 🔍 测试用例详细说明

详细的测试用例说明、操作步骤、验证点和波形分析请参考：

📄 **[npu_axi_slave_test_output/README.md](./npu_axi_slave_test_output/README.md)**

该文档包含：
- 每个测试用例的完整描述
- 地址映射表
- 时序特性分析
- 调试建议
- 覆盖率统计

---

## 🏗️ 架构概览

### 模块层次结构

```
tb_npu_axi_slave_test (测试平台)
    └── dut (npu_axi_slave)
        ├── npu_config (配置寄存器)
        │   ├── REG_CTRL, REG_MODE
        │   ├── REG_M, REG_N, REG_K
        │   ├── REG_IRQ_EN, TILE_MASK, ITERATIONS
        │   └── 状态信号: npu_busy, npu_done, npu_error, npu_irq
        │
        └── npu_buffer_mgr (Buffer管理器)
            ├── A Buffer (0x0100-0x3FFF): 输入矩阵A
            ├── B Buffer (0x4000-0x7FFF): 输入矩阵B
            └── C Buffer (0x8000-0x9FFF): 输出矩阵C
```

### AXI 接口
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
- **axi_rdata 输出**: 组合逻辑直连（消除额外延迟）
- **总延迟**: 从 AR 请求到 R 数据输出约 2 拍

### 4. Burst 传输支持
- 最大支持 256 beats (len=255)
- 自动地址递增（每次 +4 字节）
- rlast 信号正确标记最后一拍

---

## ⚠️ 注意事项

### 时序约束
- **时钟频率**: 测试使用 10ns 周期 (100 MHz)
- **握手时序**: valid/ready 必须遵循 AXI 协议规范
- **数据稳定性**: axi_rdata 在 axi_rvalid 有效期间保持稳定

### 地址对齐
- 所有访问必须是 4 字节对齐
- 非对齐访问可能导致未定义行为

### 复位要求
- 异步低电平复位 (`rst_n`)
- 复位后所有状态机回到 IDLE
- 连续测试之间需确保状态完全清理

---

## 🛠️ 调试技巧

### 波形分析关键点

1. **AXI 握手验证**
   - 观察 `axi_arvalid/axi_arready` 配对
   - 检查 `axi_rvalid/axi_rready` 时序
   - 确认 `axi_awvalid/axi_wvalid/axi_bready` 协调

2. **状态机跟踪**
   - 监控 `r_state` 变化 (R_IDLE → R_WAIT → R_DATA)
   - 验证 `w_state` 状态转换
   - 检查计数器 `r_cnt`, `w_cnt` 递增

3. **Buffer 接口**
   - `buf_rd_en` / `buf_rd_valid` 时序关系
   - `buf_rd_addr` 地址正确性
   - `buf_rd_data` 数据有效性

4. **数据一致性**
   - 对比写入值和读取值
   - 验证 Burst 传输的数据顺序
   - 检查边界地址的数据完整性

### 常见问题排查

| 问题现象 | 可能原因 | 检查点 |
|---------|---------|--------|
| 读取返回全0 | 地址错误或 Buffer 未初始化 | buf_rd_addr, buf_rd_en |
| 读取返回全Z | 端口未赋值或高阻态 | assign 语句, 端口连接 |
| 握手超时 | valid/ready 不匹配 | 状态机卡死, 条件判断错误 |
| 数据错位 | 地址递增错误 | r_addr_inc, w_addr_inc |
| Burst 不完整 | rlast 信号错误 | r_cnt vs r_len 比较 |

---

## 📈 测试覆盖率

### 功能覆盖
- ✅ 寄存器读写: 100% (6/6)
- ✅ 单次读写: 100% (4/4)
- ✅ Burst 写入: 100% (2/2)
- ✅ Burst 读取: 100% (2/2)
- ✅ 地址边界: 100% (2/2)
- ✅ 大 Burst 传输: 100% (1/1)

### 代码覆盖
- **AXI Slave FSM**: 所有状态和转换路径已验证
- **Buffer Manager**: A/B/C 三端口全部测试
- **Config 模块**: 所有寄存器访问路径覆盖

---

## 🔄 版本历史

### v1.0 (2026-05-09)
- ✅ 完成基础功能验证（16个测试用例）
- ✅ 修复 axi_rdata 时序问题（改为组合逻辑输出）
- ✅ 优化 Buffer Manager 读地址保持逻辑
- ✅ 完善测试文档和调试指南

---

## 📚 相关文档

- **详细测试报告**: [npu_axi_slave_test_output/README.md](./npu_axi_slave_test_output/README.md)
- **测试日志**: [npu_axi_slave_test_output/test_log.txt](./npu_axi_slave_test_output/test_log.txt)
- **RTL 源码**: `../rtl/` 目录
- **设计规范**: 参考项目根目录的设计文档

---

## 💡 扩展建议

如需增加新的测试用例，建议：

1. **增量测试策略**: 从小到大逐个添加，每次验证一个功能点
2. **清理旧文件**: 新增测试前清理 `npu_axi_slave_test_output/` 目录
3. **宏控制**: 使用 `ENABLE_TESTx` 宏选择性启用测试
4. **波形保存**: 为关键测试单独保存 VCD 文件便于对比

---

## 📞 技术支持

如有问题或建议，请：
1. 查看详细测试报告了解具体测试步骤
2. 分析波形文件定位时序问题
3. 参考调试技巧章节进行问题排查

---

**最后更新**: 2026-05-09  
**测试状态**: ✅ 全部通过  
**文档版本**: v1.0
