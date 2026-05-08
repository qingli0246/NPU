`timescale 1ns/1ps
`include "npu_defs.vh"

// NPU Debug Test - Check if NPU starts correctly
module tb_npu_debug;

    // Clock and Reset
    reg clk;
    reg rst_n;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

    // AXI-Lite signals
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

    // AXI4 signals
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

    // NPU status
    wire npu_busy;
    wire npu_done;
    wire npu_error;
    wire npu_irq;

    // Simple AXI4 memory model
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rdata   <= 32'd0;
            m_axi_rlast   <= 1'b0;
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
        end else begin
            // Always accept requests
            m_axi_arready <= m_axi_arvalid;
            m_axi_awready <= m_axi_awvalid;
            m_axi_wready  <= m_axi_wvalid;

            // Read response
            if (m_axi_arready) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rdata  <= 32'hDEADBEEF;  // Test pattern
                m_axi_rlast  <= 1'b1;
            end else begin
                m_axi_rvalid <= 1'b0;
            end

            // Write response
            if (m_axi_wready && m_axi_wlast) begin
                m_axi_bvalid <= 1'b1;
            end else begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    // Instantiate NPU
    npu_top u_npu (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awlen   (m_axi_awlen),
        .m_axi_awsize  (m_axi_awsize),
        .m_axi_awburst (m_axi_awburst),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wlast   (m_axi_wlast),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arlen   (m_axi_arlen),
        .m_axi_arsize  (m_axi_arsize),
        .m_axi_arburst (m_axi_arburst),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rlast   (m_axi_rlast),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready),
        .npu_busy      (npu_busy),
        .npu_done      (npu_done),
        .npu_error     (npu_error),
        .npu_irq       (npu_irq)
    );

    // Monitor NPU state
    always @(posedge clk) begin
        if (npu_busy)
            $display("[%0t] NPU busy", $time);
        if (npu_done)
            $display("[%0t] NPU done", $time);
        if (m_axi_arvalid)
            $display("[%0t] AXI Read request", $time);
        if (m_axi_awvalid)
            $display("[%0t] AXI Write request", $time);
    end

    // AXI-Lite write task
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
            $display("[%0t] Write 0x%h = 0x%h", $time, addr, data);
        end
    endtask

    // Main test
    initial begin
        s_axi_awaddr  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;

        @(posedge rst_n);
        #200;

        $display("\n=== NPU Debug Test ===\n");

        // Simple configuration
        axi_write(32'h04, 32'd0);       // mode=0
        axi_write(32'h08, 32'h1000);    // A_base
        axi_write(32'h0C, 32'h2000);    // B_base
        axi_write(32'h10, 32'h3000);    // C_base
        axi_write(32'h14, 32'd4);       // M=4
        axi_write(32'h18, 32'd4);       // N=4
        axi_write(32'h1C, 32'd4);       // K=4
        axi_write(32'h20, 32'h0001);    // tile_mask=1 (tile 0 only)
        axi_write(32'h30, 32'd0);       // burst_len=0

        $display("\n--- Starting NPU ---");
        axi_write(32'h00, 32'd1);       // Start

        #5000;

        $display("\n--- Status ---");
        $display("npu_busy = %b", npu_busy);
        $display("npu_done = %b", npu_done);
        $display("npu_error = %b", npu_error);

        $display("\n=== Test Complete ===\n");
        #1000;
        $finish;
    end

    initial begin
        $dumpfile("npu_debug.vcd");
        $dumpvars(0, tb_npu_debug);
    end

endmodule
