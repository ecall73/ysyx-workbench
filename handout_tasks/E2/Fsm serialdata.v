module top_module(
    input clk,
    input in,
    input reset,    // Synchronous reset
    output [7:0] out_byte,
    output done
);

    parameter READY = 2'd0;
    parameter RECEIVE = 2'd1;
    parameter DONE = 2'd2;
    parameter ERROR = 2'd3;
    
    reg [1:0] state, next_state;
    reg [3:0] bit_count;
    reg [7:0] data_reg;

    always @(posedge clk) begin
        if (reset)
            state <= READY;
        else
            state <= next_state;
    end

    always @(posedge clk) begin
        if (reset)
            bit_count <= 4'd0;
        else if (state == RECEIVE && bit_count != 4'd8)
            bit_count <= bit_count + 4'd1;
        else if (state == DONE || state == ERROR)
            bit_count <= 4'd0;
    end

    always @(posedge clk) begin
        if (reset)
            data_reg <= 8'd0;
        else if (state == RECEIVE && bit_count < 4'd8) begin
            case (bit_count)
                4'd0: data_reg[0] <= in;
                4'd1: data_reg[1] <= in;
                4'd2: data_reg[2] <= in;
                4'd3: data_reg[3] <= in;
                4'd4: data_reg[4] <= in;
                4'd5: data_reg[5] <= in;
                4'd6: data_reg[6] <= in;
                4'd7: data_reg[7] <= in;
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (state)
            READY: begin
                if (in)
                    next_state = READY;
                else
                    next_state = RECEIVE;
            end
            
            RECEIVE: begin
                if (bit_count == 4'd8) begin
                    if (in)
                        next_state = DONE;
                    else
                        next_state = ERROR;
                end
                else begin
                    next_state = RECEIVE;
                end
            end
            
            DONE: begin
                if (in)
                    next_state = READY;
                else
                    next_state = RECEIVE;
            end
            
            ERROR: begin
                if (in)
                    next_state = READY;
                else
                    next_state = ERROR;
            end
            
            default: next_state = READY;
        endcase
    end

    assign done = (state == DONE);
    assign out_byte = data_reg;

endmodule