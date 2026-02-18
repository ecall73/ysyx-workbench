module top_module(
    input clk,
    input in,
    input reset,    // Synchronous reset
    output [7:0] out_byte,
    output done
);

    parameter READY = 4'd0;
    parameter START = 4'd1;
    parameter D0 = 4'd2;
    parameter D1 = 4'd3;
    parameter D2 = 4'd4;
    parameter D3 = 4'd5;
    parameter D4 = 4'd6;
    parameter D5 = 4'd7;
    parameter D6 = 4'd8;
    parameter D7 = 4'd9;
    parameter PAR = 4'd10;
    parameter ERR = 4'd11;
    
    reg [3:0] state, next;
    reg [7:0] data_byte;
    reg rst_parity;
    reg odd_bit;
    reg done_out;

    always @(posedge clk) begin
        if (reset || rst_parity)
            odd_bit <= 1'b0;
        else if (in)
            odd_bit <= ~odd_bit;
    end

    always @(*) begin
        case (state)
            READY:  next = in ? READY : START;
            START:  next = D0;
            D0:     next = D1;
            D1:     next = D2;
            D2:     next = D3;
            D3:     next = D4;
            D4:     next = D5;
            D5:     next = D6;
            D6:     next = D7;
            D7:     next = PAR;
            PAR:    next = in ? READY : ERR;
            ERR:    next = in ? READY : ERR;
            default: next = READY;
        endcase
    end

    always @(posedge clk) begin
        if (reset)
            state <= READY;
        else
            state <= next;
    end

    always @(posedge clk) begin
        if (reset) begin
            data_byte <= 8'd0;
            rst_parity <= 1'b1;
            done_out <= 1'b0;
        end
        else begin
            if (next == D0 || next == D1 || next == D2 || next == D3 || 
                next == D4 || next == D5 || next == D6 || next == D7) begin
                data_byte <= {in, data_byte[7:1]};
            end
            else if (next == START) begin
                data_byte <= 8'd0;
                rst_parity <= 1'b0;
                done_out <= 1'b0;
            end
            else if (next == READY) begin
                done_out <= odd_bit;
            end
            else if (next == PAR) begin
                rst_parity <= 1'b1;
            end
        end
    end

    assign done = done_out;
    assign out_byte = done_out ? data_byte : 8'd0;

endmodule