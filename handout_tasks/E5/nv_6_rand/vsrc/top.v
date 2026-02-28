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


module top(
    input clk,
    input rst,
    input btn,
    output reg [7:0] ledr,
    output reg [7:0] seg2,
    output reg [7:0] seg1,
    output reg [7:0] seg0
);  

    // 没招了这虚拟板卡真难用真不如实体板一根我说实话
    // 懒得自己写rst延迟释放逻辑了，直接initial吧
    initial begin
        ledr = 8'b00000001;
    end

    always @(posedge btn) begin
        ledr <= {ledr[4] ^ ledr[3] ^ ledr[2] ^ ledr[0], ledr[7:1]};
    end

    wire [7:0] hundreds = ledr / 8'd100;
    wire [7:0] tens = (ledr % 8'd100) / 8'd10;
    wire [7:0] units = ledr % 8'd10;
    
    // 数码管不赖，至少没让我写字段位段驱动代码
    // 就是这编码不合理啊，正常数码管哪有这样的，这很诡异你们知道吗
    always @(*) begin
        case(units)
            0: seg0 = `SEG_0;
            1: seg0 = `SEG_1;
            2: seg0 = `SEG_2;
            3: seg0 = `SEG_3;
            4: seg0 = `SEG_4;
            5: seg0 = `SEG_5;
            6: seg0 = `SEG_6;
            7: seg0 = `SEG_7;
            8: seg0 = `SEG_8;
            9: seg0 = `SEG_9;
            default: seg0 = `SEG_X;
        endcase
        
        case(tens)
            0: seg1 = `SEG_0;
            1: seg1 = `SEG_1;
            2: seg1 = `SEG_2;
            3: seg1 = `SEG_3;
            4: seg1 = `SEG_4;
            5: seg1 = `SEG_5;
            6: seg1 = `SEG_6;
            7: seg1 = `SEG_7;
            8: seg1 = `SEG_8;
            9: seg1 = `SEG_9;
            default: seg1 = `SEG_X;
        endcase
        
        case(hundreds)
            0: seg2 = `SEG_0;
            1: seg2 = `SEG_1;
            2: seg2 = `SEG_2;
            3: seg2 = `SEG_3;
            4: seg2 = `SEG_4;
            5: seg2 = `SEG_5;
            6: seg2 = `SEG_6;
            7: seg2 = `SEG_7;
            8: seg2 = `SEG_8;
            9: seg2 = `SEG_9;
            default: seg2 = `SEG_X;
        endcase
    end

endmodule
