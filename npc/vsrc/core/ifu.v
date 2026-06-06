`timescale 1ns / 1ps

module ifu #(
    parameter [31:0] RESET_PC = 32'h3000_0000
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        if_ready,
    input  wire        redirect_flush,

    // IF stage request side
    output wire        if_valid,
    output wire [31:0] if_pc,
    output wire [31:0] if_pc4,
    output wire        if_flush,

    input  wire [31:0] npc
);
    reg [31:0] next_pc;

    wire req_fire;

    assign if_valid = !redirect_flush;
    assign if_pc = next_pc;
    assign if_pc4 = next_pc + 32'd4;
    assign if_flush = redirect_flush;

    assign req_fire = if_valid && if_ready;

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
