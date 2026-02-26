module top(
    input clk,
    input rst,
    input [7:0] sw,
    output reg [15:0] ledr
);

    reg [23:0] counter;

    always @(posedge clk) begin
        if(rst) begin
            ledr <= 16'h0001;
            counter <= 24'h000000;
        end else if(sw[0]) begin
            counter <= counter + 1;
            if(counter == 24'h000000) begin
                ledr <= {ledr[14:0], ledr[15]};
            end
        end
    end

endmodule
