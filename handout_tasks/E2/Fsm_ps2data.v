module top_module(
    input clk,
    input [7:0] in,
    input reset,    // Synchronous reset
    output [23:0] out_bytes,
    output done
);

    parameter BYTE1 = 3'd1, BYTE2 = 3'd2, BYTE3 = 3'd3, DONE = 3'd4;
    reg [2:0] state, next_state;
    reg [23:0] data;

    always @(*) begin
        case ({state, in[3]})
            {BYTE1, 1'b0}: next_state = BYTE1;
            {BYTE1, 1'b1}: next_state = BYTE2;
            {BYTE2, 1'b0}: next_state = BYTE3;
            {BYTE2, 1'b1}: next_state = BYTE3;
            {BYTE3, 1'b0}: next_state = DONE;
            {BYTE3, 1'b1}: next_state = DONE;
            {DONE, 1'b0}: next_state = BYTE1;
            {DONE, 1'b1}: next_state = BYTE2;
            default: next_state = BYTE1;
        endcase
    end

    always @(posedge clk) begin
        if (reset)
            state <= BYTE1;
        else
            state <= next_state;
    end

    assign done = (state == DONE);

    always @(posedge clk) begin
        if (reset)
            data <= 24'd0;
        else begin
            data[23:16] <= data[15:8];
            data[15:8] <= data[7:0];
            data[7:0] <= in;
        end
    end

    assign out_bytes = (done) ? data : 24'd0;

endmodule