`timescale 1ns/1ps
`include "npu_defs.vh"

// AXI4 Burst传输测试
// 测试DMA读写的Burst功能
module tb_burst_test;

    // 时钟和复位
    reg clk;
    reg rst_n;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz
    end

    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

    // AXI-Lite 接口信号
    reg  [31:0] s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [31:0] s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // AXI4 数据接口信号
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    reg         m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;
    reg         m_axi_bvalid;
    wire        m_axi_bready;
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    reg         m_axi_arready;
    reg  [31:0] m_axi_rdata;
    reg         m_axi_rlast;
    reg         m_axi_rvalid;
    wire        m_axi_rready;

    // NPU状态信号
    wire npu_busy;
    wire npu_done;
    wire npu_error;
    wire npu_irq;

    // 简单的AXI4内存模型 (用于测试)
    reg [31:0] mem [0:1023];  // 1KB内存
    reg [7:0]  rd_burst_cnt;
    reg [7:0]  wr_burst_cnt;

    // 初始化内存
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            mem[i] = i;  // 递增数据
        end
    end

    // AXI4 读响应逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rdata   <= 32'd0;
            m_axi_rlast   <= 1'b0;
            rd_burst_cnt  <= 8'd0;
        end else begin
            // 默认值
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rlast   <= 1'b0;

            // 接收读地址
            if (m_axi_arvalid && !m_axi_arready) begin
                m_axi_arready <= 1'b1;
                rd_burst_cnt  <= 8'd0;
                $display("[%0t] [MEM] Read request: addr=0x%h, len=%d",
                         $time, m_axi_araddr, m_axi_arlen);
            end

            // 发送读数据
            if (m_axi_rready && !m_axi_rvalid && m_axi_arready) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rdata  <= mem[rd_burst_cnt];
                m_axi_rlast  <= (rd_burst_cnt == m_axi_arlen);
                $display("[%0t] [MEM] Read data[%0d]=0x%h, last=%b",
                         $time, rd_burst_cnt, mem[rd_burst_cnt], (rd_burst_cnt == m_axi_arlen));
                rd_burst_cnt <= rd_burst_cnt + 1;
            end
        end
    end

    // AXI4 写响应逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
            wr_burst_cnt  <= 8'd0;
        end else begin
            // 默认值
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;

            // 接收写地址
            if (m_axi_awvalid && !m_axi_awready) begin
                m_axi_awready <= 1'b1;
                wr_burst_cnt  <= 8'd0;
                $display("[%0t] [MEM] Write request: addr=0x%h, len=%d",
                         $time, m_axi_awaddr, m_axi_awlen);
            end

            // 接收写数据
            if (m_axi_wvalid && !m_axi_wready) begin
                m_axi_wready <= 1'b1;
                $display("[%0t] [MEM] Write data[%0d]=0x%h, last=%b",
                         $time, wr_burst_cnt, m_axi_wdata, m_axi_wlast);
                wr_burst_cnt <= wr_burst_cnt + 1;

                // 最后一拍，发送写响应
                if (m_axi_wlast) begin
                    m_axi_bvalid <= 1'b1;
                end
            end
        end
    end

    // 实例化NPU顶层
    npu_top u_npu (
        .clk              (clk),
        .rst_n            (rst_n),
        // AXI-Lite
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        // AXI4 数据接口
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),
        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready),
        // 状态
        .npu_busy         (npu_busy),
        .npu_done         (npu_done),
        .npu_error        (npu_error),
        .npu_irq          (npu_irq)
    );

    // 监控NPU状态变化
    reg prev_npu_busy;
    always @(posedge clk) begin
        prev_npu_busy <= npu_busy;
        if (npu_busy && !prev_npu_busy) begin
            $display("[%0t] [NPU] Started!", $time);
        end
        if (!npu_busy && prev_npu_busy) begin
            $display("[%0t] [NPU] Stopped!", $time);
        end
        if (npu_done) begin
            $display("[%0t] [NPU] Done asserted!", $time);
        end
    end

    // AXI-Lite写任务
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;
            @(posedge clk);
            while (!s_axi_awready || !s_axi_wready) @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            @(posedge clk);
            while (!s_axi_bvalid) @(posedge clk);
            s_axi_bready <= 1'b0;
            @(posedge clk);
            $display("[%0t] [AXI-Lite] Write: addr=0x%h, data=0x%h", $time, addr, data);
        end
    endtask

    // 主测试流程
    initial begin
        // 初始化
        s_axi_awaddr  = 32'd0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'd0;
        s_axi_wstrb   = 4'h0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = 32'd0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        // 等待复位完成
        @(posedge rst_n);
        #200;

        $display("\n========================================");
        $display("   AXI4 Burst Transfer Test");
        $display("========================================\n");

        // ============================================
        // 测试: Burst模式 (burst_len=3, 4-beat)
        // ============================================
        $display("\n--- Test: Burst Mode (burst_len=3) ---");

        // 配置NPU
        // 寄存器地址映射 (字节地址):
        //   0x00 = reg_ctrl (bit0: start)
        //   0x04 = reg_mode
        //   0x08 = reg_a_base
        //   0x0C = reg_b_base
        //   0x10 = reg_c_base
        //   0x14 = reg_m
        //   0x18 = reg_n
        //   0x1C = reg_k
        //   0x20 = reg_tile_mask
        //   0x24 = reg_h_link_en
        //   0x28 = reg_v_link_en
        //   0x2C = reg_group_master
        //   0x30 = reg_burst_len
        $display("[%0t] Configuring NPU...", $time);
        axi_write(32'h04, 32'h0000_0000);  // reg_mode=0
        axi_write(32'h08, 32'h0000_0000);  // A基地址
        axi_write(32'h0C, 32'h0000_0100);  // B基地址
        axi_write(32'h10, 32'h0000_0200);  // C基地址
        axi_write(32'h14, 32'h0000_0008);  // M=8
        axi_write(32'h18, 32'h0000_0008);  // N=8
        axi_write(32'h1C, 32'h0000_0008);  // K=8
        axi_write(32'h20, 32'hFFFF_FFFF);  // tile_mask (all tiles)
        axi_write(32'h30, 32'h0000_0003);  // burst_len=3 (4-beat)

        // 启动NPU
        $display("[%0t] Starting NPU...", $time);
        axi_write(32'h00, 32'h0000_0001);  // reg_ctrl[0]=1 (start)

        // 等待一段时间观察行为
        #10000;

        // 检查NPU状态
        $display("[%0t] NPU Status: busy=%b, done=%b, error=%b",
                 $time, npu_busy, npu_done, npu_error);

        $display("\n========================================");
        $display("   Test Complete");
        $display("========================================\n");

        #1000;
        $finish;
    end

    // 波形输出
    initial begin
        $dumpfile("burst_test.vcd");
        $dumpvars(0, tb_burst_test);
    end

endmodule
