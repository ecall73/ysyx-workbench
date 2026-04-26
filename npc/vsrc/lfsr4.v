`timescale 1ns / 1ps

module lfsr4 (
    input  wire       clk,
    input  wire       rst,
    input  wire       en,
    output wire [3:0] random
);

    reg [3:0] lfsr_reg;
    wire      feedback;
    wire [3:0] next_lfsr;

    // Polynomial: x^4 + x^3 + 1
    assign feedback = lfsr_reg[3] ^ lfsr_reg[2];
    assign next_lfsr = {lfsr_reg[2:0], feedback};
    assign random = lfsr_reg;

    always @(posedge clk) begin
        if (rst) begin
            lfsr_reg <= 4'h1;
        end else if (en) begin
            if (next_lfsr == 4'b0000) begin
                lfsr_reg <= 4'h1;
            end else begin
                lfsr_reg <= next_lfsr;
            end
        end
    end

endmodule
