`timescale 1ns / 1ps

`include "defines.v"

module RF(
    input  wire        clk,
    input  wire        rst,
    // Write rd                   
    input  wire        wen,
    input  wire [ 4:0] waddr,
    input  wire [31:0] wdata,
    // Read  rs1 rs2
    input  wire [ 4:0] rR1,
    input  wire [ 4:0] rR2,

    output reg  [31:0] rR1_data,
    output reg  [31:0] rR2_data
);

    reg [31:0] reg_bank [0:31];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                reg_bank[i] <= 0;
            end
        end
        else if (wen & (waddr != 5'd0)) begin
            reg_bank[waddr] <= wdata;
        end
    end

    always @(*) begin
        rR1_data = reg_bank[rR1];
        rR2_data = reg_bank[rR2];
    end

endmodule
