`timescale 1ns / 1ps
`include "defines.v"

module lsu (
    input  wire        clk,
    input  wire        rst,

    // ME1 Stage inputs
    input  wire [31:0] me1_ALUResult,
    input  wire [ 2:0] me1_mask,
    input  wire        me1_MemWrite,
    input  wire        me1_MemRead,
    input  wire [31:0] me1_rR2_data,

    input  wire        me1_RegWrite,
    input  wire [ 4:0] me1_RFwaddr,
    input  wire [31:0] me1_RFwdata,

    // Peripheral Interface
    input  wire [31:0] perip_rdata,
    output wire [31:0] perip_addr,
    output wire [ 2:0] perip_mask,
    output wire        perip_wen,
    output wire        perip_ren,
    output wire [31:0] perip_wdata,

    // ME2 Stage outputs
    output reg         me2_RegWrite,
    output reg  [ 4:0] me2_RFwaddr,
    output wire [31:0] me2_RFwdata

    `ifdef RUN_TRACE
    ,   input  wire [31:0] pc_ME1,
        input  wire        have_inst_ME1,
        input  wire        me1_ebreak,
        output reg  [31:0] pc_ME2,
        output reg         have_inst_ME2,
        output reg         me2_ebreak
    `endif
);

    reg [31:0] me2_RFwdata_tmp;
    reg        me2_MemRead;

    // MEM - DRAM
    assign perip_addr = me1_ALUResult;
    assign perip_mask = me1_mask;
    assign perip_wen = me1_MemWrite;
    assign perip_ren = me1_MemRead;
    assign perip_wdata = me1_rR2_data;

    // Expanded ME1_ME2 module logic
    always @(posedge clk) begin
        if(rst) begin
            me2_RegWrite    <= 0;
            me2_RFwaddr     <= 0;
            me2_MemRead     <= 0;
            me2_RFwdata_tmp <= 0;
        end else begin
            me2_RegWrite    <= me1_RegWrite;
            me2_RFwaddr     <= me1_RFwaddr;
            me2_MemRead     <= me1_MemRead;
            me2_RFwdata_tmp <= me1_RFwdata;
        end
    end

    //trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst)    pc_ME2 <= 32'b0;
            else        pc_ME2 <= pc_ME1;
        end
        always @(posedge clk) begin
            if (rst)    have_inst_ME2 <= 1'b0;
            else        have_inst_ME2 <= have_inst_ME1;
        end
        always @(posedge clk) begin
            if (rst)    me2_ebreak <= 1'b0;
            else        me2_ebreak <= me1_ebreak;
        end
    `endif

    assign me2_RFwdata = me2_MemRead ? perip_rdata : me2_RFwdata_tmp;

endmodule
