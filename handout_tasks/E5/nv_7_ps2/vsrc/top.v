module top(
    input clk,
    input rst,
    input [4:0] btn,
    input [7:0] sw,
    input ps2_clk,
    input ps2_data,
    output [7:0] seg0,
    output [7:0] seg1,
    output [7:0] seg2,
    output [7:0] seg3,
    output [7:0] seg4,
    output [7:0] seg5
);

    wire [7:0] scancode;
    wire valid;

    ps2_keyboard my_keyboard(
        .clk(clk),
        .resetn(~rst),
        .ps2_clk(ps2_clk),
        .ps2_data(ps2_data),
        .scancode(scancode),
        .valid(valid)
    );

    reg [1:0] state;
    localparam S_IDLE = 2'd0;
    localparam S_HOLD = 2'd1;
    localparam S_RELEASE = 2'd2;

    reg [7:0] current_key;
    reg [7:0] press_count;
    reg key_pressed_flag;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            current_key <= 8'h00;
            press_count <= 8'h00;
            key_pressed_flag <= 1'b0;
        end else begin
            if (valid) begin
                case (state)
                    S_IDLE: begin
                        if (scancode != 8'hF0) begin
                            current_key <= scancode;
                            press_count <= press_count + 1'b1;
                            key_pressed_flag <= 1'b1;
                            state <= S_HOLD;
                        end
                    end
                    S_HOLD: begin
                        if (scancode == 8'hF0) begin
                            state <= S_RELEASE;
                        end else if (scancode != current_key) begin
                            // 新的按键被按下，重新识别
                            current_key <= scancode;
                            press_count <= press_count + 1'b1;
                            key_pressed_flag <= 1'b1;
                        end
                    end
                    S_RELEASE: begin
                        // 释放时需要忽略下一次receive
                        key_pressed_flag <= 1'b0;
                        state <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end

    // ASCII Lookup Table
    reg [7:0] ascii_val;
    always @(*) begin
        case(current_key)
            8'h1C: ascii_val = 8'h41; // A
            8'h32: ascii_val = 8'h42; // B
            8'h21: ascii_val = 8'h43; // C
            8'h23: ascii_val = 8'h44; // D
            8'h24: ascii_val = 8'h45; // E
            8'h2B: ascii_val = 8'h46; // F
            8'h34: ascii_val = 8'h47; // G
            8'h33: ascii_val = 8'h48; // H
            8'h43: ascii_val = 8'h49; // I
            8'h3B: ascii_val = 8'h4A; // J
            8'h42: ascii_val = 8'h4B; // K
            8'h4B: ascii_val = 8'h4C; // L
            8'h3A: ascii_val = 8'h4D; // M
            8'h31: ascii_val = 8'h4E; // N
            8'h44: ascii_val = 8'h4F; // O
            8'h4D: ascii_val = 8'h50; // P
            8'h15: ascii_val = 8'h51; // Q
            8'h2D: ascii_val = 8'h52; // R
            8'h1B: ascii_val = 8'h53; // S
            8'h2C: ascii_val = 8'h54; // T
            8'h3C: ascii_val = 8'h55; // U
            8'h2A: ascii_val = 8'h56; // V
            8'h1D: ascii_val = 8'h57; // W
            8'h22: ascii_val = 8'h58; // X
            8'h35: ascii_val = 8'h59; // Y
            8'h1A: ascii_val = 8'h5A; // Z
            8'h16: ascii_val = 8'h31; // 1
            8'h1E: ascii_val = 8'h32; // 2
            8'h26: ascii_val = 8'h33; // 3
            8'h25: ascii_val = 8'h34; // 4
            8'h2E: ascii_val = 8'h35; // 5
            8'h36: ascii_val = 8'h36; // 6
            8'h3D: ascii_val = 8'h37; // 7
            8'h3E: ascii_val = 8'h38; // 8
            8'h46: ascii_val = 8'h39; // 9
            8'h45: ascii_val = 8'h30; // 0
            default: ascii_val = 8'h00;
        endcase
    end

    seg_decoder seg0_dec (.val(key_pressed_flag ? current_key[3:0] : 4'hF), .seg(seg0), .force_off(!key_pressed_flag));
    seg_decoder seg1_dec (.val(key_pressed_flag ? current_key[7:4] : 4'hF), .seg(seg1), .force_off(!key_pressed_flag));
    seg_decoder seg2_dec (.val(key_pressed_flag ? ascii_val[3:0] : 4'hF), .seg(seg2), .force_off(!key_pressed_flag));
    seg_decoder seg3_dec (.val(key_pressed_flag ? ascii_val[7:4] : 4'hF), .seg(seg3), .force_off(!key_pressed_flag));
    
    seg_decoder seg4_dec (.val(press_count[3:0]), .seg(seg4), .force_off(1'b0));
    seg_decoder seg5_dec (.val(press_count[7:4]), .seg(seg5), .force_off(1'b0));

endmodule
