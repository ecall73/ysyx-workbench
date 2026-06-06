`timescale 1ns / 1ps

module idu (
    input  wire        clock,
    input  wire        reset,
    input  wire        id_valid,
    output wire        id_ready,
    output wire        id_issue_valid,
    input  wire        id_issue_ready,
    input  wire        id_block,

    // From IF_ID
    input  wire [31:0] id_inst,

    // To ID_EX / Forwarding
    output wire [ 3:0] id_ALUControl,
    output wire        id_RegWrite,
    output wire [ 2:0] id_MemToReg,
    output wire        id_MemWrite,
    output wire        id_ALUSrcA,
    output wire        id_ALUSrcB,
    output reg  [31:0] id_imm,
    output wire [31:0] id_rR1_data,
    output wire [31:0] id_rR2_data,

    // Branch/jump type decode
    output wire        id_btype,
    output wire        id_jtype,
    output wire        id_ijtype,

    // CSR
    output wire        id_CSRSrc,
    output wire [11:0] id_CSRaddr,
    output wire [ 4:0] id_CSRControl,
    output wire        id_FenceI

    `ifndef SYNTHESIS
    , output wire      have_inst_ID
    `endif
);

    localparam [6:0] OP_R_TYPE   = 7'b011_0011;
    localparam [6:0] OP_I_TYPE   = 7'b001_0011;
    localparam [6:0] OP_IL_TYPE  = 7'b000_0011;
    localparam [6:0] OP_IJ_TYPE  = 7'b110_0111;
    localparam [6:0] OP_S_TYPE   = 7'b010_0011;
    localparam [6:0] OP_B_TYPE   = 7'b110_0011;
    localparam [6:0] OP_U_TYPE   = 7'b011_0111;
    localparam [6:0] OP_UA_TYPE  = 7'b001_0111;
    localparam [6:0] OP_J_TYPE   = 7'b110_1111;
    localparam [6:0] OP_CSR_TYPE = 7'b111_0011;

    localparam [2:0] MEM_TO_REG_ALU  = 3'b001;
    localparam [2:0] MEM_TO_REG_DRAM = 3'b100;
    localparam [2:0] MEM_TO_REG_IMM  = 3'b011;
    localparam [2:0] MEM_TO_REG_CSR  = 3'b010;
    wire id_can_go;

    assign id_can_go = ~id_block;
    assign id_ready = ~id_valid || (id_can_go && id_issue_ready);
    assign id_issue_valid = id_valid && id_can_go;

    // Compact ALU control encoding
    localparam [3:0] ADD      = 4'd0;
    localparam [3:0] SUB      = 4'd1;
    localparam [3:0] AND      = 4'd2;
    localparam [3:0] OR       = 4'd3;
    localparam [3:0] XOR      = 4'd4;
    localparam [3:0] SLL      = 4'd5;
    localparam [3:0] SRL      = 4'd6;
    localparam [3:0] SRA      = 4'd7;
    localparam [3:0] SLT      = 4'd8;
    localparam [3:0] SLTU     = 4'd9;
    localparam [3:0] ERR      = 4'd15;

    wire [6:0] opcode = id_inst[6:0];
    wire [3:0] funct = {id_inst[30],id_inst[14:12]};
    wire       op_misc_mem;
    wire       op_fencei;

    wire op_add, op_sub, op_and, op_or, op_xor, op_sll, op_srl;
    wire op_sra, op_slt, op_sltu;

    assign id_ALUControl = op_add  ? ADD  :
                           op_sub  ? SUB  :
                           op_and  ? AND  :
                           op_or   ? OR   :
                           op_xor  ? XOR  :
                           op_sll  ? SLL  :
                           op_srl  ? SRL  :
                           op_sra  ? SRA  :
                           op_slt  ? SLT  :
                           op_sltu ? SLTU :
                                     ERR;

    wire rtype, itype, load, store, jal, jalr, auipc, branch;

    assign rtype = opcode == OP_R_TYPE;
    assign itype = opcode == OP_I_TYPE;
    assign load = opcode == OP_IL_TYPE;
    assign store = opcode == OP_S_TYPE;
    assign jal = opcode == OP_J_TYPE;
    assign jalr = opcode == OP_IJ_TYPE;
    assign auipc = opcode == OP_UA_TYPE;
    assign branch = opcode == OP_B_TYPE;

    assign id_btype = branch;
    assign id_jtype = jal;
    assign id_ijtype = jalr;

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
                    branch ||
                    jal ||
                    auipc || (jalr && funct[2:0] == 3'b000);
    assign op_sub = (rtype && funct == 4'b1000);
    assign op_and = (rtype && funct == 4'b0111) || (itype && funct[2:0] == 3'b111);
    assign op_or = (rtype && funct == 4'b0110) || (itype && funct[2:0] == 3'b110);
    assign op_xor = (rtype && funct == 4'b0100) || (itype && funct[2:0] == 3'b100);
    assign op_sll = (rtype || itype) && funct == 4'b0001;
    assign op_srl = (rtype || itype) && funct == 4'b0101;
    assign op_sra = (rtype || itype) && funct == 4'b1101;
    assign op_sltu = (rtype && funct == 4'b0011) || (itype && funct[2:0] == 3'b011);
    assign op_slt = (rtype && funct == 4'b0010) || (itype && funct[2:0] == 3'b010);

    // Expanded Control module logic
    wire [2:0] funct3 = id_inst[14:12];
    wire op_branch, op_store, op_rtype, op_itype, op_load, op_auipc, op_lui, op_csr;

    assign op_branch    = opcode == OP_B_TYPE;
    assign op_store     = opcode == OP_S_TYPE;
    assign op_rtype     = opcode == OP_R_TYPE;
    assign op_itype     = opcode == OP_I_TYPE;
    assign op_load      = opcode == OP_IL_TYPE;
    assign op_auipc     = opcode == OP_UA_TYPE;
    assign op_lui       = opcode == OP_U_TYPE;
    assign op_csr       = (opcode == OP_CSR_TYPE) && (funct3 != 3'b0);
    assign op_misc_mem  = opcode == 7'b000_1111;
    assign op_fencei    = id_inst == 32'h0000_100f;

    assign id_RegWrite = ~(op_branch | op_store | op_misc_mem);

    assign id_MemToReg = {3{op_rtype}} & MEM_TO_REG_ALU |
                    {3{op_itype}} & MEM_TO_REG_ALU |
                    {3{op_auipc}} & MEM_TO_REG_ALU |
                    {3{op_load}} & MEM_TO_REG_DRAM |
                    {3{op_lui}} & MEM_TO_REG_IMM |
                    {3{op_csr}} & MEM_TO_REG_CSR;

    assign id_MemWrite = op_store;

    assign id_ALUSrcA = op_auipc | op_branch | jal;
    assign id_ALUSrcB = ~(op_rtype | op_misc_mem);
    assign id_FenceI = op_fencei;

    `ifndef SYNTHESIS
        wire op_jal, op_jalr, op_sys;
        assign op_jal = opcode == OP_J_TYPE;
        assign op_jalr = opcode == OP_IJ_TYPE;
        // Keep retire trace aligned with NEMU: treat SYSTEM opcode (CSR/ecall/ebreak/mret) as real instructions.
        assign op_sys = opcode == OP_CSR_TYPE;
        // Include MISC-MEM (fence/fence.i) so commit trace won't skip retired instructions.
        assign have_inst_ID = op_rtype | op_itype | op_load | op_jalr | op_store | op_branch | op_lui | op_auipc | op_jal | op_sys | op_misc_mem;
    `endif

    // Expanded IMMGEN module logic
    always @(*) begin
        case(opcode)
            OP_I_TYPE,
            OP_IL_TYPE,
            OP_IJ_TYPE:   id_imm = {{20{id_inst[31]}}, id_inst[31:20]};
            OP_S_TYPE:    id_imm = {{20{id_inst[31]}}, id_inst[31:25], id_inst[11:7]};
            OP_B_TYPE:    id_imm = {{20{id_inst[31]}}, id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
            OP_U_TYPE,
            OP_UA_TYPE:   id_imm = {id_inst[31:12], 12'b0};
            OP_J_TYPE:    id_imm = {{12{id_inst[31]}}, id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};
            OP_CSR_TYPE:  id_imm = {27'b0, id_inst[19:15]};
            default:    id_imm = 32'b0;
        endcase
    end

    // Expanded CCTL module logic
    assign id_CSRSrc = id_inst[14];
    assign id_CSRaddr = id_inst[31:20];
    assign id_CSRControl[0] = (id_inst[6:0] == OP_CSR_TYPE) && (id_inst[13:12] == 2'b01); // csrrw, csrrwi
    assign id_CSRControl[1] = (id_inst[6:0] == OP_CSR_TYPE) && (id_inst[13:12] == 2'b10); // csrrs, csrrsi
    assign id_CSRControl[2] = (id_inst[6:0] == OP_CSR_TYPE) && (id_inst[13:12] == 2'b11); // csrrc, csrrci
    assign id_CSRControl[3] = id_inst == 32'h00000073; // ecall
    assign id_CSRControl[4] = id_inst == 32'h30200073; // mret

endmodule
