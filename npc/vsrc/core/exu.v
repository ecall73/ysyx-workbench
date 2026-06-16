module ysyx_26030082_exu (
    input  wire        clock,
    input  wire        reset,

    input  wire        fetch_valid,
    output wire        fetch_ready,
    input  wire [31:0] fetch_pc,
    input  wire [31:0] fetch_inst,

    input  wire        ex_out_ready,
    output wire        ex_out_valid,

    input  wire        rf_wen,
    input  wire [ 4:0] rf_waddr,
    input  wire [31:0] rf_wdata,
    input  wire        ls_load_pending,

    output wire        ex_rf_wen,
    output wire        ex_mem_ren,
    output wire        ex_mem_wen,
    output wire [ 2:0] ex_funct3,
    output wire [ 4:0] ex_rf_waddr,
    output reg  [31:0] ex_mem_addr,
    output reg         ex_redirect,
    output reg  [31:0] ex_wdata,
    output reg         ex_fence_i
);

    localparam [6:0] OPCODE_OP   = 7'b011_0011;
    localparam [6:0] OPCODE_OP_IMM   = 7'b001_0011;
    localparam [6:0] OPCODE_LOAD  = 7'b000_0011;
    localparam [6:0] OPCODE_JALR  = 7'b110_0111;
    localparam [6:0] OPCODE_STORE   = 7'b010_0011;
    localparam [6:0] OPCODE_BRANCH   = 7'b110_0011;
    localparam [6:0] OPCODE_LUI   = 7'b011_0111;
    localparam [6:0] OPCODE_AUIPC  = 7'b001_0111;
    localparam [6:0] OPCODE_JAL   = 7'b110_1111;
    localparam [6:0] OPCODE_SYSTEM = 7'b111_0011;
    localparam [6:0] OPCODE_MISC_MEM = 7'b000_1111;

    localparam [11:0] CSR_MSTATUS   = 12'h300;
    localparam [11:0] CSR_MTVEC     = 12'h305;
    localparam [11:0] CSR_MEPC      = 12'h341;
    localparam [11:0] CSR_MCAUSE    = 12'h342;
    localparam [11:0] CSR_MVENDORID = 12'hF11;
    localparam [11:0] CSR_MARCHID   = 12'hF12;

    localparam [11:0] F12_ECALL = 12'h000;
    localparam [11:0] F12_MRET  = 12'h302;

    localparam [2:0] F3_PRIV = 3'b000;
    localparam [2:0] F3_CSRRW  = 3'b001;
    localparam [2:0] F3_CSRRS  = 3'b010;
    localparam [2:0] F3_CSRRC  = 3'b011;
    localparam [2:0] F3_CSRRWI = 3'b101;
    localparam [2:0] F3_CSRRSI = 3'b110;
    localparam [2:0] F3_CSRRCI = 3'b111;

    localparam [2:0] F3_BEQ  = 3'b000;
    localparam [2:0] F3_BNE  = 3'b001;
    localparam [2:0] F3_BLT  = 3'b100;
    localparam [2:0] F3_BGE  = 3'b101;
    localparam [2:0] F3_BLTU = 3'b110;
    localparam [2:0] F3_BGEU = 3'b111;

    localparam [31:0] CAUSE_ECALL = 32'd11;

    // Common decode fields.
    wire [6:0] opcode;
    wire       funct7_5;
    wire [4:0] rf_raddr1;
    wire [4:0] rf_raddr2;
    wire [11:0] csr_addr;
    wire       op_rtype;
    wire       op_itype;
    wire       op_load;
    wire       op_store;
    wire       op_branch;
    wire       op_auipc;
    wire       op_jal;
    wire       op_jalr;
    wire       op_system;
    wire       op_misc_mem;

    // RF + forward.
    reg  [31:0] reg_bank [1:15];
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;
    wire        load_use_hazard;
    wire [31:0] rf_rdata1_forward;
    wire [31:0] rf_rdata2_forward;

    // Immediate.
    reg  [31:0] imm;

    // Execute datapath.
    wire [31:0] ex_pc4;
    wire [31:0] add_lhs;
    wire [31:0] add_rhs;
    wire        add_sub;
    wire [31:0] add_rhs_xor;
    wire [31:0] add_result;
    wire        add_carry;
    wire [31:0] logic_lhs;
    wire [31:0] logic_rhs;
    wire [31:0] and_result;
    wire [31:0] or_result;
    wire [31:0] xor_result;
    wire [31:0] sll_result;
    wire [31:0] srl_result;
    wire [31:0] sra_result;
    wire        cmp_lt;
    wire        cmp_ltu;
    wire        branch_cmp_eq;
    wire        branch_cmp_lt;
    wire        branch_cmp_ltu;

    // CSR.
    reg  [31:0] csr_mstatus;
    reg  [31:0] csr_mtvec;
    reg  [31:0] csr_mepc;
    reg  [31:0] csr_mcause;
    reg  [31:0] csr_rdata;
    wire [31:0] csr_src_data;
    reg  [31:0] csr_write_data;

    assign opcode = fetch_inst[6:0];
    assign ex_funct3 = fetch_inst[14:12];
    assign funct7_5 = fetch_inst[30];
    assign rf_raddr1 = fetch_inst[19:15];
    assign rf_raddr2 = fetch_inst[24:20];
    assign csr_addr = fetch_inst[31:20];

    assign op_rtype    = opcode == OPCODE_OP;
    assign op_itype    = opcode == OPCODE_OP_IMM;
    assign op_load     = opcode == OPCODE_LOAD;
    assign op_store    = opcode == OPCODE_STORE;
    assign op_branch   = opcode == OPCODE_BRANCH;
    assign op_auipc    = opcode == OPCODE_AUIPC;
    assign op_jal      = opcode == OPCODE_JAL;
    assign op_jalr     = opcode == OPCODE_JALR;
    assign op_system   = opcode == OPCODE_SYSTEM;
    assign op_misc_mem = opcode == OPCODE_MISC_MEM;

    // RF + forward.
    always @(posedge clock) begin
        if (rf_wen & (rf_waddr != 5'd0) & ~rf_waddr[4]) begin
            reg_bank[rf_waddr[3:0]] <= rf_wdata;
        end
    end

    assign rf_rdata1 = (rf_raddr1 == 5'd0 || rf_raddr1[4]) ? 32'b0 : reg_bank[rf_raddr1[3:0]];
    assign rf_rdata2 = (rf_raddr2 == 5'd0 || rf_raddr2[4]) ? 32'b0 : reg_bank[rf_raddr2[3:0]];

    assign rf_rdata1_forward = ((rf_raddr1 == rf_waddr) && rf_wen && (rf_waddr != 5'b0)) ? rf_wdata : rf_rdata1;
    assign rf_rdata2_forward = ((rf_raddr2 == rf_waddr) && rf_wen && (rf_waddr != 5'b0)) ? rf_wdata : rf_rdata2;

    assign load_use_hazard = ls_load_pending &&
                             (rf_waddr != 5'b0) &&
                             (((op_rtype | op_itype | op_load | op_store | op_branch | op_jalr |
                                (op_system && (ex_funct3 != F3_PRIV) && ~ex_funct3[2])) &&
                               (rf_raddr1 == rf_waddr)) ||
                              ((op_rtype | op_store | op_branch) &&
                               (rf_raddr2 == rf_waddr)));

    assign fetch_ready = ~fetch_valid || (~load_use_hazard && ex_out_ready);
    assign ex_out_valid = fetch_valid && ~load_use_hazard;

    assign ex_rf_wen = ~(op_branch | op_store | op_misc_mem);
    assign ex_mem_wen = op_store;
    assign ex_mem_ren = op_load;
    assign ex_rf_waddr = fetch_inst[11:7];

    // Immediate.
    always @(*) begin
        case (opcode)
            OPCODE_OP_IMM,
            OPCODE_LOAD,
            OPCODE_JALR:   imm = {{20{fetch_inst[31]}}, fetch_inst[31:20]};
            OPCODE_STORE:  imm = {{20{fetch_inst[31]}}, fetch_inst[31:25], fetch_inst[11:7]};
            OPCODE_BRANCH: imm = {{20{fetch_inst[31]}}, fetch_inst[7], fetch_inst[30:25], fetch_inst[11:8], 1'b0};
            OPCODE_LUI,
            OPCODE_AUIPC:  imm = {fetch_inst[31:12], 12'b0};
            OPCODE_JAL:    imm = {{12{fetch_inst[31]}}, fetch_inst[19:12], fetch_inst[20], fetch_inst[30:21], 1'b0};
            OPCODE_SYSTEM: imm = {27'b0, fetch_inst[19:15]};
            default:       imm = 32'b0;
        endcase
    end

    // CSR read.
    assign ex_pc4 = fetch_pc + 32'd4;
    assign csr_src_data = ex_funct3[2] ? imm : rf_rdata1_forward;

    always @(*) begin
        case (csr_addr)
            CSR_MSTATUS:   csr_rdata = csr_mstatus;
            CSR_MTVEC:     csr_rdata = csr_mtvec;
            CSR_MEPC:      csr_rdata = csr_mepc;
            CSR_MCAUSE:    csr_rdata = csr_mcause;
            CSR_MVENDORID: csr_rdata = 32'h7973_7978;
            CSR_MARCHID:   csr_rdata = 32'd26030082;
            default:       csr_rdata = 32'b0;
        endcase
    end

    // ALU / BRU.
    assign add_lhs = (op_auipc | op_jal | op_branch) ? fetch_pc : rf_rdata1_forward;
    assign add_rhs = op_rtype ? rf_rdata2_forward : imm;
    assign add_sub = (op_rtype && ex_funct3 == 3'b000 && funct7_5) ||
                     ((op_rtype || op_itype) && (ex_funct3 == 3'b010 || ex_funct3 == 3'b011));
    assign add_rhs_xor = add_sub ? ~add_rhs : add_rhs;
    assign {add_carry, add_result} = {1'b0, add_lhs} + {1'b0, add_rhs_xor} + {32'b0, add_sub};

    assign logic_lhs = op_system ? csr_rdata : rf_rdata1_forward;
    assign logic_rhs = op_system ?
                       ((ex_funct3 == F3_CSRRC || ex_funct3 == F3_CSRRCI) ? ~csr_src_data : csr_src_data) :
                       (op_rtype ? rf_rdata2_forward : imm);
    assign and_result = logic_lhs & logic_rhs;
    assign or_result = logic_lhs | logic_rhs;
    assign xor_result = logic_lhs ^ logic_rhs;
    assign sll_result = rf_rdata1_forward << logic_rhs[4:0];
    assign srl_result = rf_rdata1_forward >> logic_rhs[4:0];
    assign sra_result = ($signed(rf_rdata1_forward)) >>> logic_rhs[4:0];
    assign cmp_lt = (add_lhs[31] & ~add_rhs[31]) |
                    ((add_lhs[31] ~^ add_rhs[31]) & add_result[31]);
    assign cmp_ltu = ~add_carry;
    assign branch_cmp_eq = (rf_rdata1_forward == rf_rdata2_forward);
    assign branch_cmp_lt = ($signed(rf_rdata1_forward) < $signed(rf_rdata2_forward));
    assign branch_cmp_ltu = (rf_rdata1_forward < rf_rdata2_forward);

    // Address / redirect target. ex_mem_addr is also the redirect target when ex_redirect is high.
    always @(*) begin
        ex_mem_addr = add_result;

        case (opcode)
            OPCODE_JALR: begin
                ex_mem_addr = {add_result[31:1], 1'b0};
            end

            OPCODE_SYSTEM: begin
                case (ex_funct3)
                    F3_PRIV: begin
                        case (csr_addr)
                            F12_ECALL: begin
                                ex_mem_addr = {csr_mtvec[31:2], 2'b0};
                            end
                            F12_MRET: begin
                                ex_mem_addr = csr_mepc;
                            end
                            default: begin
                            end
                        endcase
                    end

                    default: begin
                    end
                endcase
            end

            OPCODE_MISC_MEM: begin
                case (ex_funct3)
                    3'b001: begin
                        ex_mem_addr = ex_pc4;
                    end
                    default: begin
                    end
                endcase
            end

            default: begin
            end
        endcase
    end

    // Redirect / frontend invalidate.
    always @(*) begin
        ex_redirect = 1'b0;
        ex_fence_i = 1'b0;

        case (opcode)
            OPCODE_BRANCH: begin
                case (ex_funct3)
                    F3_BEQ:  ex_redirect = branch_cmp_eq;
                    F3_BNE:  ex_redirect = ~branch_cmp_eq;
                    F3_BLT:  ex_redirect = branch_cmp_lt;
                    F3_BGE:  ex_redirect = ~branch_cmp_lt;
                    F3_BLTU: ex_redirect = branch_cmp_ltu;
                    F3_BGEU: ex_redirect = ~branch_cmp_ltu;
                    default: begin
                    end
                endcase
            end

            OPCODE_JAL: begin
                ex_redirect = 1'b1;
            end

            OPCODE_JALR: begin
                ex_redirect = 1'b1;
            end

            OPCODE_SYSTEM: begin
                case (ex_funct3)
                    F3_PRIV: begin
                        case (csr_addr)
                            F12_ECALL: begin
                                ex_redirect = 1'b1;
                            end
                            F12_MRET: begin
                                ex_redirect = 1'b1;
                            end
                            default: begin
                            end
                        endcase
                    end

                    default: begin
                    end
                endcase
            end

            OPCODE_MISC_MEM: begin
                case (ex_funct3)
                    3'b001: begin
                        ex_redirect = 1'b1;
                        ex_fence_i = 1'b1;
                    end
                    default: begin
                    end
                endcase
            end

            default: begin
            end
        endcase
    end

    // RF writeback payload and CSR write data.
    always @(*) begin
        ex_wdata = add_result;
        csr_write_data = csr_src_data;

        case (opcode)
            OPCODE_OP,
            OPCODE_OP_IMM: begin
                case (ex_funct3)
                    3'b001: begin
                        ex_wdata = sll_result;
                    end
                    3'b010: begin
                        ex_wdata = {31'b0, cmp_lt};
                    end
                    3'b011: begin
                        ex_wdata = {31'b0, cmp_ltu};
                    end
                    3'b100: begin
                        ex_wdata = xor_result;
                    end
                    3'b101: begin
                        case (funct7_5)
                            1'b0: ex_wdata = srl_result;
                            1'b1: ex_wdata = sra_result;
                        endcase
                    end
                    3'b110: begin
                        ex_wdata = or_result;
                    end
                    3'b111: begin
                        ex_wdata = and_result;
                    end
                    default: begin
                    end
                endcase
            end

            OPCODE_LUI: begin
                ex_wdata = imm;
            end

            OPCODE_STORE: begin
                ex_wdata = rf_rdata2_forward;
            end

            OPCODE_JAL,
            OPCODE_JALR: begin
                ex_wdata = ex_pc4;
            end

            OPCODE_SYSTEM: begin
                ex_wdata = csr_rdata;
                case (ex_funct3)
                    F3_CSRRW,
                    F3_CSRRWI: begin
                        csr_write_data = csr_src_data;
                    end

                    F3_CSRRS,
                    F3_CSRRSI: begin
                        csr_write_data = or_result;
                    end

                    F3_CSRRC,
                    F3_CSRRCI: begin
                        csr_write_data = and_result;
                    end

                    default: begin
                    end
                endcase
            end

            OPCODE_MISC_MEM: begin
            end

            default: begin
            end
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            csr_mstatus <= 32'h1800;
            csr_mtvec   <= 32'h1;
            csr_mepc    <= 32'h0;
            csr_mcause  <= 32'h0;
        end else if (ex_out_valid && ex_out_ready && op_system) begin
            case (ex_funct3)
                F3_PRIV: begin
                    case (csr_addr)
                        F12_ECALL: begin
                            csr_mstatus[3] <= 1'b0;
                            csr_mstatus[7] <= csr_mstatus[3];
                            csr_mstatus[12:11] <= 2'b11;
                            csr_mepc <= fetch_pc;
                            csr_mcause <= CAUSE_ECALL;
                        end
                        F12_MRET: begin
                            csr_mstatus[3] <= csr_mstatus[7];
                        end
                        default: begin
                        end
                    endcase
                end

                F3_CSRRW,
                F3_CSRRS,
                F3_CSRRC,
                F3_CSRRWI,
                F3_CSRRSI,
                F3_CSRRCI: begin
                    case (csr_addr)
                        CSR_MSTATUS: csr_mstatus <= csr_write_data;
                        CSR_MTVEC:   csr_mtvec   <= csr_write_data;
                        CSR_MEPC:    csr_mepc    <= csr_write_data;
                        CSR_MCAUSE:  csr_mcause  <= csr_write_data;
                        default: begin
                        end
                    endcase
                end

                default: begin
                end
            endcase
        end
    end

endmodule
