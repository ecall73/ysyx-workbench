`timescale 1ns / 1ps
`include "defines.v"

module idu (
    input  wire        clk,
    input  wire        rst,

    // From IF_ID
    input  wire [31:0] id_inst,

    // From WB stage (for RF write)
    input  wire        wb_RegWrite,
    input  wire [ 4:0] wb_RFwaddr,
    input  wire [31:0] wb_RFwdata,

    // To ID_EX / Hazard / Forwarding
    output wire [13:0] id_ALUControl,
    output wire        id_RegWrite,
    output wire [ 2:0] id_MemToReg,
    output wire        id_MemWrite,
    output wire        id_ALUSrcA,
    output wire        id_ALUSrcB,
    output reg  [31:0] id_imm,
    output wire [31:0] id_rR1_data,
    output wire [31:0] id_rR2_data,

    // RV32M
    output wire        id_m_en,
    output wire [ 2:0] id_MDUControl,

    // CSR
    output wire        id_CSRSrc,
    output wire [11:0] id_CSRaddr,
    output wire [ 4:0] id_CSRControl

    `ifdef RUN_TRACE
    , output wire      have_inst_ID
    , output wire [31:0] id_reg_file [0:31]
    `endif
);

    // Expanded ACTL module logic
    localparam ADD      = 14'h0001;
    localparam SUB      = 14'h0002;
    localparam AND      = 14'h0004;
    localparam OR       = 14'h0008;
    localparam XOR      = 14'h0010;
    localparam SLL      = 14'h0020;
    localparam SRL      = 14'h0040;
    localparam SRA      = 14'h0080;
    localparam BEQ      = 14'h0100;
    localparam BNE      = 14'h0200;
    localparam BLT      = 14'h0400;
    localparam BGE      = 14'h0800;
    localparam BGEU     = 14'h1000;
    localparam BLTU     = 14'h2000;

    localparam ERR      = 14'h0;

    wire [6:0] opcode = id_inst[6:0];
    wire [3:0] funct = {id_inst[30],id_inst[14:12]};

    wire op_add, op_sub, op_and, op_or, op_xor, op_sll, op_srl;
    wire op_sra, op_beq, op_bne, op_blt, op_bge, op_bgeu, op_bltu;

    assign id_ALUControl = {14{op_add}} & ADD |
                        {14{op_sub}} & SUB |
                        {14{op_and}} & AND |
                        {14{op_or}} & OR |
                        {14{op_xor}} & XOR |
                        {14{op_sll}} & SLL |
                        {14{op_srl}} & SRL |
                        {14{op_sra}} & SRA |
                        {14{op_beq}} & BEQ |
                        {14{op_bne}} & BNE |
                        {14{op_blt}} & BLT |
                        {14{op_bge}} & BGE |
                        {14{op_bgeu}} & BGEU |
                        {14{op_bltu}} & BLTU;

    wire rtype, itype, load, store, jalr, auipc, branch;

    assign rtype = opcode == `R_TYPE;
    assign itype = opcode == `I_TYPE;
    assign load = opcode == `IL_TYPE;
    assign store = opcode == `S_TYPE;
    assign jalr = opcode == `IJ_TYPE;
    assign auipc = opcode == `UA_TYPE;
    assign branch = opcode == `B_TYPE;

    assign op_add = (rtype && funct == 4'b0000) ||
                    (itype && funct[2:0] == 3'b000) ||
                    (load && funct[2:0] == 3'b000) ||
                    (load && funct[2:0] == 3'b001) ||
                    (load && funct[2:0] == 3'b010) ||
                    (load && funct[2:0] == 3'b100) ||
                    (load && funct[2:0] == 3'b101) ||
                    (store && funct[2:0] == 3'b000) ||
                    (store && funct[2:0] == 3'b001) ||
                    (store && funct[2:0] == 3'b010) ||
                    auipc || (jalr && funct[2:0] == 3'b000);
    assign op_sub = (rtype && funct == 4'b1000);
    assign op_and = (rtype && funct == 4'b0111) || (itype && funct[2:0] == 3'b111);
    assign op_or = (rtype && funct == 4'b0110) || (itype && funct[2:0] == 3'b110);
    assign op_xor = (rtype && funct == 4'b0100) || (itype && funct[2:0] == 3'b100);
    assign op_sll = (rtype || itype) && funct == 4'b0001;
    assign op_srl = (rtype || itype) && funct == 4'b0101;
    assign op_sra = (rtype || itype) && funct == 4'b1101;
    assign op_bltu = (rtype && funct == 4'b0011) || (branch && funct[2:0] == 3'b110) || (itype && funct[2:0] == 3'b011);
    assign op_blt = (rtype && funct == 4'b0010) || (branch && funct[2:0] == 3'b100) || (itype && funct[2:0] == 3'b010);
    assign op_beq = branch && funct[2:0] == 3'b000;
    assign op_bne = branch && funct[2:0] == 3'b001;
    assign op_bge = branch && funct[2:0] == 3'b101;
    assign op_bgeu = branch && funct[2:0] == 3'b111;

    // Expanded Control module logic
    wire [2:0] funct3 = id_inst[14:12];
    // wire [2:0] NpcOp; // Not used outside?

    wire op_branch, op_store, op_rtype, op_itype, op_load, op_auipc, op_lui, op_csr;

    assign op_branch    = opcode == `B_TYPE;
    assign op_store     = opcode == `S_TYPE;
    assign op_rtype     = opcode == `R_TYPE;
    assign op_itype     = opcode == `I_TYPE;
    assign op_load      = opcode == `IL_TYPE;
    assign op_auipc     = opcode == `UA_TYPE;
    assign op_lui       = opcode == `U_TYPE;
    assign op_csr       = (opcode == `CSR_TYPE) && (funct3 != 3'b0);

    assign id_RegWrite = ~(op_branch | op_store);

    assign id_MemToReg = {3{op_rtype}} & `MemToReg_ALU |
                    {3{op_itype}} & `MemToReg_ALU | 
                    {3{op_auipc}} & `MemToReg_ALU | 
                    {3{op_load}} & `MemToReg_DRAM |
                    {3{op_lui}} & `MemToReg_IMM |
                    {3{op_csr}} & `MemToReg_CSR;

    assign id_MemWrite = op_store;

    assign id_ALUSrcA = op_auipc;
    assign id_ALUSrcB = ~(op_rtype | op_branch);

    /*
    always @(*) begin
        case(opcode)
            `B_TYPE: NpcOp = `NpcOp_BRANCH;
            `J_TYPE: NpcOp = `NpcOp_JAL;
            `IJ_TYPE: NpcOp = `NpcOp_JALR;
            `CSR_TYPE: NpcOp = funct3 ? `NpcOp_NEXT : `NpcOp_CSR;
            default: NpcOp = `NpcOp_NEXT;
        endcase
    end
    */

    `ifdef RUN_TRACE
        wire op_jal, op_jalr;
        assign op_jal = opcode == `J_TYPE;
        assign op_jalr = opcode == `IJ_TYPE;
        assign have_inst_ID = op_rtype | op_itype | op_load | op_jalr | op_store | op_branch | op_lui | op_auipc | op_jal;
    `endif

    RF u_RF (
        .clk                    (clk),
        .rst                    (rst),

        .wen                    (wb_RegWrite),
        .waddr                  (wb_RFwaddr),
        .wdata                  (wb_RFwdata),

        .rR1                    (id_inst[19:15]),
        .rR2                    (id_inst[24:20]),

        .rR1_data               (id_rR1_data),
        .rR2_data               (id_rR2_data)

        `ifdef RUN_TRACE
        ,.reg_file              (id_reg_file)
        `endif
    );

    // Expanded IMMGEN module logic
    always @(*) begin
        case(opcode)
            `I_TYPE,
            `IL_TYPE,
            `IJ_TYPE:   id_imm = {{20{id_inst[31]}}, id_inst[31:20]};
            `S_TYPE:    id_imm = {{20{id_inst[31]}}, id_inst[31:25], id_inst[11:7]};
            `B_TYPE:    id_imm = {{20{id_inst[31]}}, id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
            `U_TYPE,
            `UA_TYPE:   id_imm = {id_inst[31:12], 12'b0};
            `J_TYPE:    id_imm = {{12{id_inst[31]}}, id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};
            `CSR_TYPE:  id_imm = {27'b0, id_inst[19:15]};
            default:    id_imm = 32'b0;
        endcase
    end

    // Expanded MCTL module logic
    `ifdef RV32IM
        wire rtype_m;
        assign rtype_m = opcode == `R_TYPE;
        assign id_m_en = rtype_m & id_inst[25];
        assign id_MDUControl = funct3;
    `endif

    `ifdef RV32I
        assign id_m_en = 1'b0;
        assign id_MDUControl = 3'b0;
    `endif

    // Expanded CCTL module logic
    assign id_CSRSrc = id_inst[14];
    assign id_CSRaddr = id_inst[31:20];
    assign id_CSRControl[0] = (id_inst[6:0] == `CSR_TYPE) && (id_inst[13:12] == 2'b01); // csrrw, csrrwi
    assign id_CSRControl[1] = (id_inst[6:0] == `CSR_TYPE) && (id_inst[13:12] == 2'b10); // csrrs, csrrsi
    assign id_CSRControl[2] = (id_inst[6:0] == `CSR_TYPE) && (id_inst[13:12] == 2'b11); // csrrc, csrrci
    assign id_CSRControl[3] = id_inst == 32'h00000073; // ecall
    assign id_CSRControl[4] = id_inst == 32'h30200073; // mret

endmodule
