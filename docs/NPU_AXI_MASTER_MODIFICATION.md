# NPU 增加 AXI4 Master 接口修改方案

## 一、问题分析

PicoRV32 CPU 仅提供 **AXI4-Lite Master** 接口（单拍传输），当前 NPU 只有 AXI Slave 接口，导致：
- CPU 每次只能写 1 个 32bit，传输效率极低
- 总线带宽利用率无法满足赛题≥60%的要求

**解决方案**：NPU 增加 AXI4 Master 接口，主动从共享 BRAM DMA 读取数据到内部 Buffer。

---

## 二、架构设计

### 2.1 核心原则

**禁止将串行 AXI Master 直接连接并行 Tile。** 必须通过内部 Buffer 实现串并转换：

```
共享 BRAM → AXI Master (Burst读) → 内部 A/B Buffer → Tile Pool (并行计算)
                                              ↓
内部 C Buffer ← 结果收集 ← Tile Pool
     ↓
AXI Master (Burst写) → 共享 BRAM
```

### 2.2 接口定义

NPU 顶层拥有两组 AXI 接口：

| 接口 | 协议 | 用途 |
|------|------|------|
| `s_axi_*` | AXI4-Lite Slave | CPU 配置寄存器、读状态 |
| `m_axi_*` | AXI4 Full Master | NPU DMA 读写外部 BRAM |



## 三、模块修改清单

### 3.1 新增：npu_axi_master.v

将内部 DMA 请求转换为 AXI4 Master 协议事务，支持 INCR Burst 传输。

**关键功能**：
- 读写通道独立 FSM
- 自动处理 `wlast`/`rlast` 生成
- 握手协议完整实现

### 3.2 修改：npu_data_mover.v

**接口变更**：
```verilog
// DMA 读接口（从外部 BRAM 读取数据）
output reg                    dma_rd_req,
output reg  [31:0]            dma_rd_addr,
output reg  [7:0]             dma_rd_len,
input  wire [31:0]            dma_rd_data,
input  wire                   dma_rd_valid,
input  wire                   dma_rd_done,

// DMA 写接口（向外部 BRAM 发送 C 结果数据）
output reg                    dma_wr_req,
output reg  [31:0]            dma_wr_addr,
output reg  [7:0]             dma_wr_len,
output reg  [31:0]            dma_wr_data,
output reg                    dma_wr_valid,
input  wire                   dma_wr_ready,
input  wire                   dma_wr_done,
```

**状态机调整**：
- `S_LOAD_A/B`：发起 DMA 读请求 → 等待 `dma_rd_done` → 数据存入内部 Buffer
- `S_STORE`：发起 DMA 写请求 → 等待 `dma_wr_done`

### 3.3 修改：npu_buffer_mgr.v

**保留内部 A/B/C Buffer**（串并转换必需），Port B 角色调整：

| Buffer | Port A | Port B |
|--------|--------|--------|
| A_Buffer | AXI 读（调试） | **DMA 写 + Mover 读** |
| B_Buffer | AXI 读（调试） | **DMA 写 + Mover 读** |
| C_Buffer | AXI 读（CPU 取结果） | **Mover 写 + DMA 读** |

**容量验证**：
- 单 Tile A 矩阵 = 8行 × 64列 × 1字节 = 512 字节（K=64）
- 32 Tile 总计 = 32 × 512 = **16KB**
- 当前 `NPU_A_BUFFER_SIZE = 16KB` ✅ **刚好够用**

### 3.4 修改：npu_config.v

**新增寄存器**（避开现有 `REG_IRQ_EN = 0x20`）：

| 地址 | 名称 | 描述 |
|------|------|------|
| 0x24 | REG_A_BASE_ADDR | A 矩阵在共享 BRAM 的基地址 |
| 0x28 | REG_B_BASE_ADDR | B 矩阵在共享 BRAM 的基地址 |
| 0x2C | REG_C_BASE_ADDR | C 结果写回 BRAM 的基地址 |
| 0x30 | REG_DMA_CTRL | DMA 控制（bit0:启动, bit1:busy, bit2:error） |

### 3.5 修改：npu_top.v


## 四、软件工作流程

```
// 1. 在共享 BRAM 准备数据
uint8_t A[8][64];  // 地址 0x1000_1000
uint8_t B[64][8];  // 地址 0x1000_4000

// 2. 配置 NPU 参数
NPU_WRITE(REG_MODE,      MODE_INDEP);
NPU_WRITE(REG_M,         8);
NPU_WRITE(REG_N,         8);
NPU_WRITE(REG_K,         64);
NPU_WRITE(REG_TILE_MASK, 0xFFFFFFFF);

// 3. 配置 DMA 地址
NPU_WRITE(REG_A_BASE_ADDR, 0x1000_1000);
NPU_WRITE(REG_B_BASE_ADDR, 0x1000_4000);
NPU_WRITE(REG_C_BASE_ADDR, 0x1000_8000);

// 4. 启动 NPU
NPU_WRITE(REG_CTRL, START_BIT);

// 5. NPU 自动执行：
//    DMA读A → A_Buffer → Tile分发 → 计算 → C_Buffer → DMA写C

// 6. 等待完成
while (!(NPU_READ(REG_STATUS) & DONE_BIT));

// 7. 读取结果
int32_t result = *(volatile int32_t*)0x1000_8000;
```

---

## 五、验证要点

| 测试项 | 方法 | 预期 |
|--------|------|------|
| AXI4 Burst 读写 | DMA 传输已知数据，校验内容 | 数据一致 |
| 串并转换 | 监控 Buffer 写入过程 | 对齐且完整 |
| 带宽利用率 | 测量有效数据占比 | ≥60% |
| 并发访问 | CPU 读 BRAM 同时 NPU DMA 写 | 无冲突 |
| 端到端计算 | 对比硬件输出与软件参考值 | 完全一致 |
| 32-Tile 并行 | 启用全部 Tile 验证分发 | 所有 Tile 数据正确 |

---

## 六、涉及文件

| 文件 | 操作 |
|------|------|
| `rtl/npu_axi_master.v` | **新增** |
| `rtl/npu_top.v` | **修改**（增加 m_axi 端口） |
| `rtl/npu_data_mover.v` | **修改**（接口改为 dma_rd/wr） |
| `rtl/npu_buffer_mgr.v` | **修改**（Port B 角色调整） |
| `rtl/npu_config.v` | **修改**（新增 4 个寄存器） |
| `rtl/npu_defs.vh` | **修改**（新增地址定义） |

---

## 七、实施注意事项

1. **AXI Interconnect 仲裁**：共享 BRAM 需支持 CPU 和 NPU 并发访问，配置 Round-Robin 策略
2. **DMA 同步**：确保 `dma_rd_done` 后才启动 Tile 分发
3. **测试平台**：新增共享 BRAM 模型，支持双协议访问和仲裁逻辑
