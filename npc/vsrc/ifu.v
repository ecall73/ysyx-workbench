`timescale 1ns / 1ps
`include "defines.v"

module ifu (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall_PC,

    // IROM Interface
    input  wire [31:0] irom_data,
    output wire [31:0] irom_addr,
    output wire        irom_ren,

    // To ID stage
    output reg  [31:0] if_pc,
    output wire [31:0] if_pc4,
    output wire [31:0] if_inst,

    input  wire [31:0] npc // Now input from myCPU
);
    reg [31:0] pre_pc;

    assign if_pc4 = if_pc + 4;

    // Expanded PC module logic
    always @(posedge clk) begin
        if (rst)        if_pc <= 32'h8000_0000;
        else if (stall_PC) if_pc <= if_pc;
        else            if_pc <= npc;
    end

    always @(*) begin
        if (rst)        pre_pc = 32'h8000_0000;
        else if (stall_PC) pre_pc = if_pc;
        else            pre_pc = npc;
    end

    assign irom_ren = ~stall_PC;
    assign irom_addr = pre_pc;
    assign if_inst = irom_data;

endmodule
