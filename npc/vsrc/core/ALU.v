`timescale 1ns / 1ps

module ALU(
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [ 3:0] ALUControl,
    output wire [31:0] Result
);

    localparam [3:0] ALU_ADD  = 4'd0;
    localparam [3:0] ALU_SUB  = 4'd1;
    localparam [3:0] ALU_AND  = 4'd2;
    localparam [3:0] ALU_OR   = 4'd3;
    localparam [3:0] ALU_XOR  = 4'd4;
    localparam [3:0] ALU_SLL  = 4'd5;
    localparam [3:0] ALU_SRL  = 4'd6;
    localparam [3:0] ALU_SRA  = 4'd7;
    localparam [3:0] ALU_SLT  = 4'd8;
    localparam [3:0] ALU_SLTU = 4'd9;

    wire [31:0] add_sub_result, and_result, or_result, xor_result;
    wire [31:0] sll_result, srl_result, sra_result;
    wire        is_sub_family;
    wire        cmp_lt;
    wire        cmp_ltu;
    reg  [31:0] result_r;

    wire [31:0] adder_a, adder_b;
    wire cin, carry;

    assign adder_a = A;
    assign is_sub_family = (ALUControl == ALU_SUB) ||
                           (ALUControl == ALU_SLT) ||
                           (ALUControl == ALU_SLTU);
    assign adder_b = is_sub_family ? ~B : B;
    assign cin = is_sub_family ? 1'b1 : 1'b0;

    assign {carry, add_sub_result} = adder_a + adder_b + cin;

    assign and_result   = A & B;
    assign or_result    = A | B;
    assign xor_result   = A ^ B;
    assign sll_result   = A << B[4:0];
    assign srl_result   = A >> B[4:0];
    assign sra_result   = ($signed(A)) >>> B[4:0];
    assign cmp_lt = (A[31] & ~B[31]) | ((~A[31] ^ B[31]) & add_sub_result[31]);
    assign cmp_ltu = ~carry;

    always @(*) begin
        case (ALUControl)
            ALU_ADD:  result_r = add_sub_result;
            ALU_SUB:  result_r = add_sub_result;
            ALU_AND:  result_r = and_result;
            ALU_OR:   result_r = or_result;
            ALU_XOR:  result_r = xor_result;
            ALU_SLL:  result_r = sll_result;
            ALU_SRL:  result_r = srl_result;
            ALU_SRA:  result_r = sra_result;
            ALU_SLT:  result_r = {31'b0, cmp_lt};
            ALU_SLTU: result_r = {31'b0, cmp_ltu};
            default:  result_r = 32'b0;
        endcase
    end

    assign Result = result_r;

endmodule
