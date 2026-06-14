module ysyx_26030082_exu (
    input  wire        clock,
    input  wire        reset,

    input  wire        fetch_valid,
    output wire        fetch_ready,
    input  wire [31:0] fetch_pc,
    input  wire [31:0] fetch_inst,
    input  wire [31:0] fetch_rR1_data,
    input  wire [31:0] fetch_rR2_data,

    input  wire        ex_out_ready,
    output wire        ex_out_valid,

    input  wire        ls_RegWrite,
    input  wire [ 4:0] ls_RFwaddr,
    input  wire [31:0] ls_RFwdata,
    input  wire        ls_load_pending,

    output wire        ex_RegWrite,
    output wire        ex_MemRead,
    output wire        ex_MemWrite,
    output wire [31:0] ex_rR2_data,
    output wire [ 2:0] ex_funct3,
    output wire [ 4:0] ex_RFwaddr,
    output wire [31:0] ex_ALUResult,
    output wire [31:0] ex_pc4,
    output wire        ex_Redirect,
    output wire [31:0] ex_RedirectTarget,
    output wire        ex_CSRjump,
    output wire [31:0] ex_CSRnpc,
    output wire [31:0] ex_WBAltData,
    output wire        ex_WBUseAlt,
    output wire        ex_FenceI,
    output wire        ex_have_inst
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

    localparam [3:0] ADD      = 4'b0000;
    localparam [3:0] SUB      = 4'b1000;
    localparam [3:0] SLL      = 4'b0001;
    localparam [3:0] SLT      = 4'b0010;
    localparam [3:0] SLTU     = 4'b0011;
    localparam [3:0] XOR      = 4'b0100;
    localparam [3:0] SRL      = 4'b0101;
    localparam [3:0] SRA      = 4'b1101;
    localparam [3:0] OR       = 4'b0110;
    localparam [3:0] AND      = 4'b0111;
    localparam [3:0] ERR      = 4'b1111;

    wire [6:0] opcode;
    wire [2:0] funct3;
    wire       funct7_5;
    wire [3:0] funct;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [31:0] imm;
    wire       op_misc_mem;
    wire       op_fencei;
    wire       op_branch;
    wire       op_store;
    wire       op_rtype;
    wire       op_itype;
    wire       op_load;
    wire       op_auipc;
    wire       op_lui;
    wire       op_jal;
    wire       op_jalr;
    wire       op_system;
    wire       op_csr;
    wire       op_add;
    wire       op_sub;
    wire       op_and;
    wire       op_or;
    wire       op_xor;
    wire       op_sll;
    wire       op_srl;
    wire       op_sra;
    wire       op_slt;
    wire       op_sltu;
    wire [3:0] ALUControl;
    wire [2:0] MemToReg;
    wire       ALUSrcA;
    wire       ALUSrcB;
    wire       rs1_used;
    wire       rs2_used;
    wire       is_system;
    wire [11:0] CSRaddr;

    wire        forward_ls_A;
    wire        forward_ls_B;
    wire        load_use_hazard;
    wire [31:0] rR1_data_forward;
    wire [31:0] rR2_data_forward;

    wire [31:0] CSRrdata;
    wire        BRUResult;
    wire [31:0] redirect_base;
    wire [31:0] redirect_target_sum;
    wire        ex_fire;
    reg  [31:0] imm_r;

    assign opcode = fetch_inst[6:0];
    assign funct3 = fetch_inst[14:12];
    assign funct7_5 = fetch_inst[30];
    assign funct = {funct7_5, funct3};
    assign rs1 = fetch_inst[19:15];
    assign rs2 = fetch_inst[24:20];

    assign op_branch    = opcode == OP_B_TYPE;
    assign op_store     = opcode == OP_S_TYPE;
    assign op_rtype     = opcode == OP_R_TYPE;
    assign op_itype     = opcode == OP_I_TYPE;
    assign op_load      = opcode == OP_IL_TYPE;
    assign op_auipc     = opcode == OP_UA_TYPE;
    assign op_lui       = opcode == OP_U_TYPE;
    assign op_jal       = opcode == OP_J_TYPE;
    assign op_jalr      = opcode == OP_IJ_TYPE;
    assign op_misc_mem  = opcode == 7'b000_1111;
    assign op_fencei    = fetch_inst == 32'h0000_100f;
    assign op_system    = opcode == OP_CSR_TYPE;
    assign op_csr       = op_system && (funct3 != 3'b000);

    assign op_add = (op_rtype && funct == 4'b0000) ||
                    (op_itype && funct3 == 3'b000) ||
                    op_load ||
                    op_store ||
                    op_branch ||
                    op_jal ||
                    op_auipc ||
                    (op_jalr && funct3 == 3'b000);
    assign op_sub = op_rtype && funct == 4'b1000;
    assign op_and = (op_rtype && funct == 4'b0111) || (op_itype && funct3 == 3'b111);
    assign op_or = (op_rtype && funct == 4'b0110) || (op_itype && funct3 == 3'b110);
    assign op_xor = (op_rtype && funct == 4'b0100) || (op_itype && funct3 == 3'b100);
    assign op_sll = (op_rtype || op_itype) && (funct == 4'b0001);
    assign op_srl = (op_rtype || op_itype) && (funct == 4'b0101);
    assign op_sra = (op_rtype || op_itype) && (funct == 4'b1101);
    assign op_sltu = (op_rtype && funct == 4'b0011) || (op_itype && funct3 == 3'b011);
    assign op_slt = (op_rtype && funct == 4'b0010) || (op_itype && funct3 == 3'b010);

    assign ALUControl = op_add  ? ADD  :
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

    assign ex_RegWrite = fetch_valid && ~(op_branch | op_store | op_misc_mem);
    assign MemToReg = ({3{op_rtype}} & MEM_TO_REG_ALU) |
                      ({3{op_itype}} & MEM_TO_REG_ALU) |
                      ({3{op_auipc}} & MEM_TO_REG_ALU) |
                      ({3{op_load}} & MEM_TO_REG_DRAM) |
                      ({3{op_lui}} & MEM_TO_REG_IMM) |
                      ({3{op_csr}} & MEM_TO_REG_CSR);
    assign ex_MemWrite = fetch_valid && op_store;
    assign ex_MemRead = MemToReg[2];
    assign ALUSrcA = op_auipc | op_branch | op_jal;
    assign ALUSrcB = ~(op_rtype | op_misc_mem);
    assign rs1_used = op_rtype | op_itype | op_load | op_store | op_branch | op_jalr |
                      (op_csr && ~funct3[2]);
    assign rs2_used = op_rtype | op_store | op_branch;
    assign is_system = op_system;
    assign CSRaddr = fetch_inst[31:20];

    assign forward_ls_A = (rs1 == ls_RFwaddr) && ls_RegWrite && (ls_RFwaddr != 5'b0);
    assign forward_ls_B = (rs2 == ls_RFwaddr) && ls_RegWrite && (ls_RFwaddr != 5'b0);

    assign rR1_data_forward = forward_ls_A ? ls_RFwdata : fetch_rR1_data;
    assign rR2_data_forward = forward_ls_B ? ls_RFwdata : fetch_rR2_data;

    assign load_use_hazard = ls_load_pending &&
                             (ls_RFwaddr != 5'b0) &&
                             ((rs1_used && (rs1 == ls_RFwaddr)) ||
                              (rs2_used && (rs2 == ls_RFwaddr)));

    assign fetch_ready = ~fetch_valid || (~load_use_hazard && ex_out_ready);
    assign ex_out_valid = fetch_valid && ~load_use_hazard;
    assign ex_fire = ex_out_valid && ex_out_ready;

    assign ex_funct3 = funct3;
    assign ex_RFwaddr = fetch_inst[11:7];
    assign ex_rR2_data = rR2_data_forward;

    assign ex_pc4 = fetch_pc + 32'd4;

    assign redirect_base = op_jalr ? rR1_data_forward : fetch_pc;
    assign redirect_target_sum = redirect_base + imm;
    assign ex_Redirect = fetch_valid && (op_jal || op_jalr || (op_branch && BRUResult));
    assign ex_RedirectTarget = op_jalr ? {redirect_target_sum[31:1], 1'b0}
                                       : redirect_target_sum;
    assign ex_FenceI = fetch_valid && op_fencei;

    assign ex_WBAltData = MemToReg[1] ?
                              (MemToReg[0] ? imm : CSRrdata) :
                              ex_pc4;
    assign ex_WBUseAlt = ~MemToReg[2] && (MemToReg[1] || ~MemToReg[0]);

    assign ex_have_inst = op_rtype | op_itype | op_load | op_jalr | op_store |
                          op_branch | op_lui | op_auipc | op_jal | op_system | op_misc_mem;

    always @(*) begin
        case (opcode)
            OP_I_TYPE,
            OP_IL_TYPE,
            OP_IJ_TYPE:   imm_r = {{20{fetch_inst[31]}}, fetch_inst[31:20]};
            OP_S_TYPE:    imm_r = {{20{fetch_inst[31]}}, fetch_inst[31:25], fetch_inst[11:7]};
            OP_B_TYPE:    imm_r = {{20{fetch_inst[31]}}, fetch_inst[7], fetch_inst[30:25], fetch_inst[11:8], 1'b0};
            OP_U_TYPE,
            OP_UA_TYPE:   imm_r = {fetch_inst[31:12], 12'b0};
            OP_J_TYPE:    imm_r = {{12{fetch_inst[31]}}, fetch_inst[19:12], fetch_inst[20], fetch_inst[30:21], 1'b0};
            OP_CSR_TYPE:  imm_r = {27'b0, fetch_inst[19:15]};
            default:      imm_r = 32'b0;
        endcase
    end

    assign imm = imm_r;

    ysyx_26030082_ALU ALU (
        .ALUSrcA    (ALUSrcA),
        .ALUSrcB    (ALUSrcB),
        .rR1_data   (rR1_data_forward),
        .rR2_data   (rR2_data_forward),
        .pc         (fetch_pc),
        .imm        (imm),
        .ALUControl (ALUControl),
        .BRUFunct3  (funct3),
        .Result     (ex_ALUResult),
        .BRUResult  (BRUResult)
    );

    ysyx_26030082_CSR CSR (
        .clock      (clock),
        .reset      (reset),
        .csr_fire   (ex_fire),
        .is_system  (is_system),
        .CSRaddr    (CSRaddr),
        .funct3     (funct3),
        .rR1_data   (rR1_data_forward),
        .imm        (imm),
        .pc         (fetch_pc),
        .CSRrdata   (CSRrdata),
        .CSRjump    (ex_CSRjump),
        .CSRnpc     (ex_CSRnpc)
    );

endmodule
