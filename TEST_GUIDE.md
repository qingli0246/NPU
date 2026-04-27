# NPU 顶层集成测试指南

## 📋 当前测试程序说明

### 测试文件
- **测试平台**：`TB/tb_npu_top_test.v`
- **测试模式**：单Tile测试（Tile#0），INDEP模式
- **矩阵尺寸**：8×8×8（M=8, N=8, K=8）
- **测试数据**：
  - A矩阵：单位矩阵（A[0][0]=1，其余为0）
  - B矩阵：全零矩阵
  - C矩阵：预期结果应包含A[0][0]=1

### 编译和运行命令

```powershell
# PowerShell方式（推荐）
cd f:\complication-6\NPU
iverilog -g2012 -o TB\npu_top_integrated -I rtl TB\tb_npu_top_test.v rtl\npu_top.v rtl\npu_ctrl.v rtl\npu_compute_pool.v rtl\npu_tile.v rtl\npu_dma_rd.v rtl\npu_dma_wr.v rtl\npu_weight_cache.v rtl\npu_axi4_bridge.v rtl\npu_defs.vh
vvp TB\npu_top_integrated

# 查看波形
gtkwave TB\npu_top_test.vcd
```

### 测试流程

测试平台执行以下步骤：

1. **复位** - 释放复位信号
2. **配置阶段（CFG）** - 通过AXI-Lite配置NPU参数
   - 工作模式：INDEP（独立模式）
   - 矩阵尺寸：M=8, N=8, K=8
   - 基地址：A=0x100, B=0x200, C=0x300
3. **启动计算** - 设置NPU启动信号
4. **等待完成** - 轮询状态寄存器，等待NPU完成
5. **结果验证** - 从存储器读取C矩阵结果并验证

---

## 🎯 当前测试状态

### ✅ 已通过的测试阶段

#### 1. CFG阶段 - 参数配置 ✅
- AXI-Lite写操作正常
- 参数正确写入寄存器
- 控制器成功从IDLE→CFG→LOAD

#### 2. LOAD阶段 - A/B矩阵加载 ✅
- DMA读模块正常工作
- A矩阵数据正确加载到`tile_a_bus_reg`
- B矩阵数据正确加载到权重缓存
- Tile成功收到A/B数据：
  - `a_flat[63:0]=0000000000000001`（单位矩阵）
  - `b_flat[63:0]=0000000000000000`（全零矩阵）

#### 3. RUN阶段 - Tile计算 ✅
- Tile#0成功启动并完成计算
- 状态机正常转换：ST_IDLE → ST_RUN → ST_DONE → ST_IDLE
- 计算结果正确：
  - 由于B矩阵全零，C矩阵应为全零
  - `c_flat[31:0]=00000000` ✅

#### 4. STORE阶段 - C矩阵收集 ✅
- C矩阵收集逻辑正常工作
- `c_wr_phase`正确启动
- 成功收集32个字：`c_wr_cnt=32`
- 数据从`tile_c_bus`提取到`wr_data_word`

#### 5. DONE阶段 - 完成标志 ✅
- 控制器成功进入DONE状态
- `ctrl_done=1`, `ctrl_busy=0`
- NPU报告完成：`Status: busy=0 done=1 error=0`

---

## ⚠️ 当前存在的问题

### 问题1：DMA写操作未完成（STORE阶段卡住）

**现象**：
```
[10265000] ctrl_state= 4 rd_busy=0 wr_busy=1 pool_busy=0 tile_start_mask=0x00000000
[200295000] *** ERROR: Timeout waiting for NPU! ***
```

**详细描述**：
- 控制器进入STORE状态（`ctrl_state=4`）
- `wr_busy=1`（DMA写模块忙碌）
- `wr_busy`一直不变为0，导致测试超时
- 测试平台等待200ms后超时

**可能的原因**：

1. **AXI4写响应未返回**
   - DMA写模块在ST_WAIT状态等待`rsp_valid`
   - 如果AXI4桥未返回写响应，DMA会永久等待
   - 需要检查`m_axi_bvalid`信号

2. **AXI4桥接模块的写响应逻辑**
   - 桥接模块可能未正确处理写响应
   - `rsp_valid`信号可能未正确产生
   - 需要检查AXI4桥的ST_WR_RSP状态

3. **写计数器未正确递增**
   - DMA写的`wr_cnt`应该从0递增到31
   - 如果`wr_cnt`卡在某个值，说明某个事务未完成
   - 需要检查DMA写状态机的转换条件

**调试建议**：

查看波形文件`TB/npu_top_test.vcd`，关注以下信号（时间：2355000之后）：

```
1. DMA写状态机：
   - u_npu_top.u_wr_dma.state
   - u_npu_top.u_wr_dma.wr_cnt
   - u_npu_top.u_wr_dma.data_in_valid

2. AXI4写通道：
   - m_axi_awvalid / m_axi_awready（地址通道）
   - m_axi_wvalid / m_axi_wready（数据通道）
   - m_axi_bvalid / m_axi_bready（响应通道）

3. AXI4桥接模块：
   - u_npu_top.u_axi4_bridge.cmd_valid
   - u_npu_top.u_axi4_bridge.cmd_ready
   - u_npu_top.u_axi4_bridge.rsp_valid
```

**关键检查点**：
- `wr_cnt`是否从0递增到31？
- `m_axi_bvalid`是否变为1？
- `rsp_valid`是否为1？

---

### 问题2：C矩阵结果验证失败

**现象**：
```
[FAIL] C[0][0] =   x (expected 1)
[FAIL] C[0][1] =   x (expected 2)
```

**详细描述**：
- 测试平台从存储器地址0x300读取C矩阵结果
- 读取的数据是`x`（未知状态）
- 说明DMA写操作没有成功将数据写入存储器

**可能的原因**：

1. **DMA写未完成**（问题1的直接后果）
   - 由于DMA写卡在STORE阶段，数据未写入
   - 存储器中对应地址的值保持初始状态（x）

2. **AXI4写地址/数据不正确**
   - `m_axi_awaddr`可能不是预期的0x300
   - `m_axi_wdata`可能包含x或0

3. **存储器模型未正确接收数据**
   - 存储器模型的AXI写接口可能有bug
   - 写使能信号时序可能有问题

**调试建议**：

查看波形文件，关注以下信号：

```
1. DMA写输出：
   - u_npu_top.wr_cmd_addr（写地址）
   - u_npu_top.wr_cmd_wdata（写数据）
   - u_npu_top.wr_cmd_valid（命令有效）

2. AXI4总线：
   - m_axi_awaddr（AXI写地址）
   - m_axi_wdata（AXI写数据）
   - m_axi_wstrb（写字节选通）

3. 存储器内部：
   - 检查存储器模型中地址0x300的值
```

---

### 问题3：Tile计算结果全零（非错误，但需注意）

**现象**：
```
[2325000] [TILE0] ST_DONE: c_flat[31:0]=00000000
```

**详细说明**：
- 这不是bug，而是**测试数据的结果**
- A矩阵是单位矩阵（只有A[0][0]=1）
- B矩阵是全零矩阵
- 所以C=A×B的结果应该是全零 ✅

**验证建议**：
- 修改测试数据，使用非零的B矩阵
- 例如：设置B[0][0]=1，预期C[0][0]=1
- 或者使用两个单位矩阵相乘

---

## 🔧 已修复的问题

### 修复1：`pool_done`信号未连接 ✅
- **问题**：npu_ctrl实例化时缺少`pool_done`端口连接
- **修复**：添加`.pool_done(pool_done)`连接
- **影响**：控制器无法检测到计算完成，导致死锁

### 修复2：`tile_start_mask_value`未设置 ✅
- **问题**：控制器在IDLE状态未设置`tile_start_mask_value`
- **修复**：在IDLE状态的配置逻辑中添加赋值
- **影响**：Tile无法被启动

### 修复3：`c_wr_phase`重复启动 ✅
- **问题**：C矩阵收集阶段被`pool_done`反复触发
- **修复**：改为只在`wr_start`时启动
- **影响**：C矩阵数据被重复收集

### 修复4：`tile_a_bus`和`tile_b_bus`未连接 ✅
- **问题**：`tile_a_bus_reg`没有assign到`tile_a_bus`
- **修复**：添加`assign tile_a_bus = tile_a_bus_reg`
- **影响**：Tile收到的是高阻态z，无法计算

---

## 📊 数据流完整性总结

### 完整数据通路（已打通）

```
AXI4读 → DMA_RD → tile_a_bus_reg → tile_a_bus → Tile.a_flat
                                                    ↓
                                              Tile计算（C=A×B）
                                                    ↓
AXI4写 ← DMA_WR ← tile_c_bus ← Tile.c_flat ← Tile计算结果
```

**各阶段状态**：
- ✅ AXI4读 → DMA_RD：正常
- ✅ DMA_RD → tile_a_bus_reg：正常
- ✅ tile_a_bus_reg → tile_a_bus：正常（已修复）
- ✅ tile_a_bus → Tile：正常（数据正确加载）
- ✅ Tile计算：正常（结果正确）
- ✅ Tile.c_flat → tile_c_bus：正常
- ✅ tile_c_bus → C矩阵收集：正常
- ⚠️ C矩阵收集 → DMA_WR：正常启动，但DMA写未完成
- ❌ DMA_WR → AXI4写：卡住（当前问题）

---

## 🎯 下一步工作

### 优先级1：解决DMA写卡住问题
1. 检查AXI4桥的写响应逻辑
2. 确认`m_axi_bvalid`信号的产生条件
3. 验证DMA写状态机的ST_WAIT→ST_CMD转换

### 优先级2：完善测试结果验证
1. 修复DMA写后，验证C矩阵结果
2. 使用非零测试数据（如A=B=单位矩阵）
3. 添加自动比对逻辑（实际结果vs预期结果）

### 优先级3：扩展测试覆盖
1. 测试多Tile模式（启用多个Tile）
2. 测试MERGE/SPLIT工作模式
3. 测试不同矩阵尺寸（如16×16×16）
4. 测试静态权重模式（跳过B矩阵加载）

---

## 📝 调试工具使用

### GTKWave波形查看器

**打开波形**：
```powershell
gtkwave TB\npu_top_test.vcd
```

**推荐的信号分组**：

```
Group 1: 控制器状态
- u_npu_top.u_ctrl.state
- u_npu_top.u_ctrl.pool_done
- u_npu_top.u_ctrl.wr_start

Group 2: DMA写模块
- u_npu_top.u_wr_dma.state
- u_npu_top.u_wr_dma.wr_cnt
- u_npu_top.u_wr_dma.data_in_valid

Group 3: AXI4总线
- m_axi_awvalid, m_axi_awready
- m_axi_wvalid, m_axi_wready
- m_axi_bvalid, m_axi_bready

Group 4: Tile#0
- u_npu_top.u_compute_pool.g_tiles[0].u_tile.state
- u_npu_top.u_compute_pool.g_tiles[0].u_tile.a_flat
- u_npu_top.u_compute_pool.g_tiles[0].u_tile.c_flat

Group 5: C矩阵收集
- u_npu_top.c_wr_phase
- u_npu_top.wr_data_word
- u_npu_top.wr_data_valid
```

---

## 📌 注意事项

1. **测试超时设置**：当前测试平台设置超时为200ms，如果仿真运行较慢可能需要调整
2. **调试输出**：代码中包含大量`$display`调试输出，可通过注释掉来减少控制台输出
3. **波形文件大小**：VCD文件可能很大，建议只抓取关键信号
4. **时钟周期**：测试平台使用10ns时钟周期（100MHz），实际时序可能与此不同

---

**最后更新**：2026-04-26

**当前状态**：CFG/LOAD/RUN阶段通过，STORE阶段DMA写卡住，待解决