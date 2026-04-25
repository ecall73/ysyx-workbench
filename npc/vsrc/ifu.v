`timescale 1ns / 1ps
`include "defines.v"

module ifu (
    input  wire        clk,
    input  wire        rst,
    input  wire        if_in_valid,
    output wire        if_in_ready,
    input  wire        if_out_ready,
    input  wire        redirect_flush,

    // IROM Interface
    input  wire [31:0] irom_data,
    output wire [31:0] irom_addr,
    output wire        irom_ren,

    // To ID stage
    output wire        if_out_valid,
    output reg  [31:0] if_pc,
    output wire [31:0] if_pc4,
    output wire [31:0] if_inst,

    input  wire [31:0] npc
);
    reg [31:0] pre_pc;
    wire if_advance;

    assign if_pc4 = if_pc + 4;
    assign if_in_ready = if_out_ready || redirect_flush;
    assign if_out_valid = if_in_valid && ~rst;
    assign if_advance = if_in_valid && if_in_ready;

    always @(posedge clk) begin
        if (rst) begin
            if_pc <= 32'h8000_0000;
        end else if (if_advance) begin
            if_pc <= npc;
        end
    end

    always @(*) begin
        if (rst) begin
            pre_pc = 32'h8000_0000;
        end else if (if_advance) begin
            pre_pc = npc;
        end else begin
            pre_pc = if_pc;
        end
    end

    assign irom_ren = rst || if_advance;
    assign irom_addr = pre_pc;
    assign if_inst = irom_data;

endmodule
