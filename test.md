Step 1  npu_config        ← 最简单，验证寄存器读写
Step 2  npu_status        ← 依赖 config，验证状态/中断
Step 3  npu_axi_slave     ← 验证 AXI 协议处理和地址解码
Step 4  npu_buffer_mgr    ← 验证 BRAM 读写和双端口仲裁
Step 5  npu_tile          ← 核心：验证单 Tile 8×8 矩阵乘法
Step 6  npu_scheduler     ← 验证状态机流程控制
Step 7  npu_compute_pool  ← 32 Tile 并行
Step 8  npu_data_mover    ← 三种模式数据分发
Step 9  npu_top           ← 全系统端到端
