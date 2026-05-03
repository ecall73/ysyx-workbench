`timescale 1ns / 1ps

module uart_axi4lite (
    input  wire        clk,
    input  wire        rst,
    // AXI read address channel
    input  wire [31:0] uart_axi_araddr,
    input  wire        uart_axi_arvalid,
    output wire        uart_axi_arready,
    // AXI read data channel
    output wire [31:0] uart_axi_rdata,
    output wire [ 1:0] uart_axi_rresp,
    output wire        uart_axi_rvalid,
    input  wire        uart_axi_rready,
    // AXI write address channel
    input  wire [31:0] uart_axi_awaddr,
    input  wire        uart_axi_awvalid,
    output wire        uart_axi_awready,
    // AXI write data channel
    input  wire [31:0] uart_axi_wdata,
    input  wire [ 3:0] uart_axi_wstrb,
    input  wire        uart_axi_wvalid,
    output wire        uart_axi_wready,
    // AXI write response channel
    output wire [ 1:0] uart_axi_bresp,
    output wire        uart_axi_bvalid,
    input  wire        uart_axi_bready
);
    localparam U_IDLE       = 2'd0;
    localparam U_RD_RVALID  = 2'd1;
    localparam U_WR_AW_W    = 2'd2;
    localparam U_WR_BVALID  = 2'd3;

    reg [1:0]  state;
    reg [31:0] uart_reg;
    reg        wr_aw_done;
    reg        wr_w_done;
    reg [31:0] wr_data_reg;
    reg [3:0]  wr_strb_reg;

    wire ar_fire;
    wire r_fire;
    wire aw_fire;
    wire w_fire;
    wire b_fire;
    wire aw_done_next;
    wire w_done_next;
    wire [31:0] wr_data_next;
    wire [3:0]  wr_strb_next;

    reg [31:0] uart_next;

    assign uart_axi_arready = (state == U_IDLE);
    assign uart_axi_rvalid = (state == U_RD_RVALID);
    assign uart_axi_rdata = uart_reg;
    assign uart_axi_rresp = 2'b00;

    assign uart_axi_awready = (state == U_WR_AW_W) && ~wr_aw_done;
    assign uart_axi_wready = (state == U_WR_AW_W) && ~wr_w_done;
    assign uart_axi_bvalid = (state == U_WR_BVALID);
    assign uart_axi_bresp = 2'b00;

    assign ar_fire = uart_axi_arvalid && uart_axi_arready;
    assign r_fire = uart_axi_rvalid && uart_axi_rready;
    assign aw_fire = uart_axi_awvalid && uart_axi_awready;
    assign w_fire = uart_axi_wvalid && uart_axi_wready;
    assign b_fire = uart_axi_bvalid && uart_axi_bready;

    assign aw_done_next = wr_aw_done || aw_fire;
    assign w_done_next = wr_w_done || w_fire;
    assign wr_data_next = w_fire ? uart_axi_wdata : wr_data_reg;
    assign wr_strb_next = w_fire ? uart_axi_wstrb : wr_strb_reg;

    always @(*) begin
        uart_next = uart_reg;
        if (wr_strb_next[0]) uart_next[7:0]   = wr_data_next[7:0];
        if (wr_strb_next[1]) uart_next[15:8]  = wr_data_next[15:8];
        if (wr_strb_next[2]) uart_next[23:16] = wr_data_next[23:16];
        if (wr_strb_next[3]) uart_next[31:24] = wr_data_next[31:24];
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= U_IDLE;
            uart_reg <= 32'b0;
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
            wr_data_reg <= 32'b0;
            wr_strb_reg <= 4'b0;
        end else begin
            case (state)
                U_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                    wr_data_reg <= 32'b0;
                    wr_strb_reg <= 4'b0;
                    if (uart_axi_arvalid) begin
                        state <= U_RD_RVALID;
                    end else if (uart_axi_awvalid || uart_axi_wvalid) begin
                        state <= U_WR_AW_W;
                    end
                end

                U_RD_RVALID: begin
                    if (r_fire) begin
                        state <= U_IDLE;
                    end
                end

                U_WR_AW_W: begin
                    if (aw_fire) begin
                        wr_aw_done <= 1'b1;
                    end
                    if (w_fire) begin
                        wr_w_done <= 1'b1;
                        wr_data_reg <= uart_axi_wdata;
                        wr_strb_reg <= uart_axi_wstrb;
                    end

                    if (aw_done_next && w_done_next) begin
                        uart_reg <= uart_next;
                        $write("%c", wr_data_next[7:0]);
                        state <= U_WR_BVALID;
                    end
                end

                U_WR_BVALID: begin
                    if (b_fire) begin
                        state <= U_IDLE;
                    end
                end

                default: begin
                    state <= U_IDLE;
                end
            endcase
        end
    end

    wire _unused_ok;
    assign _unused_ok = &{1'b0, uart_axi_araddr, uart_axi_awaddr};
endmodule
