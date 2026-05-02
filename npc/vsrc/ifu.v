`timescale 1ns / 1ps
`include "defines.v"

module ifu (
    input  wire        clk,
    input  wire        rst,
    input  wire        if_in_valid,
    output wire        if_in_ready,
    input  wire        if_out_ready,
    input  wire        redirect_flush,

    // IFU AXI4-Lite master interface
    // Read address channel
    output wire [31:0] ifu_axi_araddr,
    output wire        ifu_axi_arvalid,
    input  wire        ifu_axi_arready,
    // Read data channel
    input  wire [31:0] ifu_axi_rdata,
    input  wire [ 1:0] ifu_axi_rresp,
    input  wire        ifu_axi_rvalid,
    output wire        ifu_axi_rready,
    // Write address channel (unused by IFU)
    output wire [31:0] ifu_axi_awaddr,
    output wire        ifu_axi_awvalid,
    input  wire        ifu_axi_awready,
    // Write data channel (unused by IFU)
    output wire [31:0] ifu_axi_wdata,
    output wire [ 3:0] ifu_axi_wstrb,
    output wire        ifu_axi_wvalid,
    input  wire        ifu_axi_wready,
    // Write response channel (unused by IFU)
    input  wire [ 1:0] ifu_axi_bresp,
    input  wire        ifu_axi_bvalid,
    output wire        ifu_axi_bready,

    // To ID stage
    output wire        if_out_valid,
    output wire [31:0] if_pc,
    output wire [31:0] if_pc4,
    output wire [31:0] if_inst,

    input  wire [31:0] npc
);
    localparam F_AR_VALID        = 2'b00;
    localparam F_WAIT_RESP_VALID = 2'b01;
    localparam F_R_READY         = 2'b10;
    localparam F_HOLD_OUT        = 2'b11;

    reg  [1:0]  state;
    reg  [31:0] req_pc;
    reg  [31:0] hold_pc;
    reg  [31:0] hold_inst;
    reg         drop_resp;
    reg  [31:0] redirect_pc;

    wire hold_valid;
    wire hold_fire;
    wire ar_fire;
    wire r_fire;
    wire drop_active;
    wire direct_valid;

    assign hold_valid = (state == F_HOLD_OUT);
    assign hold_fire = hold_valid && if_out_ready;

    assign ifu_axi_arvalid = (state == F_AR_VALID) && if_in_valid;
    assign ifu_axi_araddr = req_pc;

    assign ifu_axi_rready = (state == F_R_READY);

    assign ifu_axi_awaddr = 32'b0;
    assign ifu_axi_awvalid = 1'b0;
    assign ifu_axi_wdata = 32'b0;
    assign ifu_axi_wstrb = 4'b0000;
    assign ifu_axi_wvalid = 1'b0;
    assign ifu_axi_bready = 1'b0;

    assign ar_fire = ifu_axi_arvalid && ifu_axi_arready;
    assign r_fire = ifu_axi_rvalid && ifu_axi_rready;
    assign drop_active = drop_resp || redirect_flush;
    assign direct_valid = (state == F_R_READY) && r_fire && if_out_ready && ~drop_active;

    assign if_in_ready = (state == F_AR_VALID) && ifu_axi_arready;
    assign if_out_valid = hold_valid || direct_valid;
    assign if_pc = hold_valid ? hold_pc : req_pc;
    assign if_pc4 = if_pc + 32'd4;
    assign if_inst = hold_valid ? hold_inst : ifu_axi_rdata;

    always @(posedge clk) begin
        if (rst) begin
            state <= F_AR_VALID;
            req_pc <= 32'h8000_0000;
            hold_pc <= 32'b0;
            hold_inst <= 32'b0;
            drop_resp <= 1'b0;
            redirect_pc <= 32'b0;
        end else begin
            case (state)
                F_AR_VALID: begin
                    if (redirect_flush) begin
                        drop_resp <= 1'b1;
                        redirect_pc <= npc;
                    end
                    if (ar_fire) begin
                        state <= F_WAIT_RESP_VALID;
                    end
                end

                F_WAIT_RESP_VALID: begin
                    if (redirect_flush) begin
                        drop_resp <= 1'b1;
                        redirect_pc <= npc;
                    end
                    if (ifu_axi_rvalid) begin
                        state <= F_R_READY;
                    end
                end

                F_R_READY: begin
                    if (redirect_flush) begin
                        drop_resp <= 1'b1;
                        redirect_pc <= npc;
                    end

                    if (r_fire) begin
                        if (drop_active) begin
                            drop_resp <= 1'b0;
                            req_pc <= redirect_flush ? npc : redirect_pc;
                            state <= F_AR_VALID;
                        end else if (if_out_ready) begin
                            req_pc <= req_pc + 32'd4;
                            state <= F_AR_VALID;
                        end else begin
                            hold_pc <= req_pc;
                            hold_inst <= ifu_axi_rdata;
                            req_pc <= req_pc + 32'd4;
                            state <= F_HOLD_OUT;
                        end
                    end
                end

                F_HOLD_OUT: begin
                    if (redirect_flush) begin
                        hold_pc <= 32'b0;
                        hold_inst <= 32'b0;
                        req_pc <= npc;
                        drop_resp <= 1'b0;
                        state <= F_AR_VALID;
                    end else if (hold_fire) begin
                        state <= F_AR_VALID;
                    end
                end

                default: begin
                    state <= F_AR_VALID;
                end
            endcase
        end
    end

    // Read-only IFU ignores write channels.
    wire _unused_ok;
    assign _unused_ok = &{1'b0, ifu_axi_rresp, ifu_axi_awready, ifu_axi_wready, ifu_axi_bresp, ifu_axi_bvalid};

endmodule
