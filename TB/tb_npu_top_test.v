`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_npu_top_test;

    // 时钟与复位
    reg clk;
    reg rst_n;

    // AXI-Lite 控制接口信号
    reg [31:0] s_axi_awaddr;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;
    reg [31:0] s_axi_araddr;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;

    // AXI4 数据接口信号（连接到模拟的BRAM）
    wire [31:0] m_axi_awaddr;
    wire m_axi_awvalid;
    wire [31:0] m_axi_wdata;
    wire [3:0] m_axi_wstrb;
    wire m_axi_wvalid;
    wire m_axi_wlast;
    wire m_axi_awready;
    wire m_axi_wready;
    wire [1:0] m_axi_bresp;
    wire m_axi_bvalid;
    reg m_axi_bready;
    
    wire [31:0] m_axi_araddr;
    wire m_axi_arvalid;
    wire m_axi_arready;
    wire [31:0] m_axi_rdata;  // 由存储器模型驱动
    wire [1:0] m_axi_rresp;
    wire m_axi_rlast;
    wire m_axi_rvalid;        // 由存储器模型驱动
    reg m_axi_rready;

    // NPU状态信号
    wire npu_busy;
    wire npu_done;
    wire npu_error;
    wire npu_irq;

    // 测试用寄存器
    reg [31:0] status_data;
    reg [31:0] read_data_buf;
    integer verify_errors;
    integer verify_total;

    // 实例化NPU顶层模块
    npu_top u_npu_top (
        .clk(clk),
        .rst_n(rst_n),
        // AXI-Lite Control Interface
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        // AXI4 Data Interface
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .npu_busy(npu_busy),
        .npu_done(npu_done),
        .npu_error(npu_error),
        .npu_irq(npu_irq)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 生成VCD波形文件
    initial begin
        $dumpfile("TB/npu_top_test.vcd");
        $dumpvars(0, tb_npu_top_test);
    end

    // ============================================================
    // ========================================
    // AXI4 存储器模型实例化
    // ========================================
    
    axi4_bram_model u_axi4_bram_model (
        .clk(clk),
        .rst_n(rst_n),
        // Write Address Channel
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        // Write Data Channel
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wready(m_axi_wready),
        // Write Response Channel
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        // Read Address Channel
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        // Read Data Channel
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    // AXI-Lite写寄存器任务
    task axil_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1;
            s_axi_wdata = data;
            s_axi_wstrb = 4'hF;
            s_axi_wvalid = 1;
            
            wait(s_axi_awready && s_axi_wready);
            @(posedge clk);
            s_axi_awvalid = 0;
            s_axi_wvalid = 0;
            
            wait(s_axi_bvalid);
            s_axi_bready = 1;
            @(posedge clk);
            s_axi_bready = 0;
        end
    endtask

    // AXI-Lite读寄存器任务
    task axil_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1;
            
            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid = 0;
            
            wait(s_axi_rvalid);
            data = s_axi_rdata;
            s_axi_rready = 1;
            @(posedge clk);
            s_axi_rready = 0;
        end
    endtask

    // 测试流程
    initial begin
        // 初始化
        rst_n = 0;
        s_axi_awaddr = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        
        $display("\n========================================");
        $display("[Test] NPU Top Level Integration Test");
        $display("[Mode] Single Tile (Tile#0) - 8x8 Matrix Multiply");
        $display("========================================");
        
        #20;
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        #10;

        // ========================================
        // 步骤1: 配置NPU参数 (内存已在 initial 块中预加载)
        // ========================================
        $display("\n========================================");
        $display("[Step 2] Configure NPU via AXI-Lite");
        $display("========================================");
        
        // 配置模式寄存器（INDEP模式）
        axil_write(32'h04, 32'h00);  // reg_mode = INDEP
        
        // 配置矩阵维度（8x8x8）
        axil_write(32'h14, 32'd8);   // reg_m = 8
        axil_write(32'h18, 32'd8);   // reg_n = 8
        axil_write(32'h1C, 32'd8);   // reg_k = 8
        
        // 配置数据基地址
        axil_write(32'h08, 32'h00000100);  // reg_a_base = 0x100
        axil_write(32'h0C, 32'h00000200);  // reg_b_base = 0x200
        axil_write(32'h10, 32'h00000300);  // reg_c_base = 0x300
        
        // 配置Tile掩码（只启用Tile#0）
        axil_write(32'h20, 32'h00000001);  // reg_tile_mask = Tile#0
        
        $display("[%0t] Configuration complete", $time);
        
        // ========================================
        // 步骤3: 启动NPU计算
        // ========================================
        $display("\n========================================");
        $display("[Step 3] Start NPU Computation");
        $display("========================================");
        
        axil_write(32'h00, 32'h01);  // reg_ctrl = start
        
        $display("[%0t] NPU started, waiting for completion...", $time);
        
        // 等待计算完成或超时
        fork
            begin
                wait(npu_done == 1);
                $display("[%0t] *** NPU computation completed! ***", $time);
                $display("[%0t] Status: busy=%b done=%b error=%b", 
                         $time, npu_busy, npu_done, npu_error);
            end
            begin
                #200000;  // 200us超时
                $display("[%0t] *** ERROR: Timeout waiting for NPU! ***", $time);
                $display("[%0t] Status: busy=%b done=%b error=%b", 
                         $time, npu_busy, npu_done, npu_error);
                $finish;
            end
        join_any
        disable fork;
        
        #100;

        // ========================================
        // 步骤4: 验证C矩阵结果
        // ========================================
        $display("\n========================================");
        $display("[Step 4] Verify C Matrix Results");
        $display("========================================");
        
        // C矩阵应该是A × B = A × I = A
        // 所以C[0][0]应该等于A[0][0] = 1
        
        verify_errors = 0;
        verify_total = 0;
        
        // 读取C矩阵的前几个元素
        // 使用层次化引用访问 BRAM 模型中的存储器
        $display("Reading C matrix from address 0x300...");
        $display("C[0][0] = 0x%h", u_axi4_bram_model.axi4_mem[192]);
        $display("C[0][1] = 0x%h", u_axi4_bram_model.axi4_mem[193]);
        
        // 验证C[0][0]
        verify_total = verify_total + 1;
        if (u_axi4_bram_model.axi4_mem[192] == 32'h00000001) begin
            $display("[PASS] C[0][0] = 1 (correct!)");
        end else begin
            $display("[FAIL] C[0][0] = %d (expected 1)", u_axi4_bram_model.axi4_mem[192]);
            verify_errors = verify_errors + 1;
        end
        
        // 验证C[0][1]
        verify_total = verify_total + 1;
        if (u_axi4_bram_model.axi4_mem[193] == 32'h00000002) begin
            $display("[PASS] C[0][1] = 2 (correct!)");
        end else begin
            $display("[FAIL] C[0][1] = %d (expected 2)", u_axi4_bram_model.axi4_mem[193]);
            verify_errors = verify_errors + 1;
        end
        
        $display("\n========================================");
        $display("[Summary] Verification Results");
        $display("========================================");
        $display("Total checks: %0d", verify_total);
        $display("Passed: %0d", verify_total - verify_errors);
        $display("Failed: %0d", verify_errors);
        
        if (verify_errors == 0) begin
            $display("\n[SUCCESS] All tests passed! NPU integration verified.");
        end else begin
            $display("\n[WARNING] Some tests failed. Check waveforms for details.");
        end
        
        $display("\n[VCD] TB/npu_top_test.vcd");
        $display("[GTKWave] gtkwave TB/npu_top_test.vcd");
        
        #100;
        $finish;
    end

endmodule

// ============================================================
// AXI4 BRAM 模型模块
// ============================================================
module axi4_bram_model (
    input wire clk,
    input wire rst_n,
    
    // Write Address Channel
    input wire [31:0] m_axi_awaddr,
    input wire m_axi_awvalid,
    output reg m_axi_awready,
    
    // Write Data Channel
    input wire [31:0] m_axi_wdata,
    input wire [3:0] m_axi_wstrb,
    input wire m_axi_wvalid,
    input wire m_axi_wlast,
    output reg m_axi_wready,
    
    // Write Response Channel
    output wire [1:0] m_axi_bresp,
    output wire m_axi_bvalid,
    input wire m_axi_bready,
    
    // Read Address Channel
    input wire [31:0] m_axi_araddr,
    input wire m_axi_arvalid,
    output reg m_axi_arready,
    
    // Read Data Channel
    output wire [31:0] m_axi_rdata,
    output wire [1:0] m_axi_rresp,
    output wire m_axi_rlast,
    output wire m_axi_rvalid,
    input wire m_axi_rready
);

    // Internal registers to drive output wires
    reg [31:0] m_axi_rdata_reg;
    reg m_axi_rvalid_reg;
    reg m_axi_bvalid_reg;

    assign m_axi_rdata = m_axi_rdata_reg;
    assign m_axi_rvalid = m_axi_rvalid_reg;
    assign m_axi_bvalid = m_axi_bvalid_reg;

    reg [31:0] axi4_mem [0:1023];  // 4KB存储空间 (32-bit wide)
    
    // Integer variables for initialization and logic
    integer i;
    integer idx;
    integer word_idx;
    integer byte_idx;
    
    reg [31:0] mem_addr_wr;
    reg [31:0] mem_addr_rd;
    reg aw_accepted;

    assign m_axi_bresp = 2'b00; // OKAY
    assign m_axi_rresp = 2'b00; // OKAY
    assign m_axi_rlast = 1'b1;  // Single beat transfer

    initial begin
        // 初始化存储器内容
        for (i = 0; i < 1024; i = i + 1) begin
            axi4_mem[i] = 32'hDEADBEEF;  // 默认填充
        end
        
        // A矩阵数据（8x8矩阵，16个32bit字，基地址0x100 -> Word Addr 64）
        // 每个字包含4个字节，这里简单地将每个字的低8位设置为索引值+1，用于验证
        // 注意：如果NPU是按字节或半字处理，可能需要调整。这里假设验证代码只检查最低字节或特定位置。
        // 为了配合验证代码 axi4_mem[192][7:0] == 1 等，我们需要确保A矩阵的数据布局符合预期。
        // 假设验证代码期望 C = A * I = A。
        // 验证代码检查: C[0][0] (mem[192][7:0]) == 1, C[0][1] (mem[192][15:8]) == 2.
        // 这意味着 A[0][0]=1, A[0][1]=2.
        // 让我们初始化 A 矩阵，使得前几个元素符合这个预期。
        
        // 初始化 A 矩阵 (Word Addr 64 - 79)
        // 为了简单起见，让每个字的第j个字节等于 4*i + j + 1 ? 
        // 或者更简单：让内存单元 64 的低8位为1，次低8位为2...
        axi4_mem[64] = 32'h04030201; // Row 0: 1, 2, 3, 4
        axi4_mem[65] = 32'h08070605; // Row 0: 5, 6, 7, 8 (如果是一维展开) 或者 Row 1
        // 通常矩阵按行主序或列主序存储。假设按字存储，每个字包含4个元素。
        // 如果 NPU 期望的是标准矩阵乘法，且验证代码只检查前两个元素。
        // 我们只需确保 axi4_mem[64] 的低字节符合预期即可。
        
        // B矩阵数据（8x8矩阵，单位矩阵，基地址0x200 -> Word Addr 128）
        // B = I (Identity Matrix)
        // Linear indexing: idx = i*8 + j, then word_idx = idx/4, byte_idx = idx%4
        // 直接赋值，避免位操作问题
        
        // 清零所有B矩阵word
        for (i = 0; i < 16; i = i + 1) begin
            axi4_mem[128 + i] = 32'h00000000;
        end
        
        // 设置对角线元素为1
        // i=0: idx=0,  word=0,  byte=0 → axi4_mem[128]
        axi4_mem[128] = 32'h00000001;
        // i=1: idx=9,  word=2,  byte=1 → axi4_mem[130]
        axi4_mem[130] = 32'h00000100;
        // i=2: idx=18, word=4,  byte=2 → axi4_mem[132]
        axi4_mem[132] = 32'h00010000;
        // i=3: idx=27, word=6,  byte=3 → axi4_mem[134]
        axi4_mem[134] = 32'h01000000;
        // i=4: idx=36, word=9,  byte=0 → axi4_mem[137]
        axi4_mem[137] = 32'h00000001;
        // i=5: idx=45, word=11, byte=1 → axi4_mem[139]
        axi4_mem[139] = 32'h00000100;
        // i=6: idx=54, word=13, byte=2 → axi4_mem[141]
        axi4_mem[141] = 32'h00010000;
        // i=7: idx=63, word=15, byte=3 → axi4_mem[143]
        axi4_mem[143] = 32'h01000000;

        // C矩阵区域清零（基地址0x300 -> Word Addr 192）
        for (i = 0; i < 16; i = i + 1) begin
            axi4_mem[192 + i] = 32'h00000000; 
        end
    end

    // ----------------------------------------
    // AXI4 写通道逻辑 (AW, W & B)
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 0;
            m_axi_wready  <= 0;
            m_axi_bvalid_reg <= 0;
            aw_accepted   <= 0;
            mem_addr_wr   <= 0;
        end else begin
            // AW Channel Handshake
            if (m_axi_awvalid && !aw_accepted) begin
                m_axi_awready <= 1;
                mem_addr_wr <= m_axi_awaddr[31:2]; // 锁存字地址
                aw_accepted <= 1;
            end else begin
                m_axi_awready <= 0;
            end

            // W Channel Handshake
            if (aw_accepted && m_axi_wvalid && !m_axi_wready) begin
                m_axi_wready <= 1;
                // 执行写入
                if (mem_addr_wr < 1024) begin
                    axi4_mem[mem_addr_wr] <= m_axi_wdata;
                end
            end else begin
                m_axi_wready <= 0;
            end

            // B Channel Response
            if (m_axi_wready && m_axi_wvalid) begin
                m_axi_bvalid_reg <= 1;
                aw_accepted <= 0; 
            end 
            else if (m_axi_bvalid_reg && m_axi_bready) begin
                m_axi_bvalid_reg <= 0;
            end
        end
    end

    // ----------------------------------------
    // AXI4 读通道逻辑 (AR & R)
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 0;
            m_axi_rvalid_reg  <= 0;
            m_axi_rdata_reg   <= 0;
        end else begin
            // AR Channel: 接收读地址
            if (m_axi_arvalid && !m_axi_rvalid_reg) begin
                m_axi_arready <= 1;
            end else begin
                m_axi_arready <= 0;
            end

            // R Channel: 返回读数据
            if (m_axi_arvalid && m_axi_arready && !m_axi_rvalid_reg) begin
                mem_addr_rd = m_axi_araddr[31:2]; // 转换为字地址
                if (mem_addr_rd < 1024) begin
                    m_axi_rdata_reg <= axi4_mem[mem_addr_rd];
                end else begin
                    m_axi_rdata_reg <= 32'hDEAD_BEEF; // 越界保护
                end
                m_axi_rvalid_reg <= 1;
            end 
            // 当数据被消费者接收后，撤销 valid
            else if (m_axi_rvalid_reg && m_axi_rready) begin
                m_axi_rvalid_reg <= 0;
            end
        end
    end

endmodule
