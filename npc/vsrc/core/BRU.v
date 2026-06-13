module ysyx_26030082_BRU(
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [ 2:0] funct3,
    output wire        Result
);

    wire cmp_eq;
    wire cmp_lt;
    wire cmp_ltu;
    wire [32:0] sub_result;

    assign cmp_eq = (A == B);
    assign sub_result = {1'b0, A} - {1'b0, B};
    assign cmp_lt = (A[31] & ~B[31]) | ((A[31] ~^ B[31]) & sub_result[31]);
    assign cmp_ltu = sub_result[32];

    assign Result = (funct3 == 3'b000) ? cmp_eq   :
                    (funct3 == 3'b001) ? ~cmp_eq  :
                    (funct3 == 3'b100) ? cmp_lt   :
                    (funct3 == 3'b101) ? ~cmp_lt  :
                    (funct3 == 3'b110) ? cmp_ltu  :
                    (funct3 == 3'b111) ? ~cmp_ltu :
                                         1'b0;

endmodule
