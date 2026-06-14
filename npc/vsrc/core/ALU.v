module ysyx_26030082_ALU(
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [31:0] BRU_A,
    input  wire [31:0] BRU_B,
    input  wire [ 3:0] ALUControl,
    input  wire [ 2:0] BRUFunct3,
    output wire [31:0] Result,
    output wire        BRUResult
);

    localparam [3:0] ALU_ADD  = 4'b0000;
    localparam [3:0] ALU_SUB  = 4'b1000;
    localparam [3:0] ALU_SLL  = 4'b0001;
    localparam [3:0] ALU_SLT  = 4'b0010;
    localparam [3:0] ALU_SLTU = 4'b0011;
    localparam [3:0] ALU_XOR  = 4'b0100;
    localparam [3:0] ALU_SRL  = 4'b0101;
    localparam [3:0] ALU_SRA  = 4'b1101;
    localparam [3:0] ALU_OR   = 4'b0110;
    localparam [3:0] ALU_AND  = 4'b0111;

    wire [31:0] add_sub_result, and_result, or_result, xor_result;
    wire [31:0] shift_result;
    wire [31:0] shift_src;
    wire [31:0] shift_stage0;
    wire [31:0] shift_stage1;
    wire [31:0] shift_stage2;
    wire [31:0] shift_stage3;
    wire [31:0] shift_stage4;
    wire [31:0] shift_right_result;
    wire        is_left_shift;
    wire        is_arith_shift;
    wire        shift_fill;
    wire        is_sub_family;
    wire        cmp_lt;
    wire        cmp_ltu;
    wire        bru_cmp_eq;
    wire        bru_cmp_lt;
    wire        bru_cmp_ltu;
    wire [32:0] bru_sub_result;
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
    assign is_left_shift = (ALUControl == ALU_SLL);
    assign is_arith_shift = (ALUControl == ALU_SRA);
    assign shift_fill = is_arith_shift && A[31];
    assign shift_src = is_left_shift ? {A[0],  A[1],  A[2],  A[3],  A[4],  A[5],  A[6],  A[7],
                                        A[8],  A[9],  A[10], A[11], A[12], A[13], A[14], A[15],
                                        A[16], A[17], A[18], A[19], A[20], A[21], A[22], A[23],
                                        A[24], A[25], A[26], A[27], A[28], A[29], A[30], A[31]} : A;
    assign shift_stage0 = B[0] ? {shift_fill, shift_src[31:1]} : shift_src;
    assign shift_stage1 = B[1] ? {{2{shift_fill}}, shift_stage0[31:2]} : shift_stage0;
    assign shift_stage2 = B[2] ? {{4{shift_fill}}, shift_stage1[31:4]} : shift_stage1;
    assign shift_stage3 = B[3] ? {{8{shift_fill}}, shift_stage2[31:8]} : shift_stage2;
    assign shift_stage4 = B[4] ? {{16{shift_fill}}, shift_stage3[31:16]} : shift_stage3;
    assign shift_right_result = shift_stage4;
    assign shift_result = is_left_shift ? {shift_right_result[0],  shift_right_result[1],
                                           shift_right_result[2],  shift_right_result[3],
                                           shift_right_result[4],  shift_right_result[5],
                                           shift_right_result[6],  shift_right_result[7],
                                           shift_right_result[8],  shift_right_result[9],
                                           shift_right_result[10], shift_right_result[11],
                                           shift_right_result[12], shift_right_result[13],
                                           shift_right_result[14], shift_right_result[15],
                                           shift_right_result[16], shift_right_result[17],
                                           shift_right_result[18], shift_right_result[19],
                                           shift_right_result[20], shift_right_result[21],
                                           shift_right_result[22], shift_right_result[23],
                                           shift_right_result[24], shift_right_result[25],
                                           shift_right_result[26], shift_right_result[27],
                                           shift_right_result[28], shift_right_result[29],
                                           shift_right_result[30], shift_right_result[31]} : shift_right_result;
    assign cmp_lt = (A[31] & ~B[31]) | ((~A[31] ^ B[31]) & add_sub_result[31]);
    assign cmp_ltu = ~carry;
    assign bru_cmp_eq = (BRU_A == BRU_B);
    assign bru_sub_result = {1'b0, BRU_A} - {1'b0, BRU_B};
    assign bru_cmp_lt = (BRU_A[31] & ~BRU_B[31]) |
                        ((BRU_A[31] ~^ BRU_B[31]) & bru_sub_result[31]);
    assign bru_cmp_ltu = bru_sub_result[32];

    always @(*) begin
        case (ALUControl)
            ALU_ADD:  result_r = add_sub_result;
            ALU_SUB:  result_r = add_sub_result;
            ALU_AND:  result_r = and_result;
            ALU_OR:   result_r = or_result;
            ALU_XOR:  result_r = xor_result;
            ALU_SLL:  result_r = shift_result;
            ALU_SRL:  result_r = shift_result;
            ALU_SRA:  result_r = shift_result;
            ALU_SLT:  result_r = {31'b0, cmp_lt};
            ALU_SLTU: result_r = {31'b0, cmp_ltu};
            default:  result_r = 32'b0;
        endcase
    end

    assign Result = result_r;
    assign BRUResult = (BRUFunct3 == 3'b000) ? bru_cmp_eq   :
                       (BRUFunct3 == 3'b001) ? ~bru_cmp_eq  :
                       (BRUFunct3 == 3'b100) ? bru_cmp_lt   :
                       (BRUFunct3 == 3'b101) ? ~bru_cmp_lt  :
                       (BRUFunct3 == 3'b110) ? bru_cmp_ltu  :
                       (BRUFunct3 == 3'b111) ? ~bru_cmp_ltu :
                                                1'b0;

endmodule
