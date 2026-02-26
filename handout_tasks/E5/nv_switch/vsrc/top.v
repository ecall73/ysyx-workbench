module top(
    input clk,
    input rst,
    input [7:0] sw,
    output [15:0] ledr
);

assign ledr[0] = sw[0] ^ sw[1];

endmodule
