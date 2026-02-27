`define SEG_X 8'b11111111
`define SEG_0 8'b00000011
`define SEG_1 8'b10011111
`define SEG_2 8'b00100101
`define SEG_3 8'b00001101
`define SEG_4 8'b10011001
`define SEG_5 8'b01001001
`define SEG_6 8'b01000001
`define SEG_7 8'b00011111
`define SEG_8 8'b00000001
`define SEG_9 8'b00001001
`define SEG_A 8'b00010001
`define SEG_B 8'b11000001
`define SEG_C 8'b11100101
`define SEG_D 8'b10000101
`define SEG_E 8'b01100001
`define SEG_F 8'b01110001

module seg_decoder(
    input [3:0] val,
    output reg [7:0] seg,
    input force_off
);
    always @(*) begin
        if (force_off) begin
            seg = `SEG_X;
        end else begin
            case(val)
                4'h0: seg = `SEG_0;
                4'h1: seg = `SEG_1;
                4'h2: seg = `SEG_2;
                4'h3: seg = `SEG_3;
                4'h4: seg = `SEG_4;
                4'h5: seg = `SEG_5;
                4'h6: seg = `SEG_6;
                4'h7: seg = `SEG_7;
                4'h8: seg = `SEG_8;
                4'h9: seg = `SEG_9;
                4'hA: seg = `SEG_A;
                4'hB: seg = `SEG_B;
                4'hC: seg = `SEG_C;
                4'hD: seg = `SEG_D;
                4'hE: seg = `SEG_E;
                4'hF: seg = `SEG_F;
                default: seg = `SEG_X;
            endcase
        end
    end
endmodule
