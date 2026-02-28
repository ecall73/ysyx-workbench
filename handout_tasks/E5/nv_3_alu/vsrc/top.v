module top(
    input clk,
    input rst,
    input [15:0] sw,
    output [15:0] ledr
);

    wire [3:0] A = sw[7:4];
    wire [3:0] B = sw[3:0];
    wire [2:0] ALUControl = sw[15:13];

    wire [3:0] add_result;
    wire add_carry;
    assign {add_carry, add_result} = A + B;
    wire overflow_add = (A[3] == B[3]) && (add_result[3] != A[3]);

    wire [3:0] sub_result;
    wire sub_borrow;
    assign {sub_borrow, sub_result} = A - B;
    wire overflow_sub = (A[3] != B[3]) && (sub_result[3] != A[3]);

    wire [3:0] not_result = ~A;
    wire [3:0] and_result = A & B;
    wire [3:0] or_result  = A | B;
    wire [3:0] xor_result = A ^ B;
    
    wire slt_result = $signed(A) < $signed(B);
    wire eq_result  = (A == B);

    reg [3:0] result;
    always @(*) begin
        case (ALUControl)
            3'b000: result = add_result;
            3'b001: result = sub_result;
            3'b010: result = not_result;
            3'b011: result = and_result;
            3'b100: result = or_result;
            3'b101: result = xor_result;
            3'b110: result = {3'b0, slt_result};
            3'b111: result = {3'b0, eq_result};
            default: result = 4'b0;
        endcase
    end

    wire overflow = (ALUControl == 3'b000) ? overflow_add :
                    (ALUControl == 3'b001) ? overflow_sub : 1'b0;
    wire carry = (ALUControl == 3'b000) ? add_carry :
                 (ALUControl == 3'b001) ? sub_borrow : 1'b0;
    wire zero = (result == 4'b0);

    assign ledr[3:0] = result;
    assign ledr[15]  = zero;
    assign ledr[14]  = overflow;
    assign ledr[13]  = carry;
    assign ledr[12:4] = 9'b0;

endmodule
