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

    localparam [31:0] CAUSE_ECALL = 32'd11;

    localparam [11:0] INST_ECALL = 12'h000;
    localparam [11:0] INST_MRET  = 12'h302;
    localparam [2:0]  F3_CSRRW   = 3'b001;
    localparam [2:0]  F3_CSRRS   = 3'b010;
    localparam [2:0]  F3_CSRRC   = 3'b011;
    localparam [2:0]  F3_CSRRWI  = 3'b101;
    localparam [2:0]  F3_CSRRSI  = 3'b110;
    localparam [2:0]  F3_CSRRCI  = 3'b111;

    wire        csr_is_imm = funct3[2];
    wire [31:0] CSRwdata = csr_is_imm ? imm : rR1_data;  // csrrxi: imm, csrrx: rR1

    wire [31:0] trap_vector = {mtvec[31:2], 2'b0};
    wire        csr_priv = is_system && (funct3 == 3'b000);
    wire        csr_ecall = csr_priv && (CSRaddr == INST_ECALL);
    wire        csr_mret  = csr_priv && (CSRaddr == INST_MRET);

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

    assign CSRjump = csr_ecall || csr_mret;

    // SYSTEM instructions alone are allowed to update CSR state.
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

            if (is_system) begin
                case (funct3)
                    3'b000: begin
                        case (CSRaddr)
                            INST_ECALL: begin
                                mstatus[3] <= 1'b0;
                                mstatus[7] <= mstatus[3];
                                mstatus[12:11] <= 2'b11;
                                mepc <= pc;
                                mcause <= CAUSE_ECALL;
                            end
                            INST_MRET: begin
                                mstatus[3] <= mstatus[7];
                            end
                            default: begin
                            end
                        endcase
                    end

                    F3_CSRRW,
                    F3_CSRRWI: begin
                        case (CSRaddr)
                            CSR_mstatus: mstatus <= CSRwdata;
                            CSR_mtvec:   mtvec   <= CSRwdata;
                            CSR_mepc:    mepc    <= CSRwdata;
                            default: begin
                            end
                        endcase
                    end

                    F3_CSRRS,
                    F3_CSRRSI: begin
                        case (CSRaddr)
                            CSR_mstatus: mstatus <= mstatus | CSRwdata;
                            CSR_mtvec:   mtvec   <= mtvec | CSRwdata;
                            CSR_mepc:    mepc    <= mepc | CSRwdata;
                            default: begin
                            end
                        endcase
                    end

                    F3_CSRRC,
                    F3_CSRRCI: begin
                        case (CSRaddr)
                            CSR_mstatus: mstatus <= mstatus & ~CSRwdata;
                            CSR_mtvec:   mtvec   <= mtvec & ~CSRwdata;
                            CSR_mepc:    mepc    <= mepc & ~CSRwdata;
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
        else if (csr_ecall)                         CSRnpc = {mtvec[31:2], 2'b0};
        else if (csr_mret)                          CSRnpc = mepc;
        else                                        CSRnpc = mepc;
    end
    
endmodule
