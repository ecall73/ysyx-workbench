`timescale 1ns / 1ps

`include "defines.v"

`define MUL_mul 2'b00
`define MUL_mulh 2'b01
`define MUL_mulhsu 2'b10
`define MUL_mulhu 2'b11

module mul(
    input clk,
    input rst,
    input in_valid,
    input [1:0] mul_type,
    input [31:0] A,
    input [31:0] B,
    output out_valid,
    output reg [63:0] P
    );
    
    // Valid Logic with Reset
    reg [2:0] valid_d;
    always @(posedge clk) begin
        if(rst) valid_d <= 3'b0;
        else    valid_d <= {valid_d[1:0], in_valid};
    end
    assign out_valid = valid_d[2];

    reg aSigned, bSigned;
    reg [1:0] aSigned_d, bSigned_d;


    always @(*) begin
        case(mul_type)
            `MUL_mulh: begin
                aSigned = 1'b1;
                bSigned = 1'b1;
            end
            `MUL_mulhsu: begin
                aSigned = 1'b1;
                bSigned = 1'b0;
            end
            `MUL_mulhu: begin
                aSigned = 1'b0;
                bSigned = 1'b0;
            end
            default: begin
                aSigned = 1'b0;
                bSigned = 1'b0;
            end
        endcase
    end

    

    always @(posedge clk) begin
        aSigned_d <= {aSigned_d[0], aSigned};
        bSigned_d <= {bSigned_d[0], bSigned};
    end

`ifdef DSP48E2_MULT
    wire [31:0] P_ll, P_lh, P_hl, P_hh;
    wire [26:0] ALow, AHigh;
    wire [17:0] BLow, BHigh;
    assign ALow = {11'b0, A[15:0]};
    assign BLow = {2'b0, B[15:0]};
    assign AHigh = {{11{aSigned && A[31]}}, A[31:16]};
    assign BHigh = {{2{bSigned && B[31]}}, B[31:16]};

    dsp48e2_mult mult_ll (
        .CLK(clk),
        .A(ALow),
        .B(BLow),
        .P(P_ll)
    );
    dsp48e2_mult mult_lh (
        .CLK(clk),
        .A(ALow),
        .B(BHigh),
        .P(P_lh)
    );
    dsp48e2_mult mult_hl (
        .CLK(clk),
        .A(AHigh),
        .B(BLow),
        .P(P_hl)
    );
    dsp48e2_mult mult_hh (
        .CLK(clk),
        .A(AHigh),
        .B(BHigh),
        .P(P_hh)
    );

`elsif DSP48E1_MULT
    wire [31:0] P_ll, P_lh, P_hl, P_hh;
    wire [24:0] ALow, AHigh;
    wire [17:0] BLow, BHigh;
    assign ALow = {9'b0, A[15:0]};
    assign BLow = {2'b0, B[15:0]};
    assign AHigh = {{9{aSigned && A[31]}}, A[31:16]};
    assign BHigh = {{2{bSigned && B[31]}}, B[31:16]};

    dsp48e1_mult mult_ll (
        .CLK(clk),
        .A(ALow),
        .B(BLow),
        .P(P_ll)
    );
    dsp48e1_mult mult_lh (
        .CLK(clk),
        .A(ALow),
        .B(BHigh),
        .P(P_lh)
    );
    dsp48e1_mult mult_hl (
        .CLK(clk),
        .A(AHigh),
        .B(BLow),
        .P(P_hl)
    );
    dsp48e1_mult mult_hh (
        .CLK(clk),
        .A(AHigh),
        .B(BHigh),
        .P(P_hh)
    );

`else
    reg [31:0] P_ll, P_lh, P_hl, P_hh;
    wire [16:0] ALow, AHigh; 
    reg [16:0] ALow_d1, AHigh_d1;
    wire [16:0] BLow, BHigh; 
    reg [16:0] BLow_d1, BHigh_d1;
    assign ALow = {1'b0, A[15:0]};
    assign BLow = {1'b0, B[15:0]};
    assign AHigh = {{1{aSigned && A[31]}}, A[31:16]};
    assign BHigh = {{1{bSigned && B[31]}}, B[31:16]};

    always @(posedge clk) begin
        ALow_d1     <= ALow;
        BLow_d1     <= BLow;
        AHigh_d1    <= AHigh;
        BHigh_d1    <= BHigh;
        
        P_ll        <= $signed(ALow_d1) * $signed (BLow_d1);
        P_lh        <= $signed(ALow_d1) * $signed (BHigh_d1);
        P_hl        <= $signed(AHigh_d1) * $signed (BLow_d1);
        P_hh        <= $signed(AHigh_d1) * $signed (BHigh_d1);
    end

`endif

    always @(posedge clk) begin
        P <= {P_hh, 32'b0} + {{16{aSigned_d[1] && P_hl[31]}}, P_hl, 16'b0} + {{16{bSigned_d[1] && P_lh[31]}}, P_lh, 16'b0} + P_ll;
    end

endmodule
