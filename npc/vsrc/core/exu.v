module ysyx_26030082_exu (
    input  wire        clock,
    input  wire        reset,

    input  wire        ex_in_valid,
    output wire        ex_in_ready,
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_inst,

    output wire        ex_out_ready,
    output wire        ex_out_valid,
    output wire        ls_out_valid,

    input  wire [63:0] ex_mtime,

    output wire        ex_redirect,
    output reg  [31:0] ex_redirect_pc,
    output wire        ex_fence_i,

    output wire [31:0] lsu_axi_araddr,
    output wire [ 2:0] lsu_axi_arsize,
    output wire        lsu_axi_arvalid,
    input  wire        lsu_axi_arready,
    input  wire [31:0] lsu_axi_rdata,
    input  wire [ 1:0] lsu_axi_rresp,
    input  wire        lsu_axi_rvalid,
    output wire        lsu_axi_rready,
    output wire [31:0] lsu_axi_awaddr,
    output wire [ 2:0] lsu_axi_awsize,
    output wire        lsu_axi_awvalid,
    input  wire        lsu_axi_awready,
    output wire [31:0] lsu_axi_wdata,
    output wire [ 3:0] lsu_axi_wstrb,
    output wire        lsu_axi_wvalid,
    input  wire        lsu_axi_wready,
    input  wire [ 1:0] lsu_axi_bresp,
    input  wire        lsu_axi_bvalid,
    output wire        lsu_axi_bready
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
    localparam L_IDLE      = 3'd0;
    localparam L_RD_AR     = 3'd1;
    localparam L_RD_WAIT_R = 3'd2;
    localparam L_WR_AW_W   = 3'd3;
    localparam L_WR_WAIT_B = 3'd4;
    localparam [15:0] CLINT_BASE_HI     = 16'h0200;
    localparam [13:0] MTIME_WORD_OFFSET  = 14'h2ffe;
    localparam [13:0] MTIMEH_WORD_OFFSET = 14'h2fff;

    // Common decode fields.
    wire [6:0] opcode;
    wire       funct7_5;
    wire [2:0] ex_funct3;
    wire [4:0] rf_raddr1;
    wire [4:0] rf_raddr2;
    wire [4:0] ex_rf_waddr;
    wire [11:0] csr_addr;
    reg        branch_redirect;

    // RF.
    reg  [31:0] reg_bank [1:15];
    reg         ex_rf_wen;
    reg  [31:0] ex_wdata;
    wire        rf_write;
    wire [31:0] rf_wdata;
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;

    // Immediate.
    wire [31:0] imm;

    // ALU.
    wire [31:0] ex_pc4;
    wire        ex_mem_ren;
    wire        ex_mem_wen;
    wire [31:0] ex_mem_addr;
    reg  [31:0] bit_lhs;
    wire [31:0] bit_rhs;
    wire [31:0] addsub_lhs;
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
    wire [31:0] csr_write_data;
    wire        csr_wdata_or_sel;
    wire        csr_wdata_and_sel;

    // LSU.
    reg  [2:0]  lsu_state;
    reg         wr_aw_done;
    reg         wr_w_done;
    wire        lsu_is_mem;
    wire        lsu_is_load;
    wire        lsu_is_clint;
    wire        lsu_is_local;
    wire        lsu_is_local_load;
    wire        ex_ready_go;
    wire        ex_fire;
    wire        ar_fire;
    wire        r_fire;
    wire        aw_fire;
    wire        w_fire;
    wire        b_fire;
    wire [1:0]  lsu_offset;
    reg  [31:0] lsu_local_rdata;
    wire [31:0] lsu_load_raw_data;
    reg  [3:0]  lsu_wmask_calc;
    reg  [31:0] lsu_wdata_aligned;
    reg  [31:0] lsu_rdata_decoded;
    reg  [2:0]  lsu_axi_size;

    assign opcode = ex_inst[6:0];
    assign ex_funct3 = ex_inst[14:12];
    assign funct7_5 = ex_inst[30];
    assign rf_raddr1 = ex_inst[19:15];
    assign rf_raddr2 = ex_inst[24:20];
    assign csr_addr = ex_inst[31:20];

    // RF.
    assign ex_fire = ex_out_valid && ex_out_ready;
    assign rf_write = ex_fire && ex_rf_wen && (ex_rf_waddr != 5'b0);
    assign rf_wdata = ex_mem_ren ? lsu_rdata_decoded : ex_wdata;

    always @(posedge clock) begin
        if (rf_write & ~ex_rf_waddr[4]) begin
            reg_bank[ex_rf_waddr[3:0]] <= rf_wdata;
        end
    end

    assign rf_rdata1 = (rf_raddr1 == 5'd0 || rf_raddr1[4]) ? 32'b0 : reg_bank[rf_raddr1[3:0]];
    assign rf_rdata2 = (rf_raddr2 == 5'd0 || rf_raddr2[4]) ? 32'b0 : reg_bank[rf_raddr2[3:0]];

    assign ex_in_ready = ~ex_in_valid || ex_ready_go;
    assign ex_out_valid = ex_in_valid;
    assign ex_out_ready = ex_ready_go;
    assign ls_out_valid = ex_fire;

    assign ex_rf_waddr = ex_inst[11:7];

    assign imm = ({32{(opcode == OPCODE_OP_IMM) ||
                      (opcode == OPCODE_LOAD) ||
                      (opcode == OPCODE_JALR)}} &
                  {{20{ex_inst[31]}}, ex_inst[31:20]}) |
                 ({32{opcode == OPCODE_STORE}} &
                  {{20{ex_inst[31]}}, ex_inst[31:25], ex_inst[11:7]}) |
                 ({32{opcode == OPCODE_BRANCH}} &
                  {{20{ex_inst[31]}}, ex_inst[7], ex_inst[30:25], ex_inst[11:8], 1'b0}) |
                 ({32{(opcode == OPCODE_LUI) ||
                      (opcode == OPCODE_AUIPC)}} &
                  {ex_inst[31:12], 12'b0}) |
                 ({32{opcode == OPCODE_JAL}} &
                  {{12{ex_inst[31]}}, ex_inst[19:12], ex_inst[20], ex_inst[30:21], 1'b0}) |
                 ({32{opcode == OPCODE_SYSTEM}} &
                  {27'b0, ex_inst[19:15]});

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
    assign ex_pc4 = ex_pc + 32'd4;
    assign csr_src_data = ex_funct3[2] ? imm : rf_rdata1;
    always @(*) begin
        addsub_rhs = 32'b0;
        addsub_sub = 1'bx;
        bit_lhs = 32'bx;
        shift_shamt = 5'b0;
        cmp_rhs = 32'bx;

        case (opcode)
            OPCODE_OP: begin
                addsub_rhs = rf_rdata2;
                addsub_sub = (ex_funct3 == F3_ADD_SUB) && funct7_5;
                bit_lhs = rf_rdata1;
                shift_shamt = rf_rdata2[4:0];
                cmp_rhs = rf_rdata2;
            end

            OPCODE_OP_IMM: begin
                addsub_rhs = imm;
                addsub_sub = 1'b0;
                bit_lhs = rf_rdata1;
                shift_shamt = imm[4:0];
                cmp_rhs = imm;
            end

            OPCODE_LOAD,
            OPCODE_STORE,
            OPCODE_JALR: begin
                addsub_rhs = imm;
                addsub_sub = 1'b0;
            end

            OPCODE_AUIPC,
            OPCODE_JAL: begin
                addsub_rhs = imm;
                addsub_sub = 1'b0;
            end

            OPCODE_BRANCH: begin
                addsub_rhs = imm;
                addsub_sub = 1'b0;
                cmp_rhs = rf_rdata2;
            end

            OPCODE_SYSTEM: begin
                case (ex_funct3)
                    F3_CSRRS,
                    F3_CSRRSI: begin
                        bit_lhs = csr_rdata;
                    end

                    F3_CSRRC,
                    F3_CSRRCI: begin
                        bit_lhs = csr_rdata;
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
    assign sll_result = rf_rdata1 << shift_shamt;
    assign srl_result = rf_rdata1 >> shift_shamt;
    assign sra_result = ($signed(rf_rdata1)) >>> shift_shamt;
    assign cmp_eq = (rf_rdata1 == cmp_rhs);
    assign cmp_lt = ($signed(rf_rdata1) < $signed(cmp_rhs));
    assign cmp_ltu = (rf_rdata1 < cmp_rhs);

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
    assign addsub_lhs = ({32{(opcode == OPCODE_OP) ||
                              (opcode == OPCODE_OP_IMM) ||
                              (opcode == OPCODE_LOAD) ||
                              (opcode == OPCODE_STORE) ||
                              (opcode == OPCODE_JALR)}} & rf_rdata1) |
                        ({32{(opcode == OPCODE_AUIPC) ||
                              (opcode == OPCODE_JAL) ||
                              (opcode == OPCODE_BRANCH)}} & ex_pc);
    assign csr_wdata_or_sel = (ex_funct3 == F3_CSRRS) ||
                              (ex_funct3 == F3_CSRRSI);
    assign csr_wdata_and_sel = (ex_funct3 == F3_CSRRC) ||
                               (ex_funct3 == F3_CSRRCI);
    assign bit_rhs = ({32{opcode == OPCODE_OP}} & rf_rdata2) |
                     ({32{opcode == OPCODE_OP_IMM}} & imm) |
                     ({32{(opcode == OPCODE_SYSTEM) && csr_wdata_or_sel}} & csr_src_data) |
                     ({32{(opcode == OPCODE_SYSTEM) && csr_wdata_and_sel}} & ~csr_src_data);
    assign csr_write_data = ({32{csr_wdata_or_sel}} & or_result) |
                            ({32{csr_wdata_and_sel}} & and_result) |
                            ({32{~csr_wdata_or_sel && ~csr_wdata_and_sel}} & csr_src_data);
    assign ex_mem_addr = addsub_result;

    // LSU.
    assign lsu_is_mem = ex_mem_ren || ex_mem_wen;
    assign lsu_is_load = ex_mem_ren && ~ex_mem_wen;
    assign lsu_is_clint = (ex_mem_addr[31:16] == CLINT_BASE_HI);
    assign lsu_is_local = lsu_is_mem && lsu_is_clint;
    assign lsu_is_local_load = lsu_is_load && lsu_is_clint;
    assign ar_fire = lsu_axi_arvalid && lsu_axi_arready;
    assign r_fire = lsu_axi_rvalid && lsu_axi_rready;
    assign aw_fire = lsu_axi_awvalid && lsu_axi_awready;
    assign w_fire = lsu_axi_wvalid && lsu_axi_wready;
    assign b_fire = lsu_axi_bvalid && lsu_axi_bready;
    assign lsu_offset = ex_mem_addr[1:0];
    assign lsu_load_raw_data = lsu_is_local_load ? lsu_local_rdata : lsu_axi_rdata;
    assign ex_ready_go = (lsu_state == L_IDLE) ? ~(ex_in_valid && lsu_is_mem && ~lsu_is_local) :
                         (lsu_state == L_RD_WAIT_R) ? lsu_axi_rvalid :
                         (lsu_state == L_WR_WAIT_B) ? lsu_axi_bvalid : 1'b0;
    assign lsu_axi_araddr = ex_mem_addr;
    assign lsu_axi_arsize = lsu_axi_size;
    assign lsu_axi_arvalid = (lsu_state == L_RD_AR);
    assign lsu_axi_rready = (lsu_state == L_RD_WAIT_R);
    assign lsu_axi_awaddr = ex_mem_addr;
    assign lsu_axi_awsize = lsu_axi_size;
    assign lsu_axi_awvalid = (lsu_state == L_WR_AW_W) && ~wr_aw_done;
    assign lsu_axi_wdata = lsu_wdata_aligned;
    assign lsu_axi_wstrb = lsu_wmask_calc;
    assign lsu_axi_wvalid = (lsu_state == L_WR_AW_W) && ~wr_w_done;
    assign lsu_axi_bready = (lsu_state == L_WR_WAIT_B);

    always @(*) begin
        case (ex_mem_addr[15:2])
            MTIME_WORD_OFFSET:  lsu_local_rdata = ex_mtime[31:0];
            MTIMEH_WORD_OFFSET: lsu_local_rdata = ex_mtime[63:32];
            default:            lsu_local_rdata = 32'b0;
        endcase
    end

    always @(*) begin
        lsu_wmask_calc = 4'b0000;
        lsu_wdata_aligned = ex_wdata;
        lsu_axi_size = 3'b010;
        case (ex_funct3)
            F3_SB: begin
                lsu_axi_size = 3'b000;
                case (lsu_offset)
                    2'b00: begin
                        lsu_wmask_calc = 4'b0001;
                        lsu_wdata_aligned = {24'b0, ex_wdata[7:0]};
                    end
                    2'b01: begin
                        lsu_wmask_calc = 4'b0010;
                        lsu_wdata_aligned = {16'b0, ex_wdata[7:0], 8'b0};
                    end
                    2'b10: begin
                        lsu_wmask_calc = 4'b0100;
                        lsu_wdata_aligned = {8'b0, ex_wdata[7:0], 16'b0};
                    end
                    2'b11: begin
                        lsu_wmask_calc = 4'b1000;
                        lsu_wdata_aligned = {ex_wdata[7:0], 24'b0};
                    end
                endcase
            end
            F3_SH: begin
                lsu_axi_size = 3'b001;
                case (lsu_offset[1])
                    1'b0: begin
                        lsu_wmask_calc = 4'b0011;
                        lsu_wdata_aligned = {16'b0, ex_wdata[15:0]};
                    end
                    1'b1: begin
                        lsu_wmask_calc = 4'b1100;
                        lsu_wdata_aligned = {ex_wdata[15:0], 16'b0};
                    end
                endcase
            end
            F3_LBU: begin
                lsu_axi_size = 3'b000;
            end
            F3_LHU: begin
                lsu_axi_size = 3'b001;
            end
            default: begin
                lsu_wmask_calc = 4'b1111;
                lsu_wdata_aligned = ex_wdata;
            end
        endcase
    end

    always @(*) begin
        lsu_rdata_decoded = lsu_load_raw_data;
        case (ex_funct3)
            F3_LB: begin
                case (lsu_offset)
                    2'b00: lsu_rdata_decoded = {{24{lsu_load_raw_data[7]}}, lsu_load_raw_data[7:0]};
                    2'b01: lsu_rdata_decoded = {{24{lsu_load_raw_data[15]}}, lsu_load_raw_data[15:8]};
                    2'b10: lsu_rdata_decoded = {{24{lsu_load_raw_data[23]}}, lsu_load_raw_data[23:16]};
                    2'b11: lsu_rdata_decoded = {{24{lsu_load_raw_data[31]}}, lsu_load_raw_data[31:24]};
                    default: lsu_rdata_decoded = 32'b0;
                endcase
            end
            F3_LH: begin
                case (lsu_offset[1])
                    1'b0: lsu_rdata_decoded = {{16{lsu_load_raw_data[15]}}, lsu_load_raw_data[15:0]};
                    1'b1: lsu_rdata_decoded = {{16{lsu_load_raw_data[31]}}, lsu_load_raw_data[31:16]};
                    default: lsu_rdata_decoded = 32'b0;
                endcase
            end
            F3_LBU: begin
                case (lsu_offset)
                    2'b00: lsu_rdata_decoded = {24'b0, lsu_load_raw_data[7:0]};
                    2'b01: lsu_rdata_decoded = {24'b0, lsu_load_raw_data[15:8]};
                    2'b10: lsu_rdata_decoded = {24'b0, lsu_load_raw_data[23:16]};
                    2'b11: lsu_rdata_decoded = {24'b0, lsu_load_raw_data[31:24]};
                    default: lsu_rdata_decoded = 32'b0;
                endcase
            end
            F3_LHU: begin
                case (lsu_offset[1])
                    1'b0: lsu_rdata_decoded = {16'b0, lsu_load_raw_data[15:0]};
                    1'b1: lsu_rdata_decoded = {16'b0, lsu_load_raw_data[31:16]};
                    default: lsu_rdata_decoded = 32'b0;
                endcase
            end
            default: lsu_rdata_decoded = lsu_load_raw_data;
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
        ex_redirect_pc = 32'bx;
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
                ex_wdata = rf_rdata2;
            end

            OPCODE_LOAD: begin
            end

            OPCODE_BRANCH: begin
                ex_redirect_pc = addsub_result;
            end

            OPCODE_JAL: begin
                ex_redirect_pc = addsub_result;
                ex_wdata = ex_pc4;
            end

            OPCODE_JALR: begin
                ex_redirect_pc = {addsub_result[31:1], 1'b0};
                ex_wdata = ex_pc4;
            end

            OPCODE_SYSTEM: begin
                case (ex_funct3)
                    F3_PRIV: begin
                        case (csr_addr)
                            F12_ECALL: begin
                                ex_redirect_pc = {csr_mtvec[31:2], 2'b0};
                            end

                            F12_MRET: begin
                                ex_redirect_pc = csr_mepc;
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
                        ex_redirect_pc = ex_pc4;
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
                            csr_mepc <= ex_pc;
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

    always @(posedge clock) begin
        if (reset) begin
            lsu_state <= L_IDLE;
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
        end else begin
            case (lsu_state)
                L_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                    if (ex_in_valid && lsu_is_mem && ~lsu_is_local) begin
                        if (lsu_is_load) begin
                            lsu_state <= L_RD_AR;
                        end else begin
                            lsu_state <= L_WR_AW_W;
                        end
                    end
                end

                L_RD_AR: begin
                    if (ar_fire) begin
                        lsu_state <= L_RD_WAIT_R;
                    end
                end

                L_RD_WAIT_R: begin
                    if (r_fire) begin
                        lsu_state <= L_IDLE;
                    end
                end

                L_WR_AW_W: begin
                    if (aw_fire) begin
                        wr_aw_done <= 1'b1;
                    end
                    if (w_fire) begin
                        wr_w_done <= 1'b1;
                    end
                    if ((wr_aw_done || aw_fire) && (wr_w_done || w_fire)) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        lsu_state <= L_WR_WAIT_B;
                    end
                end

                L_WR_WAIT_B: begin
                    if (b_fire) begin
                        lsu_state <= L_IDLE;
                    end
                end

                default: begin
                    lsu_state <= L_IDLE;
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                end
            endcase
        end
    end

endmodule
