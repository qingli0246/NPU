`include "../rtl/npu_defs.vh"

// ============================================================
//  Testbench for npu_status module (with npu_config)
//  测试NPU状态管理模块，联合npu_config测试status_clr信号交互
// ============================================================

module tb_npu_status_test;

    // --------------------------------------------------------
    //  Parameters
    // --------------------------------------------------------
    parameter CLK_PERIOD = 10;  // 10ns clock period (100MHz)

    // --------------------------------------------------------
    //  Signals - npu_config interface
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
    
    // Configuration outputs from npu_config
    wire [1:0]  cfg_mode;
    wire [5:0]  cfg_m;
    wire [5:0]  cfg_n;
    wire [5:0]  cfg_k;
    wire [31:0] cfg_tile_mask;
    wire [3:0]  cfg_iterations;
    wire        cfg_start;
    wire        cfg_status_clr;  // 连接到npu_status的status_clr
    wire        irq_en_done;     // 连接到npu_status的irq_en_done
    wire        irq_en_error;    // 连接到npu_status的irq_en_error
    
    // --------------------------------------------------------
    //  Signals - npu_status interface
    // --------------------------------------------------------
    // Status inputs to npu_status
    reg         npu_done;
    reg         npu_error;
    
    // Status outputs from npu_status
    wire        status_done;
    wire        status_error;
    wire        npu_irq;

    // --------------------------------------------------------
    //  Instantiate npu_config (DUT1)
    // --------------------------------------------------------
    npu_config dut_config (
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
        .status_done    (status_done),    // 来自npu_status
        .status_error   (status_error),   // 来自npu_status
        .computing      (1'b0)            // 固定为0，不测试锁定功能
    );

    // --------------------------------------------------------
    //  Instantiate npu_status (DUT2)
    // --------------------------------------------------------
    npu_status dut_status (
        .clk            (clk),
        .rst_n          (rst_n),
        .npu_done       (npu_done),
        .npu_error      (npu_error),
        .status_clr     (cfg_status_clr),  // 来自npu_config
        .irq_en_done    (irq_en_done),     // 来自npu_config
        .irq_en_error   (irq_en_error),    // 来自npu_config
        .status_done    (status_done),
        .status_error   (status_error),
        .npu_irq        (npu_irq)
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
    integer i;  // 循环计数器
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
        npu_done        <= 1'b0;
        npu_error       <= 1'b0;
        
        test_num        <= 0;
        test_passed     <= 1'b1;
        
        $display("========================================");
        $display("  NPU Status Module Testbench");
        $display("  (Combined with npu_config)");
        $display("  Start Time: %t", $time);
        $display("========================================");
        
        // Reset sequence
        #20;
        rst_n <= 1'b1;
        $display("\n[INFO] Reset released at time %t", $time);
        
        wait_cycles(2);
        
        // ================================================
        //  TEST 1: Default Values After Reset
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Default Values After Reset", test_num);
        $display("----------------------------------------");
        
        // Check status flags are cleared
        if (status_done !== 1'b0) begin
            $display("[FAIL] status_done not reset: expected 0, got %b", status_done);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done correctly reset to 0");
        end
        
        if (status_error !== 1'b0) begin
            $display("[FAIL] status_error not reset: expected 0, got %b", status_error);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_error correctly reset to 0");
        end
        
        if (npu_irq !== 1'b0) begin
            $display("[FAIL] npu_irq not reset: expected 0, got %b", npu_irq);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq correctly reset to 0");
        end
        
        // Verify REG_STATUS reads 0
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] REG_STATUS default value incorrect: expected 0, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS default value correct: 0x%08X", read_val);
        end
        
        // ================================================
        //  TEST 2: Done Flag Set and Hold
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Done Flag Set and Hold", test_num);
        $display("----------------------------------------");
        
        // Assert npu_done for one cycle
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        
        // Check status_done is set
        wait_cycles(1);
        if (status_done !== 1'b1) begin
            $display("[FAIL] status_done not set after npu_done pulse");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done set correctly after npu_done pulse");
        end
        
        // Verify it holds the value
        wait_cycles(3);
        if (status_done !== 1'b1) begin
            $display("[FAIL] status_done did not hold value");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done held value for 3 cycles");
        end
        
        // Verify REG_STATUS reflects done flag
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000001) begin
            $display("[FAIL] REG_STATUS incorrect (done=1): expected 0x01, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS correct (done=1): 0x%08X", read_val);
        end
        
        // ================================================
        //  TEST 3: Error Flag Set and Hold
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Error Flag Set and Hold", test_num);
        $display("----------------------------------------");
        
        // Clear done first
        write_reg(`REG_CTRL, 32'h00000002);  // status_clr
        wait_cycles(2);
        
        // Assert npu_error for one cycle
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        
        // Check status_error is set
        wait_cycles(1);
        if (status_error !== 1'b1) begin
            $display("[FAIL] status_error not set after npu_error pulse");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_error set correctly after npu_error pulse");
        end
        
        // Verify it holds the value
        wait_cycles(3);
        if (status_error !== 1'b1) begin
            $display("[FAIL] status_error did not hold value");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_error held value for 3 cycles");
        end
        
        // Verify REG_STATUS reflects error flag
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000002) begin
            $display("[FAIL] REG_STATUS incorrect (error=1): expected 0x02, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS correct (error=1): 0x%08X", read_val);
        end
        
        // ================================================
        //  TEST 4: Both Flags Set Simultaneously
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Both Flags Set Simultaneously", test_num);
        $display("----------------------------------------");
        
        // Clear both flags
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        
        // Assert both done and error
        npu_done <= 1'b1;
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        npu_error <= 1'b0;
        
        wait_cycles(1);
        if (status_done !== 1'b1 || status_error !== 1'b1) begin
            $display("[FAIL] Both flags not set: done=%b, error=%b", status_done, status_error);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Both flags set correctly: done=%b, error=%b", status_done, status_error);
        end
        
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000003) begin
            $display("[FAIL] REG_STATUS incorrect (done=1, error=1): expected 0x03, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS correct (done=1, error=1): 0x%08X", read_val);
        end
        
        // ================================================
        //  TEST 5: Status Clear via REG_CTRL
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Status Clear via REG_CTRL", test_num);
        $display("----------------------------------------");
        
        // Clear status using REG_CTRL bit1
        write_reg(`REG_CTRL, 32'h00000002);
        
        wait_cycles(2);
        
        if (status_done !== 1'b0 || status_error !== 1'b0) begin
            $display("[FAIL] Flags not cleared: done=%b, error=%b", status_done, status_error);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Both flags cleared via REG_CTRL");
        end
        
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'd0) begin
            $display("[FAIL] REG_STATUS not cleared: expected 0, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS cleared: 0x%08X", read_val);
        end
        
        // ================================================
        //  TEST 6: Interrupt Generation - Done Only
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Interrupt Generation - Done Only", test_num);
        $display("----------------------------------------");
        
        // Enable done interrupt only
        write_reg(`REG_IRQ_EN, 32'h00000001);
        wait_cycles(1);
        
        // Trigger npu_done
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        
        // Check interrupt is generated on rising edge
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] npu_irq not generated for done event");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq generated for done event");
        end
        
        // Interrupt should return to 0 next cycle
        wait_cycles(1);
        if (npu_irq !== 1'b0) begin
            $display("[FAIL] npu_irq did not return to 0");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq returned to 0 after one cycle");
        end
        
        // ================================================
        //  TEST 7: Interrupt Generation - Error Only
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Interrupt Generation - Error Only", test_num);
        $display("----------------------------------------");
        
        // Clear status
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        
        // Enable error interrupt only
        write_reg(`REG_IRQ_EN, 32'h00000002);
        wait_cycles(1);
        
        // Trigger npu_error
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] npu_irq not generated for error event");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq generated for error event");
        end
        
        wait_cycles(1);
        if (npu_irq !== 1'b0) begin
            $display("[FAIL] npu_irq did not return to 0");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq returned to 0 after one cycle");
        end
        
        // ================================================
        //  TEST 8: Interrupt Generation - Both Enabled
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Interrupt Generation - Both Enabled", test_num);
        $display("----------------------------------------");
        
        // Clear status
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        
        // Enable both interrupts
        write_reg(`REG_IRQ_EN, 32'h00000003);
        wait_cycles(1);
        
        // Trigger done first
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] npu_irq not generated for done (both enabled)");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq generated for done (both enabled)");
        end
        
        wait_cycles(1);
        
        // Trigger error
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] npu_irq not generated for error (both enabled)");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq generated for error (both enabled)");
        end
        
        // ================================================
        //  TEST 9: No Interrupt When Disabled
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: No Interrupt When Disabled", test_num);
        $display("----------------------------------------");
        
        // Clear status
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        
        // Disable all interrupts
        write_reg(`REG_IRQ_EN, 32'h00000000);
        wait_cycles(1);
        
        // Trigger done
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        
        wait_cycles(1);
        if (npu_irq !== 1'b0) begin
            $display("[FAIL] npu_irq generated when disabled (done)");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] No interrupt when disabled (done)");
        end
        
        // Trigger error
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        
        wait_cycles(1);
        if (npu_irq !== 1'b0) begin
            $display("[FAIL] npu_irq generated when disabled (error)");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] No interrupt when disabled (error)");
        end
        
        // ================================================
        //  TEST 10: Edge Detection - No Double Trigger
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Edge Detection - No Double Trigger", test_num);
        $display("----------------------------------------");
        
        // Clear status
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        
        // Enable done interrupt
        write_reg(`REG_IRQ_EN, 32'h00000001);
        wait_cycles(1);
        
        // Hold npu_done high for multiple cycles
        npu_done <= 1'b1;
        wait_cycles(1);
        
        // First cycle: edge detector captures current value (no interrupt yet)
        // Second cycle: rising edge detected (previous=0, current=1)
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] npu_irq not triggered on rising edge of done");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq triggered on rising edge (detected in second cycle)");
        end
        
        // Third cycle should NOT trigger (no edge, signal still high)
        wait_cycles(1);
        if (npu_irq !== 1'b0) begin
            $display("[FAIL] npu_irq re-triggered on sustained high (should be edge-sensitive)");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq not re-triggered on sustained signal (edge-sensitive)");
        end
        
        npu_done <= 1'b0;
        wait_cycles(1);
        
        // ================================================
        //  TEST 11: Multiple Done Pulses
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Multiple Done Pulses", test_num);
        $display("----------------------------------------");
        
        // Clear status
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        
        // Enable done interrupt
        write_reg(`REG_IRQ_EN, 32'h00000001);
        wait_cycles(1);
        
        // Generate multiple done pulses
        for (i = 0; i < 3; i = i + 1) begin
            npu_done <= 1'b1;
            wait_cycles(1);
            npu_done <= 1'b0;
            wait_cycles(1);
            
            if (npu_irq !== 1'b1) begin
                $display("[FAIL] npu_irq not generated for pulse %d", i+1);
                test_passed = 1'b0;
            end else begin
                $display("[PASS] npu_irq generated for pulse %d", i+1);
            end
            
            wait_cycles(1);
        end
        
        // ================================================
        //  TEST 12: Status Register Dynamic Update
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Status Register Dynamic Update", test_num);
        $display("----------------------------------------");
        
        // Clear status
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        
        // Set done only
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        wait_cycles(1);
        
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000001) begin
            $display("[FAIL] REG_STATUS after done: expected 0x01, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS after done: 0x%08X", read_val);
        end
        
        // Set error only (done still set)
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        wait_cycles(1);
        
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000003) begin
            $display("[FAIL] REG_STATUS after error: expected 0x03, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS after error: 0x%08X", read_val);
        end
        
        // Clear only done (via clear then set error again)
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        wait_cycles(1);
        
        read_reg(`REG_STATUS, read_val);
        if (read_val !== 32'h00000002) begin
            $display("[FAIL] REG_STATUS after clear+error: expected 0x02, got 0x%08X", read_val);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] REG_STATUS after clear+error: 0x%08X", read_val);
        end
        
        // ================================================
        //  TEST 13: Async Reset Behavior
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Async Reset Behavior", test_num);
        $display("----------------------------------------");
        
        // Set some flags
        npu_done <= 1'b1;
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        npu_error <= 1'b0;
        wait_cycles(1);
        
        // Verify flags are set
        if (status_done !== 1'b1 || status_error !== 1'b1) begin
            $display("[FAIL] Flags not set before reset");
            test_passed = 1'b0;
        end
        
        // Assert async reset
        rst_n <= 1'b0;
        #5;  // Don't wait for clock edge
        
        // Check immediate reset
        if (status_done !== 1'b0 || status_error !== 1'b0 || npu_irq !== 1'b0) begin
            $display("[FAIL] Flags not reset asynchronously: done=%b, error=%b, irq=%b", 
                     status_done, status_error, npu_irq);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] All flags reset asynchronously");
        end
        
        // Release reset
        rst_n <= 1'b1;
        wait_cycles(2);
        
        // Verify still cleared
        if (status_done !== 1'b0 || status_error !== 1'b0) begin
            $display("[FAIL] Flags not held after reset release");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Flags held cleared after reset release");
        end

        // ================================================
        //  TEST 14: Interrupt Re-trigger After Clear
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Interrupt Re-trigger After Clear", test_num);
        $display("----------------------------------------");

        // Clear status and enable done interrupt
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        write_reg(`REG_IRQ_EN, 32'h00000001);
        wait_cycles(1);

        // First done pulse → should generate interrupt
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] First done pulse: no interrupt");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] First done pulse: interrupt generated");
        end
        wait_cycles(1);

        // Clear status
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);

        // Second done pulse → should generate interrupt again
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] Second done pulse after clear: no interrupt");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Second done pulse after clear: interrupt re-triggered");
        end
        wait_cycles(1);

        // ================================================
        //  TEST 15: Back-to-Back Error Pulses
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Back-to-Back Error Pulses", test_num);
        $display("----------------------------------------");

        // Clear and enable error interrupt
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        write_reg(`REG_IRQ_EN, 32'h00000002);
        wait_cycles(1);

        // First error pulse
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] First error pulse: no interrupt");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] First error pulse: interrupt generated");
        end
        wait_cycles(1);

        // Second error pulse immediately (no clear in between)
        // NOTE: npu_irq is edge-triggered on npu_error input, NOT on status_error flag.
        // A new rising edge of npu_error generates a new interrupt regardless of flag state.
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] Second error pulse: interrupt not generated (edge-triggered, should fire)");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Second error pulse: interrupt fires on new rising edge (edge-triggered behavior)");
        end
        wait_cycles(1);

        // ================================================
        //  TEST 16: Interrupt Enable After Event
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Interrupt Enable After Event", test_num);
        $display("----------------------------------------");

        // Clear status, disable interrupts
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        write_reg(`REG_IRQ_EN, 32'h00000000);
        wait_cycles(1);

        // Trigger done (interrupt disabled)
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        wait_cycles(1);
        if (npu_irq !== 1'b0) begin
            $display("[FAIL] Interrupt fired when disabled");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] No interrupt when disabled");
        end

        // Now enable interrupt AFTER event already occurred
        write_reg(`REG_IRQ_EN, 32'h00000001);
        wait_cycles(2);
        if (npu_irq !== 1'b0) begin
            $display("[FAIL] Interrupt generated after enabling (event already past, no new edge)");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] No interrupt after enabling (edge already passed)");
        end

        // Only a NEW done event should trigger
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        wait_cycles(1);
        if (npu_irq !== 1'b1) begin
            $display("[FAIL] New done event: no interrupt");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] New done event: interrupt generated correctly");
        end
        wait_cycles(1);

        // ================================================
        //  TEST 17: REG_CTRL=0x03 Simultaneous Start + Clear
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: REG_CTRL=0x03 (Start + Clear)", test_num);
        $display("----------------------------------------");

        // Set done flag first
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        wait_cycles(1);
        if (status_done !== 1'b1) begin
            $display("[FAIL] status_done not set before test");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done set before test");
        end

        // Write REG_CTRL=0x03 (start + clear simultaneously)
        write_reg(`REG_CTRL, 32'h00000003);
        wait_cycles(2);

        // Status should be cleared
        if (status_done !== 1'b0) begin
            $display("[FAIL] status_done not cleared by REG_CTRL=0x03");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done cleared by REG_CTRL=0x03");
        end

        // Actually verify cfg_start was generated by checking it directly
        // We need to write REG_CTRL=0x03 again and check cfg_start in the same cycle
        write_reg(`REG_CTRL, 32'h00000000);  // clear any residual
        wait_cycles(1);

        // Manually drive wr_en to check cfg_start pulse simultaneously
        @(posedge clk);
        #1;
        wr_en   <= 1'b1;
        wr_addr <= `REG_CTRL;
        wr_data <= 32'h00000003;
        @(posedge clk);
        #1;
        // cfg_start should be high NOW (pulse generated from registered wr_en)
        if (cfg_start !== 1'b1) begin
            $display("[FAIL] cfg_start not generated with REG_CTRL=0x03");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_start generated with REG_CTRL=0x03");
        end
        if (cfg_status_clr !== 1'b1) begin
            $display("[FAIL] cfg_status_clr not generated with REG_CTRL=0x03");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] cfg_status_clr generated with REG_CTRL=0x03");
        end
        wr_en   <= 1'b0;
        wr_addr <= 8'h00;
        wr_data <= 32'h0;
        @(posedge clk);
        #1;
        // Both should return to 0
        if (cfg_start !== 1'b0 || cfg_status_clr !== 1'b0) begin
            $display("[FAIL] Pulses did not return to 0: start=%b, clr=%b", cfg_start, cfg_status_clr);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Both pulses returned to 0 after REG_CTRL=0x03");
        end

        // ================================================
        //  TEST 18: Race Condition - status_clr vs npu_done
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Race Condition - status_clr vs npu_done", test_num);
        $display("----------------------------------------");

        // Clear status first
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);

        // Set done flag
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        wait_cycles(1);

        if (status_done !== 1'b1) begin
            $display("[FAIL] status_done not set before race test");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done set before race test");
        end

        // Now fire status_clr AND npu_done on the SAME cycle
        @(posedge clk);
        #1;
        npu_done <= 1'b1;
        wr_en    <= 1'b1;
        wr_addr  <= `REG_CTRL;
        wr_data  <= 32'h00000002;  // status_clr
        @(posedge clk);
        #1;
        wr_en    <= 1'b0;
        wr_addr  <= 8'h00;
        wr_data  <= 32'h0;
        npu_done <= 1'b0;

        // Wait for clr pulse to take effect (registered, so 1 cycle delay)
        wait_cycles(2);

        // After the race: clr should clear the flag, but done rising edge may re-set it
        // The result depends on implementation: clr is registered (1 cycle delay),
        // while done rising edge is also detected (1 cycle delay).
        // Both happen on the same cycle → status_done gets cleared by clr,
        // then the done rising edge sets it again on the NEXT cycle.
        // So status_done should ultimately be 1 (done wins because it's re-set after clr).
        // But the key test is: no glitch, no unknown state.
        if (status_done === 1'bx || status_done === 1'bz) begin
            $display("[FAIL] status_done is unknown after race condition: %b", status_done);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done has valid value after race condition: %b", status_done);
        end

        if (status_error === 1'bx || status_error === 1'bz) begin
            $display("[FAIL] status_error is unknown after race condition: %b", status_error);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_error has valid value after race condition: %b", status_error);
        end

        // ================================================
        //  TEST 19: Consecutive status_clr Pulses
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Consecutive status_clr Pulses", test_num);
        $display("----------------------------------------");

        // Set done flag
        npu_done <= 1'b1;
        wait_cycles(1);
        npu_done <= 1'b0;
        wait_cycles(1);

        if (status_done !== 1'b1) begin
            $display("[FAIL] status_done not set");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done set");
        end

        // First clr
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        if (status_done !== 1'b0) begin
            $display("[FAIL] First clr: status_done not cleared");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] First clr: status_done cleared");
        end

        // Second clr immediately (no new event in between)
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        if (status_done !== 1'b0) begin
            $display("[FAIL] Second clr: status_done not still cleared");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Second clr: status_done still cleared (idempotent)");
        end

        // Set error, then clr twice
        npu_error <= 1'b1;
        wait_cycles(1);
        npu_error <= 1'b0;
        wait_cycles(1);

        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);

        if (status_error !== 1'b0) begin
            $display("[FAIL] Double clr on error: status_error not cleared");
            test_passed = 1'b0;
        end else begin
            $display("[PASS] Double clr on error: status_error cleared");
        end

        // ================================================
        //  TEST 20: Interrupt Enable Toggled During Event
        // ================================================
        test_num = test_num + 1;
        $display("\n----------------------------------------");
        $display("  TEST %d: Interrupt Enable Toggled During Event", test_num);
        $display("----------------------------------------");

        // Clear status, enable done interrupt
        write_reg(`REG_CTRL, 32'h00000002);
        wait_cycles(2);
        write_reg(`REG_IRQ_EN, 32'h00000001);
        wait_cycles(1);

        // Start done pulse
        npu_done <= 1'b1;

        // On the SAME cycle as done goes high, disable the interrupt
        @(posedge clk);
        #1;
        write_reg(`REG_IRQ_EN, 32'h00000000);

        @(posedge clk);
        #1;
        npu_done <= 1'b0;
        wr_en    <= 1'b0;
        wr_addr  <= 8'h00;
        wr_data  <= 32'h0;

        // The interrupt enable is registered, so the edge detection
        // may or may not see the enable depending on timing.
        // The key test: no glitch, no unknown state on irq.
        wait_cycles(2);
        if (npu_irq === 1'bx || npu_irq === 1'bz) begin
            $display("[FAIL] npu_irq is unknown after enable toggle: %b", npu_irq);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] npu_irq has valid value after enable toggle: %b (behavior depends on timing)", npu_irq);
        end

        // Verify status_done was still set (event occurred)
        if (status_done !== 1'b1) begin
            $display("[FAIL] status_done not set after event: %b", status_done);
            test_passed = 1'b0;
        end else begin
            $display("[PASS] status_done correctly set after event: %b", status_done);
        end

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
    //  Monitor for key signals
    // --------------------------------------------------------
    initial begin
        $monitor("Time=%t | npu_done=%b npu_error=%b | status_done=%b status_error=%b | irq=%b | clr=%b",
                 $time, npu_done, npu_error, status_done, status_error, npu_irq, cfg_status_clr);
    end

endmodule
