`timescale 1ns / 1ps

module BRU(
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [ 2:0] funct3,
    output wire        Result
);

    wire cmp_eq;
    wire cmp_lt;
    wire cmp_ltu;

    assign cmp_eq = (A == B);
    assign cmp_lt = ($signed(A) < $signed(B));
    assign cmp_ltu = (A < B);

    assign Result = (funct3 == 3'b000) ? cmp_eq   :
                    (funct3 == 3'b001) ? ~cmp_eq  :
                    (funct3 == 3'b100) ? cmp_lt   :
                    (funct3 == 3'b101) ? ~cmp_lt  :
                    (funct3 == 3'b110) ? cmp_ltu  :
                    (funct3 == 3'b111) ? ~cmp_ltu :
                                         1'b0;

endmodule
