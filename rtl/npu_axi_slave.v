`include "npu_defs.vh"

// ============================================================
// npu_axi_slave - AXI4 Slave 接口模块（标准FSM三分法重构）
// 处理 AXI4 协议，将事务转换为内部寄存器读写和 Buffer 读写请求
// 
// FSM设计原则：
// 1. 时序逻辑块：仅包含状态寄存器更新
// 2. 组合逻辑块（下一状态）：纯组合逻辑，计算next_state
// 3. 组合逻辑块（输出）：纯组合逻辑，计算所有输出信号
// ============================================================
module npu_axi_slave #(
    parameter ADDR_WIDTH = `NPU_AXI_ADDR_WIDTH,
    parameter DATA_WIDTH = `NPU_AXI_DATA_WIDTH
)(
    input  wire                    clk,
    input  wire                    rst_n,
    // ---- AXI4 Slave 接口 ----
    // AW 通道
    input  wire [ADDR_WIDTH-1:0]   axi_awaddr,
    input  wire [7:0]              axi_awlen,
    input  wire [2:0]              axi_awsize,
    input  wire [1:0]              axi_awburst,
    input  wire                    axi_awvalid,
    output reg                     axi_awready,
    // W 通道
    input  wire [DATA_WIDTH-1:0]   axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] axi_wstrb,
    input  wire                    axi_wlast,
    input  wire                    axi_wvalid,
    output reg                     axi_wready,
    // B 通道
    output reg  [1:0]              axi_bresp,
    output reg                     axi_bvalid,
    input  wire                    axi_bready,
    // AR 通道
    input  wire [ADDR_WIDTH-1:0]   axi_araddr,
    input  wire [7:0]              axi_arlen,
    input  wire [2:0]              axi_arsize,
    input  wire [1:0]              axi_arburst,
    input  wire                    axi_arvalid,
    output reg                     axi_arready,
    // R 通道
    output wire [DATA_WIDTH-1:0]   axi_rdata,
    output reg  [1:0]              axi_rresp,
    output reg                     axi_rlast,
    output reg                     axi_rvalid,
    input  wire                    axi_rready,
    // ---- 内部寄存器接口 ----
    output reg                     reg_wr_en,
    output reg  [7:0]              reg_wr_addr,
    output reg  [31:0]             reg_wr_data,
    output reg                     reg_rd_en,
    output reg  [7:0]              reg_rd_addr,
    input  wire [31:0]             reg_rd_data,
    // ---- 内部 Buffer 接口 ----
    output reg                     buf_wr_en,
    output reg  [ADDR_WIDTH-1:0]   buf_wr_addr,
    output reg  [DATA_WIDTH-1:0]   buf_wr_data,
    output reg  [3:0]              buf_wr_strb,
    output reg                     buf_rd_en,
    output reg  [ADDR_WIDTH-1:0]   buf_rd_addr,
    input  wire [DATA_WIDTH-1:0]   buf_rd_data,
    input  wire                    buf_rd_valid
);

    // ========================================================
    //  地址解码辅助信号
    // ========================================================
    wire aw_is_reg = (axi_awaddr < `NPU_AXI_LITE_SIZE);
    wire ar_is_reg = (axi_araddr < `NPU_AXI_LITE_SIZE);

    // ========================================================
    //  写通道 FSM - 标准三分法
    //  状态定义：W_IDLE → W_DATA → W_RESP
    // ========================================================
    localparam W_IDLE = 2'd0, W_DATA = 2'd1, W_RESP = 2'd2;

    // ---- 写通道状态寄存器（时序逻辑）----
    reg [1:0]              w_state;
    reg [ADDR_WIDTH-1:0]   w_addr;
    reg [7:0]              w_len;
    reg [7:0]              w_cnt;
    reg                    w_is_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state    <= W_IDLE;
            w_addr     <= {ADDR_WIDTH{1'b0}};
            w_len      <= 8'd0;
            w_cnt      <= 8'd0;
            w_is_reg   <= 1'b0;
        end else begin
            w_state    <= w_next_state;
            w_addr     <= w_addr_next;
            w_len      <= w_len_next;
            w_cnt      <= w_cnt_next;
            w_is_reg   <= w_is_reg_next;
        end
    end

    // ---- 写通道下一状态逻辑（组合逻辑）----
    reg [1:0]              w_next_state;
    reg [ADDR_WIDTH-1:0]   w_addr_next;
    reg [7:0]              w_len_next;
    reg [7:0]              w_cnt_next;
    reg                    w_is_reg_next;

    wire [ADDR_WIDTH-1:0] w_addr_inc = w_addr + (DATA_WIDTH/8);

    always @(*) begin
        // 默认值
        w_next_state = w_state;
        w_addr_next  = w_addr;
        w_len_next   = w_len;
        w_cnt_next   = w_cnt;
        w_is_reg_next= w_is_reg;

        case (w_state)
            // ---- W_IDLE: 等待 AW 或 W 有效 ----
            W_IDLE: begin
                if (axi_awvalid && axi_wvalid) begin
                    // AW+W 同时有效：直接接受，下一状态 W_RESP
                    w_next_state = W_RESP;
                    w_cnt_next   = 8'd0;
                    w_is_reg_next= aw_is_reg;
                end else if (axi_awvalid) begin
                    // 仅 AW 有效：捕获地址，下一状态 W_DATA
                    w_next_state = W_DATA;
                    w_addr_next  = axi_awaddr;
                    w_len_next   = axi_awlen;
                    w_cnt_next   = 8'd0;
                    w_is_reg_next= aw_is_reg;
                end
            end

            // ---- W_DATA: 等待 W 数据 ----
            W_DATA: begin
                if (axi_wvalid) begin
                    w_addr_next = w_addr_inc;
                    w_cnt_next  = w_cnt + 8'd1;
                    if (axi_wlast) begin
                        w_next_state = W_RESP;
                    end
                end
            end

            // ---- W_RESP: 发送 B 响应 ----
            W_RESP: begin
                if (axi_bready) begin
                    w_next_state = W_IDLE;
                end
            end

            default: w_next_state = W_IDLE;
        endcase
    end

    // ---- 写通道输出逻辑（组合逻辑）----
    reg w_awready;
    reg w_wready;
    reg w_bvalid;
    reg [1:0] w_bresp;
    reg w_reg_wr_en;
    reg [7:0] w_reg_wr_addr;
    reg [31:0] w_reg_wr_data;
    reg w_buf_wr_en;
    reg [ADDR_WIDTH-1:0] w_buf_wr_addr;
    reg [DATA_WIDTH-1:0] w_buf_wr_data;
    reg [3:0] w_buf_wr_strb;

    always @(*) begin
        // 默认值
        w_awready      = 1'b0;
        w_wready       = 1'b0;
        w_bvalid       = 1'b0;
        w_bresp        = `AXI_RESP_OKAY;
        w_reg_wr_en    = 1'b0;
        w_reg_wr_addr  = 8'h0;
        w_reg_wr_data  = 32'h0;
        w_buf_wr_en    = 1'b0;
        w_buf_wr_addr  = {ADDR_WIDTH{1'b0}};
        w_buf_wr_data  = {DATA_WIDTH{1'b0}};
        w_buf_wr_strb  = 4'h0;

        case (w_state)
            // ---- W_IDLE: 等待 AW 或 W ----
            W_IDLE: begin
                if (axi_awvalid && axi_wvalid) begin
                    // AW+W 同时有效
                    w_awready = 1'b1;
                    w_wready  = 1'b1;
                    if (aw_is_reg) begin
                        w_reg_wr_en   = 1'b1;
                        w_reg_wr_addr = axi_awaddr[7:0];
                        w_reg_wr_data = axi_wdata;
                    end else begin
                        w_buf_wr_en   = 1'b1;
                        w_buf_wr_addr = axi_awaddr;
                        w_buf_wr_data = axi_wdata;
                        w_buf_wr_strb = axi_wstrb;
                    end
                end else if (axi_awvalid) begin
                    // 仅 AW 有效
                    w_awready = 1'b1;
                end
            end

            // ---- W_DATA: 接收 W 数据 ----
            W_DATA: begin
                w_wready = 1'b1;
                if (axi_wvalid) begin
                    if (w_is_reg) begin
                        w_reg_wr_en   = 1'b1;
                        w_reg_wr_addr = w_addr[7:0];
                        w_reg_wr_data = axi_wdata;
                    end else begin
                        w_buf_wr_en   = 1'b1;
                        w_buf_wr_addr = w_addr;
                        w_buf_wr_data = axi_wdata;
                        w_buf_wr_strb = axi_wstrb;
                    end
                end
            end

            // ---- W_RESP: 发送 B 响应 ----
            W_RESP: begin
                w_bvalid = 1'b1;
                w_bresp  = `AXI_RESP_OKAY;
            end

            default: ;
        endcase
    end

    // ---- 写通道输出赋值（时序逻辑）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= `AXI_RESP_OKAY;
            reg_wr_en   <= 1'b0;
            reg_wr_addr <= 8'h0;
            reg_wr_data <= 32'h0;
            buf_wr_en   <= 1'b0;
            buf_wr_addr <= {ADDR_WIDTH{1'b0}};
            buf_wr_data <= {DATA_WIDTH{1'b0}};
            buf_wr_strb <= 4'h0;
        end else begin
            axi_awready <= w_awready;
            axi_wready  <= w_wready;
            axi_bvalid  <= w_bvalid;
            axi_bresp   <= w_bresp;
            reg_wr_en   <= w_reg_wr_en;
            reg_wr_addr <= w_reg_wr_addr;
            reg_wr_data <= w_reg_wr_data;
            buf_wr_en   <= w_buf_wr_en;
            buf_wr_addr <= w_buf_wr_addr;
            buf_wr_data <= w_buf_wr_data;
            buf_wr_strb <= w_buf_wr_strb;
        end
    end

    // ========================================================
    //  读通道 FSM - 标准三分法
    //  状态定义：R_IDLE → R_WAIT → R_DATA
    // ========================================================
    localparam R_IDLE = 2'd0, R_WAIT = 2'd1, R_DATA = 2'd2;

    // ---- 读通道状态寄存器（时序逻辑）----
    reg [1:0]              r_state;
    reg [ADDR_WIDTH-1:0]   r_addr;
    reg [7:0]              r_len;
    reg [7:0]              r_cnt;
    reg                    r_is_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state    <= R_IDLE;
            r_addr     <= {ADDR_WIDTH{1'b0}};
            r_len      <= 8'd0;
            r_cnt      <= 8'd0;
            r_is_reg   <= 1'b0;
        end else begin
            r_state    <= r_next_state;
            r_addr     <= r_addr_next;
            r_len      <= r_len_next;
            r_cnt      <= r_cnt_next;
            r_is_reg   <= r_is_reg_next;
        end
    end

    // ---- 读通道下一状态逻辑（组合逻辑）----
    reg [1:0]              r_next_state;
    reg [ADDR_WIDTH-1:0]   r_addr_next;
    reg [7:0]              r_len_next;
    reg [7:0]              r_cnt_next;
    reg                    r_is_reg_next;

    wire [ADDR_WIDTH-1:0] r_addr_inc = r_addr + (DATA_WIDTH/8);

    always @(*) begin
        // 默认值
        r_next_state = r_state;
        r_addr_next  = r_addr;
        r_len_next   = r_len;
        r_cnt_next   = r_cnt;
        r_is_reg_next= r_is_reg;

        case (r_state)
            // ---- R_IDLE: 等待 AR 握手 ----
            R_IDLE: begin
                if (axi_arvalid) begin
                    r_next_state  = R_WAIT;
                    r_addr_next   = axi_araddr;
                    r_len_next    = axi_arlen;
                    r_cnt_next    = 8'd0;
                    r_is_reg_next = ar_is_reg;
                end
            end

            // ---- R_WAIT: 发起读请求 ----
            R_WAIT: begin
                r_next_state = R_DATA;
            end

            // ---- R_DATA: 输出数据 ----
            R_DATA: begin
                if (axi_rvalid && axi_rready) begin
                    if (r_cnt == r_len) begin
                        // 最后一拍完成
                        r_next_state = R_IDLE;
                    end else begin
                        // 继续下一拍
                        r_next_state = R_WAIT;
                        r_addr_next  = r_addr_inc;
                        r_cnt_next   = r_cnt + 8'd1;
                    end
                end
            end

            default: r_next_state = R_IDLE;
        endcase
    end

    // ---- 读通道输出逻辑（组合逻辑）----
    reg r_arready;
    reg r_rvalid;
    reg r_rlast;
    reg [DATA_WIDTH-1:0] r_rdata;
    reg [1:0] r_rresp;
    reg r_reg_rd_en;
    reg [7:0] r_reg_rd_addr;
    reg r_buf_rd_en;
    reg [ADDR_WIDTH-1:0] r_buf_rd_addr;
    // ========================================================
    //  读数据直接输出（组合逻辑，消除一拍延迟）
    // ========================================================
    assign axi_rdata = r_rdata;
    
    always @(*) begin
        // 默认值
        r_arready    = 1'b0;
        r_rvalid     = 1'b0;
        r_rlast      = 1'b0;
        r_rdata      = {DATA_WIDTH{1'b0}};
        r_rresp      = `AXI_RESP_OKAY;
        r_reg_rd_en  = 1'b0;
        r_reg_rd_addr= 8'h0;
        r_buf_rd_en  = 1'b0;
        r_buf_rd_addr= {ADDR_WIDTH{1'b0}};

        case (r_state)
            // ---- R_IDLE: 等待 AR ----
            R_IDLE: begin
                if (axi_arvalid) begin
                    r_arready = 1'b1;
                end
            end

            // ---- R_WAIT: 发起读请求 ----
            R_WAIT: begin
                if (r_is_reg) begin
                    r_reg_rd_en   = 1'b1;
                    r_reg_rd_addr = r_addr[7:0];
                end else begin
                    r_buf_rd_en   = 1'b1;
                    r_buf_rd_addr = r_addr;
                end
            end

            // ---- R_DATA: 输出数据 ----
            R_DATA: begin
                // 保持读使能
                if (r_is_reg) begin
                    r_reg_rd_en   = 1'b1;
                    r_reg_rd_addr = r_addr[7:0];
                end else begin
                    r_buf_rd_en   = 1'b1;
                    r_buf_rd_addr = r_addr;
                end

                // 输出数据
                if (r_is_reg) begin
                    r_rdata = reg_rd_data;
                end else begin
                    r_rdata = buf_rd_valid ? buf_rd_data : {DATA_WIDTH{1'b0}};
                end
                r_rresp = `AXI_RESP_OKAY;

                // 控制输出有效
                if (!axi_rvalid || (axi_rvalid && axi_rready)) begin
                    r_rvalid = 1'b1;
                    r_rlast  = (r_cnt == r_len);
                end
            end

            default: ;
        endcase
    end

    // ---- 读通道输出赋值（时序逻辑）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rlast   <= 1'b0;
           // axi_rdata   <= {DATA_WIDTH{1'b0}};
            axi_rresp   <= `AXI_RESP_OKAY;
            reg_rd_en   <= 1'b0;
            reg_rd_addr <= 8'h0;
            buf_rd_en   <= 1'b0;
            buf_rd_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            axi_arready <= r_arready;
            axi_rvalid  <= r_rvalid;
            axi_rlast   <= r_rlast;
            // axi_rdata   <= r_rdata;
            axi_rresp   <= r_rresp;
            reg_rd_en   <= r_reg_rd_en;
            reg_rd_addr <= r_reg_rd_addr;
            buf_rd_en   <= r_buf_rd_en;
            buf_rd_addr <= r_buf_rd_addr;
        end
    end

    // ========================================================
    //  Debug 输出（仿真时启用）
    // ========================================================
    // synthesis translate_off
    always @(posedge clk) begin
        if (r_state != R_IDLE || axi_rvalid)
            $display("[AXI_DBG] t=%0t r_state=%0d rvalid=%b rlast=%b rready=%b arvalid=%b r_cnt=%0d r_addr=0x%04X",
                $time, r_state, axi_rvalid, axi_rlast, axi_rready, axi_arvalid, r_cnt, r_addr);
    end
    // synthesis translate_on

endmodule