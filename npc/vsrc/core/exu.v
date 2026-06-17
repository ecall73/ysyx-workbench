module ysyx_26030082_exu (
    input  wire        clock,
    input  wire        reset,

    input  wire        fetch_valid,
    output wire        fetch_ready,
    input  wire [31:0] fetch_pc,
    input  wire [31:0] fetch_inst,

    input  wire        ex_out_ready,
    output wire        ex_out_valid,

    input  wire        ls_out_valid,
    input  wire        ls_rf_wen,
    input  wire [ 4:0] ls_rf_waddr,
    input  wire [31:0] ls_rf_wdata,
    input  wire        ls_load_pending,

    output reg         ex_rf_wen,
    output wire        ex_mem_ren,
    output wire        ex_mem_wen,
    output wire [ 2:0] ex_funct3,
    output wire [ 4:0] ex_rf_waddr,
    output reg  [31:0] ex_mem_addr,
    output wire        ex_redirect,
    output reg  [31:0] ex_wdata,
    output wire        ex_fence_i
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

    localparam [2:0] F3_ADD_SUB = 3'b000;
    localparam [2:0] F3_SLL     = 3'b001;
    localparam [2:0] F3_SLT     = 3'b010;
    localparam [2:0] F3_SLTU    = 3'b011;
    localparam [2:0] F3_XOR     = 3'b100;
    localparam [2:0] F3_SRL_SRA = 3'b101;
    localparam [2:0] F3_OR      = 3'b110;
    localparam [2:0] F3_AND     = 3'b111;

    localparam [2:0] F3_BEQ  = 3'b000;
    localparam [2:0] F3_BNE  = 3'b001;
    localparam [2:0] F3_BLT  = 3'b100;
    localparam [2:0] F3_BGE  = 3'b101;
    localparam [2:0] F3_BLTU = 3'b110;
    localparam [2:0] F3_BGEU = 3'b111;

    localparam [2:0] F3_FENCE   = 3'b000;
    localparam [2:0] F3_FENCE_I = 3'b001;
    localparam [2:0] F3_LB      = 3'b000;
    localparam [2:0] F3_LH      = 3'b001;
    localparam [2:0] F3_LW      = 3'b010;
    localparam [2:0] F3_LBU     = 3'b100;
    localparam [2:0] F3_LHU     = 3'b101;
    localparam [2:0] F3_SB      = 3'b000;
    localparam [2:0] F3_SH      = 3'b001;
    localparam [2:0] F3_SW      = 3'b010;
    localparam [2:0] F3_JALR    = 3'b000;

    localparam [31:0] CAUSE_ECALL = 32'd11;

    // Common decode fields.
    wire [6:0] opcode;
    wire       funct7_5;
    wire [4:0] rf_raddr1;
    wire [4:0] rf_raddr2;
    wire [11:0] csr_addr;
    wire       rs1_used;
    wire       rs2_used;
    wire       csr_rs1_used;
    reg        branch_redirect;

    // RF + forward.
    reg  [31:0] reg_bank [1:15];
    wire        ls_rf_write;
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;
    wire        load_use_hazard;
    wire [31:0] rf_rdata1_forward;
    wire [31:0] rf_rdata2_forward;

    // Immediate.
    reg  [31:0] imm;

    // ALU.
    wire [31:0] ex_pc4;
    reg  [31:0] bit_lhs;
    reg  [31:0] bit_rhs;
    reg  [31:0] addsub_lhs;
    reg  [31:0] addsub_rhs;
    reg         addsub_sub;
    wire [31:0] addsub_rhs_xor;
    wire [31:0] addsub_result;
    wire [31:0] and_result;
    wire [31:0] or_result;
    wire [31:0] xor_result;
    reg  [ 4:0] shift_shamt;
    wire [31:0] sll_result;
    wire [31:0] srl_result;
    wire [31:0] sra_result;
    reg  [31:0] cmp_rhs;
    wire        cmp_eq;
    wire        cmp_lt;
    wire        cmp_ltu;

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

    // RF + forward.
    assign ls_rf_write = ls_out_valid && ls_rf_wen && (ls_rf_waddr != 5'b0);

    always @(posedge clock) begin
        if (ls_rf_write & ~ls_rf_waddr[4]) begin
            reg_bank[ls_rf_waddr[3:0]] <= ls_rf_wdata;
        end
    end

    assign rf_rdata1 = (rf_raddr1 == 5'd0 || rf_raddr1[4]) ? 32'b0 : reg_bank[rf_raddr1[3:0]];
    assign rf_rdata2 = (rf_raddr2 == 5'd0 || rf_raddr2[4]) ? 32'b0 : reg_bank[rf_raddr2[3:0]];

    assign rf_rdata1_forward = ((rf_raddr1 == ls_rf_waddr) && ls_rf_write) ? ls_rf_wdata : rf_rdata1;
    assign rf_rdata2_forward = ((rf_raddr2 == ls_rf_waddr) && ls_rf_write) ? ls_rf_wdata : rf_rdata2;

    assign csr_rs1_used = (opcode == OPCODE_SYSTEM) &&
                          ~ex_funct3[2] &&
                          (ex_funct3[1:0] != 2'b00);
    assign rs2_used = (opcode == OPCODE_OP) ||
                      (opcode == OPCODE_STORE) ||
                      (opcode == OPCODE_BRANCH);
    assign rs1_used = rs2_used ||
                      (opcode == OPCODE_OP_IMM) ||
                      (opcode == OPCODE_LOAD) ||
                      (opcode == OPCODE_JALR) ||
                      csr_rs1_used;

    assign load_use_hazard = ls_load_pending &&
                             ls_rf_write &&
                             ((rs1_used && (rf_raddr1 == ls_rf_waddr)) ||
                              (rs2_used && (rf_raddr2 == ls_rf_waddr)));

    assign fetch_ready = ~fetch_valid || (~load_use_hazard && ex_out_ready);
    assign ex_out_valid = fetch_valid && ~load_use_hazard;

    assign ex_rf_waddr = fetch_inst[11:7];

    // Immediate.
    always @(*) begin
        case (opcode)
            OPCODE_OP_IMM,
            OPCODE_LOAD,
            OPCODE_JALR:  imm = {{20{fetch_inst[31]}}, fetch_inst[31:20]};
            OPCODE_STORE:   imm = {{20{fetch_inst[31]}}, fetch_inst[31:25], fetch_inst[11:7]};
            OPCODE_BRANCH:   imm = {{20{fetch_inst[31]}}, fetch_inst[7], fetch_inst[30:25], fetch_inst[11:8], 1'b0};
            OPCODE_LUI,
            OPCODE_AUIPC:  imm = {fetch_inst[31:12], 12'b0};
            OPCODE_JAL:   imm = {{12{fetch_inst[31]}}, fetch_inst[19:12], fetch_inst[20], fetch_inst[30:21], 1'b0};
            OPCODE_SYSTEM: imm = {27'b0, fetch_inst[19:15]};
            OPCODE_OP,
            OPCODE_MISC_MEM: imm = 32'b0;
            default:     imm = 32'b0;
        endcase
    end

    // CSR read.
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

    // ALU.
    assign ex_pc4 = fetch_pc + 32'd4;
    assign csr_src_data = ex_funct3[2] ? imm : rf_rdata1_forward;
    always @(*) begin
        addsub_lhs = 32'bx;
        addsub_rhs = 32'bx;
        addsub_sub = 1'bx;
        bit_lhs = 32'bx;
        bit_rhs = 32'bx;
        shift_shamt = 5'bx;
        cmp_rhs = 32'bx;

        if (opcode == OPCODE_BRANCH) begin
            cmp_rhs = rf_rdata2_forward;
        end

        case (opcode)
            OPCODE_OP: begin
                addsub_lhs = rf_rdata1_forward;
                addsub_rhs = rf_rdata2_forward;
                addsub_sub = (ex_funct3 == F3_ADD_SUB) && funct7_5;
                bit_lhs = rf_rdata1_forward;
                bit_rhs = rf_rdata2_forward;
                shift_shamt = rf_rdata2_forward[4:0];
                cmp_rhs = rf_rdata2_forward;
            end

            OPCODE_OP_IMM: begin
                addsub_lhs = rf_rdata1_forward;
                addsub_rhs = imm;
                addsub_sub = 1'b0;
                bit_lhs = rf_rdata1_forward;
                bit_rhs = imm;
                shift_shamt = imm[4:0];
                cmp_rhs = imm;
            end

            OPCODE_LOAD,
            OPCODE_STORE,
            OPCODE_JALR: begin
                addsub_lhs = rf_rdata1_forward;
                addsub_rhs = imm;
                addsub_sub = 1'b0;
            end

            OPCODE_AUIPC,
            OPCODE_JAL,
            OPCODE_BRANCH: begin
                addsub_lhs = fetch_pc;
                addsub_rhs = imm;
                addsub_sub = 1'b0;
            end

            OPCODE_SYSTEM: begin
                case (ex_funct3)
                    F3_CSRRS,
                    F3_CSRRSI: begin
                        bit_lhs = csr_rdata;
                        bit_rhs = csr_src_data;
                    end

                    F3_CSRRC,
                    F3_CSRRCI: begin
                        bit_lhs = csr_rdata;
                        bit_rhs = ~csr_src_data;
                    end

                    default: begin
                    end
                endcase
            end

            default: begin
            end
        endcase
    end

    assign addsub_rhs_xor = addsub_sub ? ~addsub_rhs : addsub_rhs;
    assign addsub_result = addsub_lhs + addsub_rhs_xor + {31'b0, addsub_sub};
    assign and_result = bit_lhs & bit_rhs;
    assign or_result = bit_lhs | bit_rhs;
    assign xor_result = bit_lhs ^ bit_rhs;
    assign sll_result = rf_rdata1_forward << shift_shamt;
    assign srl_result = rf_rdata1_forward >> shift_shamt;
    assign sra_result = ($signed(rf_rdata1_forward)) >>> shift_shamt;
    assign cmp_eq = (rf_rdata1_forward == cmp_rhs);
    assign cmp_lt = ($signed(rf_rdata1_forward) < $signed(cmp_rhs));
    assign cmp_ltu = (rf_rdata1_forward < cmp_rhs);

    always @(*) begin
        case (ex_funct3)
            F3_BEQ:  branch_redirect = cmp_eq;
            F3_BNE:  branch_redirect = ~cmp_eq;
            F3_BLT:  branch_redirect = cmp_lt;
            F3_BGE:  branch_redirect = ~cmp_lt;
            F3_BLTU: branch_redirect = cmp_ltu;
            F3_BGEU: branch_redirect = ~cmp_ltu;
            default: branch_redirect = 1'b0;
        endcase
    end

    assign ex_redirect = ((opcode == OPCODE_BRANCH) && branch_redirect) ||
                         (opcode == OPCODE_JAL) ||
                         (opcode == OPCODE_JALR) ||
                         ((opcode == OPCODE_SYSTEM) && (ex_funct3 == F3_PRIV)) ||
                         ex_fence_i;
    assign ex_mem_ren = (opcode == OPCODE_LOAD);
    assign ex_mem_wen = (opcode == OPCODE_STORE);
    assign ex_fence_i = (opcode == OPCODE_MISC_MEM) &&
                        (ex_funct3 == F3_FENCE_I);

    always @(*) begin
        case (ex_funct3)
            F3_CSRRW,
            F3_CSRRWI: csr_write_data = csr_src_data;
            F3_CSRRS,
            F3_CSRRSI: csr_write_data = or_result;
            F3_CSRRC,
            F3_CSRRCI: csr_write_data = and_result;
            default:   csr_write_data = csr_src_data;
        endcase
    end

    always @(*) begin
        case (opcode)
            OPCODE_OP,
            OPCODE_OP_IMM,
            OPCODE_LUI,
            OPCODE_AUIPC,
            OPCODE_LOAD,
            OPCODE_JAL,
            OPCODE_JALR:   ex_rf_wen = 1'b1;
            OPCODE_SYSTEM: ex_rf_wen = (ex_funct3 != F3_PRIV);
            default:       ex_rf_wen = 1'b0;
        endcase
    end

    // Output mux.
    always @(*) begin
        ex_mem_addr = 32'bx;
        ex_wdata = 32'bx;

        case (opcode)
            OPCODE_OP,
            OPCODE_OP_IMM: begin
                case (ex_funct3)
                    F3_ADD_SUB: begin
                        ex_wdata = addsub_result;
                    end

                    F3_SLL: begin
                        ex_wdata = sll_result;
                    end

                    F3_SLT: begin
                        ex_wdata = {31'b0, cmp_lt};
                    end

                    F3_SLTU: begin
                        ex_wdata = {31'b0, cmp_ltu};
                    end

                    F3_XOR: begin
                        ex_wdata = xor_result;
                    end

                    F3_SRL_SRA: begin
                        case (funct7_5)
                            1'b0: begin
                                ex_wdata = srl_result;
                            end

                            1'b1: begin
                                ex_wdata = sra_result;
                            end
                        endcase
                    end

                    F3_OR: begin
                        ex_wdata = or_result;
                    end

                    F3_AND: begin
                        ex_wdata = and_result;
                    end

                    default: begin
                    end
                endcase
            end

            OPCODE_LUI: begin
                ex_wdata = imm;
            end

            OPCODE_AUIPC: begin
                ex_wdata = addsub_result;
            end

            OPCODE_STORE: begin
                ex_mem_addr = addsub_result;
                ex_wdata = rf_rdata2_forward;
            end

            OPCODE_LOAD: begin
                ex_mem_addr = addsub_result;
            end

            OPCODE_BRANCH: begin
                ex_mem_addr = addsub_result;
            end

            OPCODE_JAL: begin
                ex_mem_addr = addsub_result;
                ex_wdata = ex_pc4;
            end

            OPCODE_JALR: begin
                ex_mem_addr = {addsub_result[31:1], 1'b0};
                ex_wdata = ex_pc4;
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

                    F3_CSRRW,
                    F3_CSRRWI: begin
                        ex_wdata = csr_rdata;
                    end

                    F3_CSRRS,
                    F3_CSRRSI: begin
                        ex_wdata = csr_rdata;
                    end

                    F3_CSRRC,
                    F3_CSRRCI: begin
                        ex_wdata = csr_rdata;
                    end

                    default: begin
                    end
                endcase
            end

            OPCODE_MISC_MEM: begin
                case (ex_funct3)
                    F3_FENCE_I: begin
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

    always @(posedge clock) begin
        if (reset) begin
            csr_mstatus <= 32'h1800;
            csr_mtvec   <= 32'h1;
            csr_mepc    <= 32'h0;
            csr_mcause  <= 32'h0;
        end else if (ex_out_valid && ex_out_ready && (opcode == OPCODE_SYSTEM)) begin
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
