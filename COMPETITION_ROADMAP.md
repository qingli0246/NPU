# 飞腾赛题三 - NPU优化与实施路线图

> **文档版本**: v2.0 (现实版)
> **最后更新**: 2026-05-08
> **项目状态**: 核心RTL完成,多项关键功能待实现

---

## 📊 一、当前项目状态评估 (实际)

### ✅ 已完成功能 (可拿分)

| 模块 | 状态 | 实际情况 |
|------|------|---------|
| **NPU架构** | ✅ 完成 | 32个Tile,支持INDEP/MERGE/SPLIT三种模式 |
| **AXI接口** | ⚠️ 部分完成 | AXI-Lite配置完成,AXI4仅支持单拍传输(无Burst) |
| **DMA控制器** | ⚠️ 部分完成 | 读/写DMA完整,但仅单拍模式 |
| **权重缓存** | ✅ 完成 | 支持动态/静态、共享/独立四种组合 |
| **功能仿真** | ⚠️ 部分完成 | 3个测试套件(15个子测试)通过,其他testbench未验证 |

### ❌ 未完成功能 (需实现才能拿分)

| 功能项 | 赛题分值 | 当前真实状态 | 优先级 |
|--------|---------|-------------|--------|
| **AXI Burst传输** | 基础要求 | ❌ 仅单拍,无Burst | **P0** |
| **时钟门控低功耗** | 5分 | ⚠️ 有clk_en通路,但非ICG硬件门控 | **P0** |
| **性能实测≥0.5 TOPS** | 40-50分 | ❌ 无测试代码,无周期计数器 | **P0** |
| **设计文档完善** | 10分 | ❌ 无架构图、时序图、覆盖率报告 | **P0** |
| **代码覆盖率≥95%** | 基础要求 | ❌ 未收集 | **P0** |
| **动态可调阵列** | +5分 | ⚠️ MERGE模式可包装,需配置寄存器 | P1 |
| **DFS动态调频** | 创新分 | ❌ 完全未实现 | P2 |
| **FPGA验证** | +10分 | ❌ 无任何FPGA文件 | P2 |

### 🔴 关键差距分析

**距离提交还有多少工作?**

```
已完成: ~40% (核心架构+基本功能仿真)
待完成: ~60% (Burst传输+低功耗+性能测试+文档)

具体分解:
- AXI Burst实现: 3-5天
- 真正的时钟门控(ICG): 2-3天  
- 性能测试框架+实测: 5-7天
- 设计文档(7章): 5-7天
- 覆盖率收集+补充测试: 3-5天
- 动态可调阵列(可选): 3-5天
- 调试和问题修复: 预留5-7天缓冲

总计: 约26-39天 (4-6周全职投入)
```

---

## 🎯 二、赛题评分策略分析 (现实版)

### 基础指标 (必须拿到的分数: 35-45分)

```
✅ 脉动阵列实现 (20分) - 已完成
   └─ 32 Tile架构,灵活可配,优于固定4×4

⚠️ AXI共享总线 (5分) - 需补充Burst
   └─ 当前仅单拍,必须实现Burst传输才能拿分
   └─ 工作量: 3-5天

⚠️ DMA控制器 (5分) - 已有,但需配合Burst
   └─ npu_dma_rd/wr完整,但需支持Burst模式

❌ 时钟门控 (5分) - 需实现ICG
   └─ 当前仅clk_en寄存器级控制,需改为真正ICG单元
   └─ 工作量: 2-3天

❌ 设计文档+验证 (10分) - 完全没有
   └─ 需架构图、时序图、测试覆盖率≥95%
   └─ 工作量: 5-7天
```

### 优化指标 (能拿多少看进度: 0-50分)

```
🎯 性能优化 (40-50分,线性评分) - 未开始
   ├─ 基准线: 0.5 TOPS @ INT8 → 0分
   ├─ 目标线: 1.0 TOPS @ INT8 → 50分
   ├─ 理论峰值: 0.4096 TOPS (32×64MAC @ 200MHz)
   ├─ 问题: 距0.5 TOPS还有22%差距!
   └─ 工作量: 5-7天 (测试框架+优化+实测)

🎯 动态可调阵列 (+5分) - 可包装
   └─ 利用现有MERGE模式,添加配置寄存器
   └─ 工作量: 3-5天

🎯 DFS动态调频 (创新加分) - 未实现
   └─ 需实现时钟分频器+动态切换逻辑
   └─ 工作量: 3-5天 (可选,优先级低)

🎯 FPGA验证 (+10分) - 未开始
   └─ 需综合、布局布线、板级测试
   └─ 工作量: 2-3周 (时间不够可放弃)
```

### **现实总分预估**

| 场景 | 基础分 | 优化分 | FPGA加分 | 总分 | 可能性 |
|------|--------|--------|---------|------|--------|
| **最低保底** | 25 | 0 | 0 | **25** | 如果Burst/门控/文档没做完 |
| **保守估计** | 35 | 15 | 0 | **50** | 完成基础项,性能刚达标 |
| **正常发挥** | 40 | 30 | 0 | **70** | 完成大部分,性能有余量 |
| **优秀表现** | 45 | 45 | 0 | **90** | 全部完成,性能接近1 TOPS |
| **完美表现** | 45 | 50 | 10 | **105**(封顶100) | 理想情况,时间充裕 |

**现实建议**: 目标70分,争取85分,FPGA验证量力而行

---

## 🚀 三、实施路线图 (现实版, 6-8周)

### **阶段0: 紧急修复 (Week 0, 3天)**

#### 任务0.1: 实现AXI Burst传输 ⚠️ 必须完成

**问题**: 当前DMA仅支持单拍传输,不满足赛题基础要求

**实施方案**:
```verilog
// npu_dma_rd.v 修改
// 添加Burst支持
reg [7:0] burst_len;  // Burst长度-1 (AXI ARLEN)
reg [31:0] burst_addr; // Burst起始地址

// 状态机添加BURST状态
localparam S_IDLE = 0, S_ADDR = 1, S_BURST = 2, S_DONE = 3;

// AXI信号
assign m_axi_arlen = burst_len;      // Burst长度
assign m_axi_arsize = 3'b010;        // 4字节
assign m_axi_arburst = 2'b01;        // INCR递增模式
```

**验证**:
- 修改现有testbench,测试16-beat Burst
- 检查地址递增是否正确
- 确保突发传输不中断

---

### **阶段1: 低功耗实现 (Week 1-2)**

#### 任务1.1: 实现真正的时钟门控 (ICG) (3天)

**问题**: 当前仅clk_en寄存器控制,赛题可能要求ICG单元

**实施方案**:
```verilog
// 新建 icg_cell.v - 时钟门控单元
module icg_cell (
    input wire clk,
    input wire en,
    output wire clk_gated
);
    reg en_latch;
    
    // 电平锁存:在clk低电平期间锁存en信号
    always @(*) begin
        if (!clk) begin
            en_latch = en;
        end
    end
    
    // 门控输出
    assign clk_gated = clk & en_latch;
    
endmodule

// 在npu_compute_pool.v中实例化
generate
    for (i = 0; i < `NPU_NUM_TILES; i++) begin : gen_icg
        wire tile_clk_gated;
        
        icg_cell u_icg (
            .clk(clk),
            .en(tile_clk_en[i]),  // 来自控制器
            .clk_gated(tile_clk_gated)
        );
        
        npu_tile u_tile (
            .clk(tile_clk_gated),  // 使用门控时钟
            // ...
        );
    end
endgenerate
```

**修改npu_top.v**:
```verilog
// 移除硬编码的 .clk_en(1'b1)
// 改为从控制器输出
wire pool_clk_en;
assign pool_clk_en = ctrl_clk_en;  // 来自npu_ctrl

npu_compute_pool u_pool (
    .clk(clk),
    .rst_n(rst_n),
    .clk_en(pool_clk_en),  // 真正的门控控制
    // ...
);
```

**验证**:
- 仿真观察:IDLE状态时tile_clk_gated应为0
- 功耗对比:门控前后动态功耗应有差异

---

#### 任务1.2: 建立性能测试框架 (5天)

**步骤1: 在npu_top添加周期计数器**
```verilog
// npu_top.v 添加
reg [63:0] cycle_count;
reg count_en;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_count <= 64'd0;
        count_en <= 1'b0;
    end else begin
        // NPU开始工作时启动计数
        if (state == `NPU_ST_RUN && !count_en) begin
            count_en <= 1'b1;
            cycle_count <= 64'd0;
        end
        // NPU完成时停止计数
        if (state == `NPU_ST_DONE && count_en) begin
            count_en <= 1'b0;
        end
        // 计数
        if (count_en) begin
            cycle_count <= cycle_count + 1;
        end
    end
end

// 添加只读寄存器让CPU读取
// AXI-Lite地址: 0x0100 (低32位), 0x0104 (高32位)
```

**步骤2: 编写性能测试testbench**
```verilog
// TB/tb_performance_test.v
module tb_performance_test;
    // ... 常规例化
    
    integer M, N, K;
    integer mac_ops;
    real gops, tops;
    
    initial begin
        // 测试1: 8x8x8
        M=8; N=8; K=8;
        run_gemm(M, N, K);
        #100;
        $display("Matrix %0dx%0dx%0d: %0d cycles", M, N, K, cycle_count);
        mac_ops = M * N * K;
        gops = mac_ops * 1.0 / cycle_count * CLK_FREQ / 1e9;
        $display("Performance: %0.3f GOPS = %0.6f TOPS", gops, gops/1000);
        
        // 测试2: 32x32x32
        M=32; N=32; K=32;
        // ... 重复
        
        // 测试3: 更大规模
        // ...
    end
endmodule
```

**步骤3: 运行并记录数据**
```bash
# 运行性能测试
cd TB
iverilog -o perf_test tb_performance_test.v ../rtl/*.v
vvp perf_test > performance_results.txt
```

---

#### 任务1.3: 性能优化 (3天)

**目标**: 确保达到0.5 TOPS

**优化方案 (按优先级)**:

1. **提高时钟频率** (最简单)
   - 如果当前200MHz → 提高到250MHz
   - 理论: 0.4096 × 1.25 = 0.512 TOPS ✓
   - 风险: FPGA时序可能不收敛

2. **启用全部32 Tile** (已做)
   - 确保所有Tile都在工作
   - 检查是否有Tile被禁用

3. **减少状态机开销**
   - 优化LOAD/STORE状态的延迟
   - 减少空闲周期

4. **DMA Burst优化** (配合任务0.1)
   - Burst传输减少地址开销
   - 提高总线利用率

**验证**: 运行性能测试,确保≥0.5 TOPS

---

### **阶段2: 文档与测试完善 (Week 3-4)**

#### 任务2.1: 收集代码覆盖率 (2天)

**方法1: 使用iverilog (推荐)**
```bash
# 编译时启用覆盖率
iverilog -o npu_cov -gcover-args rtl/*.v TB/tb_npu_top_test.v

# 运行仿真
vvp npu_cov

# 生成覆盖率报告
# 会生成 coverage.dat 文件
```

**方法2: 手动统计**
- 列出所有always块、case语句、if-else分支
- 编写测试用例覆盖每个分支
- 目标: ≥95%

---

#### 任务2.2: 完善设计文档 (5-7天)

**必须章节** (按重要性排序):

**1. 系统架构** (最重要)
- 整体框图: CPU ↔ AXI ↔ NPU ↔ Memory
- 数据流: A/B矩阵如何进入,C矩阵如何输出
- 状态机: IDLE→CFG→LOAD→RUN→STORE→DONE

**2. NPU详细设计**
- 32 Tile架构图
- 单Tile内部: 8×8 MAC阵列
- 三种模式说明: INDEP/MERGE/SPLIT

**3. 低功耗设计**
- ICG时钟门控原理图
- DFS动态调频框图(如有实现)
- 功耗估算数据

**4. 接口设计**
- AXI-Lite寄存器映射表
- AXI4 Burst传输协议
- CPU-NPU通信协议

**5. 验证方案**
- 测试用例列表 (至少15个)
- 覆盖率报告
- 波形截图

**6. 性能分析**
- GOPS/TOPS实测数据
- 带宽利用率
- 与理论峰值对比

**7. 创新点**
- 32 Tile灵活配置
- 动态可调阵列(如有)
- DFS调频(如有)

---

### **阶段3: 可选优化 (Week 5-6)**

#### 任务3.1: 动态可调阵列 (3-5天) [可选]

**目标**: 包装现有MERGE模式,争取+5分

**实施方案**:
```verilog
// npu_top.v 添加配置寄存器
reg [31:0] reg_reconfig_mode;  // 0x0030

// 定义模式
`define RECONFIG_INDEP      4'b0000  // 32独立Tile
`define RECONFIG_ROW_MERGE  4'b0001  // 行级联
`define RECONFIG_COL_MERGE  4'b0010  // 列级联
`define RECONFIG_FULL_MERGE 4'b0011  // 全级联

// 传递给compute_pool
npu_compute_pool u_pool (
    .reconfig_mode(reg_reconfig_mode[3:0]),
    // ...
);
```

**测试**: 切换不同模式,验证功能正确

---

#### 任务3.2: DFS动态调频 (3-5天) [可选]

**目标**: 根据负载调整频率,降低功耗

**简化方案**:
```verilog
// 新建 clk_divider.v
module clk_divider (
    input wire clk_in,
    input wire rst_n,
    input wire [1:0] div_sel,  // 00:÷1, 01:÷2, 10:÷4, 11:÷8
    output wire clk_out
);
    // ... 实现
endmodule

// npu_top.v 集成
wire clk_npu;
clk_divider u_div (
    .clk_in(clk),
    .div_sel(reg_freq_div[1:0]),
    .clk_out(clk_npu)
);

npu_compute_pool u_pool (
    .clk(clk_npu),  // 使用分频时钟
    // ...
);
```

**测试**: 对比不同频率下的功耗

---

### **阶段4: FPGA验证 (Week 7-8) [可选,时间允许]**

#### 任务4.1: 创建Vivado工程 (2天)

```tcl
# create_project.tcl
create_project npu_fpga ./npu_fpga -part xc7a35tcsg324-1
add_files [glob rtl/*.v]
set_property top npu_top [current_fileset]
```

#### 任务4.2: 综合与实现 (3天)

```bash
# 运行综合
vivado -mode batch -source run_synth.tcl

# 检查时序
# WNS必须>0
```

#### 任务4.3: 板级测试 (3天)

- 烧录bitstream
- LED显示状态
- UART输出调试信息
- 运行简单GEMM测试

---

## 📈 四、性能优化专项分析 (现实版)

### 当前性能瓶颈

**理论计算**:
```
32 Tile × 64 MAC/Tile/cycle = 2048 MAC/cycle
@ 200 MHz → 409.6 GOPS = 0.4096 TOPS

距离0.5 TOPS缺口: 0.0904 TOPS (约22%差距)
```

**问题**: 必须优化才能达标!

### 优化方案 (按优先级)

| 方案 | 提升幅度 | 实现难度 | 优先级 | 预计时间 |
|------|---------|---------|--------|---------|
| **提高时钟至250MHz** | +25% | 低 | P0 | 0.5天 |
| **实现AXI Burst** | +10-15% | 中 | P0 | 3天 |
| **启用全部32 Tile** | 已做 | - | - | - |
| **减少状态机开销** | +5-10% | 低 | P1 | 1天 |
| **权重缓存优化** | +5% | 低 | P1 | 1天 |

### 推荐策略

```
方案1(必须): 提高时钟 + Burst优化
  → 0.4096 × 1.25 × 1.1 = 0.563 TOPS ✓ 达标且有余量
  → 工作量: 3-4天

方案2(冲击高分): 方案1 + 全面优化
  → 0.563 × 1.15 = 0.647 TOPS ✓ 接近0.7
  → 工作量: 5-7天
```

**注意**: 提高时钟频率需确保FPGA能跑到250MHz,否则需降回200MHz并加大其他优化

---

## ⚠️ 五、风险管理与应对 (现实版)

### 🔴 高风险项

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| **时间不够** | **高** | **致命** | 砍掉可选功能(DFS/FPGA),专注拿基础分 |
| **性能不达标** | 高 | 极高 | 提高时钟+Burst优化,预留调试时间 |
| **AXI Burst实现困难** | 中 | 高 | 参考PicoRV32 AXI实现,必要时简化为4-beat |
| **时钟门控引入bug** | 中 | 高 | 先用clk_en寄存器级控制,最后再改ICG |

### 🟡 中风险项

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| **文档工作量超预期** | 高 | 中 | 边开发边写,不要最后集中补 |
| **覆盖率不足95%** | 中 | 中 | 重点覆盖状态机和数据通路 |
| **FPGA时序不收敛** | 中 | 低 | 可放弃FPGA加分,专注RTL仿真 |

### 🟢 低风险项 (可选功能,放弃也不影响大局)

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| **动态重构bug** | 低 | 低 | 时间不够直接放弃,仅加分项 |
| **DFS实现问题** | 低 | 低 | 优先级最低,可不实现 |

### 紧急预案

**如果时间严重不足 (只剩2周)**:
1. ✅ 保证AXI Burst实现 (基础要求)
2. ✅ 用clk_en代替ICG (能解释就行)
3. ✅ 写简化版文档 (至少有架构图和测试结果)
4. ❌ 放弃DFS、动态重构、FPGA
5. 目标分数: 50-60分

**如果时间刚好 (4周)**:
1. ✅ 完成所有P0任务
2. ⚠️ 尝试动态可调阵列 (+5分)
3. ❌ 放弃DFS和FPGA
4. 目标分数: 70-80分

**如果时间充裕 (6周+)**:
1. ✅ 完成所有功能
2. ✅ 尝试FPGA验证
3. 目标分数: 85-100分

---

## 📅 六、详细时间表 (现实版, 6-8周)

### Week 0: 紧急修复 (3天)
- **Day 1**: 实现AXI Burst传输 (npu_dma_rd.v修改)
- **Day 2**: 测试Burst功能,修复bug
- **Day 3**: 确保所有testbench通过

### Week 1: 低功耗 + 性能测试框架
- **Day 1-2**: 实现ICG时钟门控单元
- **Day 3-4**: 添加周期计数器,编写性能testbench
- **Day 5**: 首次性能实测,记录数据

### Week 2: 性能优化 + 测试完善
- **Day 1-2**: 提高时钟频率至250MHz,测试时序
- **Day 3-4**: 优化状态机减少开销,再次测试
- **Day 5**: 确认性能≥0.5 TOPS,收集覆盖率数据

### Week 3: 文档编写 (上)
- **Day 1-2**: 绘制系统架构图、状态机图
- **Day 3-4**: 编写NPU详细设计、接口设计章节
- **Day 5**: 编写低功耗设计章节

### Week 4: 文档编写 (下) + 测试
- **Day 1-2**: 编写验证方案、性能分析章节
- **Day 3-4**: 补充波形截图、测试数据
- **Day 5**: 文档review,定稿

### Week 5-6: 可选优化 (时间允许)
- **Week 5**: 实现动态可调阵列 (+5分)
- **Week 6**: 实现DFS动态调频 (创新分)

### Week 7-8: FPGA验证 (时间允许)
- **Week 7**: Vivado工程搭建,综合实现
- **Week 8**: 板级测试

**关键里程碑**:
- ✅ Week 0结束: AXI Burst实现
- ✅ Week 2结束: 性能≥0.5 TOPS
- ✅ Week 4结束: 文档完成
- ⚠️ Week 6结束: 可选功能完成
- ⚠️ Week 8结束: FPGA验证完成

---

## ✅ 七、验收检查清单 (现实版)

### 🔴 必须完成 (P0)

- [ ] **AXI Burst传输实现** - 基础要求,必须有
- [ ] **时钟门控** - 至少有clk_en通路,最好有ICG
- [ ] **性能≥0.5 TOPS** - 核心得分点,必须实测证明
- [ ] **设计文档** - 7个章节,架构图+时序图+测试数据
- [ ] **代码覆盖率≥95%** - 基础要求

### 🟡 争取完成 (P1)

- [ ] **动态可调阵列** - 利用现有MERGE模式包装,争取+5分
- [ ] **总线带宽利用率≥60%** - 配合Burst传输
- [ ] **测试用例≥20个** - 覆盖更多场景

### 🟢 可选完成 (P2)

- [ ] **DFS动态调频** - 创新加分,时间不够可放弃
- [ ] **FPGA验证** - +10分,但需要2-3周
- [ ] **性能接近1 TOPS** - 冲刺高分

### 提交前自检

**文档检查**:
- [ ] 有系统架构图吗?
- [ ] 有状态机时序图吗?
- [ ] 有AXI接口时序图吗?
- [ ] 有性能测试数据表格吗?
- [ ] 有覆盖率报告吗?
- [ ] 创新点写清楚了吗?

**代码检查**:
- [ ] 所有testbench通过吗?
- [ ] AXI Burst功能正常吗?
- [ ] 时钟门控仿真波形正确吗?
- [ ] 性能测试结果记录了吗?

**功能检查**:
- [ ] 32 Tile都能工作吗?
- [ ] INDEP/MERGE/SPLIT三种模式都测试了吗?
- [ ] DMA读写都正常吗?
- [ ] 寄存器读写都正确吗?

---

## 🎓 八、答辩准备要点 (现实版)

### 核心卖点 (必须能讲清楚)

1. **32 Tile灵活架构**
   - 为什么不用固定4×4? → 灵活性,可适配不同负载
   - 三种模式的使用场景: INDEP(小任务), MERGE(大任务), SPLIT(多任务)

2. **实测性能数据**
   - 必须有真实的TOPS数字
   - 对比理论峰值,分析差距原因
   - 说明优化手段(时钟、Burst等)

3. **低功耗设计**
   - 时钟门控原理和效果
   - DFS调频(如有实现)

4. **完整性**
   - 从RTL仿真到FPGA验证(如有)的完整流程

### 常见问题预演

**Q: 为什么选择32 Tile而非4×4?**
A: 32 Tile提供更高灵活性:
- 可配置为多种阵列形态(8×4, 4×8, 16×2)
- 支持INDEP/MERGE/SPLIT三种工作模式
- 更好适配不同规模的AI任务

**Q: 如何保证0.5 TOPS性能?**
A: (必须有实测数据!)
- 理论峰值: 32×64MAC×200MHz = 0.4096 TOPS
- 优化手段: 提高时钟至250MHz + Burst传输
- 实测结果: XX TOPS (用数据说话)

**Q: 动态重构的实际应用场景?**
A: CNN不同Layer需求不同:
- 卷积层: 需要大矩阵乘法,用MERGE模式
- 全连接层: 小矩阵,用INDEP模式
- 动态切换提升资源利用率

**Q: 时钟门控如何实现?**
A: (根据实际实现回答)
- 方案A: ICG单元 + 电平锁存
- 方案B: clk_en寄存器控制(简化版)
- 效果: IDLE时关闭Tile时钟,降低动态功耗

---

## 📞 九、联系方式与支持

- **赛题答疑邮箱**: zhangyouzhi1859@phytium.com.cn
- **RISC-V源码**: https://github.com/YosysHQ/picorv32.git
- **本项目仓库**: f:\complication-6\NPU

---

**下一步行动** (立即开始):

### 今天就做:
1. **实现AXI Burst传输** - 这是基础要求,必须先完成
   - 修改 `npu_dma_rd.v` 和 `npu_dma_wr.v`
   - 参考 `npu_axi4_bridge.v` 的AXI4协议实现
   - 测试16-beat Burst功能

### 本周内完成:
2. **添加周期计数器** - 为性能测试做准备
   - 在 `npu_top.v` 添加64位计数器
   - 添加只读寄存器让CPU能读取

3. **实现真正的时钟门控** - 拿到5分
   - 创建 `icg_cell.v` 模块
   - 在 `npu_compute_pool.v` 中实例化

### 下周完成:
4. **首次性能实测** - 确认能否达到0.5 TOPS
   - 编写性能测试testbench
   - 运行并记录数据
   - 如果不达标,提高时钟频率

---

**记住**: 
- 时间很紧,优先拿基础分(40-50分)
- 可选功能(DFS/FPGA)量力而行
- 文档要边做边写,不要最后补

**祝比赛顺利!**
