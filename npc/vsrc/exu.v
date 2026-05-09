`timescale 1ns / 1ps
`include "defines.v"

module exu (
    input  wire        clk,
    input  wire        rst,
    input  wire        ex_in_valid,
    output wire        ex_in_ready,
    output wire        ex_out_valid,
    input  wire        ex_out_ready,

    // ALU inputs
    input  wire        ex_ALUSrcA,
    input  wire        ex_ALUSrcB,
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_pc4,
    input  wire [31:0] ex_rR1_data,
    input  wire [31:0] ex_rR2_data,
    input  wire [31:0] ex_imm,
    input  wire [13:0] ex_ALUControl,

    // CSR inputs
    input  wire        ex_CSRSrc,
    input  wire [11:0] ex_CSRaddr,
    input  wire [ 4:0] ex_CSRControl,

    // Control for WB data selection
    input  wire [ 2:0] ex_MemToReg,

    // Outputs
    output wire [31:0] ex_ALUResult,
    output wire [31:0] ex_BranchTarget,
    output wire        ex_ALUisTrue,

    output wire [31:0] CSRrdata,
    output wire        ex_CSRjump,
    output wire [31:0] ex_CSRnpc,

    output wire [31:0] ex_RFwdata,
    output wire        ex_MemRead
);

    wire [31:0] ex_A;
    wire [31:0] ex_B;

    assign ex_in_ready = ~ex_in_valid || ex_out_ready;
    assign ex_out_valid = ex_in_valid;

    assign ex_A = ex_ALUSrcA ? ex_pc : ex_rR1_data;
    assign ex_B = ex_ALUSrcB ? ex_imm : ex_rR2_data;
    assign ex_BranchTarget = ex_pc + ex_imm;

    ALU u_ALU (
        .A                      (ex_A),
        .B                      (ex_B),
        .ALUControl             (ex_ALUControl),

        .Result                 (ex_ALUResult),
        .isTrue                 (ex_ALUisTrue)
    );

    CSR u_CSR (
        .clk                    (clk),
        .rst                    (rst),

        .CSRControl             (ex_CSRControl),
        .CSRaddr                (ex_CSRaddr),
        .CSRSrc                 (ex_CSRSrc),
        .rR1_data               (ex_rR1_data),
        .imm                    (ex_imm),

        .pc                     (ex_pc),

        .CSRrdata               (CSRrdata),
        .CSRjump                (ex_CSRjump),
        .CSRnpc                 (ex_CSRnpc)
    );

    assign ex_RFwdata = ex_MemToReg[1] ?
                            (ex_MemToReg[0] ? ex_imm : CSRrdata) :
                            (ex_MemToReg[0] ? ex_ALUResult : ex_pc4);

    assign ex_MemRead = ex_MemToReg[2];

endmodule
