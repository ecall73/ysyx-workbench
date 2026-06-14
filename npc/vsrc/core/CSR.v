module ysyx_26030082_CSR (
    input  wire        clock,
    input  wire        reset,

    input  wire        is_system,
    input  wire [11:0] CSRaddr,
    input  wire [ 2:0] funct3,
    input  wire [31:0] rR1_data,   // CSR写入寄存器值(csrrx),已递进
    input  wire [31:0] imm,        // CSR写入立即数(csrrxi)

    input  wire [31:0] pc,         // CSR所在EX段的pc

    output reg  [31:0] CSRrdata,   // CSR读出数据
    output wire        CSRjump,    // CSR触发跳转 PCTrap
    output reg  [31:0] CSRnpc      // CSR跳转pc
);

    localparam [11:0] CSR_mstatus   = 12'h300;
    localparam [11:0] CSR_mtvec     = 12'h305;
    localparam [11:0] CSR_mepc      = 12'h341;
    localparam [11:0] CSR_mcause    = 12'h342;
    localparam [11:0] CSR_mvendorid = 12'hF11;
    localparam [11:0] CSR_marchid   = 12'hF12;

    reg  [31:0] mstatus, mtvec, mepc, mcause;

    localparam [31:0] CAUSE_ECALL_M = 32'd11;

    localparam [11:0] INST_ECALL = 12'h000;
    localparam [11:0] INST_MRET  = 12'h302;
    localparam [2:0]  F3_CSRRW   = 3'b001;
    localparam [2:0]  F3_CSRRS   = 3'b010;
    localparam [2:0]  F3_CSRRC   = 3'b011;
    localparam [2:0]  F3_CSRRWI  = 3'b101;
    localparam [2:0]  F3_CSRRSI  = 3'b110;
    localparam [2:0]  F3_CSRRCI  = 3'b111;
    localparam [1:0]  CSR_OP_NONE = 2'b00;
    localparam [1:0]  CSR_OP_RW   = 2'b01;
    localparam [1:0]  CSR_OP_RS   = 2'b10;
    localparam [1:0]  CSR_OP_RC   = 2'b11;
    localparam [1:0]  CSR_DST_NONE    = 2'b00;
    localparam [1:0]  CSR_DST_MSTATUS = 2'b01;
    localparam [1:0]  CSR_DST_MTVEC   = 2'b10;
    localparam [1:0]  CSR_DST_MEPC    = 2'b11;

    wire        csr_is_imm = funct3[2];
    wire [31:0] CSRwdata = csr_is_imm ? imm : rR1_data;  // csrrxi: imm, csrrx: rR1

    reg         trap_ecall;
    reg         trap_mret;
    reg  [1:0] csr_write_op;
    reg  [1:0] csr_write_dst;

    wire        trap_is_interrupt = 1'b0;
    wire [31:0] trap_cause_code = CAUSE_ECALL_M;
    wire [31:0] trap_vector = {mtvec[31:2], 2'b0};

    always @(*) begin
        trap_ecall   = 1'b0;
        trap_mret    = 1'b0;
        csr_write_op = CSR_OP_NONE;
        csr_write_dst = CSR_DST_NONE;

        if (is_system) begin
            case (funct3)
                3'b000: begin
                    case (CSRaddr)
                        INST_ECALL: trap_ecall = 1'b1;
                        INST_MRET:  trap_mret = 1'b1;
                        default: begin
                        end
                    endcase
                end

                F3_CSRRW,
                F3_CSRRWI: begin
                    csr_write_op = CSR_OP_RW;
                    case (CSRaddr)
                        CSR_mstatus: csr_write_dst = CSR_DST_MSTATUS;
                        CSR_mtvec:   csr_write_dst = CSR_DST_MTVEC;
                        CSR_mepc:    csr_write_dst = CSR_DST_MEPC;
                        default: begin
                        end
                    endcase
                end

                F3_CSRRS,
                F3_CSRRSI: begin
                    csr_write_op = CSR_OP_RS;
                    case (CSRaddr)
                        CSR_mstatus: csr_write_dst = CSR_DST_MSTATUS;
                        CSR_mtvec:   csr_write_dst = CSR_DST_MTVEC;
                        CSR_mepc:    csr_write_dst = CSR_DST_MEPC;
                        default: begin
                        end
                    endcase
                end

                F3_CSRRC,
                F3_CSRRCI: begin
                    csr_write_op = CSR_OP_RC;
                    case (CSRaddr)
                        CSR_mstatus: csr_write_dst = CSR_DST_MSTATUS;
                        CSR_mtvec:   csr_write_dst = CSR_DST_MTVEC;
                        CSR_mepc:    csr_write_dst = CSR_DST_MEPC;
                        default: begin
                        end
                    endcase
                end

                default: begin
                end
            endcase
        end
    end

    // CSR read
    always @(*) begin
        case(CSRaddr)
            CSR_mstatus:   CSRrdata = mstatus;
            CSR_mtvec:     CSRrdata = mtvec;
            CSR_mepc:      CSRrdata = mepc;
            CSR_mcause:    CSRrdata = mcause;
            CSR_mvendorid: CSRrdata = 32'h7973_7978;
            CSR_marchid:   CSRrdata = 32'd26030082;
            default:        CSRrdata = 0;
        endcase
    end

    assign CSRjump = trap_ecall || trap_mret;

    // Write-side decode is shared across all CSRs so synthesis can reuse the SYSTEM/CSR address checks.
    always @(posedge clock) begin
        if (reset) begin
            mstatus <= 32'h1800;
            mtvec   <= 32'h1;
            mepc    <= 32'h0;
            mcause  <= 32'h0;
        end else begin
            mstatus <= mstatus;
            mtvec   <= mtvec;
            mepc    <= mepc;
            mcause  <= mcause;

            if (trap_ecall) begin
                mstatus[3] <= 1'b0;
                mstatus[7] <= mstatus[3];
                mstatus[12:11] <= 2'b11;
                mepc <= pc;
                mcause <= {trap_is_interrupt, trap_cause_code[30:0]};
            end else if (trap_mret) begin
                mstatus[3] <= mstatus[7];
            end else begin
                case (csr_write_op)
                    CSR_OP_RW: begin
                        case (csr_write_dst)
                            CSR_DST_MSTATUS: mstatus <= CSRwdata;
                            CSR_DST_MTVEC:   mtvec   <= CSRwdata;
                            CSR_DST_MEPC:    mepc    <= CSRwdata;
                            default: begin
                            end
                        endcase
                    end

                    CSR_OP_RS: begin
                        case (csr_write_dst)
                            CSR_DST_MSTATUS: mstatus <= mstatus | CSRwdata;
                            CSR_DST_MTVEC:   mtvec   <= mtvec | CSRwdata;
                            CSR_DST_MEPC:    mepc    <= mepc | CSRwdata;
                            default: begin
                            end
                        endcase
                    end

                    CSR_OP_RC: begin
                        case (csr_write_dst)
                            CSR_DST_MSTATUS: mstatus <= mstatus & ~CSRwdata;
                            CSR_DST_MTVEC:   mtvec   <= mtvec & ~CSRwdata;
                            CSR_DST_MEPC:    mepc    <= mepc & ~CSRwdata;
                            default: begin
                            end
                        endcase
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

    // CSRnpc
    always @(*) begin
        if (reset)                                    CSRnpc = 0;
        else if (trap_ecall)                        CSRnpc = trap_vector;
        else if (trap_mret)                         CSRnpc = mepc;
        else                                        CSRnpc = mepc;
    end
    
endmodule
