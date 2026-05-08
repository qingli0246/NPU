`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_npu_simple;

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

    // AXI4 (tie off)
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_bready;
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    wire        m_axi_rready;
    wire npu_busy, npu_done, npu_error, npu_irq;

    // Simple memory: always ready
    reg m_axi_arready_r, m_axi_rvalid_r, m_axi_rlast_r;
    reg m_axi_awready_r, m_axi_wready_r, m_axi_bvalid_r;
    reg [31:0] m_axi_rdata_r;
    reg [7:0] rd_cnt;

    assign m_axi_arready = m_axi_arready_r;
    // Don't drive rvalid from reg, drive it combinationally for simplicity

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready_r <= 0;
            m_axi_rvalid_r  <= 0;
            m_axi_rlast_r   <= 0;
            m_axi_rdata_r   <= 0;
            m_axi_awready_r <= 0;
            m_axi_wready_r  <= 0;
            m_axi_bvalid_r  <= 0;
            rd_cnt          <= 0;
        end else begin
            m_axi_arready_r <= 0;
            m_axi_rvalid_r  <= 0;
            m_axi_rlast_r   <= 0;
            m_axi_awready_r <= 0;
            m_axi_wready_r  <= 0;
            m_axi_bvalid_r  <= 0;

            if (m_axi_arvalid && !m_axi_arready_r) begin
                m_axi_arready_r <= 1;
                rd_cnt <= 0;
            end

            if (m_axi_rready && !m_axi_rvalid_r && m_axi_arready_r) begin
                m_axi_rvalid_r <= 1;
                m_axi_rdata_r  <= {24'd0, rd_cnt};
                m_axi_rlast_r  <= (rd_cnt == m_axi_arlen);
                rd_cnt <= rd_cnt + 1;
            end

            if (m_axi_awvalid && !m_axi_awready_r) begin
                m_axi_awready_r <= 1;
            end

            if (m_axi_wvalid && !m_axi_wready_r) begin
                m_axi_wready_r <= 1;
                if (m_axi_wlast) begin
                    m_axi_bvalid_r <= 1;
                end
            end
        end
    end

    // Tie off AXI4 outputs to prevent undriven warnings
    // Use continuous assignment for rvalid/rdata/rlast
    assign m_axi_rvalid = m_axi_rvalid_r;
    assign m_axi_rdata  = m_axi_rdata_r;
    assign m_axi_rlast  = m_axi_rlast_r;
    assign m_axi_awready = m_axi_awready_r;
    assign m_axi_wready  = m_axi_wready_r;
    assign m_axi_bvalid  = m_axi_bvalid_r;

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
        .s_axi_araddr  (32'd0),
        .s_axi_arvalid (1'b0),
        .s_axi_arready (),
        .s_axi_rdata   (),
        .s_axi_rresp   (),
        .s_axi_rvalid  (),
        .s_axi_rready  (1'b0),
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

    // Simple test: write registers directly
    integer timeout;

    initial begin
        s_axi_awaddr  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;

        @(posedge rst_n);
        #200;

        $display("\n=== Simple NPU Test ===");

        // Write reg_mode (0x04)
        $display("[%0t] Writing reg_mode...", $time);
        @(posedge clk);
        s_axi_awaddr  <= 32'h04;
        s_axi_awvalid <= 1;
        s_axi_wdata   <= 32'd0;
        s_axi_wstrb   <= 4'hF;
        s_axi_wvalid  <= 1;
        s_axi_bready  <= 1;

        // Wait for ready
        timeout = 0;
        while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 100) begin
            $display("[%0t] ERROR: Timeout waiting for awready/wready", $time);
            $finish;
        end

        @(posedge clk);
        s_axi_awvalid <= 0;
        s_axi_wvalid  <= 0;

        // Wait for bvalid
        timeout = 0;
        while (!s_axi_bvalid && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 100) begin
            $display("[%0t] ERROR: Timeout waiting for bvalid", $time);
            $finish;
        end

        @(posedge clk);
        s_axi_bready <= 0;
        $display("[%0t] reg_mode written OK", $time);

        #100;

        // Write reg_a_base (0x08)
        $display("[%0t] Writing reg_a_base...", $time);
        @(posedge clk);
        s_axi_awaddr  <= 32'h08;
        s_axi_awvalid <= 1;
        s_axi_wdata   <= 32'h1000;
        s_axi_wstrb   <= 4'hF;
        s_axi_wvalid  <= 1;
        s_axi_bready  <= 1;

        timeout = 0;
        while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(posedge clk);
        s_axi_awvalid <= 0;
        s_axi_wvalid  <= 0;

        timeout = 0;
        while (!s_axi_bvalid && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(posedge clk);
        s_axi_bready <= 0;
        $display("[%0t] reg_a_base written OK", $time);

        #100;

        // Write reg_ctrl to start
        $display("[%0t] Starting NPU...", $time);
        @(posedge clk);
        s_axi_awaddr  <= 32'h00;
        s_axi_awvalid <= 1;
        s_axi_wdata   <= 32'd1;
        s_axi_wstrb   <= 4'hF;
        s_axi_wvalid  <= 1;
        s_axi_bready  <= 1;

        timeout = 0;
        while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(posedge clk);
        s_axi_awvalid <= 0;
        s_axi_wvalid  <= 0;

        timeout = 0;
        while (!s_axi_bvalid && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(posedge clk);
        s_axi_bready <= 0;
        $display("[%0t] NPU Started!", $time);

        #5000;
        $display("[%0t] Status: busy=%b, done=%b", $time, npu_busy, npu_done);

        $display("\n=== Test Complete ===\n");
        #1000;
        $finish;
    end

    initial begin
        $dumpfile("npu_simple.vcd");
        $dumpvars(0, tb_npu_simple);
    end

endmodule
