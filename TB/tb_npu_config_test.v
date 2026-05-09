`include "../rtl/npu_defs.vh"

// ============================================================
//  Testbench for npu_config module
//  测试NPU配置寄存器模块的读写功能、脉冲生成、锁定机制等
// ============================================================

module tb_npu_config_test;

    // --------------------------------------------------------
    //  Parameters
    // --------------------------------------------------------
    parameter CLK_PERIOD = 10;  // 10ns clock period (100MHz)

    // --------------------------------------------------------
    //  Signals
    // --------------------------------------------------------
    reg         clk;
    reg         rst_n;
    
    // Write interface
    reg         wr_en;
    reg  [7:0]  wr_addr;
    reg  [31:0] wr_data;
    
    // Read interface
    reg         rd_en;
    reg  [7:0]  rd_addr;
    wire [31:0] rd_data;
    
    // Configuration outputs
    wire [1:0]  cfg_mode;
    wire [5:0]  cfg_m;
    wire [5:0]  cfg_n;
    wire [5:0]  cfg_k;
    wire [31:0] cfg_tile_mask;
    wire [3:0]  cfg_iterations;
    wire        cfg_start;
    wire        cfg_status_clr;
    wire        irq_en_done;
    wire        irq_en_error;
    
    // Status inputs
    reg         status_done;
    reg         status_error;
    reg         computing;

    // --------------------------------------------------------
    //  Instantiate DUT (Device Under Test)
    // --------------------------------------------------------
    npu_config dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .wr_en          (wr_en),
        .wr_addr        (wr_addr),
        .wr_data        (wr_data),
        .rd_en          (rd_en),
        .rd_addr        (rd_addr),
        .rd_data        (rd_data),
        .cfg_mode       (cfg_mode),
        .cfg_m          (cfg_m),
        .cfg_n          (cfg_n),
        .cfg_k          (cfg_k),
        .cfg_tile_mask  (cfg_tile_mask),
        .cfg_iterations (cfg_iterations),
        .cfg_start      (cfg_start),
        .cfg_status_clr (cfg_status_clr),
        .irq_en_done    (irq_en_done),
        .irq_en_error   (irq_en_error),
        .status_done    (status_done),
        .status_error   (status_error),
        .computing      (computing)
    );

    // --------------------------------------------------------
    //  Clock generation
    // --------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --------------------------------------------------------
    //  Helper tasks
    // --------------------------------------------------------
    
    // Task: Write to register
    task write_reg;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            #1;
            wr_en   <= 1'b1;
            wr_addr <= addr;
            wr_data <= data;
            @(posedge clk);
            #1;
            wr_en   <= 1'b0;
            wr_addr <= 8'h00;
            wr_data <= 32'h0;
        end
    endtask

    // Task: Read from register
    task read_reg;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            #1;
            rd_en   <= 1'b1;
            rd_addr <= addr;
            @(posedge clk);
            @(posedge clk);  // Wait one more cycle for rd_data to be valid
            #1;
            data    = rd_data;  // Use blocking assignment to capture value
            rd_en   <= 1'b0;
            rd_addr <= 8'h00;
        end
    endtask

    // Task: Wait for N clock cycles
    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    // --------------------------------------------------------
    //  Test sequence
    // --------------------------------------------------------
    integer test_num;
    reg [31:0] read_val;
    reg        test_passed;
    
    initial begin
        // Initialize signals
        rst_n           <= 1'b0;
        wr_en           <= 1'b0;
        wr_addr         <= 8'h00;
        wr_data         <= 32'h0;
        rd_en           <= 1'b0;
        rd_addr         <= 8'h00;
        status_done     <= 1'b0;
        status_error    <= 1'b0;
        computing       <= 1'b0;
        
        test_num        <= 0;
        test_passed     <= 1'b1;
        
        $display("========================================");
        $display("  NPU Config Module Testbench");
        $display("  Start Time: %t", $time);
        $display("========================================");
        
        // Reset sequence
        #20;
        rst_n <= 1'b1;
        $display("\n[INFO] Reset released at time %t", $time);
        
        wait_cycles(2);
        
        // ================================================
        //  TEST 1: Check default values after reset
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Default Values After Reset", test_num);
        $display("----------------------------------------");
        
        read_reg(`REG_CTRL, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] REG_CTRL default value incorrect: expected 0x%08X, got 0x%08X", 32'd0, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_CTRL default value correct: 0x%08X", read_val);
        end
        
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd8) begin
            $display("[FAIL] REG_M default value incorrect: expected 8, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M default value correct: %d", read_val);
        end
        
        read_reg(`REG_N, read_val);
        if (read_val !== 32'd8) begin
            $display("[FAIL] REG_N default value incorrect: expected 8, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_N default value correct: %d", read_val);
        end
        
        read_reg(`REG_K, read_val);
        if (read_val !== 32'd8) begin
            $display("[FAIL] REG_K default value incorrect: expected 8, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_K default value correct: %d", read_val);
        end
        
        read_reg(`REG_TILE_MASK, read_val);
        if (read_val !== 32'hFFFFFFFF) begin
            $display("[FAIL] REG_TILE_MASK default value incorrect: expected 0xFFFFFFFF, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_TILE_MASK default value correct: 0x%08X", read_val);
        end
        
        read_reg(`REG_ITERATIONS, read_val);
        if (read_val !== 32'd1) begin
            $display("[FAIL] REG_ITERATIONS default value incorrect: expected 1, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_ITERATIONS default value correct: %d", read_val);
        end
        
        // Verify output ports match default values
        if (cfg_m !== 6'd8 || cfg_n !== 6'd8 || cfg_k !== 6'd8) begin
            $display("[FAIL] Output ports mismatch with defaults: M=%d, N=%d, K=%d", cfg_m, cfg_n, cfg_k);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Output ports match defaults: M=%d, N=%d, K=%d", cfg_m, cfg_n, cfg_k);
        end
        
        // ================================================
        //  TEST 2: Write and Read Back - Basic Registers
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Write and Read Back - Basic Registers", test_num);
        $display("----------------------------------------");
        
        // Write M=16, N=32, K=64
        write_reg(`REG_M, 32'd16);
        write_reg(`REG_N, 32'd32);
        write_reg(`REG_K, 32'd64);
        
        wait_cycles(1);
        
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd16) begin
            $display("[FAIL] REG_M write/read failed: expected 16, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M write/read successful: %d", read_val);
        end
        
        read_reg(`REG_N, read_val);
        if (read_val !== 32'd32) begin
            $display("[FAIL] REG_N write/read failed: expected 32, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_N write/read successful: %d", read_val);
        end
        
        read_reg(`REG_K, read_val);
        if (read_val !== 32'd64) begin
            $display("[FAIL] REG_K write/read failed: expected 64, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_K write/read successful: %d", read_val);
        end
        
        // Verify output ports updated
        if (cfg_m !== 6'd16 || cfg_n !== 6'd32 || cfg_k !== 6'd64) begin
            $display("[FAIL] Output ports not updated: M=%d, N=%d, K=%d", cfg_m, cfg_n, cfg_k);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Output ports updated correctly: M=%d, N=%d, K=%d", cfg_m, cfg_n, cfg_k);
        end
        
        // ================================================
        //  TEST 3: Write Mode Register
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Write Mode Register", test_num);
        $display("----------------------------------------");
        
        // Set mode to MERGE (01) with static weight (bit2=1) and independent (bit3=1)
        write_reg(`REG_MODE, 32'h0000000C);  // bits[3:2]=11, bits[1:0]=00
        
        wait_cycles(1);
        
        read_reg(`REG_MODE, read_val);
        if (read_val !== 32'h0000000C) begin
            $display("[FAIL] REG_MODE write/read failed: expected 0x%08X, got 0x%08X", 32'h0000000C, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_MODE write/read successful: 0x%08X", read_val);
        end
        
        if (cfg_mode !== 2'b00) begin
            $display("[FAIL] cfg_mode output incorrect: expected 2'b00, got %b", cfg_mode);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_mode output correct: %b", cfg_mode);
        end
        
        // ================================================
        //  TEST 4: Write Tile Mask and Iterations
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Write Tile Mask and Iterations", test_num);
        $display("----------------------------------------");
        
        write_reg(`REG_TILE_MASK, 32'h0000FFFF);
        write_reg(`REG_ITERATIONS, 32'd8);
        
        wait_cycles(1);
        
        read_reg(`REG_TILE_MASK, read_val);
        if (read_val !== 32'h0000FFFF) begin
            $display("[FAIL] REG_TILE_MASK write/read failed: expected 0x%08X, got 0x%08X", 32'h0000FFFF, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_TILE_MASK write/read successful: 0x%08X", read_val);
        end
        
        if (cfg_tile_mask !== 32'h0000FFFF) begin
            $display("[FAIL] cfg_tile_mask output incorrect: expected 0x%08X, got 0x%08X", 32'h0000FFFF, cfg_tile_mask);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_tile_mask output correct: 0x%08X", cfg_tile_mask);
        end
        
        read_reg(`REG_ITERATIONS, read_val);
        if (read_val !== 32'd8) begin
            $display("[FAIL] REG_ITERATIONS write/read failed: expected 8, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_ITERATIONS write/read successful: %d", read_val);
        end
        
        if (cfg_iterations !== 4'd8) begin
            $display("[FAIL] cfg_iterations output incorrect: expected 8, got %d", cfg_iterations);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_iterations output correct: %d", cfg_iterations);
        end
        
        // ================================================
        //  TEST 5: Start Pulse Generation
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Start Pulse Generation", test_num);
        $display("----------------------------------------");
        
        // Write bit0=1 to generate start pulse
        write_reg(`REG_CTRL, 32'h00000001);
        
        // Check that cfg_start pulses high for one cycle
        wait_cycles(1);
        if (cfg_start !== 1'b1) begin
            $display("[FAIL] cfg_start pulse not generated in first cycle");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_start pulse generated in first cycle");
        end
        
        wait_cycles(1);
        if (cfg_start !== 1'b0) begin
            $display("[FAIL] cfg_start pulse did not return to 0 in second cycle");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_start pulse returned to 0 in second cycle");
        end
        
        // ================================================
        //  TEST 6: Status Clear Pulse Generation
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Status Clear Pulse Generation", test_num);
        $display("----------------------------------------");
        
        // Write bit1=1 to generate clear pulse
        write_reg(`REG_CTRL, 32'h00000002);
        
        wait_cycles(1);
        if (cfg_status_clr !== 1'b1) begin
            $display("[FAIL] cfg_status_clr pulse not generated in first cycle");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_status_clr pulse generated in first cycle");
        end
        
        wait_cycles(1);
        if (cfg_status_clr !== 1'b0) begin
            $display("[FAIL] cfg_status_clr pulse did not return to 0 in second cycle");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_status_clr pulse returned to 0 in second cycle");
        end
        
        // ================================================
        //  TEST 7: IRQ Enable Register
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: IRQ Enable Register", test_num);
        $display("----------------------------------------");
        
        // Enable both done and error interrupts
        write_reg(`REG_IRQ_EN, 32'h00000003);
        
        wait_cycles(1);
        
        read_reg(`REG_IRQ_EN, read_val);
        if (read_val !== 32'h00000003) begin
            $display("[FAIL] REG_IRQ_EN write/read failed: expected 0x%08X, got 0x%08X", 32'h00000003, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_IRQ_EN write/read successful: 0x%08X", read_val);
        end
        
        if (irq_en_done !== 1'b1 || irq_en_error !== 1'b1) begin
            $display("[FAIL] IRQ enable outputs incorrect: done=%b, error=%b", irq_en_done, irq_en_error);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] IRQ enable outputs correct: done=%b, error=%b", irq_en_done, irq_en_error);
        end
        
        // ================================================
        //  TEST 8: Status Register Read
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Status Register Read", test_num);
        $display("----------------------------------------");
        
        // Set status signals
        status_done  <= 1'b1;
        status_error <= 1'b0;
        
        wait_cycles(1);
        
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000001) begin
            $display("[FAIL] REG_STATUS read failed (done=1, error=0): expected 0x%08X, got 0x%08X", 32'h00000001, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS read successful (done=1, error=0): 0x%08X", read_val);
        end
        
        status_done  <= 1'b0;
        status_error <= 1'b1;
        
        wait_cycles(1);
        
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000002) begin
            $display("[FAIL] REG_STATUS read failed (done=0, error=1): expected 0x%08X, got 0x%08X", 32'h00000002, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS read successful (done=0, error=1): 0x%08X", read_val);
        end
        
        status_done  <= 1'b1;
        status_error <= 1'b1;
        
        wait_cycles(1);
        
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000003) begin
            $display("[FAIL] REG_STATUS read failed (done=1, error=1): expected 0x%08X, got 0x%08X", 32'h00000003, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS read successful (done=1, error=1): 0x%08X", read_val);
        end
        
        // Reset status
        status_done  <= 1'b0;
        status_error <= 1'b0;
        
        // ================================================
        //  TEST 9: Computing Lock Mechanism
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Computing Lock Mechanism", test_num);
        $display("----------------------------------------");
        
        // Set computing flag
        computing <= 1'b1;
        
        wait_cycles(1);
        
        // Try to write M register (should be locked)
        write_reg(`REG_M, 32'd100);
        
        wait_cycles(1);
        
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd16) begin
            $display("[FAIL] REG_M was modified during computing: expected 16 (locked), got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M correctly locked during computing: still %d", read_val);
        end
        
        // Try to write N register (should be locked)
        write_reg(`REG_N, 32'd200);
        
        wait_cycles(1);
        
        read_reg(`REG_N, read_val);
        if (read_val !== 32'd32) begin
            $display("[FAIL] REG_N was modified during computing: expected 32 (locked), got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_N correctly locked during computing: still %d", read_val);
        end
        
        // Try to write K register (should be locked)
        write_reg(`REG_K, 32'd128);
        
        wait_cycles(1);
        
        read_reg(`REG_K, read_val);
        if (read_val !== 32'd64) begin
            $display("[FAIL] REG_K was modified during computing: expected 64 (locked), got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_K correctly locked during computing: still %d", read_val);
        end
        
        // Try to write MODE register (should be locked)
        write_reg(`REG_MODE, 32'h000000FF);
        
        wait_cycles(1);
        
        read_reg(`REG_MODE, read_val);
        if (read_val !== 32'h0000000C) begin
            $display("[FAIL] REG_MODE was modified during computing: expected 0x%08X (locked), got 0x%08X", 32'h0000000C, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_MODE correctly locked during computing: still 0x%08X", read_val);
        end
        
        // Try to write TILE_MASK (should NOT be locked)
        write_reg(`REG_TILE_MASK, 32'hAAAAAAAA);
        
        wait_cycles(1);
        
        read_reg(`REG_TILE_MASK, read_val);
        if (read_val !== 32'hAAAAAAAA) begin
            $display("[FAIL] REG_TILE_MASK was not updated (not locked): expected 0x%08X, got 0x%08X", 32'hAAAAAAAA, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_TILE_MASK correctly updated (not locked): 0x%08X", read_val);
        end
        
        // Clear computing flag
        computing <= 1'b0;
        
        wait_cycles(1);
        
        // Now try to write M register (should work)
        write_reg(`REG_M, 32'd100);
        
        wait_cycles(1);
        
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd100) begin
            $display("[FAIL] REG_M write failed after computing cleared: expected 100, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M write successful after computing cleared: %d", read_val);
        end
        
        // ================================================
        //  TEST 10: Multiple Writes to Different Registers
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Multiple Sequential Writes", test_num);
        $display("----------------------------------------");
        
        // Quick succession of writes
        write_reg(`REG_M, 32'd24);
        write_reg(`REG_N, 32'd48);
        write_reg(`REG_K, 32'd96);
        write_reg(`REG_TILE_MASK, 32'hF0F0F0F0);
        write_reg(`REG_ITERATIONS, 32'd16);
        
        wait_cycles(2);
        
        // Verify all values
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd24) begin
            $display("[FAIL] Sequential write REG_M failed: expected 24, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Sequential write REG_M successful: %d", read_val);
        end
        
        read_reg(`REG_N, read_val);
        if (read_val !== 32'd48) begin
            $display("[FAIL] Sequential write REG_N failed: expected 48, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Sequential write REG_N successful: %d", read_val);
        end
        
        read_reg(`REG_K, read_val);
        if (read_val !== 32'd96) begin
            $display("[FAIL] Sequential write REG_K failed: expected 96, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Sequential write REG_K successful: %d", read_val);
        end
        
        read_reg(`REG_TILE_MASK, read_val);
        if (read_val !== 32'hF0F0F0F0) begin
            $display("[FAIL] Sequential write REG_TILE_MASK failed: expected 0x%08X, got 0x%08X", 32'hF0F0F0F0, read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Sequential write REG_TILE_MASK successful: 0x%08X", read_val);
        end
        
        read_reg(`REG_ITERATIONS, read_val);
        if (read_val !== 32'd16) begin
            $display("[FAIL] Sequential write REG_ITERATIONS failed: expected 16, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Sequential write REG_ITERATIONS successful: %d", read_val);
        end

        // ================================================
        //  TEST 11: Mode Register Enumeration
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Mode Register Enumeration (INDEP/MERGE/SPLIT)", test_num);
        $display("----------------------------------------");

        // INDEP mode: mode[1:0] = 2'b00
        write_reg(`REG_MODE, 32'h00000000);
        wait_cycles(1);
        if (cfg_mode !== 2'b00) begin
            $display("[FAIL] INDEP mode: cfg_mode expected 00, got %b", cfg_mode);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] INDEP mode: cfg_mode = %b", cfg_mode);
        end

        // MERGE mode: mode[1:0] = 2'b01
        write_reg(`REG_MODE, 32'h00000001);
        wait_cycles(1);
        if (cfg_mode !== 2'b01) begin
            $display("[FAIL] MERGE mode: cfg_mode expected 01, got %b", cfg_mode);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] MERGE mode: cfg_mode = %b", cfg_mode);
        end

        // SPLIT mode: mode[1:0] = 2'b10
        write_reg(`REG_MODE, 32'h00000002);
        wait_cycles(1);
        if (cfg_mode !== 2'b10) begin
            $display("[FAIL] SPLIT mode: cfg_mode expected 10, got %b", cfg_mode);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] SPLIT mode: cfg_mode = %b", cfg_mode);
        end

        // ================================================
        //  TEST 12: M/N/K Boundary Values
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: M/N/K Boundary Values (0 and 63)", test_num);
        $display("----------------------------------------");

        // Test minimum value 0
        write_reg(`REG_M, 32'd0);
        write_reg(`REG_N, 32'd0);
        write_reg(`REG_K, 32'd0);
        wait_cycles(1);
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] REG_M=0: expected 0, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M=0: read back %d", read_val);
        end
        read_reg(`REG_N, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] REG_N=0: expected 0, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_N=0: read back %d", read_val);
        end
        read_reg(`REG_K, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] REG_K=0: expected 0, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_K=0: read back %d", read_val);
        end

        // Test maximum value 63 (6-bit max)
        write_reg(`REG_M, 32'd63);
        write_reg(`REG_N, 32'd63);
        write_reg(`REG_K, 32'd63);
        wait_cycles(1);
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd63) begin
            $display("[FAIL] REG_M=63: expected 63, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M=63: read back %d", read_val);
        end
        if (cfg_m !== 6'd63) begin
            $display("[FAIL] cfg_m output: expected 63, got %d", cfg_m);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_m output: %d", cfg_m);
        end
        read_reg(`REG_N, read_val);
        if (read_val !== 32'd63) begin
            $display("[FAIL] REG_N=63: expected 63, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_N=63: read back %d", read_val);
        end
        read_reg(`REG_K, read_val);
        if (read_val !== 32'd63) begin
            $display("[FAIL] REG_K=63: expected 63, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_K=63: read back %d", read_val);
        end
        if (cfg_k !== 6'd63) begin
            $display("[FAIL] cfg_k output: expected 63, got %d", cfg_k);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_k output: %d", cfg_k);
        end

        // Test K=64 truncation (6-bit overflow)
        write_reg(`REG_K, 32'd64);
        wait_cycles(1);
        read_reg(`REG_K, read_val);
        if (read_val !== 32'd64) begin
            $display("[FAIL] REG_K=64: expected 64, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_K=64: register stores full 32-bit value %d", read_val);
        end
        // cfg_k is 6-bit, so 64 truncates to 0
        if (cfg_k !== 6'd0) begin
            $display("[FAIL] cfg_k truncation: expected 0 (64 truncated to 6-bit), got %d", cfg_k);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_k truncation: 64 -> %d (6-bit overflow confirmed)", cfg_k);
        end

        // ================================================
        //  TEST 13: Start Pulse During Computing Lock
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Start Pulse During Computing Lock", test_num);
        $display("----------------------------------------");

        computing <= 1'b1;
        wait_cycles(1);

        // Write REG_CTRL with start bit - REG_CTRL is NOT locked
        write_reg(`REG_CTRL, 32'h00000001);
        wait_cycles(1);
        if (cfg_start !== 1'b1) begin
            $display("[FAIL] cfg_start not generated during computing lock");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_start pulse generated during computing lock (REG_CTRL not locked)");
        end

        wait_cycles(1);
        if (cfg_start !== 1'b0) begin
            $display("[FAIL] cfg_start did not return to 0");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_start returned to 0");
        end

        computing <= 1'b0;
        wait_cycles(1);

        // ================================================
        //  TEST 14: Unlocked Registers During Computing
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Unlocked Registers During Computing", test_num);
        $display("----------------------------------------");

        computing <= 1'b1;
        wait_cycles(1);

        // REG_ITERATIONS should NOT be locked
        write_reg(`REG_ITERATIONS, 32'd15);
        wait_cycles(1);
        read_reg(`REG_ITERATIONS, read_val);
        if (read_val !== 32'd15) begin
            $display("[FAIL] REG_ITERATIONS locked during computing: expected 15, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_ITERATIONS writable during computing: %d", read_val);
        end

        // REG_IRQ_EN should NOT be locked
        write_reg(`REG_IRQ_EN, 32'h00000001);
        wait_cycles(1);
        read_reg(`REG_IRQ_EN, read_val);
        if (read_val !== 32'h00000001) begin
            $display("[FAIL] REG_IRQ_EN locked during computing: expected 0x01, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_IRQ_EN writable during computing: 0x%08X", read_val);
        end

        computing <= 1'b0;
        wait_cycles(1);

        // ================================================
        //  TEST 15: REG_CTRL Simultaneous Start + Clear
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: REG_CTRL Simultaneous Start + Clear (0x03)", test_num);
        $display("----------------------------------------");

        write_reg(`REG_CTRL, 32'h00000003);
        wait_cycles(1);
        if (cfg_start !== 1'b1) begin
            $display("[FAIL] cfg_start not asserted with REG_CTRL=0x03");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_start asserted with REG_CTRL=0x03");
        end
        if (cfg_status_clr !== 1'b1) begin
            $display("[FAIL] cfg_status_clr not asserted with REG_CTRL=0x03");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_status_clr asserted with REG_CTRL=0x03");
        end

        wait_cycles(1);
        if (cfg_start !== 1'b0 || cfg_status_clr !== 1'b0) begin
            $display("[FAIL] Pulses did not return to 0: start=%b, clr=%b", cfg_start, cfg_status_clr);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Both pulses returned to 0");
        end

        // ================================================
        //  TEST 16: Async Reset Recovery
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Async Reset Recovery", test_num);
        $display("----------------------------------------");

        // Set non-default values
        write_reg(`REG_M, 32'd32);
        write_reg(`REG_N, 32'd48);
        write_reg(`REG_K, 32'd16);
        write_reg(`REG_MODE, 32'h00000002);
        write_reg(`REG_TILE_MASK, 32'h12345678);
        write_reg(`REG_ITERATIONS, 32'd5);
        wait_cycles(1);

        // Assert async reset
        rst_n <= 1'b0;
        #5;  // Don't wait for clock edge - async reset

        // Check outputs immediately
        if (cfg_m !== 6'd8 || cfg_n !== 6'd8 || cfg_k !== 6'd8) begin
            $display("[FAIL] M/N/K not reset: M=%d, N=%d, K=%d", cfg_m, cfg_n, cfg_k);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] M/N/K reset to defaults: M=%d, N=%d, K=%d", cfg_m, cfg_n, cfg_k);
        end

        // Release reset
        rst_n <= 1'b1;
        wait_cycles(2);

        // Verify all registers are at default
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd8) begin
            $display("[FAIL] REG_M after reset: expected 8, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M after reset: %d", read_val);
        end

        read_reg(`REG_MODE, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] REG_MODE after reset: expected 0, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_MODE after reset: 0x%08X", read_val);
        end

        read_reg(`REG_TILE_MASK, read_val);
        if (read_val !== 32'hFFFFFFFF) begin
            $display("[FAIL] REG_TILE_MASK after reset: expected 0xFFFFFFFF, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_TILE_MASK after reset: 0x%08X", read_val);
        end

        read_reg(`REG_ITERATIONS, read_val);
        if (read_val !== 32'd1) begin
            $display("[FAIL] REG_ITERATIONS after reset: expected 1, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_ITERATIONS after reset: %d", read_val);
        end

        // ================================================
        //  TEST 17: Address Decoding - Illegal Addresses
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Address Decoding - Illegal Addresses", test_num);
        $display("----------------------------------------");

        // Set known values first
        write_reg(`REG_M, 32'd16);
        wait_cycles(1);

        // Write to undefined address 0x03 (non-aligned, not a valid register)
        write_reg(8'h03, 32'hDEADBEEF);
        wait_cycles(1);

        // Read back M - should be unchanged
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd16) begin
            $display("[FAIL] REG_M corrupted by write to 0x03: expected 16, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M unaffected by write to illegal address 0x03");
        end

        // Write to out-of-range address 0xFF
        write_reg(8'hFF, 32'hCAFEBABE);
        wait_cycles(1);

        read_reg(`REG_M, read_val);
        if (read_val !== 32'd16) begin
            $display("[FAIL] REG_M corrupted by write to 0xFF: expected 16, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M unaffected by write to out-of-range address 0xFF");
        end

        // Read from undefined address - should return 0 (default case)
        read_reg(8'hFF, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] Read from 0xFF returned non-zero: 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Read from undefined address 0xFF returns 0");
        end

        // Read from non-aligned address 0x05
        read_reg(8'h05, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] Read from 0x05 returned non-zero: 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Read from non-aligned address 0x05 returns 0");
        end

        // ================================================
        //  TEST 18: Multi-Cycle Write Enable
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Multi-Cycle Write Enable (Bus Glitch)", test_num);
        $display("----------------------------------------");

        // Hold wr_en high for 3 cycles (simulating bus glitch)
        @(posedge clk);
        #1;
        wr_en   <= 1'b1;
        wr_addr <= `REG_M;
        wr_data <= 32'd24;
        @(posedge clk);
        // Still high - second cycle
        @(posedge clk);
        // Still high - third cycle
        @(posedge clk);
        #1;
        wr_en   <= 1'b0;
        wr_addr <= 8'h00;
        wr_data <= 32'h0;

        wait_cycles(1);
        read_reg(`REG_M, read_val);
        // The value should be 24 (written on first edge)
        // With multi-cycle wr_en, the register gets overwritten each cycle
        // but with the same value, so result should still be 24
        if (read_val !== 32'd24) begin
            $display("[FAIL] Multi-cycle wr_en: expected 24, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Multi-cycle wr_en: register value correct (%d)", read_val);
        end

        // Verify output ports are stable
        if (cfg_m !== 6'd24) begin
            $display("[FAIL] cfg_m incorrect after multi-cycle write: expected 24, got %d", cfg_m);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_m stable after multi-cycle write: %d", cfg_m);
        end

        // ================================================
        //  TEST 19: Back-to-Back Start Pulses
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Back-to-Back Start Pulses", test_num);
        $display("----------------------------------------");

        // First start pulse
        write_reg(`REG_CTRL, 32'h00000001);
        wait_cycles(1);
        if (cfg_start !== 1'b1) begin
            $display("[FAIL] First start pulse not generated");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] First start pulse generated");
        end
        wait_cycles(1);
        if (cfg_start !== 1'b0) begin
            $display("[FAIL] First start pulse did not return to 0");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] First start pulse returned to 0");
        end

        // Second start pulse immediately after (no gap)
        write_reg(`REG_CTRL, 32'h00000001);
        wait_cycles(1);
        if (cfg_start !== 1'b1) begin
            $display("[FAIL] Second start pulse not generated");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Second start pulse generated");
        end
        wait_cycles(1);
        if (cfg_start !== 1'b0) begin
            $display("[FAIL] Second start pulse did not return to 0");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Second start pulse returned to 0");
        end

        // ================================================
        //  TEST 20: Write to Read-Only Status Register
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Write to Read-Only STATUS Register", test_num);
        $display("----------------------------------------");

        // Set known status
        status_done  <= 1'b1;
        status_error <= 1'b0;
        wait_cycles(1);

        // Try to write to REG_STATUS (read-only, address 0x04)
        write_reg(`REG_STATUS, 32'hFFFFFFFF);
        wait_cycles(1);

        // REG_STATUS should reflect actual status inputs, not written value
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000001) begin
            $display("[FAIL] REG_STATUS corrupted by write: expected 0x01, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS is read-only, write had no effect: 0x%08X", read_val);
        end

        // Verify M register not affected by write to STATUS address
        read_reg(`REG_M, read_val);
        if (read_val !== 32'd24) begin
            $display("[FAIL] REG_M affected by write to STATUS: expected 24, got %d", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_M unaffected by write to STATUS address");
        end

        status_done  <= 1'b0;
        status_error <= 1'b0;
        wait_cycles(1);

        // ================================================
        //  Final Summary
        // ================================================
        wait_cycles(5);
        
        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("  Total Tests: %d", test_num);
        
        if (test_passed) begin
            $display("  Result: ALL TESTS PASSED ✓");
            $display("========================================");
            $display("[INFO] All tests passed successfully!");
        end else begin
            $display("  Result: SOME TESTS FAILED ✗");
            $display("========================================");
            $display("[ERROR] Some tests failed. Please check the log above.");
        end
        
        $display("  End Time: %t", $time);
        $display("========================================\n");
        
        // Finish simulation
        #50;
        $finish;
    end

    // --------------------------------------------------------
    //  Monitor for unexpected behavior
    // --------------------------------------------------------
    initial begin
        $monitor("Time=%t | wr_en=%b wr_addr=0x%02X wr_data=0x%08X | rd_en=%b rd_addr=0x%02X rd_data=0x%08X | start=%b clr=%b",
                 $time, wr_en, wr_addr, wr_data, rd_en, rd_addr, rd_data, cfg_start, cfg_status_clr);
    end

endmodule
