`define SEG_X 8'b11111111
`define SEG_0 8'b00000011
`define SEG_1 8'b10011111
`define SEG_2 8'b00100101
`define SEG_3 8'b00001101
`define SEG_4 8'b10011001
`define SEG_5 8'b01001001
`define SEG_6 8'b01000001
`define SEG_7 8'b00011111


module top(
    input clk,
    input rst,
    input [8:0] sw,
    output reg [15:0] ledr,
    output reg [7:0] seg0
);

always @(*) begin
    ledr = 16'b0;
    seg0 = `SEG_X;
    if(sw[8]) begin
        ledr[4]     = 1'b1;
        ledr[2:0]   = sw[7] ? 3'd7 :
                      sw[6] ? 3'd6 :
                      sw[5] ? 3'd5 :
                      sw[4] ? 3'd4 :
                      sw[3] ? 3'd3 :
                      sw[2] ? 3'd2 :
                      sw[1] ? 3'd1 : 3'd0;
        seg0        = sw[7] ? `SEG_7 :
                      sw[6] ? `SEG_6 :
                      sw[5] ? `SEG_5 :
                      sw[4] ? `SEG_4 :
                      sw[3] ? `SEG_3 :
                      sw[2] ? `SEG_2 :
                      sw[1] ? `SEG_1 :
                      sw[0] ? `SEG_0 : `SEG_X;
    end
end

endmodule
