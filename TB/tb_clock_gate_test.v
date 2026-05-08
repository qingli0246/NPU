`timescale 1ns/1ps
`include "npu_defs.vh"

// Test clock gating functionality
module tb_clock_gate_test;

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

    // AXI4 (simplified)
    wire [31:0] m_axi_awaddr, m_axi_araddr;
    wire [7:0]  m_axi_awlen, m_axi_arlen;
    wire [2:0]  m_axi_awsize, m_axi_arsize;
    wire [1:0]  m_axi_awburst, m_axi_arburst;
    wire        m_axi_awvalid, m_axi_arvalid;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast, m_axi_wvalid;
    wire        m_axi_bready, m_axi_rready;
    wire npu_busy, npu_done, npu_error, npu_irq;

    // Simple AXI4 memory
    reg m_axi_arready_r, m_axi_rvalid_r, m_axi_rlast_r;
    reg m_axi_awready_r, m_axi_wready_r, m_axi_bvalid_r;
    reg [31:0] m_axi_rdata_r;

    assign m_axi_arready = m_axi_arready_r;
    assign m_axi_rvalid  = m_axi_rvalid_r;
    assign m_axi_rdata   = m_axi_rdata_r;
    assign m_axi_rlast   = m_axi_rlast_r;
    assign m_axi_awready = m_axi_awready_r;
    assign m_axi_wready  = m_axi_wready_r;
    assign m_axi_bvalid  = m_axi_bvalid_r;

    // Clock gating monitor
    wire pool_clk_en = u_npu.pool_clk_en;
    wire [`NPU_NUM_TILES-1:0] tile_clk_en_mask = u_npu.pool_tile_clk_en_mask;

    // Monitor clock gating
    always @(posedge clk) begin
        $display("[%0t] CLK_GATE: pool_clk_en=%b, tile_mask=0x%h",
                 $time, pool_clk_en, tile_clk_en_mask);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready_r <= 0; m_axi_rvalid_r <= 0; m_axi_rlast_r <= 0;
            m_axi_rdata_r <= 0; m_axi_awready_r <= 0; m_axi_wready_r <= 0;
            m_axi_bvalid_r <= 0;
        end else begin
            m_axi_arready_r <= m_axi_arvalid;
            m_axi_rvalid_r  <= m_axi_arready_r;
            m_axi_rlast_r   <= 1;
            m_axi_rdata_r   <= 32'hDEADBEEF;
            m_axi_awready_r <= m_axi_awvalid;
            m_axi_wready_r  <= m_axi_wvalid;
            m_axi_bvalid_r  <= m_axi_wready_r & m_axi_wlast;
        end
    end

    npu_top u_npu (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(32'd0), .s_axi_arvalid(1'b0), .s_axi_arready(), .s_axi_rdata(), .s_axi_rresp(), .s_axi_rvalid(), .s_axi_rready(1'b0),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .npu_busy(npu_busy), .npu_done(npu_done), .npu_error(npu_error), .npu_irq(npu_irq)
    );

    integer timeout;
    task do_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr <= addr; s_axi_awvalid <= 1;
            s_axi_wdata <= data; s_axi_wstrb <= 4'hF; s_axi_wvalid <= 1;
            s_axi_bready <= 1;
            timeout = 0;
            while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
                @(posedge clk); timeout = timeout + 1;
            end
            @(posedge clk);
            s_axi_awvalid <= 0; s_axi_wvalid <= 0;
            timeout = 0;
            while (!s_axi_bvalid && timeout < 100) begin
                @(posedge clk); timeout = timeout + 1;
            end
            @(posedge clk);
            s_axi_bready <= 0;
        end
    endtask

    initial begin
        s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0;
        s_axi_wstrb = 0; s_axi_wvalid = 0; s_axi_bready = 0;

        @(posedge rst_n);
        #200;

        $display("\n=== Clock Gating Test ===\n");

        // Test 1: IDLE state - clock should be off
        $display("--- Test 1: IDLE State ---");
        $display("Expected: pool_clk_en=0");
        #100;

        // Test 2: Configure with tile_mask=0x03 (Tile 0 and 1)
        $display("\n--- Test 2: Configure with tile_mask=0x03 ---");
        do_write(32'h04, 32'd0);        // mode
        do_write(32'h08, 32'h0000);     // A_base
        do_write(32'h0C, 32'h0100);     // B_base
        do_write(32'h10, 32'h0200);     // C_base
        do_write(32'h14, 32'd4);        // M=4
        do_write(32'h18, 32'd4);        // N=4
        do_write(32'h1C, 32'd4);        // K=4
        do_write(32'h20, 32'h0003);     // tile_mask=0x03 (Tile 0,1)

        $display("Expected: pool_clk_en=1, tile_mask=0x03");

        // Start
        do_write(32'h00, 32'd1);

        #500;

        // Test 3: Configure with tile_mask=0x01 (only Tile 0)
        $display("\n--- Test 3: Configure with tile_mask=0x01 ---");
        do_write(32'h20, 32'h0001);     // tile_mask=0x01
        do_write(32'h00, 32'd1);        // start

        $display("Expected: pool_clk_en=1, tile_mask=0x01");

        #500;

        $display("\n=== Test Complete ===\n");
        #1000;
        $finish;
    end

    initial begin
        $dumpfile("clock_gate.vcd");
        $dumpvars(0, tb_clock_gate_test);
    end

endmodule
