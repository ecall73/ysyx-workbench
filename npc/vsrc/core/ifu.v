`timescale 1ns / 1ps

module ifu #(
    parameter [31:0] RESET_PC = 32'h3000_0000
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        if_in_valid,
    output wire        if_in_ready,
    input  wire        if_out_ready,
    input  wire        redirect_flush,

    // ICache request/response interface
    output wire        ic_req_valid,
    input  wire        ic_req_ready,
    output wire [31:0] ic_req_pc,
    input  wire        ic_resp_valid,
    output wire        ic_resp_ready,
    input  wire [31:0] ic_resp_pc,
    input  wire [31:0] ic_resp_inst,
    output wire        ic_flush,

    // To ID stage
    output wire        if_out_valid,
    output wire [31:0] if_pc,
    output wire [31:0] if_pc4,
    output wire [31:0] if_inst,

    input  wire [31:0] npc
);
    reg [31:0] next_pc;

    wire req_fire;

    assign ic_req_valid = if_in_valid && !redirect_flush;
    assign ic_req_pc = next_pc;
    assign ic_resp_ready = if_out_ready || redirect_flush;
    assign ic_flush = redirect_flush;

    assign req_fire = ic_req_valid && ic_req_ready;
    assign if_in_ready = ic_req_ready && !redirect_flush;

    assign if_out_valid = ic_resp_valid && !redirect_flush;
    assign if_pc = ic_resp_pc;
    assign if_pc4 = if_pc + 32'd4;
    assign if_inst = ic_resp_inst;

    always @(posedge clock) begin
        if (reset) begin
            next_pc <= RESET_PC;
        end else if (redirect_flush) begin
            next_pc <= npc;
        end else if (req_fire) begin
            next_pc <= next_pc + 32'd4;
        end
    end

endmodule
