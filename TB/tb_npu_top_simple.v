`timescale 1ns/1ps
`include "npu_defs.vh"

// ============================================================
// NPU顶层简化测试 - 单Tile模式
// 用于调试和波形分析
// ============================================================
module tb_npu_top_simple;

    // 时钟和复位
    reg clk;
    reg rst_n;
    
    // AXI-Lite Slave接口（配置接口）- 测试平台驱动的信号用reg
    reg [31:0] s_axi_awaddr;
    reg        s_axi_awvalid;
    wire       s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0]  s_axi_wstrb;
    reg        s_axi_wvalid;
    wire       s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire       s_axi_bvalid;
    reg        s_axi_bready;
    reg [31:0] s_axi_araddr;
    reg        s_axi_arvalid;
    wire       s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire       s_axi_rvalid;
    reg        s_axi_rready;
    
    // AXI4 Master接口（数据接口）- 全部声明为wire，由NPU驱动
    wire [31:0] m_axi_awaddr;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [31:0] m_axi_araddr;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire        m_axi_rvalid;
    wire        m_axi_rready;
    
    // NPU状态输出
    wire npu_busy;
    wire npu_done;
    wire npu_error;
    wire npu_irq;
    
    // 实例化NPU顶层
    npu_top u_npu_top (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI-Lite Slave
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        
        // AXI4 Master
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready),
        
        .npu_busy       (npu_busy),
        .npu_done       (npu_done),
        .npu_error      (npu_error),
        .npu_irq        (npu_irq)
    );
    
    // ============================================================
    // 时钟生成：10ns周期
    // ============================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ============================================================
    // BRAM存储器模型
    // ============================================================
    reg [31:0] bram_memory [0:1023];
    integer i;
    
    initial begin
        // 初始化BRAM
        for (i = 0; i < 1024; i = i + 1) begin
            bram_memory[i] = 32'hDEADBEEF;
        end
        
        // A矩阵数据（8x8，基地址0x100）
        for (i = 0; i < 16; i = i + 1) begin
            bram_memory[256 + i] = (i+1) * 32'h00010001;
        end
        
        // B矩阵数据（8x8，基地址0x200）
        for (i = 0; i < 16; i = i + 1) begin
            bram_memory[512 + i] = (i+1) * 32'h00020002;
        end
        
        // C矩阵区域清零（基地址0x300）
        for (i = 0; i < 16; i = i + 1) begin
            bram_memory[768 + i] = 32'h00000000;
        end
    end
    
    // ============================================================
    // AXI4接口桥接：将NPU的输出连接到测试平台的BRAM模型
    // ============================================================
    
    // AR通道响应
    reg m_axi_arready_reg;
    assign m_axi_arready = m_axi_arready_reg;
    
    // AW/W通道响应
    reg m_axi_awready_reg, m_axi_wready_reg;
    assign m_axi_awready = m_axi_awready_reg;
    assign m_axi_wready = m_axi_wready_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready_reg <= 0;
            m_axi_awready_reg <= 0;
            m_axi_wready_reg <= 0;
        end else begin
            // AR通道握手
            if (m_axi_arvalid) begin
                m_axi_arready_reg <= 1;
            end else begin
                m_axi_arready_reg <= 0;
            end
            
            // AW通道握手
            if (m_axi_awvalid && !m_axi_awready_reg) begin
                m_axi_awready_reg <= 1;
            end else begin
                m_axi_awready_reg <= 0;
            end
            
            // W通道握手和数据写入
            if (m_axi_wvalid && !m_axi_wready_reg) begin
                m_axi_wready_reg <= 1;
                bram_memory[m_axi_awaddr[11:2]] <= m_axi_wdata;
            end else begin
                m_axi_wready_reg <= 0;
            end
        end
    end
    
    // ============================================================
    // AXI-Lite Slave响应逻辑（简化版）
    // ============================================================
    reg [31:0] axil_reg [0:15];
    reg [31:0] axil_rdata;
    reg axil_awready, axil_wready, axil_bvalid;
    reg axil_arready, axil_rvalid;
    
    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            axil_reg[i] = 32'h0;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axil_awready <= 0;
            axil_wready <= 0;
            axil_bvalid <= 0;
            axil_arready <= 0;
            axil_rvalid <= 0;
            axil_rdata <= 0;
        end else begin
            // AW通道
            if (s_axi_awvalid && !axil_awready) begin
                axil_awready <= 1;
            end else begin
                axil_awready <= 0;
            end
            
            // W通道
            if (s_axi_wvalid && !axil_wready) begin
                axil_wready <= 1;
                axil_reg[s_axi_awaddr[5:2]] <= s_axi_wdata;
                axil_bvalid <= 1;
            end else begin
                axil_wready <= 0;
                if (axil_bvalid && s_axi_bready) axil_bvalid <= 0;
            end
            
            // AR通道
            if (s_axi_arvalid && !axil_arready) begin
                axil_arready <= 1;
                axil_rdata <= axil_reg[s_axi_araddr[5:2]];
                axil_rvalid <= 1;
            end else begin
                axil_arready <= 0;
                if (axil_rvalid && s_axi_rready) axil_rvalid <= 0;
            end
        end
    end
    
    assign s_axi_awready = axil_awready;
    assign s_axi_wready = axil_wready;
    assign s_axi_bvalid = axil_bvalid;
    assign s_axi_bresp = 2'b00;
    assign s_axi_arready = axil_arready;
    assign s_axi_rdata = axil_rdata;
    assign s_axi_rvalid = axil_rvalid;
    assign s_axi_rresp = 2'b00;
    
    // ============================================================
    // 测试序列
    // ============================================================
    initial begin
        // 初始化信号
        rst_n = 0;
        s_axi_awvalid = 0;
        s_axi_awaddr = 0;
        s_axi_wvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 4'hF;
        s_axi_bready = 1;
        s_axi_arvalid = 0;
        s_axi_araddr = 0;
        s_axi_rready = 1;
        
        #20;
        rst_n = 1;
        #10;
        
        $display("[%0t] === 开始配置NPU ===", $time);
        
        // 配置寄存器
        axil_write(32'h04, 32'h00);  // reg_mode = INDEP
        axil_write(32'h14, 32'd8);   // reg_m = 8
        axil_write(32'h18, 32'd8);   // reg_n = 8
        axil_write(32'h1C, 32'd8);   // reg_k = 8
        axil_write(32'h08, 32'h00000100);  // reg_a_base
        axil_write(32'h0C, 32'h00000200);  // reg_b_base
        axil_write(32'h10, 32'h00000300);  // reg_c_base
        axil_write(32'h20, 32'h00000001);  // reg_tile_mask = Tile#0 only
        
        $display("[%0t] === 启动NPU计算 ===", $time);
        axil_write(32'h00, 32'h01);  // reg_ctrl = start
        
        // 等待完成或超时
        wait (npu_done || npu_error);
        
        if (npu_done) begin
            $display("[%0t] === NPU计算完成！===", $time);
        end else if (npu_error) begin
            $display("[%0t] === NPU出错！===", $time);
        end
        
        #100;
        $finish;
    end
    
    // AXI-Lite写任务
    task axil_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awvalid = 1;
            s_axi_awaddr = addr;
            @(posedge clk);
            s_axi_wvalid = 1;
            s_axi_wdata = data;
            wait(s_axi_awready && s_axi_wready);
            @(posedge clk);
            s_axi_awvalid = 0;
            s_axi_wvalid = 0;
            wait(s_axi_bvalid);
        end
    endtask
    
    // ============================================================
    // VCD波形输出
    // ============================================================
    initial begin
        $dumpfile("TB/npu_top_simple.vcd");
        $dumpvars(0, tb_npu_top_simple);
    end
    
endmodule
