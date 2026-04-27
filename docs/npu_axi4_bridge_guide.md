# npu_axi4_bridge 使用说明

本文说明 [rtl/npu_axi4_bridge.v](rtl/npu_axi4_bridge.v) 的作用、接口含义和当前实现限制。

## 1. 这个模块有什么用

`npu_axi4_bridge` 的作用是把 NPU 内部的“简化命令握手”转换成标准 AXI4 主设备读写通道。

在当前工程里，它位于以下链路中：

- `npu_ctrl` 产生读写启动信号
- `npu_dma_rd` / `npu_dma_wr` 发出内部命令
- `npu_axi4_bridge` 把命令翻译成 AXI4 总线事务
- 外部 BRAM 或存储控制器响应 AXI4 读写

换句话说，它负责“让 NPU 去访问外部存储”，不是给 CPU 读写控制寄存器用的。

## 2. 为什么需要它

NPU 内部的 DMA 模块通常希望使用更简单的接口：

- 读请求：给一个地址，等数据回来
- 写请求：给一个地址和数据，等写响应回来

但外部 BRAM / AXI4 存储控制器使用的是标准 AXI4 通道：

- 读地址通道 `AR`
- 读数据通道 `R`
- 写地址通道 `AW`
- 写数据通道 `W`
- 写响应通道 `B`

`npu_axi4_bridge` 的任务就是在这两种接口之间做转换。

## 3. 接口分组说明

### 3.1 内部命令接口

这些信号来自 NPU 内部 DMA：

- `rd_cmd_valid` / `rd_cmd_ready`
- `rd_cmd_addr`
- `rd_rsp_valid` / `rd_rsp_rdata`

- `wr_cmd_valid` / `wr_cmd_ready`
- `wr_cmd_addr`
- `wr_cmd_wdata`
- `wr_cmd_wstrb`
- `wr_rsp_valid`

含义：

- 读命令：内部发出地址，桥接模块把它变成 AXI4 读事务
- 写命令：内部发出地址、数据和字节使能，桥接模块把它变成 AXI4 写事务

### 3.2 AXI4 主接口

这些信号连到外部 BRAM 或存储控制器：

- 写地址通道：`m_axi_awaddr`、`m_axi_awvalid`、`m_axi_awready`
- 写数据通道：`m_axi_wdata`、`m_axi_wstrb`、`m_axi_wvalid`、`m_axi_wready`
- 写响应通道：`m_axi_bvalid`、`m_axi_bready`
- 读地址通道：`m_axi_araddr`、`m_axi_arvalid`、`m_axi_arready`
- 读数据通道：`m_axi_rdata`、`m_axi_rvalid`、`m_axi_rready`

## 4. 工作流程

### 4.1 读流程

1. 内部模块拉高 `rd_cmd_valid`
2. 桥接模块在空闲态接收 `rd_cmd_addr`
3. 桥接模块发出 AXI4 `AR` 请求
4. 等待外部返回 `R` 数据
5. 把 `m_axi_rdata` 送到 `rd_rsp_rdata`
6. 拉高 `rd_rsp_valid`，告诉内部 DMA 读完成

### 4.2 写流程

1. 内部模块拉高 `wr_cmd_valid`
2. 桥接模块接收 `wr_cmd_addr`、`wr_cmd_wdata`、`wr_cmd_wstrb`
3. 桥接模块发出 AXI4 `AW` 和 `W`
4. 等待外部返回 `B` 响应
5. 拉高 `wr_rsp_valid`，告诉内部 DMA 写完成

## 5. 状态机说明

当前实现只有 4 个状态：

- `ST_IDLE`：空闲，等待读或写命令
- `ST_RD`：正在处理读事务
- `ST_WR_A`：正在处理写地址/写数据事务
- `ST_WR_B`：等待写响应

特点：

- 同一时刻只处理一个事务
- 读和写不会并发
- 不支持 burst，不支持多个 outstanding 请求

## 6. 当前实现的局限

这个模块是“简化版桥接器”，适合先把顶层流程跑通，但还不是完整高性能 AXI Master。

局限包括：

- 一次只处理一个读或写请求
- 不支持 burst 传输
- 不支持多个未完成事务排队
- 写路径中 `AW` 和 `W` 是并行发出的，适合简单存储控制器，但不是最完整的 AXI 主机实现风格

## 7. 在整个 NPU 中的作用

在当前工程里，它让以下链路能够成立：

- `npu_ctrl` 决定什么时候读 A/B、什么时候写回 C
- `npu_dma_rd` 把外部矩阵搬进来
- `npu_dma_wr` 把结果搬回去
- `npu_compute_pool` 只负责计算

如果没有这个桥，内部 DMA 就无法和外部 BRAM/控制器对话。

## 8. 后续可扩展方向

如果后面要提升性能，可以把它扩展成：

- 支持 burst 读写
- 支持多个 outstanding 请求
- 增加读写仲裁
- 增加错误返回和超时处理
- 增加对更复杂 BRAM/AXI 存储控制器的兼容性
