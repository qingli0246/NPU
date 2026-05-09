`include "npu_defs.vh"

// npu_config - 配置寄存器模块
// 通过 AXI-Lite 接口读写，存储 NPU 工作参数
module npu_config (
    input  wire        clk,
    input  wire        rst_n,
    // 写接口（来自 npu_axi_slave）
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,
    input  wire [31:0] wr_data,
    // 读接口（来自 npu_axi_slave）
    input  wire        rd_en,
    input  wire [7:0]  rd_addr,
    output reg  [31:0] rd_data,
    // 配置输出
    output wire [1:0]  cfg_mode,
    output wire [5:0]  cfg_m,
    output wire [5:0]  cfg_n,
    output wire [5:0]  cfg_k,
    output wire [31:0] cfg_tile_mask,
    output wire [3:0]  cfg_iterations,
    output wire        cfg_start,       // 启动脉冲
    output wire        cfg_status_clr,  // 状态清除脉冲
    output wire        irq_en_done,
    output wire        irq_en_error,
    // 状态输入（来自 npu_status）
    input  wire        status_done,
    input  wire        status_error,
    // 计算中锁定信号（来自 scheduler）
    input  wire        computing
);

    // ========================================================
    //  寄存器定义（时序逻辑块：状态寄存器）
    // ========================================================
    reg [31:0] reg_ctrl;          // 0x00: 控制（bit0:start, bit1:status_clr）
    reg [31:0] reg_mode;          // 0x08: 工作模式 + 权重模式
    reg [31:0] reg_m;             // 0x0C
    reg [31:0] reg_n;             // 0x10
    reg [31:0] reg_k;             // 0x14
    reg [31:0] reg_tile_mask;     // 0x18
    reg [31:0] reg_iterations;    // 0x1C
    reg [31:0] reg_irq_en;        // 0x20

    // 脉冲寄存器
    reg start_pulse;
    reg clr_pulse;

    // ---- 寄存器更新逻辑（时序）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl       <= 32'd0;
            reg_mode       <= 32'd0;
            reg_m          <= 32'd8;
            reg_n          <= 32'd8;
            reg_k          <= 32'd8;
            reg_tile_mask  <= 32'hFFFFFFFF;
            reg_iterations <= 32'd1;
            reg_irq_en     <= 32'd0;
            start_pulse    <= 1'b0;
            clr_pulse      <= 1'b0;
        end else begin
            // 计算写锁定条件
            if (wr_en && !wr_locked) begin
                case (wr_addr[7:0])
                    `REG_CTRL:       reg_ctrl       <= wr_data;
                    `REG_MODE:       reg_mode       <= wr_data;
                    `REG_M:          reg_m          <= wr_data;
                    `REG_N:          reg_n          <= wr_data;
                    `REG_K:          reg_k          <= wr_data;
                    `REG_TILE_MASK:  reg_tile_mask  <= wr_data;
                    `REG_ITERATIONS: reg_iterations <= wr_data;
                    `REG_IRQ_EN:     reg_irq_en     <= wr_data;
                    default: ;
                endcase
            end
            
            // 脉冲生成（写 1 产生单周期脉冲）
            start_pulse <= wr_en && (wr_addr[7:0] == `REG_CTRL) && wr_data[0];
            clr_pulse   <= wr_en && (wr_addr[7:0] == `REG_CTRL) && wr_data[1];
        end
    end

    // ========================================================
    //  写锁定逻辑（组合逻辑块1）
    // ========================================================
    reg wr_locked;
    
    always @(*) begin
        if (computing &&
            (wr_addr[7:0] == `REG_M  || wr_addr[7:0] == `REG_N ||
             wr_addr[7:0] == `REG_K  || wr_addr[7:0] == `REG_MODE))
            wr_locked = 1'b1;
        else
            wr_locked = 1'b0;
    end

    // ========================================================
    //  读数据逻辑（组合逻辑块2：输出逻辑）
    // ========================================================
    reg [31:0] status_reg;
    
    always @(*) begin
        status_reg = {30'd0, status_error, status_done};
        
        if (rd_en) begin
            case (rd_addr[7:0])
                `REG_CTRL:       rd_data = reg_ctrl;
                `REG_STATUS:     rd_data = status_reg;
                `REG_MODE:       rd_data = reg_mode;
                `REG_M:          rd_data = reg_m;
                `REG_N:          rd_data = reg_n;
                `REG_K:          rd_data = reg_k;
                `REG_TILE_MASK:  rd_data = reg_tile_mask;
                `REG_ITERATIONS: rd_data = reg_iterations;
                `REG_IRQ_EN:     rd_data = reg_irq_en;
                default:         rd_data = 32'd0;
            endcase
        end else begin
            rd_data = 32'd0;
        end
    end

    // ========================================================
    //  输出赋值（组合逻辑块3：输出驱动）
    // ========================================================
    assign cfg_mode       = reg_mode[1:0];
    assign cfg_m          = reg_m[5:0];
    assign cfg_n          = reg_n[5:0];
    assign cfg_k          = reg_k[5:0];
    assign cfg_tile_mask  = reg_tile_mask;
    assign cfg_iterations = reg_iterations[3:0];
    assign cfg_start      = start_pulse;
    assign cfg_status_clr = clr_pulse;
    assign irq_en_done    = reg_irq_en[0];
    assign irq_en_error   = reg_irq_en[1];

endmodule