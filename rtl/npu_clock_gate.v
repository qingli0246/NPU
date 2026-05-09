`include "npu_defs.vh"

// npu_clock_gate - ICG (Integrated Clock Gating) 单元
// 使用锁存器 + AND 门实现无毛刺时钟门控
// en=1 时时钟通过，en=0 时时钟停止（低电平）
module npu_clock_gate (
    input  wire clk_in,
    input  wire en,
    output wire clk_out
);

    // 锁存器：在时钟低电平期间锁存使能信号
    // 避免使能信号变化时产生时钟毛刺
    reg en_latched;

    always @(*) begin
        if (!clk_in)
            en_latched <= en;
    end

    // AND 门：时钟与锁存后的使能信号相与
    assign clk_out = clk_in & en_latched;

endmodule