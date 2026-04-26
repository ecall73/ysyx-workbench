`timescale 1ns / 1ps
`include "defines.v"

module ifu (
    input  wire        clk,
    input  wire        rst,
    input  wire        if_in_valid,
    output wire        if_in_ready,
    input  wire        if_out_ready,
    input  wire        redirect_flush,

    // IFU SimpleBus interface
    output wire        ifu_reqValid,
    input  wire        ifu_reqReady,
    output wire [31:0] ifu_addr,
    input  wire        ifu_respValid,
    output wire        ifu_respReady,
    input  wire [31:0] ifu_rdata,

    // To ID stage
    output wire        if_out_valid,
    output wire [31:0] if_pc,
    output wire [31:0] if_pc4,
    output wire [31:0] if_inst,

    input  wire [31:0] npc
);
    localparam F_REQ_VALID       = 2'b00;
    localparam F_WAIT_RESP_VALID = 2'b01;
    localparam F_RESP_READY      = 2'b10;
    localparam F_HOLD_OUT        = 2'b11;

    reg  [1:0]  state;
    reg  [31:0] req_pc;
    reg  [31:0] hold_pc;
    reg  [31:0] hold_inst;
    reg         drop_resp;
    reg  [31:0] redirect_pc;

    wire hold_valid;
    wire hold_fire;
    wire req_fire;
    wire resp_fire;
    wire can_accept_resp;
    wire drop_active;
    wire direct_valid;

    assign hold_valid = (state == F_HOLD_OUT);
    assign hold_fire = hold_valid && if_out_ready;

    assign ifu_reqValid = (state == F_REQ_VALID) && if_in_valid && ~redirect_flush;
    assign ifu_addr = req_pc;
    assign ifu_respReady = (state == F_RESP_READY);

    assign req_fire = ifu_reqValid && ifu_reqReady;
    assign resp_fire = ifu_respValid && ifu_respReady;
    assign can_accept_resp = if_out_ready || ~hold_valid;
    assign drop_active = drop_resp || redirect_flush;
    assign direct_valid = (state == F_RESP_READY) && resp_fire && if_out_ready && ~drop_active;

    assign if_in_ready = (state == F_REQ_VALID) && ifu_reqReady && ~redirect_flush;
    assign if_out_valid = hold_valid || direct_valid;
    assign if_pc = hold_valid ? hold_pc : req_pc;
    assign if_pc4 = if_pc + 32'd4;
    assign if_inst = hold_valid ? hold_inst : ifu_rdata;

    always @(posedge clk) begin
        if (rst) begin
            state <= F_REQ_VALID;
            req_pc <= 32'h8000_0000;
            hold_pc <= 32'b0;
            hold_inst <= 32'b0;
            drop_resp <= 1'b0;
            redirect_pc <= 32'b0;
        end else begin
            case (state)
                F_REQ_VALID: begin
                    if (redirect_flush) begin
                        req_pc <= npc;
                    end else if (req_fire) begin
                        state <= F_WAIT_RESP_VALID;
                    end
                end

                F_WAIT_RESP_VALID: begin
                    if (redirect_flush) begin
                        drop_resp <= 1'b1;
                        redirect_pc <= npc;
                    end
                    if (ifu_respValid && can_accept_resp) begin
                        state <= F_RESP_READY;
                    end
                end

                F_RESP_READY: begin
                    if (redirect_flush) begin
                        drop_resp <= 1'b1;
                        redirect_pc <= npc;
                    end

                    if (resp_fire) begin
                        if (drop_active) begin
                            drop_resp <= 1'b0;
                            req_pc <= redirect_flush ? npc : redirect_pc;
                            state <= F_REQ_VALID;
                        end else if (if_out_ready) begin
                            req_pc <= req_pc + 32'd4;
                            state <= F_REQ_VALID;
                        end else begin
                            hold_pc <= req_pc;
                            hold_inst <= ifu_rdata;
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
                        state <= F_REQ_VALID;
                    end else if (hold_fire) begin
                        state <= F_REQ_VALID;
                    end
                end

                default: begin
                    state <= F_REQ_VALID;
                end
            endcase
        end
    end

endmodule
