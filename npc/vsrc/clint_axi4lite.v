`timescale 1ns / 1ps
`include "defines.v"

module clint_axi4lite (
    input  wire        clk,
    input  wire        rst,
    // AXI read address channel
    input  wire [31:0] clint_axi_araddr,
    input  wire        clint_axi_arvalid,
    output wire        clint_axi_arready,
    // AXI read data channel
    output wire [31:0] clint_axi_rdata,
    output wire [ 1:0] clint_axi_rresp,
    output wire        clint_axi_rvalid,
    input  wire        clint_axi_rready,
    // AXI write address channel
    input  wire [31:0] clint_axi_awaddr,
    input  wire        clint_axi_awvalid,
    output wire        clint_axi_awready,
    // AXI write data channel
    input  wire [31:0] clint_axi_wdata,
    input  wire [ 3:0] clint_axi_wstrb,
    input  wire        clint_axi_wvalid,
    output wire        clint_axi_wready,
    // AXI write response channel
    output wire [ 1:0] clint_axi_bresp,
    output wire        clint_axi_bvalid,
    input  wire        clint_axi_bready
);
    localparam C_IDLE      = 2'd0;
    localparam C_RD_RVALID = 2'd1;
    localparam C_WR_AW_W   = 2'd2;
    localparam C_WR_BVALID = 2'd3;

    reg [1:0]  state;
    reg [63:0] mtime;
    reg [31:0] rdata_reg;
    reg        wr_aw_done;
    reg        wr_w_done;

    wire ar_fire;
    wire r_fire;
    wire aw_fire;
    wire w_fire;
    wire b_fire;
    wire aw_done_next;
    wire w_done_next;

    assign clint_axi_arready = (state == C_IDLE);
    assign clint_axi_rvalid = (state == C_RD_RVALID);
    assign clint_axi_rdata = rdata_reg;
    assign clint_axi_rresp = 2'b00;

    assign clint_axi_awready = (state == C_WR_AW_W) && ~wr_aw_done;
    assign clint_axi_wready = (state == C_WR_AW_W) && ~wr_w_done;
    assign clint_axi_bvalid = (state == C_WR_BVALID);
    assign clint_axi_bresp = 2'b00;

    assign ar_fire = clint_axi_arvalid && clint_axi_arready;
    assign r_fire = clint_axi_rvalid && clint_axi_rready;
    assign aw_fire = clint_axi_awvalid && clint_axi_awready;
    assign w_fire = clint_axi_wvalid && clint_axi_wready;
    assign b_fire = clint_axi_bvalid && clint_axi_bready;
    assign aw_done_next = wr_aw_done || aw_fire;
    assign w_done_next = wr_w_done || w_fire;

    always @(posedge clk) begin
        if (rst) begin
            mtime <= 64'b0;
        end else begin
            mtime <= mtime + 64'd1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= C_IDLE;
            rdata_reg <= 32'b0;
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
        end else begin
            case (state)
                C_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                    if (ar_fire) begin
                        if (clint_axi_araddr == `CLINT_MTIME_ADDR) begin
                            rdata_reg <= mtime[31:0];
                        end else if (clint_axi_araddr == `CLINT_MTIMEH_ADDR) begin
                            rdata_reg <= mtime[63:32];
                        end else begin
                            rdata_reg <= 32'b0;
                        end
                        state <= C_RD_RVALID;
                    end else if (clint_axi_awvalid || clint_axi_wvalid) begin
                        state <= C_WR_AW_W;
                    end
                end

                C_RD_RVALID: begin
                    if (r_fire) begin
                        state <= C_IDLE;
                    end
                end

                C_WR_AW_W: begin
                    if (aw_fire) begin
                        wr_aw_done <= 1'b1;
                    end
                    if (w_fire) begin
                        wr_w_done <= 1'b1;
                    end

                    if (aw_done_next && w_done_next) begin
                        state <= C_WR_BVALID;
                    end
                end

                C_WR_BVALID: begin
                    if (b_fire) begin
                        state <= C_IDLE;
                    end
                end

                default: begin
                    state <= C_IDLE;
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                end
            endcase
        end
    end

    wire _unused_ok;
    assign _unused_ok = &{1'b0, clint_axi_awaddr, clint_axi_wdata, clint_axi_wstrb};
endmodule
