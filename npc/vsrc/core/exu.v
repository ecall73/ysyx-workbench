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

    wire [6:0] opcode;
    wire [2:0] funct3;
    wire       funct7_5;
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
    wire [2:0] MemToReg;
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
    wire        bru_cmp_eq;
    wire        bru_cmp_lt;
    wire        bru_cmp_ltu;
    wire        branch_cmp_base;
    wire        branch_taken;
    wire        jump_taken;
    wire [31:0] redirect_base;
    wire [31:0] redirect_target_sum;
    wire        ex_fire;
    reg  [31:0] imm_r;
    reg  [31:0] alu_result_r;

    wire [31:0] add_lhs;
    wire [31:0] add_rhs;
    wire        alu_sub_family;
    wire [31:0] adder_b;
    wire [31:0] add_sub_result;
    wire        add_sub_carry;
    wire [31:0] and_result;
    wire [31:0] or_result;
    wire [31:0] xor_result;
    wire [31:0] sll_result;
    wire [31:0] srl_result;
    wire [31:0] sra_result;
    wire        cmp_lt;
    wire        cmp_ltu;

    assign opcode = fetch_inst[6:0];
    assign funct3 = fetch_inst[14:12];
    assign funct7_5 = fetch_inst[30];
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

    assign ex_RegWrite = fetch_valid && ~(op_branch | op_store | op_misc_mem);
    assign MemToReg = ({3{op_rtype}} & MEM_TO_REG_ALU) |
                      ({3{op_itype}} & MEM_TO_REG_ALU) |
                      ({3{op_auipc}} & MEM_TO_REG_ALU) |
                      ({3{op_load}} & MEM_TO_REG_DRAM) |
                      ({3{op_lui}} & MEM_TO_REG_IMM) |
                      ({3{op_csr}} & MEM_TO_REG_CSR);
    assign ex_MemWrite = fetch_valid && op_store;
    assign ex_MemRead = MemToReg[2];
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

    assign add_lhs = (op_auipc | op_jal) ? fetch_pc : rR1_data_forward;
    assign add_rhs = op_rtype ? rR2_data_forward : imm;
    assign alu_sub_family = (op_rtype && funct3 == 3'b000 && funct7_5) ||
                            ((op_rtype || op_itype) && (funct3 == 3'b010 || funct3 == 3'b011));
    assign adder_b = alu_sub_family ? ~add_rhs : add_rhs;
    assign {add_sub_carry, add_sub_result} = {1'b0, add_lhs} + {1'b0, adder_b} +
                                             {32'b0, alu_sub_family};
    assign and_result = rR1_data_forward & add_rhs;
    assign or_result = rR1_data_forward | add_rhs;
    assign xor_result = rR1_data_forward ^ add_rhs;
    assign sll_result = rR1_data_forward << add_rhs[4:0];
    assign srl_result = rR1_data_forward >> add_rhs[4:0];
    assign sra_result = ($signed(rR1_data_forward)) >>> add_rhs[4:0];
    assign cmp_lt = (add_lhs[31] & ~add_rhs[31]) |
                    ((add_lhs[31] ~^ add_rhs[31]) & add_sub_result[31]);
    assign cmp_ltu = ~add_sub_carry;

    always @(*) begin
        case (opcode)
            OP_R_TYPE: begin
                case (funct3)
                    3'b000:  alu_result_r = add_sub_result;
                    3'b001:  alu_result_r = sll_result;
                    3'b010:  alu_result_r = {31'b0, cmp_lt};
                    3'b011:  alu_result_r = {31'b0, cmp_ltu};
                    3'b100:  alu_result_r = xor_result;
                    3'b101:  alu_result_r = funct7_5 ? sra_result : srl_result;
                    3'b110:  alu_result_r = or_result;
                    3'b111:  alu_result_r = and_result;
                    default: alu_result_r = 32'b0;
                endcase
            end

            OP_I_TYPE: begin
                case (funct3)
                    3'b000:  alu_result_r = add_sub_result;
                    3'b001:  alu_result_r = sll_result;
                    3'b010:  alu_result_r = {31'b0, cmp_lt};
                    3'b011:  alu_result_r = {31'b0, cmp_ltu};
                    3'b100:  alu_result_r = xor_result;
                    3'b101:  alu_result_r = funct7_5 ? sra_result : srl_result;
                    3'b110:  alu_result_r = or_result;
                    3'b111:  alu_result_r = and_result;
                    default: alu_result_r = 32'b0;
                endcase
            end

            OP_IL_TYPE,
            OP_IJ_TYPE,
            OP_S_TYPE,
            OP_UA_TYPE,
            OP_J_TYPE: begin
                alu_result_r = add_sub_result;
            end

            default: begin
                alu_result_r = 32'b0;
            end
        endcase
    end

    assign ex_ALUResult = alu_result_r;

    assign bru_cmp_eq = (rR1_data_forward == rR2_data_forward);
    assign bru_cmp_lt = ($signed(rR1_data_forward) < $signed(rR2_data_forward));
    assign bru_cmp_ltu = (rR1_data_forward < rR2_data_forward);
    assign branch_cmp_base = funct3[2] ? (funct3[1] ? bru_cmp_ltu : bru_cmp_lt)
                                       : bru_cmp_eq;
    assign branch_taken = op_branch && (branch_cmp_base ^ funct3[0]);
    assign jump_taken = op_jal || op_jalr;
    assign redirect_base = op_jalr ? rR1_data_forward : fetch_pc;
    assign redirect_target_sum = redirect_base + imm;
    assign ex_Redirect = fetch_valid && (jump_taken || branch_taken);
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
