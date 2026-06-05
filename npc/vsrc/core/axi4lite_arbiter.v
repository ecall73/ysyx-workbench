`timescale 1ns / 1ps

module axi4lite_arbiter (
    input  wire        clock,
    input  wire        reset,
    // IFU master interface
    input  wire [31:0] ifu_axi_araddr,
    input  wire [ 7:0] ifu_axi_arlen,
    input  wire [ 1:0] ifu_axi_arburst,
    input  wire        ifu_axi_arvalid,
    output reg         ifu_axi_arready,
    output reg  [31:0] ifu_axi_rdata,
    output reg  [ 1:0] ifu_axi_rresp,
    output reg         ifu_axi_rlast,
    output reg         ifu_axi_rvalid,
    input  wire        ifu_axi_rready,
    input  wire [31:0] ifu_axi_awaddr,
    input  wire        ifu_axi_awvalid,
    output reg         ifu_axi_awready,
    input  wire [31:0] ifu_axi_wdata,
    input  wire [ 3:0] ifu_axi_wstrb,
    input  wire        ifu_axi_wvalid,
    output reg         ifu_axi_wready,
    output reg  [ 1:0] ifu_axi_bresp,
    output reg         ifu_axi_bvalid,
    input  wire        ifu_axi_bready,
    // LSU master interface
    input  wire [31:0] lsu_axi_araddr,
    input  wire [ 2:0] lsu_axi_arsize,
    input  wire        lsu_axi_arvalid,
    output reg         lsu_axi_arready,
    output reg  [31:0] lsu_axi_rdata,
    output reg  [ 1:0] lsu_axi_rresp,
    output reg         lsu_axi_rvalid,
    input  wire        lsu_axi_rready,
    input  wire [31:0] lsu_axi_awaddr,
    input  wire [ 2:0] lsu_axi_awsize,
    input  wire        lsu_axi_awvalid,
    output reg         lsu_axi_awready,
    input  wire [31:0] lsu_axi_wdata,
    input  wire [ 3:0] lsu_axi_wstrb,
    input  wire        lsu_axi_wvalid,
    output reg         lsu_axi_wready,
    output reg  [ 1:0] lsu_axi_bresp,
    output reg         lsu_axi_bvalid,
    input  wire        lsu_axi_bready,
    // Shared MEM slave interface
    output reg  [31:0] mem_axi_araddr,
    output reg  [ 3:0] mem_axi_arid,
    output reg  [ 7:0] mem_axi_arlen,
    output reg  [ 2:0] mem_axi_arsize,
    output reg  [ 1:0] mem_axi_arburst,
    output reg         mem_axi_arvalid,
    input  wire        mem_axi_arready,
    input  wire [31:0] mem_axi_rdata,
    input  wire [ 3:0] mem_axi_rid,
    input  wire [ 1:0] mem_axi_rresp,
    input  wire        mem_axi_rlast,
    input  wire        mem_axi_rvalid,
    output reg         mem_axi_rready,
    output reg  [31:0] mem_axi_awaddr,
    output reg  [ 3:0] mem_axi_awid,
    output reg  [ 7:0] mem_axi_awlen,
    output reg  [ 2:0] mem_axi_awsize,
    output reg  [ 1:0] mem_axi_awburst,
    output reg         mem_axi_awvalid,
    input  wire        mem_axi_awready,
    output reg  [31:0] mem_axi_wdata,
    output reg  [ 3:0] mem_axi_wstrb,
    output reg         mem_axi_wlast,
    output reg         mem_axi_wvalid,
    input  wire        mem_axi_wready,
    input  wire [ 3:0] mem_axi_bid,
    input  wire [ 1:0] mem_axi_bresp,
    input  wire        mem_axi_bvalid,
    output reg         mem_axi_bready
);

    localparam A_IDLE        = 4'd0;
    localparam A_LSU_WR_AW_W = 4'd1;
    localparam A_LSU_WR_B    = 4'd2;
    localparam A_LSU_RD_AR   = 4'd3;
    localparam A_LSU_RD_R    = 4'd4;
    localparam A_IFU_WR_AW_W = 4'd5;
    localparam A_IFU_WR_B    = 4'd6;
    localparam A_IFU_RD_AR   = 4'd7;
    localparam A_IFU_RD_R    = 4'd8;

    reg [3:0] state;
    reg       wr_aw_done;
    reg       wr_w_done;

    wire      req_lsu_wr;
    wire      req_lsu_rd;
    wire      req_ifu_wr;
    wire      req_ifu_rd;
    reg [3:0] next_req_state;

    wire lsu_aw_fire;
    wire lsu_w_fire;
    wire lsu_b_fire;
    wire lsu_ar_fire;
    wire lsu_r_fire;
    wire ifu_aw_fire;
    wire ifu_w_fire;
    wire ifu_b_fire;
    wire ifu_ar_fire;
    wire ifu_r_fire;

    assign lsu_aw_fire = (state == A_LSU_WR_AW_W) && (~wr_aw_done) && lsu_axi_awvalid && mem_axi_awready;
    assign lsu_w_fire = (state == A_LSU_WR_AW_W) && (~wr_w_done) && lsu_axi_wvalid && mem_axi_wready;
    assign lsu_b_fire = (state == A_LSU_WR_B) && mem_axi_bvalid && lsu_axi_bready;

    assign lsu_ar_fire = (state == A_LSU_RD_AR) && lsu_axi_arvalid && mem_axi_arready;
    assign lsu_r_fire = (state == A_LSU_RD_R) && mem_axi_rvalid && lsu_axi_rready;

    assign ifu_aw_fire = (state == A_IFU_WR_AW_W) && (~wr_aw_done) && ifu_axi_awvalid && mem_axi_awready;
    assign ifu_w_fire = (state == A_IFU_WR_AW_W) && (~wr_w_done) && ifu_axi_wvalid && mem_axi_wready;
    assign ifu_b_fire = (state == A_IFU_WR_B) && mem_axi_bvalid && ifu_axi_bready;

    assign ifu_ar_fire = (state == A_IFU_RD_AR) && ifu_axi_arvalid && mem_axi_arready;
    assign ifu_r_fire = (state == A_IFU_RD_R) && mem_axi_rvalid && ifu_axi_rready;

    assign req_lsu_wr = lsu_axi_awvalid || lsu_axi_wvalid;
    assign req_lsu_rd = lsu_axi_arvalid;
    assign req_ifu_wr = ifu_axi_awvalid || ifu_axi_wvalid;
    assign req_ifu_rd = ifu_axi_arvalid;

    always @(*) begin
        next_req_state = A_IDLE;
        if (req_lsu_wr) begin
            next_req_state = A_LSU_WR_AW_W;
        end else if (req_lsu_rd) begin
            next_req_state = A_LSU_RD_AR;
        end else if (req_ifu_wr) begin
            next_req_state = A_IFU_WR_AW_W;
        end else if (req_ifu_rd) begin
            next_req_state = A_IFU_RD_AR;
        end
    end

    always @(*) begin
        // IFU side defaults (blocked)
        ifu_axi_arready = 1'b0;
        ifu_axi_rdata = 32'b0;
        ifu_axi_rresp = 2'b00;
        ifu_axi_rlast = 1'b0;
        ifu_axi_rvalid = 1'b0;
        ifu_axi_awready = 1'b0;
        ifu_axi_wready = 1'b0;
        ifu_axi_bresp = 2'b00;
        ifu_axi_bvalid = 1'b0;

        // LSU side defaults (blocked)
        lsu_axi_arready = 1'b0;
        lsu_axi_rdata = 32'b0;
        lsu_axi_rresp = 2'b00;
        lsu_axi_rvalid = 1'b0;
        lsu_axi_awready = 1'b0;
        lsu_axi_wready = 1'b0;
        lsu_axi_bresp = 2'b00;
        lsu_axi_bvalid = 1'b0;

        // MEM side defaults
        mem_axi_araddr = 32'b0;
        mem_axi_arid = 4'b0;
        mem_axi_arlen = 8'b0;
        mem_axi_arsize = 3'b010;
        mem_axi_arburst = 2'b00;
        mem_axi_arvalid = 1'b0;
        mem_axi_rready = 1'b0;
        mem_axi_awaddr = 32'b0;
        mem_axi_awid = 4'b0;
        mem_axi_awlen = 8'b0;
        mem_axi_awsize = 3'b010;
        mem_axi_awburst = 2'b00;
        mem_axi_awvalid = 1'b0;
        mem_axi_wdata = 32'b0;
        mem_axi_wstrb = 4'b0000;
        mem_axi_wlast = 1'b0;
        mem_axi_wvalid = 1'b0;
        mem_axi_bready = 1'b0;

        case (state)
            A_LSU_WR_AW_W: begin
                if (~wr_aw_done) begin
                    mem_axi_awaddr = lsu_axi_awaddr;
                    mem_axi_awid = 4'h0;
                    mem_axi_awlen = 8'h00;
                    mem_axi_awsize = lsu_axi_awsize;
                    mem_axi_awburst = 2'b00;
                    mem_axi_awvalid = lsu_axi_awvalid;
                    lsu_axi_awready = mem_axi_awready;
                end
                if (~wr_w_done) begin
                    mem_axi_wdata = lsu_axi_wdata;
                    mem_axi_wstrb = lsu_axi_wstrb;
                    mem_axi_wlast = 1'b1;
                    mem_axi_wvalid = lsu_axi_wvalid;
                    lsu_axi_wready = mem_axi_wready;
                end
            end

            A_LSU_WR_B: begin
                lsu_axi_bresp = mem_axi_bresp;
                lsu_axi_bvalid = mem_axi_bvalid;
                mem_axi_bready = lsu_axi_bready;
            end

            A_LSU_RD_AR: begin
                mem_axi_araddr = lsu_axi_araddr;
                mem_axi_arid = 4'h0;
                mem_axi_arlen = 8'h00;
                mem_axi_arsize = lsu_axi_arsize;
                mem_axi_arburst = 2'b00;
                mem_axi_arvalid = lsu_axi_arvalid;
                lsu_axi_arready = mem_axi_arready;
            end

            A_LSU_RD_R: begin
                lsu_axi_rdata = mem_axi_rdata;
                lsu_axi_rresp = mem_axi_rresp;
                lsu_axi_rvalid = mem_axi_rvalid;
                mem_axi_rready = lsu_axi_rready;
            end

            A_IFU_WR_AW_W: begin
                if (~wr_aw_done) begin
                    mem_axi_awaddr = ifu_axi_awaddr;
                    mem_axi_awid = 4'h1;
                    mem_axi_awlen = 8'h00;
                    mem_axi_awsize = 3'b010;
                    mem_axi_awburst = 2'b00;
                    mem_axi_awvalid = ifu_axi_awvalid;
                    ifu_axi_awready = mem_axi_awready;
                end
                if (~wr_w_done) begin
                    mem_axi_wdata = ifu_axi_wdata;
                    mem_axi_wstrb = ifu_axi_wstrb;
                    mem_axi_wlast = 1'b1;
                    mem_axi_wvalid = ifu_axi_wvalid;
                    ifu_axi_wready = mem_axi_wready;
                end
            end

            A_IFU_WR_B: begin
                ifu_axi_bresp = mem_axi_bresp;
                ifu_axi_bvalid = mem_axi_bvalid;
                mem_axi_bready = ifu_axi_bready;
            end

            A_IFU_RD_AR: begin
                mem_axi_araddr = ifu_axi_araddr;
                mem_axi_arid = 4'h1;
                mem_axi_arlen = ifu_axi_arlen;
                mem_axi_arsize = 3'b010;
                mem_axi_arburst = ifu_axi_arburst;
                mem_axi_arvalid = ifu_axi_arvalid;
                ifu_axi_arready = mem_axi_arready;
            end

            A_IFU_RD_R: begin
                ifu_axi_rdata = mem_axi_rdata;
                ifu_axi_rresp = mem_axi_rresp;
                ifu_axi_rlast = mem_axi_rlast;
                ifu_axi_rvalid = mem_axi_rvalid;
                mem_axi_rready = ifu_axi_rready;
            end

            default: begin
            end
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            state <= A_IDLE;
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
        end else begin
            case (state)
                A_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                    if (next_req_state != A_IDLE) begin
                        state <= next_req_state;
                    end
                end

                A_LSU_WR_AW_W: begin
                    if (lsu_aw_fire) begin
                        wr_aw_done <= 1'b1;
                    end
                    if (lsu_w_fire) begin
                        wr_w_done <= 1'b1;
                    end
                    if ((wr_aw_done || lsu_aw_fire) && (wr_w_done || lsu_w_fire)) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= A_LSU_WR_B;
                    end
                end

                A_LSU_WR_B: begin
                    if (lsu_b_fire) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= next_req_state;
                    end
                end

                A_LSU_RD_AR: begin
                    if (lsu_ar_fire) begin
                        state <= A_LSU_RD_R;
                    end
                end

                A_LSU_RD_R: begin
                    if (lsu_r_fire && mem_axi_rlast) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= next_req_state;
                    end
                end

                A_IFU_WR_AW_W: begin
                    if (ifu_aw_fire) begin
                        wr_aw_done <= 1'b1;
                    end
                    if (ifu_w_fire) begin
                        wr_w_done <= 1'b1;
                    end
                    if ((wr_aw_done || ifu_aw_fire) && (wr_w_done || ifu_w_fire)) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= A_IFU_WR_B;
                    end
                end

                A_IFU_WR_B: begin
                    if (ifu_b_fire) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= next_req_state;
                    end
                end

                A_IFU_RD_AR: begin
                    if (ifu_ar_fire) begin
                        state <= A_IFU_RD_R;
                    end
                end

                A_IFU_RD_R: begin
                    if (ifu_r_fire && mem_axi_rlast) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= next_req_state;
                    end
                end

                default: begin
                    state <= A_IDLE;
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                end
            endcase
        end
    end

endmodule
