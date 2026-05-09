`include "npu_defs.vh"

// ============================================================
// npu_status - 状态管理模块（标准FSM三分法重构）
// 管理 done/error 标志，生成中断输出
// 
// FSM设计原则：
// 1. 时序逻辑块：状态标志寄存器更新
// 2. 组合逻辑块：边沿检测逻辑
// 3. 组合逻辑块：中断输出逻辑
// ============================================================
module npu_status (
    input  wire        clk,
    input  wire        rst_n,
    // 状态输入
    input  wire        npu_done,
    input  wire        npu_error,
    // 控制输入
    input  wire        status_clr,
    // 中断使能
    input  wire        irq_en_done,
    input  wire        irq_en_error,
    // 状态输出
    output reg         status_done,
    output reg         status_error,
    // 中断输出
    output reg         npu_irq
);

    // ========================================================
    //  Done 标志寄存器（时序逻辑块1）
    //  置位后保持，直到 status_clr 清除
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            status_done <= 1'b0;
        else if (status_clr)
            status_done <= 1'b0;
        else if (npu_done)
            status_done <= 1'b1;
    end

    // ========================================================
    //  Error 标志寄存器（时序逻辑块2）
    //  置位后保持，直到 status_clr 清除
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            status_error <= 1'b0;
        else if (status_clr)
            status_error <= 1'b0;
        else if (npu_error)
            status_error <= 1'b1;
    end

    // ========================================================
    //  边沿检测逻辑（时序逻辑块3：延迟寄存器）
    // ========================================================
    reg done_d, error_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_d  <= 1'b0;
            error_d <= 1'b0;
        end else begin
            done_d  <= npu_done;
            error_d <= npu_error;
        end
    end

    // ========================================================
    //  边沿检测输出（组合逻辑块1）
    // ========================================================
    wire done_rise;
    wire error_rise;
    
    assign done_rise  = npu_done  & ~done_d;
    assign error_rise = npu_error & ~error_d;

    // ========================================================
    //  中断输出逻辑（组合逻辑块2 + 时序驱动）
    // ========================================================
    reg irq_next;  // ✅ 改为 reg，因为在 always @(*) 中赋值
    
    always @(*) begin
        irq_next = (done_rise & irq_en_done) | (error_rise & irq_en_error);
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            npu_irq <= 1'b0;
        else
            npu_irq <= irq_next;
    end

endmodule