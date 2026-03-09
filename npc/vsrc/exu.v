`timescale 1ns / 1ps
`include "defines.v"

module exu (
    input  wire        clk,
    input  wire        rst,

    input  wire        flush_ID_EX,
    input  wire        flush_EX_ME1,

    input  wire [ 3:0] exception,
    input  wire [ 3:0] interrupt,

    // ALU inputs
    input  wire        ex_ALUSrcA,
    input  wire        ex_ALUSrcB,
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_pc4,
    input  wire [31:0] ex_rR1_data,
    input  wire [31:0] ex_rR2_data,
    input  wire [31:0] ex_imm,
    input  wire [13:0] ex_ALUControl,

    // MDU inputs
    input  wire        ex_m_en,
    input  wire [ 2:0] ex_MDUControl,

    // CSR inputs
    input  wire        ex_CSRSrc,
    input  wire [11:0] ex_CSRaddr,
    input  wire [ 4:0] ex_CSRControl,

    // Control for WB data selection
    input  wire [ 2:0] ex_MemToReg,

    // Outputs
    output wire [31:0] ex_ALUResult,
    output wire        ex_ALUisTrue,
    
    output wire [31:0] ex_MDUResult,
    output wire        MDUStall,

    output wire [31:0] CSRrdata,
    output wire        ex_CSRjump,
    output wire [31:0] ex_CSRnpc,

    output wire [31:0] ex_RFwdata,
    output wire        ex_MemRead
);

    wire [31:0] ex_A;
    wire [31:0] ex_B;
    wire [31:0] ex_RFwdata_temp;

    assign ex_A = ex_ALUSrcA ? ex_pc : ex_rR1_data;
    assign ex_B = ex_ALUSrcB ? ex_imm : ex_rR2_data;

    ALU u_ALU (
        .A                      (ex_A),
        .B                      (ex_B),
        .ALUControl             (ex_ALUControl),

        .Result                 (ex_ALUResult),
        .isTrue                 (ex_ALUisTrue)
    );

    `ifdef RV32IM
        wire [63:0] P;
        wire [31:0] quotient;
        wire [31:0] remainder;

        reg mdu_busy;
        wire mul_done, div_done;

        // When m_en is valid and not busy, send valid pulse (1 cycle)
        wire start_pulse = ex_m_en && !mdu_busy;

        always @(posedge clk) begin
            if (rst || flush_ID_EX) begin
                mdu_busy <= 1'b0;
            end else if (start_pulse) begin
                mdu_busy <= 1'b1;
            end else if (mul_done || div_done) begin
                mdu_busy <= 1'b0;
            end
        end

        // Stall whenever m_en is valid and result is not ready
        assign MDUStall = ex_m_en && ~(mul_done || div_done);

        mul mul_inst (
            .clk        (clk),
            .rst        (rst || flush_ID_EX),
            .in_valid   (start_pulse & ~ex_MDUControl[2]),
            .mul_type   (ex_MDUControl[1:0]),
            .A          (ex_rR1_data),
            .B          (ex_rR2_data),
            .out_valid  (mul_done),
            .P          (P)
        );

        div div_inst (
            .clk        (clk),
            .rst        (rst || flush_ID_EX),
            .in_valid   (start_pulse & ex_MDUControl[2]),
            .is_unsigned(ex_MDUControl[0]),
            .dividend   (ex_rR1_data),
            .divisor    (ex_rR2_data),
            .out_valid  (div_done),
            .quotient   (quotient),
            .remainder  (remainder)
        );

        wire [31:0] res_mul = (ex_MDUControl[1:0] == 2'b00) ? P[31:0] : P[63:32];
        wire [31:0] res_div = ex_MDUControl[1] ? remainder : quotient;
        
        assign ex_MDUResult = ex_MDUControl[2] ? res_div : res_mul;
    `endif

    `ifdef RV32I
        assign MDUStall = 1'b0;
        assign ex_MDUResult = 32'b0;
    `endif

    CSR u_CSR (
        .clk                    (clk),
        .rst                    (rst),
        .flush                  (flush_EX_ME1),

        .CSRControl             (ex_CSRControl),
        .CSRaddr                (ex_CSRaddr),
        .CSRSrc                 (ex_CSRSrc),
        .rR1_data               (ex_rR1_data),
        .imm                    (ex_imm),

        .pc                     (ex_pc),
        .exception              (exception),
        .interrupt              (interrupt),

        .CSRrdata               (CSRrdata),
        .CSRjump                (ex_CSRjump),
        .CSRnpc                 (ex_CSRnpc)
    );

    assign ex_RFwdata_temp = ex_MemToReg[1] ?
                            (ex_MemToReg[0] ? ex_imm : CSRrdata) :
                            (ex_MemToReg[0] ? ex_ALUResult : ex_pc4);

    `ifdef RV32IM
        assign ex_RFwdata = ex_m_en ? ex_MDUResult : ex_RFwdata_temp;
    `endif

    `ifdef RV32I
        assign ex_RFwdata = ex_RFwdata_temp;
    `endif

    assign ex_MemRead = ex_MemToReg[2];

endmodule
