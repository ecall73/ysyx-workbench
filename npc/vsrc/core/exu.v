module ysyx_26030082_exu (
    input             clock,
    input             reset,

    input             ex_in_valid,
    output            ex_in_ready,
    input      [31:0] ex_pc,
    input      [31:0] ex_inst,

    output            ex_out_valid,

    input      [63:0] ex_mtime,

    output            ex_redirect,
    output reg [31:0] ex_redirect_pc,
    output            ex_fence_i,

    output     [31:0] lsu_master_araddr,
    output     [ 2:0] lsu_master_arsize,
    output            lsu_master_arvalid,
    input             lsu_master_arready,
    input      [31:0] lsu_master_rdata,
    input      [ 1:0] lsu_master_rresp,
    input             lsu_master_rvalid,
    output            lsu_master_rready,
    output     [31:0] lsu_master_awaddr,
    output     [ 2:0] lsu_master_awsize,
    output            lsu_master_awvalid,
    input             lsu_master_awready,
    output reg [31:0] lsu_master_wdata,
    output     [ 3:0] lsu_master_wstrb,
    output            lsu_master_wvalid,
    input             lsu_master_wready,
    input      [ 1:0] lsu_master_bresp,
    input             lsu_master_bvalid,
    output            lsu_master_bready
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

    localparam [2:0] F3_PRIV   = 3'b000;
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
    localparam L_IDLE    = 3'd0;
    localparam L_WAIT_R  = 3'd1;
    localparam L_WAIT_AW = 3'd2;
    localparam L_WAIT_W  = 3'd3;
    localparam L_WAIT_B  = 3'd4;
    localparam [15:0] CLINT_BASE_HI     = 16'h0200;
    localparam [13:0] MTIME_WORD_OFFSET  = 14'h2ffe;
    localparam [13:0] MTIMEH_WORD_OFFSET = 14'h2fff;

    // Common decode fields.
    wire [6:0] opcode;
    wire       funct7_5;
    wire [2:0] funct3;
    wire [4:0] rf_raddr1;
    wire [4:0] rf_raddr2;
    wire [4:0] rf_waddr;
    wire [11:0] csr_addr;
    reg        branch_redirect;

    // RF.
    reg  [31:0] reg_bank [1:15];
    wire        rf_wen;
    wire        rf_write;
    reg  [31:0] rf_wdata;
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;

    // Immediate.
    wire [31:0] imm;

    // ALU.
    wire [31:0] pc4;
    wire        mem_ren;
    wire        mem_wen;
    wire [31:0] mem_addr;
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

    // Memory.
    reg  [2:0]  mem_state;
    wire        is_clint;
    wire        ext_mem_req;
    wire        ext_load_req;
    wire        ext_store_req;
    wire        ready_go;
    wire        fire;
    wire        ar_fire;
    wire        r_fire;
    wire        aw_fire;
    wire        w_fire;
    wire        b_fire;
    wire [1:0]  mem_offset;
    reg  [31:0] local_rdata;
    wire [31:0] load_raw_data;
    reg  [3:0]  wmask_calc;
    reg  [31:0] rdata_decoded;
    reg  [2:0]  mem_size;

    assign opcode = ex_inst[6:0];
    assign funct3 = ex_inst[14:12];
    assign funct7_5 = ex_inst[30];
    assign rf_raddr1 = ex_inst[19:15];
    assign rf_raddr2 = ex_inst[24:20];
    assign csr_addr = ex_inst[31:20];

    assign rf_waddr = ex_inst[11:7];

/////////////////////////
    // ID: RF read, imm gen, input mux.
    assign rf_rdata1 = (rf_raddr1 == 5'd0 || rf_raddr1[4]) ? 32'b0 : reg_bank[rf_raddr1[3:0]];
    assign rf_rdata2 = (rf_raddr2 == 5'd0 || rf_raddr2[4]) ? 32'b0 : reg_bank[rf_raddr2[3:0]];
    assign rf_rdata2 = rf_rdata2;

    assign imm = ({32{opcode == OPCODE_OP_IMM || opcode == OPCODE_LOAD || opcode == OPCODE_JALR}} & {{20{ex_inst[31]}}, ex_inst[31:20]}) |
                 ({32{opcode == OPCODE_STORE}} & {{20{ex_inst[31]}}, ex_inst[31:25], ex_inst[11:7]}) |
                 ({32{opcode == OPCODE_BRANCH}} & {{20{ex_inst[31]}}, ex_inst[7], ex_inst[30:25], ex_inst[11:8], 1'b0}) |
                 ({32{(opcode == OPCODE_LUI) || (opcode == OPCODE_AUIPC)}} & {ex_inst[31:12], 12'b0}) |
                 ({32{opcode == OPCODE_JAL}} & {{12{ex_inst[31]}}, ex_inst[19:12], ex_inst[20], ex_inst[30:21], 1'b0}) |
                 ({32{opcode == OPCODE_SYSTEM}} & {27'b0, ex_inst[19:15]});

    assign pc4 = ex_pc + 32'd4;
    assign csr_src_data = funct3[2] ? imm : rf_rdata1;
    assign mem_ren = opcode == OPCODE_LOAD;
    assign mem_wen = opcode == OPCODE_STORE;
    assign ex_fence_i = (opcode == OPCODE_MISC_MEM) && (funct3 == F3_FENCE_I);

    assign rf_wen = (opcode == OPCODE_OP) ||
                    (opcode == OPCODE_OP_IMM) ||
                    (opcode == OPCODE_LUI) ||
                    (opcode == OPCODE_AUIPC) ||
                    (opcode == OPCODE_LOAD) ||
                    (opcode == OPCODE_JAL) ||
                    (opcode == OPCODE_JALR) ||
                    ((opcode == OPCODE_SYSTEM) && (funct3 != F3_PRIV));

    always @(*) begin
        addsub_rhs = 32'b0;
        addsub_sub = 1'bx;
        bit_lhs = 32'bx;
        shift_shamt = 5'b0;
        cmp_rhs = 32'bx;

        case (opcode)
            OPCODE_OP: begin
                addsub_rhs = rf_rdata2;
                addsub_sub = (funct3 == F3_ADD_SUB) && funct7_5;
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
                bit_lhs = csr_rdata;
            end

            default: begin
            end
        endcase
    end

    assign addsub_lhs = ({32{(opcode == OPCODE_OP) ||
                              (opcode == OPCODE_OP_IMM) ||
                              (opcode == OPCODE_LOAD) ||
                              (opcode == OPCODE_STORE) ||
                              (opcode == OPCODE_JALR)}} & rf_rdata1) |
                        ({32{(opcode == OPCODE_AUIPC) ||
                              (opcode == OPCODE_JAL) ||
                              (opcode == OPCODE_BRANCH)}} & ex_pc);
    assign csr_wdata_or_sel = (funct3 == F3_CSRRS) ||
                              (funct3 == F3_CSRRSI);
    assign csr_wdata_and_sel = (funct3 == F3_CSRRC) ||
                               (funct3 == F3_CSRRCI);
    assign bit_rhs = ({32{opcode == OPCODE_OP}} & rf_rdata2) |
                     ({32{opcode == OPCODE_OP_IMM}} & imm) |
                     ({32{(opcode == OPCODE_SYSTEM) && csr_wdata_or_sel}} & csr_src_data) |
                     ({32{(opcode == OPCODE_SYSTEM) && csr_wdata_and_sel}} & ~csr_src_data);

/////////////////////////
    // EX: FU, CSR, redirect.
    assign addsub_rhs_xor = addsub_sub ? ~addsub_rhs : addsub_rhs;
    assign addsub_result = addsub_lhs + addsub_rhs_xor + {31'b0, addsub_sub};
    assign mem_addr = addsub_result;
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

    always @(*) begin
        case (funct3)
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
                         ((opcode == OPCODE_SYSTEM) && (funct3 == F3_PRIV)) ||
                         ex_fence_i;

    // Redirect mux.
    always @(*) begin
        ex_redirect_pc = 32'bx;

        case (opcode)
            OPCODE_BRANCH, OPCODE_JAL: begin
                ex_redirect_pc = addsub_result;
            end

            OPCODE_JALR: begin
                ex_redirect_pc = {addsub_result[31:1], 1'b0};
            end

            OPCODE_SYSTEM: begin
                case (funct3)
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

                    default: begin
                    end
                endcase
            end

            OPCODE_MISC_MEM: begin
                case (funct3)
                    F3_FENCE_I: begin
                        ex_redirect_pc = pc4;
                    end

                    default: begin
                    end
                endcase
            end

            default: begin
            end
        endcase
    end

    assign csr_write_data = ({32{csr_wdata_or_sel}} & or_result) |
                            ({32{csr_wdata_and_sel}} & and_result) |
                            ({32{~csr_wdata_or_sel && ~csr_wdata_and_sel}} & csr_src_data);

    always @(posedge clock) begin
        if (reset) begin
            csr_mstatus <= 32'h1800;
            csr_mtvec   <= 32'h1;
            csr_mepc    <= 32'h0;
            csr_mcause  <= 32'h0;
        end else if (fire && (opcode == OPCODE_SYSTEM)) begin
            case (funct3)
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
                        default:;
                    endcase
                end

                F3_CSRRW, F3_CSRRS, F3_CSRRC, F3_CSRRWI, F3_CSRRSI, F3_CSRRCI: begin
                    case (csr_addr)
                        CSR_MSTATUS: csr_mstatus <= csr_write_data;
                        CSR_MTVEC:   csr_mtvec   <= csr_write_data;
                        CSR_MEPC:    csr_mepc    <= csr_write_data;
                        CSR_MCAUSE:  csr_mcause  <= csr_write_data;
                        default:;
                    endcase
                end

                default: begin
                end
            endcase
        end
    end

/////////////////////////
    // LS: lsu_master.

    always @(*) begin
        wmask_calc = 4'b0000;
        lsu_master_wdata = rf_rdata2;
        mem_size = 3'b010;
        case (funct3)
            F3_SB: begin
                mem_size = 3'b000;
                case (mem_offset)
                    2'b00: begin
                        wmask_calc = 4'b0001;
                        lsu_master_wdata = {24'b0, rf_rdata2[7:0]};
                    end
                    2'b01: begin
                        wmask_calc = 4'b0010;
                        lsu_master_wdata = {16'b0, rf_rdata2[7:0], 8'b0};
                    end
                    2'b10: begin
                        wmask_calc = 4'b0100;
                        lsu_master_wdata = {8'b0, rf_rdata2[7:0], 16'b0};
                    end
                    2'b11: begin
                        wmask_calc = 4'b1000;
                        lsu_master_wdata = {rf_rdata2[7:0], 24'b0};
                    end
                endcase
            end
            F3_SH: begin
                mem_size = 3'b001;
                case (mem_offset[1])
                    1'b0: begin
                        wmask_calc = 4'b0011;
                        lsu_master_wdata = {16'b0, rf_rdata2[15:0]};
                    end
                    1'b1: begin
                        wmask_calc = 4'b1100;
                        lsu_master_wdata = {rf_rdata2[15:0], 16'b0};
                    end
                endcase
            end
            F3_LBU: begin
                mem_size = 3'b000;
            end
            F3_LHU: begin
                mem_size = 3'b001;
            end
            default: begin
                wmask_calc = 4'b1111;
                lsu_master_wdata = rf_rdata2;
            end
        endcase
    end

    assign is_clint = (mem_addr[31:16] == CLINT_BASE_HI);
    assign ext_load_req = ex_in_valid && mem_ren && ~is_clint;
    assign ext_store_req = ex_in_valid && mem_wen && ~is_clint;
    assign ext_mem_req = ext_load_req || ext_store_req;
    assign ar_fire = lsu_master_arvalid && lsu_master_arready;
    assign r_fire = lsu_master_rvalid && lsu_master_rready;
    assign aw_fire = lsu_master_awvalid && lsu_master_awready;
    assign w_fire = lsu_master_wvalid && lsu_master_wready;
    assign b_fire = lsu_master_bvalid && lsu_master_bready;
    assign mem_offset = mem_addr[1:0];
    assign load_raw_data = (mem_ren && is_clint) ? local_rdata : lsu_master_rdata;
    assign ready_go = ((mem_state == L_IDLE) && ~ext_mem_req) ||
                      ((mem_state == L_WAIT_R) && r_fire) ||
                      ((mem_state == L_WAIT_B) && b_fire);
    assign ex_in_ready = ~ex_in_valid || ready_go;
    assign fire = ex_in_valid && ready_go;
    assign ex_out_valid = fire;

    assign lsu_master_araddr = mem_addr;
    assign lsu_master_arsize = mem_size;
    assign lsu_master_arvalid = (mem_state == L_IDLE) && ext_load_req;
    assign lsu_master_rready = (mem_state == L_WAIT_R);
    assign lsu_master_awaddr = mem_addr;
    assign lsu_master_awsize = mem_size;
    assign lsu_master_awvalid = ((mem_state == L_IDLE) && ext_store_req) ||
                             (mem_state == L_WAIT_AW);
    assign lsu_master_wstrb = wmask_calc;
    assign lsu_master_wvalid = ((mem_state == L_IDLE) && ext_store_req) ||
                            (mem_state == L_WAIT_W);
    assign lsu_master_bready = (mem_state == L_WAIT_B);

    always @(*) begin
        case (mem_addr[15:2])
            MTIME_WORD_OFFSET:  local_rdata = ex_mtime[31:0];
            MTIMEH_WORD_OFFSET: local_rdata = ex_mtime[63:32];
            default:            local_rdata = 32'b0;
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            mem_state <= L_IDLE;
        end else begin
            case (mem_state)
                L_IDLE: begin
                    if (ext_load_req) begin
                        if (ar_fire) mem_state <= L_WAIT_R;
                    end else if (ext_store_req) begin
                        if (aw_fire && w_fire) mem_state <= L_WAIT_B;
                        else if (aw_fire) mem_state <= L_WAIT_W;
                        else if (w_fire) mem_state <= L_WAIT_AW;
                    end
                end
                L_WAIT_R: if (r_fire) mem_state <= L_IDLE;
                L_WAIT_AW: if (aw_fire) mem_state <= L_WAIT_B;
                L_WAIT_W: if (w_fire) mem_state <= L_WAIT_B;
                L_WAIT_B: if (b_fire) mem_state <= L_IDLE;

                default: mem_state <= L_IDLE;
            endcase
        end
    end

    always @(*) begin
        rdata_decoded = load_raw_data;
        case (funct3)
            F3_LB: begin
                case (mem_offset)
                    2'b00: rdata_decoded = {{24{load_raw_data[7]}}, load_raw_data[7:0]};
                    2'b01: rdata_decoded = {{24{load_raw_data[15]}}, load_raw_data[15:8]};
                    2'b10: rdata_decoded = {{24{load_raw_data[23]}}, load_raw_data[23:16]};
                    2'b11: rdata_decoded = {{24{load_raw_data[31]}}, load_raw_data[31:24]};
                    default: rdata_decoded = 32'b0;
                endcase
            end
            F3_LH: begin
                case (mem_offset[1])
                    1'b0: rdata_decoded = {{16{load_raw_data[15]}}, load_raw_data[15:0]};
                    1'b1: rdata_decoded = {{16{load_raw_data[31]}}, load_raw_data[31:16]};
                    default: rdata_decoded = 32'b0;
                endcase
            end
            F3_LBU: begin
                case (mem_offset)
                    2'b00: rdata_decoded = {24'b0, load_raw_data[7:0]};
                    2'b01: rdata_decoded = {24'b0, load_raw_data[15:8]};
                    2'b10: rdata_decoded = {24'b0, load_raw_data[23:16]};
                    2'b11: rdata_decoded = {24'b0, load_raw_data[31:24]};
                    default: rdata_decoded = 32'b0;
                endcase
            end
            F3_LHU: begin
                case (mem_offset[1])
                    1'b0: rdata_decoded = {16'b0, load_raw_data[15:0]};
                    1'b1: rdata_decoded = {16'b0, load_raw_data[31:16]};
                    default: rdata_decoded = 32'b0;
                endcase
            end
            default: rdata_decoded = load_raw_data;
        endcase
    end


/////////////////////////
    // WB: output mux and RF write.
    assign rf_write = fire && rf_wen && (rf_waddr != 5'b0) && ~rf_waddr[4];

    always @(*) begin
        rf_wdata = 32'bx;
        case (opcode)
            OPCODE_OP, OPCODE_OP_IMM: begin
                case (funct3)
                    F3_ADD_SUB:         rf_wdata = addsub_result;
                    F3_SLL:             rf_wdata = sll_result;
                    F3_SLT:             rf_wdata = {31'b0, cmp_lt};
                    F3_SLTU:            rf_wdata = {31'b0, cmp_ltu};
                    F3_XOR:             rf_wdata = xor_result;
                    F3_SRL_SRA:         rf_wdata = funct7_5 ? sra_result : srl_result;
                    F3_OR:              rf_wdata = or_result;
                    F3_AND:             rf_wdata = and_result;
                    default:;
                endcase
            end
            OPCODE_LUI:                 rf_wdata = imm;
            OPCODE_AUIPC:               rf_wdata = addsub_result;
            OPCODE_LOAD:                rf_wdata = rdata_decoded;
            OPCODE_JAL, OPCODE_JALR:    rf_wdata = pc4;
            OPCODE_SYSTEM:              rf_wdata = csr_rdata;
            default:;
        endcase
    end

    always @(posedge clock) begin
        if (rf_write) begin
            reg_bank[rf_waddr[3:0]] <= rf_wdata;
        end
    end

endmodule
