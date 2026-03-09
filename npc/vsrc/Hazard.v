`timescale 1ns / 1ps

`include "defines.v"

module Hazard(
    input  wire        MDUStall,
    input  wire        external_stall,

    input  wire [ 4:0] id_rR1,
    input  wire [ 4:0] id_rR2,
    
    input  wire        ex_MemRead,
    input  wire [ 4:0] ex_RFwaddr,
    
    input  wire        me1_MemRead,
    input  wire [ 4:0] me1_RFwaddr,

    input  wire        waste1,
    input  wire        waste3,

    output reg         stall_PC,
    output reg         stall_IF_ID,
    output reg         stall_ID_EX,

    output reg         flush_IF_ID,
    output reg         flush_ID_EX,
    output reg         flush_EX_ME1
);

    wire lwStall;
    wire lw_ID_EX, lw_ID_ME1;

    assign lw_ID_EX = (id_rR1 == ex_RFwaddr || id_rR2 == ex_RFwaddr) && ex_MemRead;
    assign lw_ID_ME1 = (id_rR1 == me1_RFwaddr || id_rR2 == me1_RFwaddr) && me1_MemRead;

    // stall
    assign lwStall = lw_ID_EX || lw_ID_ME1;

    /*assign stall_PC = (lwStall || MDUStall) && ~(waste1 || waste3);
    assign stall_IF_ID = lwStall || MDUStall;
    assign stall_ID_EX = MDUStall;

    // flush
    assign flush_IF_ID = (waste1 || waste3) && ~lwStall && ~MDUStall;
    assign flush_ID_EX = lwStall || waste3;
    assign flush_EX_ME1 = waste3 || MDUStall;*/

    always @(*) begin
        if (external_stall) begin
            stall_PC = 1;
            flush_IF_ID = 0;
            stall_IF_ID = 1;
            flush_ID_EX = 0;
            stall_ID_EX = 1;
            flush_EX_ME1 = 0;
        end else if (waste3) begin
            stall_PC = 0;
            flush_IF_ID = 1;
            stall_IF_ID = 0;
            flush_ID_EX = 1;
            stall_ID_EX = 0;
            flush_EX_ME1 = 1;
        end else if (MDUStall) begin
            stall_PC = 1;
            flush_IF_ID = 0;
            stall_IF_ID = 1;
            flush_ID_EX = 0;
            stall_ID_EX = 1;
            flush_EX_ME1 = 1;
        end else if (lwStall) begin
            stall_PC = 1;
            flush_IF_ID = 0;
            stall_IF_ID = 1;
            flush_ID_EX = 1;
            stall_ID_EX = 0;
            flush_EX_ME1 = 0;
        end else if (waste1) begin
            stall_PC = 0;
            flush_IF_ID = 1;
            stall_IF_ID = 0;
            flush_ID_EX = 0;
            stall_ID_EX = 0;
            flush_EX_ME1 = 0;
        end else begin
            stall_PC = 0;
            flush_IF_ID = 0;
            stall_IF_ID = 0;
            flush_ID_EX = 0;
            stall_ID_EX = 0;
            flush_EX_ME1 = 0;
        end
    end
    
endmodule
