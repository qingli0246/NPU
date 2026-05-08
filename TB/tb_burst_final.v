`timescale 1ns/1ps
`include "npu_defs.vh"

module tb_burst_final;

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

    // AXI4 signals - Write Address Channel
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    wire        m_axi_awready;

    // AXI4 signals - Write Data Channel
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_wready;

    // AXI4 signals - Write Response Channel
    wire        m_axi_bvalid;
    wire        m_axi_bready;

    // AXI4 signals - Read Address Channel
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    wire        m_axi_arready;

    // AXI4 signals - Read Data Channel
    wire [31:0] m_axi_rdata;
    wire        m_axi_rlast;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    // NPU Status
    wire npu_busy, npu_done, npu_error, npu_irq;

    // AXI4 Memory Model registers
    reg m_axi_arready_r, m_axi_rvalid_r, m_axi_rlast_r;
    reg m_axi_awready_r, m_axi_wready_r, m_axi_bvalid_r;
    reg [31:0] m_axi_rdata_r;
    reg [7:0] rd_cnt, wr_cnt;

    // Connect memory model outputs
    assign m_axi_arready = m_axi_arready_r;
    assign m_axi_rvalid  = m_axi_rvalid_r;
    assign m_axi_rdata   = m_axi_rdata_r;
    assign m_axi_rlast   = m_axi_rlast_r;
    assign m_axi_awready = m_axi_awready_r;
    assign m_axi_wready  = m_axi_wready_r;
    assign m_axi_bvalid  = m_axi_bvalid_r;

    // Memory: 1KB
    reg [31:0] mem [0:255];
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = i;
    end

    // Memory model state
    reg rd_active;
    reg [7:0] rd_burst_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready_r <= 0;
            m_axi_rvalid_r  <= 0;
            m_axi_rlast_r   <= 0;
            m_axi_rdata_r   <= 0;
            m_axi_awready_r <= 0;
            m_axi_wready_r  <= 0;
            m_axi_bvalid_r  <= 0;
            rd_active       <= 0;
            rd_burst_cnt    <= 0;
            wr_cnt          <= 0;
        end else begin
            // Default: clear single-cycle pulses
            m_axi_arready_r <= 0;
            m_axi_awready_r <= 0;
            m_axi_bvalid_r  <= 0;

            // Clear rvalid when accepted
            if (m_axi_rvalid_r && m_axi_rready) begin
                m_axi_rvalid_r <= 0;
                rd_burst_cnt <= rd_burst_cnt + 1;
                if (m_axi_rlast_r) begin
                    rd_active <= 0;
                    $display("[%0t] [MEM] RD burst complete", $time);
                end
            end

            // Clear wready when accepted
            if (m_axi_wready_r && m_axi_wvalid) begin
                m_axi_wready_r <= 0;
            end

            // Read: accept address
            if (m_axi_arvalid && !rd_active) begin
                m_axi_arready_r <= 1;
                rd_active <= 1;
                rd_burst_cnt <= 0;
                $display("[%0t] [MEM] RD addr=0x%h len=%0d", $time, m_axi_araddr, m_axi_arlen);
            end

            // Read: send data (one cycle after address accepted)
            if (rd_active && !m_axi_rvalid_r) begin
                m_axi_rvalid_r <= 1;
                m_axi_rdata_r  <= mem[rd_burst_cnt];
                m_axi_rlast_r  <= (rd_burst_cnt == m_axi_arlen);
                $display("[%0t] [MEM] RD data[%0d]=0x%h last=%b", $time, rd_burst_cnt, mem[rd_burst_cnt], (rd_burst_cnt == m_axi_arlen));
            end

            // Write: accept address
            if (m_axi_awvalid && !m_axi_awready_r) begin
                m_axi_awready_r <= 1;
                wr_cnt <= 0;
                $display("[%0t] [MEM] WR addr=0x%h len=%0d", $time, m_axi_awaddr, m_axi_awlen);
            end

            // Write: accept data
            if (m_axi_wvalid && !m_axi_wready_r) begin
                m_axi_wready_r <= 1;
                $display("[%0t] [MEM] WR data[%0d]=0x%h last=%b", $time, wr_cnt, m_axi_wdata, m_axi_wlast);
                wr_cnt <= wr_cnt + 1;
                if (m_axi_wlast)
                    m_axi_bvalid_r <= 1;
            end
        end
    end

    // NPU Instance
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

    // Monitor
    always @(posedge clk) begin
        if (npu_done) $display("[%0t] [NPU] DONE!", $time);
    end

    // Write helper
    integer timeout;
    task do_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1;
            s_axi_wdata   <= data;
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
        end
    endtask

    // Test
    initial begin
        s_axi_awaddr = 0; s_axi_awvalid = 0;
        s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_wvalid = 0;
        s_axi_bready = 0;

        @(posedge rst_n);
        #200;

        $display("\n=== NPU Burst Test ===\n");

        // Configure NPU for small matrix: 4x4x4
        // Tile 0 only, INDEP mode
        $display("--- Configuring ---");
        do_write(32'h04, 32'd0);           // mode = 0 (INDEP)
        do_write(32'h08, 32'h0000_0000);   // A_base
        do_write(32'h0C, 32'h0000_0040);   // B_base (64 bytes offset)
        do_write(32'h10, 32'h0000_0080);   // C_base (128 bytes offset)
        do_write(32'h14, 32'd4);           // M = 4
        do_write(32'h18, 32'd4);           // N = 4
        do_write(32'h1C, 32'd4);           // K = 4
        do_write(32'h20, 32'h0000_0001);   // tile_mask = 1 (tile 0)
        do_write(32'h30, 32'd3);           // burst_len = 3 (4-beat)

        $display("\n--- Starting NPU ---");
        do_write(32'h00, 32'd1);           // start

        // Wait for completion or timeout (longer wait)
        #100000;

        $display("\n--- Final Status ---");
        $display("busy=%b done=%b error=%b", npu_busy, npu_done, npu_error);

        $display("\n=== Test Complete ===\n");
        #1000;
        $finish;
    end

    initial begin
        $dumpfile("burst_final.vcd");
        $dumpvars(0, tb_burst_final);
    end

endmodule
