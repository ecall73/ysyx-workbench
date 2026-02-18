module top_module(
    input clk,
    input [7:0] in,
    input reset,    // Synchronous reset
    output done
);

    parameter BYTE1 = 0, BYTE2 = 1, BYTE3 = 2, DONE = 3;
    reg [1:0] state, next_state;

    always @(posedge clk) begin
        if (reset)
            state <= BYTE1;
        else
            state <= next_state;
    end

    always @(*) begin
        case (state)
            BYTE1: begin
                if (in[3])
                    next_state = BYTE2;
                else
                    next_state = BYTE1;
            end
            BYTE2: begin
                next_state = BYTE3;
            end
            BYTE3: begin
                next_state = DONE;
            end
            DONE: begin
                if (in[3])
                    next_state = BYTE2;
                else
                    next_state = BYTE1;
            end
            default: next_state = BYTE1;
        endcase
    end

    assign done = (state == DONE);

endmodule