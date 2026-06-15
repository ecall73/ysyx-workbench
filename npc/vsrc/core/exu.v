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

    // Decode / former IDU logic.
    wire [6:0] dec_opcode;
    wire [2:0] dec_funct3;
    wire       dec_funct7_5;
    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [11:0] csr_addr;
    wire [31:0] dec_imm;
    reg  [31:0] dec_imm_r;

    wire       op_rtype;
    wire       op_itype;
    wire       op_load;
    wire       op_store;
    wire       op_branch;
    wire       op_lui;
    wire       op_auipc;
    wire       op_jal;
    wire       op_jalr;
    wire       op_system;
    wire       op_csr;
    wire       op_misc_mem;
    wire       op_fencei;
    wire [2:0] mem_to_reg;
    wire       rs1_used;
    wire       rs2_used;

    // RF read data selection and EX/LS dependency handling.
    wire        forward_ls_rs1;
    wire        forward_ls_rs2;
    wire        load_use_hazard;
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    // Execute common control.
    wire        ex_fire;

    // ALU.
    reg  [31:0] alu_result_r;
    wire [31:0] alu_logic_rhs;
    wire [31:0] alu_add_lhs;
    wire [31:0] alu_add_rhs;
    wire        alu_sub_family;
    wire [31:0] alu_adder_rhs;
    wire [31:0] alu_addsub_result;
    wire        alu_addsub_carry;
    wire [31:0] alu_and_result;
    wire [31:0] alu_or_result;
    wire [31:0] alu_xor_result;
    wire [31:0] alu_sll_result;
    wire [31:0] alu_srl_result;
    wire [31:0] alu_sra_result;
    wire        alu_cmp_lt;
    wire        alu_cmp_ltu;

    // BRU / redirect.
    wire        bru_cmp_eq;
    wire        bru_cmp_lt;
    wire        bru_cmp_ltu;
    wire        branch_cmp_result;
    wire        branch_taken;
    wire        jump_taken;
    wire [31:0] redirect_base;
    wire [31:0] redirect_target_sum;

    // CSR.
    wire [31:0] csr_rdata;

    assign dec_opcode = fetch_inst[6:0];
    assign dec_funct3 = fetch_inst[14:12];
    assign dec_funct7_5 = fetch_inst[30];
    assign rs1_addr = fetch_inst[19:15];
    assign rs2_addr = fetch_inst[24:20];
    assign csr_addr = fetch_inst[31:20];

    assign op_rtype    = dec_opcode == OP_R_TYPE;
    assign op_itype    = dec_opcode == OP_I_TYPE;
    assign op_load     = dec_opcode == OP_IL_TYPE;
    assign op_store    = dec_opcode == OP_S_TYPE;
    assign op_branch   = dec_opcode == OP_B_TYPE;
    assign op_lui      = dec_opcode == OP_U_TYPE;
    assign op_auipc    = dec_opcode == OP_UA_TYPE;
    assign op_jal      = dec_opcode == OP_J_TYPE;
    assign op_jalr     = dec_opcode == OP_IJ_TYPE;
    assign op_system   = dec_opcode == OP_CSR_TYPE;
    assign op_csr      = op_system && (dec_funct3 != 3'b000);
    assign op_misc_mem = dec_opcode == 7'b000_1111;
    assign op_fencei   = fetch_inst == 32'h0000_100f;

    assign mem_to_reg = ({3{op_rtype}} & MEM_TO_REG_ALU) |
                        ({3{op_itype}} & MEM_TO_REG_ALU) |
                        ({3{op_auipc}} & MEM_TO_REG_ALU) |
                        ({3{op_load}}  & MEM_TO_REG_DRAM) |
                        ({3{op_lui}}   & MEM_TO_REG_IMM) |
                        ({3{op_csr}}   & MEM_TO_REG_CSR);

    assign rs1_used = op_rtype | op_itype | op_load | op_store | op_branch | op_jalr |
                      (op_csr && ~dec_funct3[2]);
    assign rs2_used = op_rtype | op_store | op_branch;

    always @(*) begin
        case (dec_opcode)
            OP_I_TYPE,
            OP_IL_TYPE,
            OP_IJ_TYPE:  dec_imm_r = {{20{fetch_inst[31]}}, fetch_inst[31:20]};
            OP_S_TYPE:   dec_imm_r = {{20{fetch_inst[31]}}, fetch_inst[31:25], fetch_inst[11:7]};
            OP_B_TYPE:   dec_imm_r = {{20{fetch_inst[31]}}, fetch_inst[7], fetch_inst[30:25], fetch_inst[11:8], 1'b0};
            OP_U_TYPE,
            OP_UA_TYPE:  dec_imm_r = {fetch_inst[31:12], 12'b0};
            OP_J_TYPE:   dec_imm_r = {{12{fetch_inst[31]}}, fetch_inst[19:12], fetch_inst[20], fetch_inst[30:21], 1'b0};
            OP_CSR_TYPE: dec_imm_r = {27'b0, fetch_inst[19:15]};
            default:     dec_imm_r = 32'b0;
        endcase
    end

    assign dec_imm = dec_imm_r;

    assign forward_ls_rs1 = (rs1_addr == ls_RFwaddr) && ls_RegWrite && (ls_RFwaddr != 5'b0);
    assign forward_ls_rs2 = (rs2_addr == ls_RFwaddr) && ls_RegWrite && (ls_RFwaddr != 5'b0);

    assign rs1_data = forward_ls_rs1 ? ls_RFwdata : fetch_rR1_data;
    assign rs2_data = forward_ls_rs2 ? ls_RFwdata : fetch_rR2_data;

    assign load_use_hazard = ls_load_pending &&
                             (ls_RFwaddr != 5'b0) &&
                             ((rs1_used && (rs1_addr == ls_RFwaddr)) ||
                              (rs2_used && (rs2_addr == ls_RFwaddr)));

    assign fetch_ready = ~fetch_valid || (~load_use_hazard && ex_out_ready);
    assign ex_out_valid = fetch_valid && ~load_use_hazard;
    assign ex_fire = ex_out_valid && ex_out_ready;

    assign ex_RegWrite = fetch_valid && ~(op_branch | op_store | op_misc_mem);
    assign ex_MemWrite = fetch_valid && op_store;
    assign ex_MemRead = mem_to_reg[2];
    assign ex_funct3 = dec_funct3;
    assign ex_RFwaddr = fetch_inst[11:7];
    assign ex_rR2_data = rs2_data;
    assign ex_have_inst = op_rtype | op_itype | op_load | op_jalr | op_store |
                          op_branch | op_lui | op_auipc | op_jal | op_system | op_misc_mem;

    // ALU.
    assign ex_pc4 = fetch_pc + 32'd4;
    assign alu_logic_rhs = op_rtype ? rs2_data : dec_imm;
    assign alu_add_lhs = (op_auipc | op_jal) ? fetch_pc : rs1_data;
    assign alu_add_rhs = op_rtype ? rs2_data : dec_imm;
    assign alu_sub_family = (op_rtype && dec_funct3 == 3'b000 && dec_funct7_5) ||
                            ((op_rtype || op_itype) && (dec_funct3 == 3'b010 || dec_funct3 == 3'b011));
    assign alu_adder_rhs = alu_sub_family ? ~alu_add_rhs : alu_add_rhs;
    assign {alu_addsub_carry, alu_addsub_result} = {1'b0, alu_add_lhs} + {1'b0, alu_adder_rhs} +
                                                   {32'b0, alu_sub_family};
    assign alu_and_result = rs1_data & alu_logic_rhs;
    assign alu_or_result = rs1_data | alu_logic_rhs;
    assign alu_xor_result = rs1_data ^ alu_logic_rhs;
    assign alu_sll_result = rs1_data << alu_logic_rhs[4:0];
    assign alu_srl_result = rs1_data >> alu_logic_rhs[4:0];
    assign alu_sra_result = ($signed(rs1_data)) >>> alu_logic_rhs[4:0];
    assign alu_cmp_lt = (alu_add_lhs[31] & ~alu_add_rhs[31]) |
                        ((alu_add_lhs[31] ~^ alu_add_rhs[31]) & alu_addsub_result[31]);
    assign alu_cmp_ltu = ~alu_addsub_carry;

    always @(*) begin
        case (dec_opcode)
            OP_R_TYPE: begin
                case (dec_funct3)
                    3'b000:  alu_result_r = alu_addsub_result;
                    3'b001:  alu_result_r = alu_sll_result;
                    3'b010:  alu_result_r = {31'b0, alu_cmp_lt};
                    3'b011:  alu_result_r = {31'b0, alu_cmp_ltu};
                    3'b100:  alu_result_r = alu_xor_result;
                    3'b101:  alu_result_r = dec_funct7_5 ? alu_sra_result : alu_srl_result;
                    3'b110:  alu_result_r = alu_or_result;
                    3'b111:  alu_result_r = alu_and_result;
                    default: alu_result_r = alu_addsub_result;
                endcase
            end

            OP_I_TYPE: begin
                case (dec_funct3)
                    3'b000:  alu_result_r = alu_addsub_result;
                    3'b001:  alu_result_r = alu_sll_result;
                    3'b010:  alu_result_r = {31'b0, alu_cmp_lt};
                    3'b011:  alu_result_r = {31'b0, alu_cmp_ltu};
                    3'b100:  alu_result_r = alu_xor_result;
                    3'b101:  alu_result_r = dec_funct7_5 ? alu_sra_result : alu_srl_result;
                    3'b110:  alu_result_r = alu_or_result;
                    3'b111:  alu_result_r = alu_and_result;
                    default: alu_result_r = alu_addsub_result;
                endcase
            end

            OP_IL_TYPE,
            OP_IJ_TYPE,
            OP_S_TYPE,
            OP_UA_TYPE,
            OP_J_TYPE: begin
                alu_result_r = alu_addsub_result;
            end

            default: begin
                alu_result_r = alu_addsub_result;
            end
        endcase
    end

    assign ex_ALUResult = alu_result_r;

    // BRU / redirect.
    assign bru_cmp_eq = (rs1_data == rs2_data);
    assign bru_cmp_lt = ($signed(rs1_data) < $signed(rs2_data));
    assign bru_cmp_ltu = (rs1_data < rs2_data);
    assign branch_cmp_result = dec_funct3[2] ? (dec_funct3[1] ? bru_cmp_ltu : bru_cmp_lt)
                                             : bru_cmp_eq;
    assign branch_taken = op_branch && (branch_cmp_result ^ dec_funct3[0]);
    assign jump_taken = op_jal || op_jalr;
    assign redirect_base = op_jalr ? rs1_data : fetch_pc;
    assign redirect_target_sum = redirect_base + dec_imm;
    assign ex_Redirect = fetch_valid && (jump_taken || branch_taken);
    assign ex_RedirectTarget = op_jalr ? {redirect_target_sum[31:1], 1'b0}
                                       : redirect_target_sum;
    assign ex_FenceI = fetch_valid && op_fencei;

    // CSR and writeback side data.
    assign ex_WBAltData = mem_to_reg[1] ?
                              (mem_to_reg[0] ? dec_imm : csr_rdata) :
                              ex_pc4;
    assign ex_WBUseAlt = ~mem_to_reg[2] && (mem_to_reg[1] || ~mem_to_reg[0]);

    ysyx_26030082_CSR CSR (
        .clock      (clock),
        .reset      (reset),
        .csr_fire   (ex_fire),
        .is_system  (op_system),
        .CSRaddr    (csr_addr),
        .funct3     (dec_funct3),
        .rR1_data   (rs1_data),
        .imm        (dec_imm),
        .pc         (fetch_pc),
        .CSRrdata   (csr_rdata),
        .CSRjump    (ex_CSRjump),
        .CSRnpc     (ex_CSRnpc)
    );

endmodule
