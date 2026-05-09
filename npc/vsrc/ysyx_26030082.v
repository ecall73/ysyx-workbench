`timescale 1ns / 1ps
`include "defines.v"

module ysyx_26030082 (
    input  wire        clock,
    input  wire        reset,
    input  wire        io_interrupt,
    // AXI4 master interface
    input  wire        io_master_awready,
    output reg         io_master_awvalid,
    output reg  [ 3:0] io_master_awid,
    output reg  [31:0] io_master_awaddr,
    output reg  [ 7:0] io_master_awlen,
    output reg  [ 2:0] io_master_awsize,
    output reg  [ 1:0] io_master_awburst,
    input  wire        io_master_wready,
    output reg         io_master_wvalid,
    output reg  [31:0] io_master_wdata,
    output reg  [ 3:0] io_master_wstrb,
    output reg         io_master_wlast,
    output reg         io_master_bready,
    input  wire        io_master_bvalid,
    input  wire [ 3:0] io_master_bid,
    input  wire [ 1:0] io_master_bresp,
    input  wire        io_master_arready,
    output reg         io_master_arvalid,
    output reg  [ 3:0] io_master_arid,
    output reg  [31:0] io_master_araddr,
    output reg  [ 7:0] io_master_arlen,
    output reg  [ 2:0] io_master_arsize,
    output reg  [ 1:0] io_master_arburst,
    output reg         io_master_rready,
    input  wire        io_master_rvalid,
    input  wire [ 3:0] io_master_rid,
    input  wire [31:0] io_master_rdata,
    input  wire [ 1:0] io_master_rresp,
    input  wire        io_master_rlast,
    // AXI4 slave interface (unused)
    output wire        io_slave_awready,
    input  wire        io_slave_awvalid,
    input  wire [ 3:0] io_slave_awid,
    input  wire [31:0] io_slave_awaddr,
    input  wire [ 7:0] io_slave_awlen,
    input  wire [ 2:0] io_slave_awsize,
    input  wire [ 1:0] io_slave_awburst,
    output wire        io_slave_wready,
    input  wire        io_slave_wvalid,
    input  wire [31:0] io_slave_wdata,
    input  wire [ 3:0] io_slave_wstrb,
    input  wire        io_slave_wlast,
    input  wire        io_slave_bready,
    output wire        io_slave_bvalid,
    output wire [ 3:0] io_slave_bid,
    output wire [ 1:0] io_slave_bresp,
    output wire        io_slave_arready,
    input  wire        io_slave_arvalid,
    input  wire [ 3:0] io_slave_arid,
    input  wire [31:0] io_slave_araddr,
    input  wire [ 7:0] io_slave_arlen,
    input  wire [ 2:0] io_slave_arsize,
    input  wire [ 1:0] io_slave_arburst,
    input  wire        io_slave_rready,
    output wire        io_slave_rvalid,
    output wire [ 3:0] io_slave_rid,
    output wire [31:0] io_slave_rdata,
    output wire [ 1:0] io_slave_rresp,
    output wire        io_slave_rlast
);

    localparam X_IDLE      = 2'd0;
    localparam X_RD_WAIT_R = 2'd1;
    localparam X_WR_AW_W   = 2'd2;
    localparam X_WR_WAIT_B = 2'd3;

    reg [1:0] state;
    reg       rd_sel_clint;
    reg       wr_sel_clint;
    reg       wr_aw_done;
    reg       wr_w_done;
    reg [3:0] rd_id_reg;
    reg [3:0] wr_id_reg;

    // Core master bus from myCPU
    wire [31:0] core_axi_araddr;
    wire [ 3:0] core_axi_arid;
    wire [ 7:0] core_axi_arlen;
    wire [ 2:0] core_axi_arsize;
    wire [ 1:0] core_axi_arburst;
    wire        core_axi_arvalid;
    reg         core_axi_arready;
    reg  [31:0] core_axi_rdata;
    reg  [ 3:0] core_axi_rid;
    reg  [ 1:0] core_axi_rresp;
    reg         core_axi_rlast;
    reg         core_axi_rvalid;
    wire        core_axi_rready;
    wire [31:0] core_axi_awaddr;
    wire [ 3:0] core_axi_awid;
    wire [ 7:0] core_axi_awlen;
    wire [ 2:0] core_axi_awsize;
    wire [ 1:0] core_axi_awburst;
    wire        core_axi_awvalid;
    reg         core_axi_awready;
    wire [31:0] core_axi_wdata;
    wire [ 3:0] core_axi_wstrb;
    wire        core_axi_wlast;
    wire        core_axi_wvalid;
    reg         core_axi_wready;
    reg  [ 3:0] core_axi_bid;
    reg  [ 1:0] core_axi_bresp;
    reg         core_axi_bvalid;
    wire        core_axi_bready;

    // Local CLINT bus (AXI4-Lite)
    reg  [31:0] clint_axi_araddr;
    reg         clint_axi_arvalid;
    wire        clint_axi_arready;
    wire [31:0] clint_axi_rdata;
    wire [ 1:0] clint_axi_rresp;
    wire        clint_axi_rvalid;
    reg         clint_axi_rready;
    reg  [31:0] clint_axi_awaddr;
    reg         clint_axi_awvalid;
    wire        clint_axi_awready;
    reg  [31:0] clint_axi_wdata;
    reg  [ 3:0] clint_axi_wstrb;
    reg         clint_axi_wvalid;
    wire        clint_axi_wready;
    wire [ 1:0] clint_axi_bresp;
    wire        clint_axi_bvalid;
    reg         clint_axi_bready;

    wire ar_to_clint;
    wire aw_to_clint;
    wire ar_fire;
    wire r_fire;
    wire aw_fire;
    wire w_fire;
    wire b_fire;
    wire aw_done_next;
    wire w_done_next;

    assign ar_to_clint = (core_axi_araddr >= `CLINT_BASE_ADDR) && (core_axi_araddr <= `CLINT_END_ADDR);
    assign aw_to_clint = (core_axi_awaddr >= `CLINT_BASE_ADDR) && (core_axi_awaddr <= `CLINT_END_ADDR);

    assign ar_fire = core_axi_arvalid && core_axi_arready;
    assign r_fire = core_axi_rvalid && core_axi_rready;
    assign aw_fire = core_axi_awvalid && core_axi_awready;
    assign w_fire = core_axi_wvalid && core_axi_wready;
    assign b_fire = core_axi_bvalid && core_axi_bready;
    assign aw_done_next = wr_aw_done || aw_fire;
    assign w_done_next = wr_w_done || w_fire;

    // Unused slave port is tied off to zero.
    assign io_slave_awready = 1'b0;
    assign io_slave_wready = 1'b0;
    assign io_slave_bvalid = 1'b0;
    assign io_slave_bid = 4'b0;
    assign io_slave_bresp = 2'b00;
    assign io_slave_arready = 1'b0;
    assign io_slave_rvalid = 1'b0;
    assign io_slave_rid = 4'b0;
    assign io_slave_rdata = 32'b0;
    assign io_slave_rresp = 2'b00;
    assign io_slave_rlast = 1'b0;

    always @(*) begin
        // defaults to core
        core_axi_arready = 1'b0;
        core_axi_rdata = 32'b0;
        core_axi_rid = 4'b0;
        core_axi_rresp = 2'b00;
        core_axi_rlast = 1'b0;
        core_axi_rvalid = 1'b0;
        core_axi_awready = 1'b0;
        core_axi_wready = 1'b0;
        core_axi_bid = 4'b0;
        core_axi_bresp = 2'b00;
        core_axi_bvalid = 1'b0;

        // defaults to external SoC bus
        io_master_araddr = 32'b0;
        io_master_arid = 4'b0;
        io_master_arlen = 8'b0;
        io_master_arsize = 3'b0;
        io_master_arburst = 2'b0;
        io_master_arvalid = 1'b0;
        io_master_rready = 1'b0;
        io_master_awaddr = 32'b0;
        io_master_awid = 4'b0;
        io_master_awlen = 8'b0;
        io_master_awsize = 3'b0;
        io_master_awburst = 2'b0;
        io_master_awvalid = 1'b0;
        io_master_wdata = 32'b0;
        io_master_wstrb = 4'b0;
        io_master_wlast = 1'b0;
        io_master_wvalid = 1'b0;
        io_master_bready = 1'b0;

        // defaults to local CLINT bus
        clint_axi_araddr = 32'b0;
        clint_axi_arvalid = 1'b0;
        clint_axi_rready = 1'b0;
        clint_axi_awaddr = 32'b0;
        clint_axi_awvalid = 1'b0;
        clint_axi_wdata = 32'b0;
        clint_axi_wstrb = 4'b0;
        clint_axi_wvalid = 1'b0;
        clint_axi_bready = 1'b0;

        case (state)
            X_IDLE: begin
                if (core_axi_arvalid) begin
                    if (ar_to_clint) begin
                        clint_axi_araddr = core_axi_araddr;
                        clint_axi_arvalid = core_axi_arvalid;
                        core_axi_arready = clint_axi_arready;
                    end else begin
                        io_master_araddr = core_axi_araddr;
                        io_master_arid = core_axi_arid;
                        io_master_arlen = core_axi_arlen;
                        io_master_arsize = core_axi_arsize;
                        io_master_arburst = core_axi_arburst;
                        io_master_arvalid = core_axi_arvalid;
                        core_axi_arready = io_master_arready;
                    end
                end
            end

            X_RD_WAIT_R: begin
                if (rd_sel_clint) begin
                    core_axi_rdata = clint_axi_rdata;
                    core_axi_rid = rd_id_reg;
                    core_axi_rresp = clint_axi_rresp;
                    core_axi_rlast = 1'b1;
                    core_axi_rvalid = clint_axi_rvalid;
                    clint_axi_rready = core_axi_rready;
                end else begin
                    core_axi_rdata = io_master_rdata;
                    core_axi_rid = io_master_rid;
                    core_axi_rresp = io_master_rresp;
                    core_axi_rlast = io_master_rlast;
                    core_axi_rvalid = io_master_rvalid;
                    io_master_rready = core_axi_rready;
                end
            end

            X_WR_AW_W: begin
                if (~wr_aw_done) begin
                    if (aw_to_clint) begin
                        clint_axi_awaddr = core_axi_awaddr;
                        clint_axi_awvalid = core_axi_awvalid;
                        core_axi_awready = clint_axi_awready;
                    end else begin
                        io_master_awaddr = core_axi_awaddr;
                        io_master_awid = core_axi_awid;
                        io_master_awlen = core_axi_awlen;
                        io_master_awsize = core_axi_awsize;
                        io_master_awburst = core_axi_awburst;
                        io_master_awvalid = core_axi_awvalid;
                        core_axi_awready = io_master_awready;
                    end
                end

                if (wr_aw_done && ~wr_w_done) begin
                    if (wr_sel_clint) begin
                        clint_axi_wdata = core_axi_wdata;
                        clint_axi_wstrb = core_axi_wstrb;
                        clint_axi_wvalid = core_axi_wvalid;
                        core_axi_wready = clint_axi_wready;
                    end else begin
                        io_master_wdata = core_axi_wdata;
                        io_master_wstrb = core_axi_wstrb;
                        io_master_wlast = core_axi_wlast;
                        io_master_wvalid = core_axi_wvalid;
                        core_axi_wready = io_master_wready;
                    end
                end
            end

            X_WR_WAIT_B: begin
                if (wr_sel_clint) begin
                    core_axi_bresp = clint_axi_bresp;
                    core_axi_bid = wr_id_reg;
                    core_axi_bvalid = clint_axi_bvalid;
                    clint_axi_bready = core_axi_bready;
                end else begin
                    core_axi_bresp = io_master_bresp;
                    core_axi_bid = io_master_bid;
                    core_axi_bvalid = io_master_bvalid;
                    io_master_bready = core_axi_bready;
                end
            end

            default: begin
            end
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            state <= X_IDLE;
            rd_sel_clint <= 1'b0;
            wr_sel_clint <= 1'b0;
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
            rd_id_reg <= 4'b0;
            wr_id_reg <= 4'b0;
        end else begin
            case (state)
                X_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                    if (core_axi_arvalid) begin
                        if (ar_fire) begin
                            rd_sel_clint <= ar_to_clint;
                            rd_id_reg <= core_axi_arid;
                            state <= X_RD_WAIT_R;
                        end
                    end else if (core_axi_awvalid || core_axi_wvalid) begin
                        state <= X_WR_AW_W;
                    end
                end

                X_RD_WAIT_R: begin
                    if (r_fire) begin
                        state <= X_IDLE;
                    end
                end

                X_WR_AW_W: begin
                    if (~wr_aw_done && aw_fire) begin
                        wr_aw_done <= 1'b1;
                        wr_sel_clint <= aw_to_clint;
                        wr_id_reg <= core_axi_awid;
                    end

                    if (wr_aw_done && ~wr_w_done && w_fire) begin
                        wr_w_done <= 1'b1;
                    end

                    if (aw_done_next && w_done_next) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= X_WR_WAIT_B;
                    end
                end

                X_WR_WAIT_B: begin
                    if (b_fire) begin
                        state <= X_IDLE;
                    end
                end

                default: begin
                    state <= X_IDLE;
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clock) begin
        if (!reset) begin
            if (core_axi_arvalid && core_axi_arready && (core_axi_arlen != 8'h00)) begin
                $fatal(1, "ysyx_26030082: burst read is not supported");
            end
            if (core_axi_awvalid && core_axi_awready && (core_axi_awlen != 8'h00)) begin
                $fatal(1, "ysyx_26030082: burst write is not supported");
            end
            if (core_axi_wvalid && core_axi_wready && (core_axi_wlast != 1'b1)) begin
                $fatal(1, "ysyx_26030082: WLAST must be 1 for single-beat write");
            end
            if (core_axi_rvalid && core_axi_rready && (core_axi_rresp !== 2'b00)) begin
                $fatal(1,
                    "ysyx_26030082: AXI read access fault: resp=%0b rid=%0d src=%0s state=%0d",
                    core_axi_rresp, core_axi_rid, rd_sel_clint ? "clint" : "soc", state);
            end
            if (core_axi_bvalid && core_axi_bready && (core_axi_bresp !== 2'b00)) begin
                $fatal(1,
                    "ysyx_26030082: AXI write access fault: resp=%0b bid=%0d src=%0s state=%0d",
                    core_axi_bresp, core_axi_bid, wr_sel_clint ? "clint" : "soc", state);
            end
        end
    end
`endif

    myCPU u_cpu (
        .clk                (clock),
        .rst                (reset),
        .mem_axi_araddr     (core_axi_araddr),
        .mem_axi_arid       (core_axi_arid),
        .mem_axi_arlen      (core_axi_arlen),
        .mem_axi_arsize     (core_axi_arsize),
        .mem_axi_arburst    (core_axi_arburst),
        .mem_axi_arvalid    (core_axi_arvalid),
        .mem_axi_arready    (core_axi_arready),
        .mem_axi_rdata      (core_axi_rdata),
        .mem_axi_rid        (core_axi_rid),
        .mem_axi_rresp      (core_axi_rresp),
        .mem_axi_rlast      (core_axi_rlast),
        .mem_axi_rvalid     (core_axi_rvalid),
        .mem_axi_rready     (core_axi_rready),
        .mem_axi_awaddr     (core_axi_awaddr),
        .mem_axi_awid       (core_axi_awid),
        .mem_axi_awlen      (core_axi_awlen),
        .mem_axi_awsize     (core_axi_awsize),
        .mem_axi_awburst    (core_axi_awburst),
        .mem_axi_awvalid    (core_axi_awvalid),
        .mem_axi_awready    (core_axi_awready),
        .mem_axi_wdata      (core_axi_wdata),
        .mem_axi_wstrb      (core_axi_wstrb),
        .mem_axi_wlast      (core_axi_wlast),
        .mem_axi_wvalid     (core_axi_wvalid),
        .mem_axi_wready     (core_axi_wready),
        .mem_axi_bid        (core_axi_bid),
        .mem_axi_bresp      (core_axi_bresp),
        .mem_axi_bvalid     (core_axi_bvalid),
        .mem_axi_bready     (core_axi_bready)
    );

    clint_axi4lite u_clint_axi4lite (
        .clk                (clock),
        .rst                (reset),
        .clint_axi_araddr   (clint_axi_araddr),
        .clint_axi_arvalid  (clint_axi_arvalid),
        .clint_axi_arready  (clint_axi_arready),
        .clint_axi_rdata    (clint_axi_rdata),
        .clint_axi_rresp    (clint_axi_rresp),
        .clint_axi_rvalid   (clint_axi_rvalid),
        .clint_axi_rready   (clint_axi_rready),
        .clint_axi_awaddr   (clint_axi_awaddr),
        .clint_axi_awvalid  (clint_axi_awvalid),
        .clint_axi_awready  (clint_axi_awready),
        .clint_axi_wdata    (clint_axi_wdata),
        .clint_axi_wstrb    (clint_axi_wstrb),
        .clint_axi_wvalid   (clint_axi_wvalid),
        .clint_axi_wready   (clint_axi_wready),
        .clint_axi_bresp    (clint_axi_bresp),
        .clint_axi_bvalid   (clint_axi_bvalid),
        .clint_axi_bready   (clint_axi_bready)
    );

    wire _unused_ok;
    assign _unused_ok = &{1'b0,
        io_interrupt,
        io_slave_awvalid, io_slave_awid, io_slave_awaddr, io_slave_awlen, io_slave_awsize, io_slave_awburst,
        io_slave_wvalid, io_slave_wdata, io_slave_wstrb, io_slave_wlast, io_slave_bready,
        io_slave_arvalid, io_slave_arid, io_slave_araddr, io_slave_arlen, io_slave_arsize, io_slave_arburst,
        io_slave_rready
    };

endmodule
