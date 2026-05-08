`timescale 1ns/1ps

// Simplified Burst Test - Test AXI4 bridge Burst functionality only
module tb_burst_simple;

    // Clock and Reset
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

    // Internal command interface signals
    reg         rd_cmd_valid;
    wire        rd_cmd_ready;
    reg  [31:0] rd_cmd_addr;
    reg  [7:0]  rd_cmd_burst_len;
    reg  [1:0]  rd_cmd_burst_type;
    wire        rd_rsp_valid;
    wire [31:0] rd_rsp_rdata;

    reg         wr_cmd_valid;
    wire        wr_cmd_ready;
    reg  [31:0] wr_cmd_addr;
    reg  [31:0] wr_cmd_wdata;
    reg  [3:0]  wr_cmd_wstrb;
    reg  [7:0]  wr_cmd_burst_len;
    reg  [1:0]  wr_cmd_burst_type;
    wire        wr_rsp_valid;

    // AXI4 Master interface
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

    // Instantiate bridge
    npu_axi4_bridge u_bridge (
        .clk              (clk),
        .rst_n            (rst_n),
        // Internal read command
        .rd_cmd_valid     (rd_cmd_valid),
        .rd_cmd_ready     (rd_cmd_ready),
        .rd_cmd_addr      (rd_cmd_addr),
        .rd_cmd_burst_len (rd_cmd_burst_len),
        .rd_cmd_burst_type(rd_cmd_burst_type),
        .rd_rsp_valid     (rd_rsp_valid),
        .rd_rsp_rdata     (rd_rsp_rdata),
        // Internal write command
        .wr_cmd_valid     (wr_cmd_valid),
        .wr_cmd_ready     (wr_cmd_ready),
        .wr_cmd_addr      (wr_cmd_addr),
        .wr_cmd_wdata     (wr_cmd_wdata),
        .wr_cmd_wstrb     (wr_cmd_wstrb),
        .wr_cmd_burst_len (wr_cmd_burst_len),
        .wr_cmd_burst_type(wr_cmd_burst_type),
        .wr_rsp_valid     (wr_rsp_valid),
        // AXI4
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
        .m_axi_rready     (m_axi_rready)
    );

    // Simple AXI4 response model
    reg [7:0] rd_cnt;
    reg [7:0] wr_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rdata   <= 32'd0;
            m_axi_rlast   <= 1'b0;
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
            rd_cnt        <= 8'd0;
            wr_cnt        <= 8'd0;
        end else begin
            // Read response
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rlast   <= 1'b0;

            if (m_axi_arvalid && !m_axi_arready) begin
                m_axi_arready <= 1'b1;
                rd_cnt <= 8'd0;
                $display("[%0t] MEM: Read request addr=0x%h, len=%d, burst=%b",
                         $time, m_axi_araddr, m_axi_arlen, m_axi_arburst);
            end

            if (m_axi_rready && !m_axi_rvalid) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rdata  <= {24'd0, rd_cnt};  // Return counter value
                m_axi_rlast  <= (rd_cnt == m_axi_arlen);
                $display("[%0t] MEM: Read data[%0d]=0x%h, last=%b",
                         $time, rd_cnt, {24'd0, rd_cnt}, (rd_cnt == m_axi_arlen));
                rd_cnt <= rd_cnt + 1;
            end

            // Write response
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;

            if (m_axi_awvalid && !m_axi_awready) begin
                m_axi_awready <= 1'b1;
                wr_cnt <= 8'd0;
                $display("[%0t] MEM: Write request addr=0x%h, len=%d, burst=%b",
                         $time, m_axi_awaddr, m_axi_awlen, m_axi_awburst);
            end

            if (m_axi_wvalid && !m_axi_wready) begin
                m_axi_wready <= 1'b1;
                $display("[%0t] MEM: Write data[%0d]=0x%h, last=%b",
                         $time, wr_cnt, m_axi_wdata, m_axi_wlast);
                wr_cnt <= wr_cnt + 1;

                if (m_axi_wlast) begin
                    m_axi_bvalid <= 1'b1;
                    $display("[%0t] MEM: Write response sent", $time);
                end
            end
        end
    end

    // Test flow
    reg [31:0] test_data;
    integer i;

    initial begin
        rd_cmd_valid      = 1'b0;
        rd_cmd_addr       = 32'd0;
        rd_cmd_burst_len  = 8'd0;
        rd_cmd_burst_type = 2'b01;
        wr_cmd_valid      = 1'b0;
        wr_cmd_addr       = 32'd0;
        wr_cmd_wdata      = 32'd0;
        wr_cmd_wstrb      = 4'hF;
        wr_cmd_burst_len  = 8'd0;
        wr_cmd_burst_type = 2'b01;

        @(posedge rst_n);
        #200;

        $display("\n========================================");
        $display("   AXI4 Bridge Burst Test");
        $display("========================================\n");

        // ========================================
        // Test 1: 4-beat Burst Read
        // ========================================
        $display("\n--- Test 1: 4-beat Burst Read ---");
        @(posedge clk);
        rd_cmd_valid      <= 1'b1;
        rd_cmd_addr       <= 32'h0000_0000;
        rd_cmd_burst_len  <= 8'd3;  // 4-beat
        rd_cmd_burst_type <= 2'b01; // INCR
        @(posedge clk);
        while (!rd_cmd_ready) @(posedge clk);
        rd_cmd_valid <= 1'b0;

        // Wait for read to complete
        #1000;

        // ========================================
        // Test 2: 8-beat Burst Write
        // ========================================
        $display("\n--- Test 2: 8-beat Burst Write ---");
        test_data = 32'hAABBCCDD;  // Initial test data

        @(posedge clk);
        wr_cmd_valid      <= 1'b1;
        wr_cmd_addr       <= 32'h0000_1000;
        wr_cmd_burst_len  <= 8'd7;  // 8-beat
        wr_cmd_burst_type <= 2'b01; // INCR
        wr_cmd_wdata      <= test_data;
        @(posedge clk);
        while (!wr_cmd_ready) @(posedge clk);
        wr_cmd_valid <= 1'b0;

        // Send 7 more data beats
        for (i = 1; i < 8; i = i + 1) begin
            @(posedge clk);
            test_data = test_data + 32'h01010101;
            wr_cmd_wdata <= test_data;
        end

        // Wait for write response
        #1000;

        $display("\n========================================");
        $display("   Test Complete");
        $display("========================================\n");

        #1000;
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("burst_simple.vcd");
        $dumpvars(0, tb_burst_simple);
    end

endmodule
