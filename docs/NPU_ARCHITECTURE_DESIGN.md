# NPU系统架构设计文档

## 一、系统概述

### 1.1 设计目标
- **计算单元**：32个8×8 Tile，每个Tile支持8-bit矩阵乘法
- **数据流**：CPU通过AXI总线推送数据到NPU（零拷贝）
- **工作模式**：支持INDEP/MERGE/SPLIT三种模式
- **性能目标**：最大化计算单元利用率，最小化数据传输延迟

### 1.2 核心架构原则
```
┌─────────────┐         AXI总线          ┌──────────────┐
│   CPU       │  ←────────────────────→  │   NPU        │
│  (Master)   │  AXI-Lite + AXI4 Burst   │  (Slave)     │
└─────────────┘                           └──────────────┘
     ↓                                            ↓
  准备数据                                  接收数据到内部Buffer
  配置寄存器                                执行矩阵乘法
  启动计算                                  返回结果
```

---

## 二、商业NPU最佳实践调研

### 2.1 数据传输策略

#### **方案对比**

| 方案 | 优点 | 缺点 | 商业案例 |
|------|------|------|----------|
| **分离传输A/B** | 清晰的数据边界，易于调试和管理 | 需要两次Burst传输 | AMD Xilinx AI Engine |
| **合并传输A+B** | 减少AXI事务开销，理论速度更快 | 地址映射复杂，难以独立管理 | NVIDIA Tensor Core |
| **交错传输** | 可重叠Load和Compute | 控制逻辑复杂 | Huawei Ascend |

#### **推荐方案：分离传输**
**理由：**
1. **清晰的时序边界**：A矩阵先传，B矩阵后传，便于验证数据完整性
2. **灵活的Buffer管理**：可以单独更新A或B（如推理时B权重不变）
3. **符合赛题"零拷贝"要求**：CPU直接写到NPU指定地址空间
4. **工业界主流做法**：AMD/Intel/Huawei均采用分离传输

### 2.2 计算启动机制

#### **方案对比**

| 方案 | 优点 | 缺点 | 商业案例 |
|------|------|------|----------|
| **显式启动命令** | 清晰的时序，支持预加载延迟执行 | 多一次AXI-Lite写操作 | AMD Xilinx, Intel Movidius |
| **自动检测B完成** | 减少CPU干预 | 难以区分"加载中"和"已就绪" | 少数嵌入式加速器 |
| **隐式启动** | 最简单 | 无法控制执行时机 | 不推荐 |

#### **推荐方案：显式启动命令**
**理由：**
1. **明确的时序控制**：CPU完全掌控执行流程
2. **支持数据预加载**：可以提前加载B权重，多次复用
3. **便于调试和验证**：每个阶段有明确的触发点
4. **工业标准做法**：几乎所有商业NPU都采用此方案

**典型流程：**
```
1. AXI-Lite: 配置M/N/K/Mode等参数
2. AXI-Burst: 传输A矩阵数据 → NPU A_Buffer
3. AXI-Burst: 传输B矩阵数据 → NPU B_Buffer
4. AXI-Lite: 写入reg_ctrl.start=1 → 启动计算
5. NPU: 从Buffer读取数据 → Tile计算 → 写入C_Buffer
6. AXI-Burst: CPU读取C_Buffer → 获取结果
```

---

## 三、Buffer容量设计

### 3.1 单Tile需求分析

**假设条件：**
- Tile尺寸：8×8
- 数据精度：INT8（1字节）
- 累加精度：INT32（4字节）
- 最大矩阵维度：M=N=K=64（可根据实际需求调整）

**单Tile Buffer需求：**
```verilog
// A矩阵：8行 × K列 × 1字节
A_TILE_SIZE = 8 * K_MAX * 1 byte = 8 * 64 * 1 = 512 bytes

// B矩阵：K行 × 8列 × 1字节  
B_TILE_SIZE = K_MAX * 8 * 1 byte = 64 * 8 * 1 = 512 bytes

// C矩阵：8行 × 8列 × 4字节（INT32累加）
C_TILE_SIZE = 8 * 8 * 4 bytes = 256 bytes

// 单Tile总计
SINGLE_TILE_BUFFER = 512 + 512 + 256 = 1280 bytes ≈ 1.25 KB
```

### 3.2 32 Tiles总需求（按工作模式）

#### **模式1：INDEP（独立模式）**
每个Tile处理不同的8×8子矩阵，需要独立的A/B/C Buffer。

```verilog
// 最坏情况：所有32个Tile同时使能
A_BUFFER_INDEP = 32 * 512 bytes = 16 KB
B_BUFFER_INDEP = 32 * 512 bytes = 16 KB
C_BUFFER_INDEP = 32 * 256 bytes = 8 KB
TOTAL_INDEP    = 40 KB

// 优化：如果K较小（如K=8），则
A_BUFFER_INDEP_K8 = 32 * 64 bytes = 2 KB
B_BUFFER_INDEP_K8 = 32 * 64 bytes = 2 KB
C_BUFFER_INDEP_K8 = 32 * 256 bytes = 8 KB
TOTAL_INDEP_K8    = 12 KB
```

#### **模式2：MERGE（合并模式）**
所有Tile共享同一组A/B权重，仅C结果独立存储。

```verilog
// A/B只需一份（主Tile加载，从Tile通过级联获取）
A_BUFFER_MERGE = 512 bytes
B_BUFFER_MERGE = 512 bytes
C_BUFFER_MERGE = 32 * 256 bytes = 8 KB
TOTAL_MERGE    = 9 KB
```

#### **模式3：SPLIT（拆分模式）**
将大矩阵拆分到多个Tile并行计算，每个Tile处理不同的子矩阵块。

```verilog
// Buffer需求与INDEP相同，每个Tile独立处理
// 但数据组织方式不同：A/B按行/列拆分到各Tile
A_BUFFER_SPLIT = 32 * 512 bytes = 16 KB
B_BUFFER_SPLIT = 32 * 512 bytes = 16 KB
C_BUFFER_SPLIT = 32 * 256 bytes = 8 KB
TOTAL_SPLIT    = 40 KB
```

### 3.3 推荐Buffer配置

**基于FPGA资源约束的折中方案：**

```verilog
// 参数化配置（可在npu_defs.vh中定义）
`define NPU_A_BUFFER_SIZE   (16 * 1024)  // 16 KB - 支持INDEP模式K=64
`define NPU_B_BUFFER_SIZE   (16 * 1024)  // 16 KB - 支持INDEP模式K=64
`define NPU_C_BUFFER_SIZE   (8 * 1024)   // 8 KB  - 32 Tiles的C结果
`define NPU_TOTAL_BUFFER    (40 * 1024)  // 40 KB 总计

// 如果FPGA BRAM有限，可采用保守配置
`define NPU_A_BUFFER_SIZE_CONSERVATIVE   (2 * 1024)  // 2 KB - 支持K=8
`define NPU_B_BUFFER_SIZE_CONSERVATIVE   (2 * 1024)  // 2 KB
`define NPU_C_BUFFER_SIZE_CONSERVATIVE   (8 * 1024)  // 8 KB
`define NPU_TOTAL_BUFFER_CONSERVATIVE    (12 * 1024) // 12 KB
```

**BRAM资源估算（以Xilinx UltraScale+为例）：**
- 单个BRAM36E：36 Kb = 4.5 KB
- 40 KB需求 ≈ 9个BRAM36E
- 12 KB需求 ≈ 3个BRAM36E

**结论：** 现代FPGA通常有数百个BRAM，40 KB完全可以接受。

---

## 四、AXI地址空间规划

### 4.1 地址映射方案

**说明：** 以下地址为NPU内部偏移地址，CPU通过AXI总线访问时需加上NPU的基地址（由系统集成时确定）。

```verilog
// 地址空间定义（在npu_defs.vh中配置）
// NPU内部地址空间总大小：64KB
`define NPU_ADDR_WIDTH      16  // 64KB地址空间

// 各区域基地址（偏移量）
`define NPU_AXI_LITE_BASE   16'h0000  // AXI-Lite寄存器区（256字节）
`define NPU_A_BUFFER_BASE   16'h0100  // A矩阵数据区
`define NPU_B_BUFFER_BASE   16'h4000  // B矩阵数据区（16KB对齐）
`define NPU_C_BUFFER_BASE   16'h8000  // C结果数据区

// 各区域大小
`define NPU_AXI_LITE_SIZE   256
`define NPU_A_BUFFER_SIZE   (16 * 1024)  // 16 KB
`define NPU_B_BUFFER_SIZE   (16 * 1024)  // 16 KB
`define NPU_C_BUFFER_SIZE   (8 * 1024)   // 8 KB
```

### 4.2 地址解码逻辑

```verilog
// 在AXI4 Slave桥接模块中实现
wire is_axi_lite_region = (axi_addr >= `NPU_AXI_LITE_BASE) && 
                          (axi_addr < `NPU_AXI_LITE_BASE + `NPU_AXI_LITE_SIZE);
                          
wire is_a_buffer_region = (axi_addr >= `NPU_A_BUFFER_BASE) && 
                          (axi_addr < `NPU_A_BUFFER_BASE + `NPU_A_BUFFER_SIZE);
                          
wire is_b_buffer_region = (axi_addr >= `NPU_B_BUFFER_BASE) && 
                          (axi_addr < `NPU_B_BUFFER_BASE + `NPU_B_BUFFER_SIZE);
                          
wire is_c_buffer_region = (axi_addr >= `NPU_C_BUFFER_BASE) && 
                          (axi_addr < `NPU_C_BUFFER_BASE + `NPU_C_BUFFER_SIZE);
```

### 4.3 Burst传输示例

**场景：传输8×64的A矩阵（K=64）**

```verilog
// CPU侧伪代码
uint8_t A_matrix[8][64];  // 512字节

// 计算Burst参数
burst_len = 512 / 4 - 1;  // 127 (128-beat, 每拍4字节)
base_addr = NPU_A_BUFFER_BASE;

// 发起AXI4 Burst写
AXI_Write_Burst(base_addr, burst_len, INCR, A_matrix);
```

**NPU侧响应：**
```
周期0:   接收AW通道（地址+长度）
周期1-128: 接收W通道数据，写入A_Buffer[0:511]
周期129: 发送B响应
```

---

## 五、完整工作流程

### 5.1 初始化阶段（一次性）

```verilog
// 1. CPU通过AXI-Lite配置NPU参数
AXI_Lite_Write(NPU_REG_MODE,      MODE_INDEP);      // 工作模式：INDEP/MERGE/SPLIT
AXI_Lite_Write(NPU_REG_M,         8);                // M维度（结果矩阵行数）
AXI_Lite_Write(NPU_REG_N,         8);                // N维度（结果矩阵列数）
AXI_Lite_Write(NPU_REG_K,         64);               // K维度（A列数=B行数）
AXI_Lite_Write(NPU_REG_TILE_MASK, 0xFFFFFFFF);       // Tile使能掩码（bit[31:0]对应32个Tile）
AXI_Lite_Write(NPU_REG_ITERATIONS, 1);               // 迭代次数（用于多次复用B权重）

// 注意：A/B/C的基地址在硬件设计时已固定，无需软件配置
// 如需支持动态地址，可添加地址寄存器（可选功能）
```

### 5.2 数据传输阶段

```verilog
// 2. CPU传输A矩阵（AXI4 Burst写入）
// 假设K=64，传输8×64=512字节，burst_len=512/4-1=127（128拍，每拍4字节）
AXI_Burst_Write(NPU_BASE + NPU_A_BUFFER_BASE, 127, INCR, A_data[0:511]);

// 3. CPU传输B矩阵（AXI4 Burst写入）
// 同样传输K×8=64×8=512字节
AXI_Burst_Write(NPU_BASE + NPU_B_BUFFER_BASE, 127, INCR, B_data[0:511]);

// 注意：NPU_BASE为NPU在系统中的基地址，由SoC集成时确定
```

### 5.3 计算启动阶段

```verilog
// 4. CPU发送启动命令
AXI_Lite_Write(NPU_REG_CTRL, 1'b1);  // start=1

// 5. NPU内部流程
//    a. 从A_Buffer读取数据 → tile_a_bus
//    b. 从B_Buffer读取数据 → tile_b_bus
//    c. 32 Tiles并行计算 C = A × B
//    d. 结果写入C_Buffer
//    e. 设置npu_done标志
```

### 5.4 结果读取阶段

```verilog
// 6. CPU等待NPU完成
// 方式1：轮询状态寄存器
while (!(AXI_Lite_Read(NPU_REG_STATUS) & NPU_STATUS_DONE));
// 方式2：使用中断（如果实现了中断功能）
// wait_for_interrupt(NPU_DONE_IRQ);

// 7. CPU读取C矩阵（AXI4 Burst读取）
// 传输8×8×4=256字节（INT32结果），burst_len=256/4-1=63（64拍）
AXI_Burst_Read(NPU_BASE + NPU_C_BUFFER_BASE, 63, INCR, C_data[0:255]);

// 8. 清除完成标志（可选，取决于状态寄存器设计）
AXI_Lite_Write(NPU_REG_STATUS_CLR, 1'b1);
```

---

## 六、关键设计决策总结

### 6.0 设计决策确认（已确定）
| 决策项 | 选择 | 理由 |
|--------|------|------|
| **传输策略** | 分离传输A/B | 时序清晰，便于独立管理，符合零拷贝要求 |
| **启动机制** | 显式启动命令 | CPU完全掌控，支持预加载，工业标准做法 |
| **Buffer配置** | 推荐配置(40KB) | 支持K≤64，满足INDEP/SPLIT模式需求 |

### 6.1 数据传输策略
✅ **已确定：采用分离传输A/B矩阵**
- A矩阵和B矩阵分开传输，各自独立写入Buffer
- 清晰的时序边界，便于验证数据完整性
- 灵活的Buffer管理：可单独更新A或B（如推理时B权重不变）
- 符合工业界主流做法（AMD/Intel/Huawei均采用）

### 6.2 计算启动机制
✅ **已确定：采用显式启动命令**
- CPU通过AXI-Lite写入reg_ctrl.start=1启动计算
- 明确的时序控制，CPU完全掌控执行流程
- 支持数据预加载：可提前加载B权重，多次复用
- 便于调试和验证：每个阶段有明确的触发点

### 6.3 Buffer容量配置
✅ **已确定：推荐配置（平衡性能和资源）**
```verilog
A_Buffer: 16 KB  (支持INDEP模式，K≤64，每Tile 512字节×32)
B_Buffer: 16 KB  (支持INDEP模式，K≤64，每Tile 512字节×32)
C_Buffer: 8 KB   (32 Tiles结果，每Tile 256字节×32)
总计:     40 KB  (约9个BRAM36E，FPGA资源可接受)
```

**备选：保守配置（仅在资源严重受限时使用）**
```verilog
A_Buffer: 2 KB   (支持K≤8)
B_Buffer: 2 KB   (支持K≤8)
C_Buffer: 8 KB
总计:     12 KB  (约3个BRAM36E)
```

### 6.4 地址空间规划
✅ **模块化地址映射**（NPU内部偏移地址，总地址空间64KB）
- AXI-Lite寄存器区：0x0000 - 0x00FF（256字节）
- A矩阵数据区：0x0100 - 0x40FF（16KB）
- B矩阵数据区：0x4000 - 0x7FFF（16KB）
- C结果数据区：0x8000 - 0x9FFF（8KB）

✅ **特点**
- 地址对齐：各区域按16KB边界对齐，便于地址解码
- 空间预留：总64KB空间，预留部分地址用于扩展
- 参数化设计：所有尺寸可在npu_defs.vh中配置

---

## 七、实现细节确认

### 7.0 确认汇总表

| 类别 | 确认项 | 决策 |
|------|--------|------|
| **时钟** | 频率 | 200MHz |
| **复位** | 方式 | 异步复位、同步释放 |
| **数据格式** | INT8符号 | 有符号(Signed) |
| **数据格式** | 排列方式 | 行优先(Row-Major) |
| **AXI** | 最大Burst长度 | 256拍(AXI4) |
| **计算单元** | MAC阵列 | 8×8全并行（可配置4×4） |
| **数据输入** | A/B输入 | 串行（1 INT8/周期） |
| **数据输出** | C输出 | 并行（8 INT32/周期） |
| **Buffer** | 仲裁优先级 | AXI优先 |
| **Buffer** | 地址映射 | 连续排列 |
| **累加器** | 初始值 | 支持非0 |

### 7.1 全局设计约束

#### 时钟与复位
- **时钟频率**：200MHz
- **复位方式**：异步复位、同步释放（商业NPU标准做法）
- **时钟域**：单一时钟（200MHz），后续可考虑跨时钟域优化

```verilog
// 标准复位电路模板
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位：立即生效
        reg_a <= 0;
    end else begin
        // 正常工作
        reg_a <= next_a;
    end
end
```

#### 数据格式
- **字节序**：小端(Little-Endian)（与主流CPU兼容）
- **A/B矩阵数据排列**：行优先(Row-Major)（C语言默认）
- **INT8符号**：有符号(Signed)（-128~127，神经网络标准）

```verilog
// 有符号乘法实现
wire signed [7:0]  a_val = a_data;
wire signed [7:0]  b_val = b_data;
wire signed [15:0] product = a_val * b_val;  // 综合工具自动使用DSP48
```

#### 参数化策略
- Tile数量：32（固定）
- Tile尺寸：8×8（可配置，兼容赛题4×4要求）
- 最大K维度：64
- Buffer大小：40KB（推荐配置）
- AXI数据宽度：32bit

### 7.2 AXI接口细节

#### AXI4协议配置
- **支持的Burst类型**：只支持INCR（递增Burst），简化设计
- **最大Burst长度**：AXI4，最大256拍
- **数据宽度**：32bit（4字节/拍），与大多数SoC兼容

#### AXI-Lite寄存器访问
- **寄存器访问宽度**：只支持32bit访问
- **未对齐访问**：忽略低位地址，强制4字节对齐
- **寄存器写保护**：计算期间锁定M/N/K/Mode，其他可选

#### Buffer区Burst访问
- **地址回绕处理**：报错（返回SLVERR）
- **字节选通(Strobe)**：支持4bit WSTRB

### 8.3 Buffer管理细节

#### 存储实现
- **BRAM类型**：双端口BRAM（True Dual Port），支持同时读写
- **Buffer初始化**：不初始化，节省资源

#### 访问仲裁
- **AXI vs Data Mover冲突**：AXI优先（CPU控制权更高）
- **A Buffer读写冲突**：调度器确保不会同时发生（先写完再读）

#### A/B/C Buffer地址计算
**Tile到Buffer地址映射**：连续排列
```
A_Buffer: [Tile0_A][Tile1_A]...[Tile31_A]
Tile[i]的A偏移 = i × 512 bytes
```

### 7.4 计算单元细节

#### MAC阵列实现
- **MAC阵列尺寸**：8×8全并行（64个MAC），可配置为4×4模式
- **乘法器实现**：使用FPGA DSP48硬核，节省LUT资源

#### 累加器设计
- **累加器初始值**：支持非0初始值，用于MERGE模式的多次迭代
- **溢出处理**：直接截断，简化设计

#### Tile数据输入方式
- **A数据输入**：串行输入，每周期1个INT8
- **B数据输入**：串行输入，每周期1个INT8
- **C数据输出**：并行输出，每周期8个INT32

### 7.5 数据搬运模块细节

#### 数据加载时序
- **A和B的加载顺序**：同时加载，减少总加载时间
- **加载与计算重叠**：先实现不重叠版本，后续优化

#### 数据分发方式
- **广播 vs 单播**：广播，节省带宽

#### 结果收集方式
- **C结果写回**：同时写回，减少延迟

### 7.6 调度器细节

#### 状态机设计
- **迭代支持**：支持复用B权重
- **错误恢复**：立即停止，报告错误

#### 完成信号
- **done信号时机**：C写回完成时
- **done清除方式**：写REG_CTRL.status_clr清除

### 7.7 调试与测试
- **调试接口**：预留ILA观察点（可选）
- **测试模式**：可选，但有利于调试

### 7.8 时钟门控低功耗设计

#### 设计目标
未使能的 Tile 通过时钟门控关闭时钟，消除动态功耗，提升能效比（TOPS/W）。

#### 实现方案
- **门控粒度**：每个 Tile 独立时钟门控
- **门控单元**：AND 门 + 锁存器（ICG 标准单元）
- **控制信号**：由 `cfg_tile_mask` 和调度器状态联合决定
- **安全机制**：仅在 Tile 空闲（IDLE）时允许关闭时钟，避免计算中误关

```
              ┌─────────┐
  clk ────────┤         │
              │   AND   ├──── tile_clk[i] ────→ npu_tile[i]
  tile_en[i] ─┤         │
              └────┬────┘
                   │
              ┌────┴────┐
  tile_en[i] ─┤ Latch   │  ← 低电平锁存，避免毛刺
              │(level)  │
              └─────────┘
```

#### 节能效果估算
| 场景 | 使能 Tile 数 | 功耗节省（理论） |
|------|-------------|----------------|
| 全部使能（32 Tile） | 32 | 0% |
| 8 Tile 运算 | 8 | ~75% |
| 1 Tile 调试 | 1 | ~97% |
| 空闲状态 | 0 | ~100%（仅时钟树静态功耗） |

#### 与 tile_en 的区别
| | tile_en（数据使能） | 时钟门控 |
|---|---|---|
| 作用 | 阻止数据流入 Tile | 关闭 Tile 时钟 |
| 寄存器状态 | 时钟仍在翻转，有动态功耗 | 时钟停止，零动态功耗 |
| 恢复延迟 | 无 | 1 个时钟周期 |
| 实现成本 | 无额外资源 | 每 Tile 1 个 ICG 单元 |

---

## 八、模块划分设计

### 8.1 模块层次结构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              npu_top (顶层模块)                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ npu_axi_slave│  │  npu_config  │  │ npu_buffer   │  │npu_compute   │   │
│  │  (AXI接口)   │  │  (配置寄存器) │  │   _mgr       │  │  _pool       │   │
│  │              │  │              │  │ (数据缓存)    │  │ (计算池)     │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│         │                 │                 │                 │            │
│         └─────────────────┴────────┬────────┴─────────────────┘            │
│                                    │                                       │
│                              ┌─────┴─────┐                                 │
│                              │npu_data   │                                 │
│                              │  _mover   │                                 │
│                              │(数据搬运)  │                                 │
│                              └─────┬─────┘                                 │
│                                    │                                       │
│  ┌─────────────────────────────────┼─────────────────────────────────────┐  │
│  │                         npu_compute_pool                              │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐       ┌─────────┐              │  │
│  │  │npu_tile │ │npu_tile │ │npu_tile │  ...  │npu_tile │  (32个Tile)  │  │
│  │  │  [0]    │ │  [1]    │ │  [2]    │       │  [31]   │              │  │
│  │  └─────────┘ └─────────┘ └─────────┘       └─────────┘              │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌──────────────┐  ┌──────────────┐                                       │
│  │ npu_scheduler│  │  npu_status  │                                       │
│  │  (调度器)     │  │  (状态管理)   │                                       │
│  └──────────────┘  └──────────────┘                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 模块功能定义

#### **8.2.1 npu_top - 顶层模块**
- **功能**：NPU系统顶层，实例化并连接所有子模块
- **接口**：AXI4 Slave接口（对外）、时钟、复位
- **职责**：
  - 子模块实例化和互连
  - 全局时钟/复位分配
  - 顶层参数传递

```verilog
module npu_top #(
    parameter ADDR_WIDTH = 16,      // 64KB地址空间
    parameter DATA_WIDTH = 32,      // AXI数据宽度
    parameter TILE_COUNT = 32       // Tile数量
)(
    // AXI4 Slave接口
    input  wire                    axi_aclk,
    input  wire                    axi_aresetn,
    // AW通道
    input  wire [ADDR_WIDTH-1:0]   axi_awaddr,
    input  wire [7:0]              axi_awlen,
    input  wire [2:0]              axi_awsize,
    input  wire [1:0]              axi_awburst,
    input  wire                    axi_awvalid,
    output wire                    axi_awready,
    // W通道
    input  wire [DATA_WIDTH-1:0]   axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] axi_wstrb,
    input  wire                    axi_wlast,
    input  wire                    axi_wvalid,
    output wire                    axi_wready,
    // B通道
    output wire [1:0]              axi_bresp,
    output wire                    axi_bvalid,
    input  wire                    axi_bready,
    // AR通道
    input  wire [ADDR_WIDTH-1:0]   axi_araddr,
    input  wire [7:0]              axi_arlen,
    input  wire [2:0]              axi_arsize,
    input  wire [1:0]              axi_arburst,
    input  wire                    axi_arvalid,
    output wire                    axi_arready,
    // R通道
    output wire [DATA_WIDTH-1:0]   axi_rdata,
    output wire [1:0]              axi_rresp,
    output wire                    axi_rlast,
    output wire                    axi_rvalid,
    input  wire                    axi_rready,
    // 中断输出
    output wire                    npu_irq
);
```

---

#### **8.2.2 npu_axi_slave - AXI4 Slave接口模块**
- **功能**：处理AXI4协议，区分AXI-Lite寄存器访问和AXI4 Burst数据传输
- **参考**：AMD AI Engine的AXI接口设计
- **职责**：
  - AXI4协议状态机（AW/W/B/AR/R通道）
  - 地址解码：区分寄存器区、A/B/C Buffer区
  - Burst传输管理：计数、对齐、响应生成
  - 协议转换：将AXI事务转换为内部读写请求

```verilog
module npu_axi_slave #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    // AXI4 Slave接口（连接npu_top）
    // ...（完整端口见7.2.1）
    // 内部接口（连接其他模块）
    // 寄存器读写接口
    output reg                     reg_wr_en,
    output reg  [7:0]              reg_wr_addr,
    output reg  [31:0]             reg_wr_data,
    output reg                     reg_rd_en,
    output reg  [7:0]              reg_rd_addr,
    input  wire [31:0]             reg_rd_data,
    // Buffer写接口
    output reg                     buf_wr_en,
    output reg  [ADDR_WIDTH-1:0]   buf_wr_addr,
    output reg  [DATA_WIDTH-1:0]   buf_wr_data,
    output reg  [3:0]              buf_wr_strb,
    // Buffer读接口
    output reg                     buf_rd_en,
    output reg  [ADDR_WIDTH-1:0]   buf_rd_addr,
    input  wire [DATA_WIDTH-1:0]   buf_rd_data,
    input  wire                    buf_rd_valid
);
```

**关键设计点：**
```
地址解码逻辑：
- 0x0000 - 0x00FF → AXI-Lite寄存器区 → reg_wr/rd接口
- 0x0100 - 0x40FF → A Buffer区 → buf_wr/rd接口（A区）
- 0x4000 - 0x7FFF → B Buffer区 → buf_wr/rd接口（B区）
- 0x8000 - 0x9FFF → C Buffer区 → buf_wr/rd接口（C区）

Burst传输处理：
- 写操作：接收W通道数据，按地址写入对应Buffer
- 读操作：从Buffer读取数据，通过R通道返回
- 支持INCR/WRAP Burst类型
```

---

#### **8.2.3 npu_config - 配置寄存器模块**
- **功能**：存储NPU工作参数，通过AXI-Lite接口配置
- **参考**：Intel Movidius的CSR（Control Status Register）设计
- **职责**：
  - 参数寄存器：M/N/K维度、工作模式、Tile使能掩码
  - 控制寄存器：启动命令、中断使能
  - 状态寄存器：完成标志、错误标志

```verilog
module npu_config (
    input  wire        clk,
    input  wire        rst_n,
    // 写接口（来自npu_axi_slave）
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,
    input  wire [31:0] wr_data,
    // 读接口（来自npu_axi_slave）
    input  wire        rd_en,
    input  wire [7:0]  rd_addr,
    output reg  [31:0] rd_data,
    // 配置输出（连接其他模块）
    output wire [1:0]  cfg_mode,        // 00:INDEP, 01:MERGE, 10:SPLIT
    output wire [5:0]  cfg_m,           // M维度（1-64）
    output wire [5:0]  cfg_n,           // N维度（1-64）
    output wire [5:0]  cfg_k,           // K维度（1-64）
    output wire [31:0] cfg_tile_mask,   // Tile使能掩码
    output wire [3:0]  cfg_iterations,  // 迭代次数
    output reg         cfg_start,       // 启动命令（脉冲）
    // 状态输入（来自npu_status）
    input  wire        status_done,
    input  wire        status_error,
    output reg         status_clr       // 清除状态
);
```

**寄存器地址映射：**
| 偏移地址 | 名称 | 读写 | 描述 |
|----------|------|------|------|
| 0x00 | REG_CTRL | W | 控制寄存器（bit0:start, bit1:status_clr） |
| 0x04 | REG_STATUS | R | 状态寄存器（bit0:done, bit1:error） |
| 0x08 | REG_MODE | RW | 工作模式（00:INDEP, 01:MERGE, 10:SPLIT） |
| 0x0C | REG_M | RW | M维度 |
| 0x10 | REG_N | RW | N维度 |
| 0x14 | REG_K | RW | K维度 |
| 0x18 | REG_TILE_MASK | RW | Tile使能掩码（bit[31:0]） |
| 0x1C | REG_ITERATIONS | RW | 迭代次数 |

---

#### **8.2.4 npu_buffer_mgr - 数据缓存管理模块**
- **功能**：管理A/B/C三个数据Buffer的读写访问
- **参考**：Huawei Ascend的Unified Buffer设计
- **职责**：
  - BRAM实例化：A Buffer(16KB) + B Buffer(16KB) + C Buffer(8KB)
  - 仲裁逻辑：仲裁AXI接口和数据搬运模块的访问请求
  - 地址映射：将逻辑地址转换为物理BRAM地址

```verilog
module npu_buffer_mgr #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    // 端口A：AXI接口访问（读写A/B/C Buffer）
    input  wire                    axi_wr_en,
    input  wire [ADDR_WIDTH-1:0]   axi_wr_addr,
    input  wire [DATA_WIDTH-1:0]   axi_wr_data,
    input  wire [3:0]              axi_wr_strb,
    input  wire                    axi_rd_en,
    input  wire [ADDR_WIDTH-1:0]   axi_rd_addr,
    output reg  [DATA_WIDTH-1:0]   axi_rd_data,
    output reg                     axi_rd_valid,
    // 端口B：数据搬运模块访问（读A/B，写C）
    input  wire                    mover_rd_en,
    input  wire [ADDR_WIDTH-1:0]   mover_rd_addr,
    output reg  [DATA_WIDTH-1:0]   mover_rd_data,
    output reg                     mover_rd_valid,
    input  wire                    mover_wr_en,
    input  wire [ADDR_WIDTH-1:0]   mover_wr_addr,
    input  wire [DATA_WIDTH-1:0]   mover_wr_data,
    input  wire [3:0]              mover_wr_strb
);
```

**Buffer实现方案：**
```
A Buffer (16KB = 4096 x 32bit):
- 使用4个BRAM36E（每个4KB）
- 支持同时读写（双端口BRAM）

B Buffer (16KB = 4096 x 32bit):
- 同A Buffer

C Buffer (8KB = 2048 x 32bit):
- 使用2个BRAM36E
- 支持同时读写

总计：10个BRAM36E（约45KB，包含冗余）
```

---

#### **8.2.5 npu_data_mover - 数据搬运模块**
- **功能**：将Buffer中的数据分发到各Tile，并收集计算结果
- **参考**：AMD AI Engine的Stream Switch + DMA
- **职责**：
  - A矩阵分发：从A Buffer读取数据，按Tile分配（每个Tile 8行×K列）
  - B矩阵分发：从B Buffer读取数据，按Tile分配（每个Tile K行×8列）
  - C结果收集：从各Tile收集结果，写入C Buffer
  - 模式适配：根据不同模式（INDEP/MERGE/SPLIT）调整数据分发策略

```verilog
module npu_data_mover #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter TILE_COUNT = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    // 配置输入
    input  wire [1:0]              cfg_mode,
    input  wire [5:0]              cfg_m,
    input  wire [5:0]              cfg_n,
    input  wire [5:0]              cfg_k,
    input  wire [31:0]             cfg_tile_mask,
    input  wire                    cfg_start,
    // Buffer读接口
    output reg                     buf_rd_en,
    output reg  [ADDR_WIDTH-1:0]   buf_rd_addr,
    input  wire [DATA_WIDTH-1:0]   buf_rd_data,
    input  wire                    buf_rd_valid,
    // Buffer写接口（写C结果）
    output reg                     buf_wr_en,
    output reg  [ADDR_WIDTH-1:0]   buf_wr_addr,
    output reg  [DATA_WIDTH-1:0]   buf_wr_data,
    output reg  [3:0]              buf_wr_strb,
    // Tile数据接口（连接npu_compute_pool）
    output reg  [TILE_COUNT-1:0]   tile_en,         // Tile使能
    output reg  [7:0]              tile_a_data [TILE_COUNT-1:0],  // A数据（8bit）
    output reg                     tile_a_valid,
    output reg  [7:0]              tile_b_data [TILE_COUNT-1:0],  // B数据（8bit）
    output reg                     tile_b_valid,
    input  wire [31:0]             tile_c_data [TILE_COUNT-1:0],  // C结果（32bit）
    input  wire                    tile_c_valid,
    output reg                     tile_c_ready,
    // 状态输出
    output reg                     mover_done
);
```

**数据分发策略：**
```
INDEP模式（独立模式）：
- A[i] → Tile[i] 的 A_Buffer (i=0~31)
- B[i] → Tile[i] 的 B_Buffer (i=0~31)
- C[i] ← Tile[i] 的 C_Buffer (i=0~31)

MERGE模式（合并模式）：
- A[0] → 所有Tile共享（通过广播或级联）
- B[0] → 所有Tile共享
- C[i] ← Tile[i] 的 C_Buffer (i=0~31)

SPLIT模式（拆分模式）：
- A按行拆分：A[8*i : 8*i+7] → Tile[i]
- B按列拆分：B[:, 8*i : 8*i+7] → Tile[i]
- C[i] ← Tile[i] 的结果块
```

---

#### **8.2.6 npu_tile - 单个计算单元**
- **功能**：执行8×8矩阵乘法（INT8输入，INT32累加）
- **参考**：NVIDIA Tensor Core、AMD AI Engine Tile
- **职责**：
  - 本地Buffer：存储A(8×K)、B(K×8)、C(8×8)数据
  - MAC阵列：8×8乘累加阵列
  - 累加器：INT32累加，支持多次迭代
  - 控制逻辑：计算状态机、数据加载控制

```verilog
module npu_tile #(
    parameter K_MAX = 64  // 最大K维度
)(
    input  wire        clk,
    input  wire        rst_n,
    // 配置输入
    input  wire [5:0]  cfg_k,          // 当前K维度
    input  wire        tile_en,        // Tile使能
    // A矩阵接口
    input  wire [7:0]  a_data,         // A数据（串行输入）
    input  wire        a_valid,
    output wire        a_ready,
    // B矩阵接口
    input  wire [7:0]  b_data,         // B数据（串行输入）
    input  wire        b_valid,
    output wire        b_ready,
    // C结果接口
    output wire [31:0] c_data,         // C结果（并行输出8×32bit）
    output wire        c_valid,
    input  wire        c_ready,
    // 状态输出
    output reg         compute_done
);
```

**内部架构：**
```
┌─────────────────────────────────────────────────────────┐
│                     npu_tile                            │
│  ┌───────────────────────────────────────────────────┐  │
│  │                本地Buffer                         │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐          │  │
│  │  │A_Buffer │  │B_Buffer │  │C_Buffer │          │  │
│  │  │(8×K)    │  │(K×8)    │  │(8×8)    │          │  │
│  │  │512B     │  │512B     │  │256B     │          │  │
│  │  └────┬────┘  └────┬────┘  └────┬────┘          │  │
│  └───────┼────────────┼────────────┼───────────────┘  │
│          │            │            │                   │
│  ┌───────┴────────────┴────────────┴───────────────┐  │
│  │              8×8 MAC阵列                        │  │
│  │  ┌─────┐ ┌─────┐ ┌─────┐       ┌─────┐        │  │
│  │  │MAC  │ │MAC  │ │MAC  │  ...  │MAC  │  (64个) │  │
│  │  │[0,0]│ │[0,1]│ │[0,2]│       │[7,7]│        │  │
│  │  └──┬──┘ └──┬──┘ └──┬──┘       └──┬──┘        │  │
│  │     │       │       │             │            │  │
│  │  ┌──┴───────┴───────┴─────────────┴──┐         │  │
│  │  │         累加器 (INT32)            │         │  │
│  │  └────────────────────────────────────┘         │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘

MAC操作：
- C[i][j] += A[i][k] * B[k][j]  (k=0~K-1)
- 每周期完成1行×1列的部分累加
- K个周期完成一个8×8结果
```

---

#### **8.2.7 npu_compute_pool - 计算池模块**
- **功能**：管理32个Tile的并行计算，协调数据流和控制流
- **参考**：Huawei Ascend的Cube Core集群
- **职责**：
  - Tile实例化：实例化32个npu_tile
  - 数据分发：将A/B数据广播或分发到各Tile
  - 结果收集：从各Tile收集C结果
  - 并行控制：协调各Tile的计算进度

```verilog
module npu_compute_pool #(
    parameter TILE_COUNT = 32,
    parameter K_MAX = 64
)(
    input  wire                    clk,
    input  wire                    rst_n,
    // 配置输入
    input  wire [5:0]              cfg_k,
    input  wire [31:0]             cfg_tile_mask,
    // 数据输入（来自npu_data_mover）
    input  wire [TILE_COUNT-1:0]   tile_en,
    input  wire [7:0]              tile_a_data [TILE_COUNT-1:0],
    input  wire                    tile_a_valid,
    input  wire [7:0]              tile_b_data [TILE_COUNT-1:0],
    input  wire                    tile_b_valid,
    // 结果输出（到npu_data_mover）
    output wire [31:0]             tile_c_data [TILE_COUNT-1:0],
    output wire                    tile_c_valid,
    input  wire                    tile_c_ready,
    // 状态输出
    output wire [TILE_COUNT-1:0]   tile_done,
    output wire                    pool_done
);
```

**Tile互联拓扑：**
```
方案1：独立模式（INDEP）
- 每个Tile独立接收A/B数据
- 无Tile间通信

方案2：级联模式（MERGE）
- Tile[0]作为主Tile，加载A/B
- 通过级联接口广播到Tile[1]~[31]
- 节省带宽，但增加延迟

方案3：混合模式（SPLIT）
- A按行分组广播
- B按列分组广播
- Tile网格化组织
```

---

#### **8.2.8 npu_scheduler - 计算调度模块**
- **功能**：控制计算流程，生成时序控制信号
- **参考**：Intel Movidius的Task Scheduler
- **职责**：
  - 流程控制：数据加载→计算→结果写回的流水线调度
  - 状态机：管理IDLE/LOAD/COMPUTE/DONE状态
  - 时序生成：生成数据搬运和计算的时序控制信号

```verilog
module npu_scheduler (
    input  wire        clk,
    input  wire        rst_n,
    // 配置输入
    input  wire [1:0]  cfg_mode,
    input  wire [5:0]  cfg_m,
    input  wire [5:0]  cfg_n,
    input  wire [5:0]  cfg_k,
    input  wire        cfg_start,
    // 控制输出
    output reg         load_start,      // 数据加载启动
    output reg         compute_start,   // 计算启动
    output reg         store_start,     // 结果存储启动
    // 状态输入
    input  wire        load_done,       // 数据加载完成
    input  wire        compute_done,    // 计算完成
    input  wire        store_done,      // 结果存储完成
    // 状态输出
    output reg         npu_done,        // 整体完成
    output reg  [1:0]  npu_state        // 状态机状态
);
```

**状态机：**
```
IDLE → LOAD → COMPUTE → STORE → DONE
  ↑      │        │        │      │
  └──────┴────────┴────────┴──────┘
         (循环处理多次迭代)

状态说明：
- IDLE: 等待启动命令
- LOAD: 数据搬运模块从Buffer加载数据到Tile
- COMPUTE: Tile执行矩阵乘法
- STORE: 数据搬运模块将结果写回Buffer
- DONE: 完成，等待状态清除
```

---

#### **8.2.9 npu_status - 状态管理模块**
- **功能**：管理NPU状态、完成标志和中断
- **参考**：通用外设状态管理设计
- **职责**：
  - 状态寄存器：维护done/error标志
  - 中断生成：计算完成时触发中断
  - 状态清除：软件写清除完成标志

```verilog
module npu_status (
    input  wire        clk,
    input  wire        rst_n,
    // 状态输入
    input  wire        npu_done,
    input  wire        npu_error,
    // 控制输入
    input  wire        status_clr,
    // 中断使能配置
    input  wire        irq_en_done,     // 完成中断使能
    input  wire        irq_en_error,    // 错误中断使能
    // 状态输出（到npu_config）
    output reg         status_done,
    output reg         status_error,
    // 中断输出
    output reg         npu_irq
);
```

---

### 8.3 模块间接口总结

```
npu_axi_slave ──┬──→ npu_config ──→ 配置信号（到所有模块）
                │
                ├──→ npu_buffer_mgr ←──→ npu_data_mover
                │                              │
                │                              ↓
                │                      npu_compute_pool
                │                         │       │
                │                         ↓       ↓
                │                      npu_tile × 32
                │
                └──→ npu_status ←── npu_scheduler

数据流：
CPU → AXI → npu_axi_slave → npu_buffer_mgr → npu_data_mover → npu_compute_pool → npu_tile
                                                                         ↓
CPU ← AXI ← npu_axi_slave ← npu_buffer_mgr ← npu_data_mover ← npu_compute_pool ← npu_tile
```

---

## 九、后续实施计划

### Phase 1: 基础架构搭建（预计3-4天）
1. 创建npu_defs.vh，定义所有参数和地址映射
2. 实现npu_axi_slave模块（AXI4协议处理）
3. 实现npu_config模块（配置寄存器）
4. 实现npu_buffer_mgr模块（BRAM管理）
5. 编写Testbench验证AXI读写

### Phase 2: 数据通路验证（预计2-3天）
1. 实现npu_data_mover模块（数据分发）
2. 验证A/B/C Buffer的读写功能
3. 验证数据分发到Tile的逻辑
4. 端到端数据传输测试

### Phase 3: 计算单元实现（预计3-4天）
1. 实现npu_tile模块（8×8 MAC阵列）
2. 实现npu_compute_pool模块（32 Tile管理）
3. 验证单Tile矩阵乘法
4. 验证多Tile并行计算

### Phase 4: 调度集成（预计2-3天）
1. 实现npu_scheduler模块（状态机控制）
2. 实现npu_status模块（状态管理）
3. 集成所有模块到npu_top
4. 端到端功能验证

### Phase 5: 优化与测试（预计2-3天）
1. 三种模式（INDEP/MERGE/SPLIT）完整测试
2. 性能优化和时序收敛
3. 边界条件测试（K=1, K=64等）
4. 文档更新和代码整理

---

## 十、参考文献

1. AMD Xilinx AI Engine Architecture Guide
2. Intel Movidius Myriad X VPU Datasheet
3. Huawei Ascend 310 Processor Architecture Whitepaper
4. NVIDIA Tensor Core Programming Guide
5. "HW-SW co-design of image classification accelerator on FPGA", Springer 2025
6. "Unlocking the AMD Neural Processing Unit for ML Training", arXiv 2025

---

**文档版本：** v2.0  
**创建日期：** 2026-05-08  
**更新日期：** 2026-05-08  
**作者：** NPU设计团队  
**状态：** 模块划分完成，待实施
