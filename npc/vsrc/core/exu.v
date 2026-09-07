module ysyx_26030082_exu (
    input  wire        clock,
    input  wire        reset,
    input  wire        ex_in_valid,
    output wire        ex_in_ready,
    output wire        ex_out_valid,
    input  wire        ex_out_ready,

    // ALU inputs
    input  wire        ex_ALUSrcA,
    input  wire        ex_ALUSrcB,
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_rR1_data,
    input  wire [31:0] ex_rR2_data,
    input  wire [ 2:0] ex_funct3,
    input  wire [31:0] ex_imm,
    input  wire [ 3:0] ex_ALUControl,

    // CSR inputs
    input  wire        ex_is_system,
    input  wire [11:0] ex_CSRaddr,

    // Control for WB data selection
    input  wire [ 2:0] ex_MemToReg,

    // Outputs
    output wire [31:0] ex_ALUResult,
    output wire        ex_BRUResult,
    output wire [31:0] ex_pc4,

    output wire        ex_CSRjump,
    output reg  [31:0] ex_CSRnpc,

    output wire [31:0] ex_RFwdata,
    output wire        ex_MemRead
);

    localparam [3:0] ALU_ADD  = 4'b0000;
    localparam [3:0] ALU_SUB  = 4'b1000;
    localparam [3:0] ALU_SLL  = 4'b0001;
    localparam [3:0] ALU_SLT  = 4'b0010;
    localparam [3:0] ALU_SLTU = 4'b0011;
    localparam [3:0] ALU_XOR  = 4'b0100;
    localparam [3:0] ALU_SRL  = 4'b0101;
    localparam [3:0] ALU_SRA  = 4'b1101;
    localparam [3:0] ALU_OR   = 4'b0110;
    localparam [3:0] ALU_AND  = 4'b0111;

    localparam [11:0] CSR_MSTATUS   = 12'h300;
    localparam [11:0] CSR_MTVEC     = 12'h305;
    localparam [11:0] CSR_MEPC      = 12'h341;
    localparam [11:0] CSR_MCAUSE    = 12'h342;
    localparam [11:0] CSR_MVENDORID = 12'hF11;
    localparam [11:0] CSR_MARCHID   = 12'hF12;

    localparam [31:0] CAUSE_ECALL = 32'd11;
    localparam [11:0] INST_ECALL  = 12'h000;
    localparam [11:0] INST_MRET   = 12'h302;

    wire [31:0] ex_A;
    wire [31:0] ex_B;
    reg  [31:0] ex_CSRrdata;

    assign ex_in_ready  = ~ex_in_valid || ex_out_ready;
    assign ex_out_valid = ex_in_valid;

    assign ex_A   = ex_ALUSrcA ? ex_pc      : ex_rR1_data;
    assign ex_B   = ex_ALUSrcB ? ex_imm     : ex_rR2_data;
    assign ex_pc4 = ex_pc + 32'd4;

    // ALU
    wire [31:0] ex_add_sub_result;
    wire [31:0] ex_and_result;
    wire [31:0] ex_or_result;
    wire [31:0] ex_xor_result;
    wire [31:0] ex_sll_result;
    wire [31:0] ex_srl_result;
    wire [31:0] ex_sra_result;
    wire        ex_is_sub_family;
    wire        ex_cmp_lt;
    wire        ex_cmp_ltu;
    wire        ex_bru_cmp_eq;
    wire        ex_bru_cmp_lt;
    wire        ex_bru_cmp_ltu;
    wire [31:0] ex_adder_a;
    wire [31:0] ex_adder_b;
    wire        ex_adder_cin;
    wire        ex_adder_carry;
    reg  [31:0] ex_result;

    assign ex_adder_a = ex_A;
    assign ex_is_sub_family = (ex_ALUControl == ALU_SUB) ||
                              (ex_ALUControl == ALU_SLT) ||
                              (ex_ALUControl == ALU_SLTU);
    assign ex_adder_b = ex_is_sub_family ? ~ex_B : ex_B;
    assign ex_adder_cin = ex_is_sub_family;
    assign {ex_adder_carry, ex_add_sub_result} =
        ex_adder_a + ex_adder_b + ex_adder_cin;

    assign ex_and_result = ex_A & ex_B;
    assign ex_or_result  = ex_A | ex_B;
    assign ex_xor_result = ex_A ^ ex_B;
    assign ex_sll_result = ex_A << ex_B[4:0];
    assign ex_srl_result = ex_A >> ex_B[4:0];
    assign ex_sra_result = ($signed(ex_A)) >>> ex_B[4:0];
    assign ex_cmp_lt = (ex_A[31] & ~ex_B[31]) |
                       ((~ex_A[31] ^ ex_B[31]) & ex_add_sub_result[31]);
    assign ex_cmp_ltu = ~ex_adder_carry;
    assign ex_bru_cmp_eq  = (ex_rR1_data == ex_rR2_data);
    assign ex_bru_cmp_lt  = ($signed(ex_rR1_data) < $signed(ex_rR2_data));
    assign ex_bru_cmp_ltu = (ex_rR1_data < ex_rR2_data);

    always @(*) begin
        case (ex_ALUControl)
            ALU_ADD:  ex_result = ex_add_sub_result;
            ALU_SUB:  ex_result = ex_add_sub_result;
            ALU_AND:  ex_result = ex_and_result;
            ALU_OR:   ex_result = ex_or_result;
            ALU_XOR:  ex_result = ex_xor_result;
            ALU_SLL:  ex_result = ex_sll_result;
            ALU_SRL:  ex_result = ex_srl_result;
            ALU_SRA:  ex_result = ex_sra_result;
            ALU_SLT:  ex_result = {31'b0, ex_cmp_lt};
            ALU_SLTU: ex_result = {31'b0, ex_cmp_ltu};
            default:  ex_result = 32'b0;
        endcase
    end

    assign ex_ALUResult = ex_result;
    assign ex_BRUResult = (ex_funct3 == 3'b000) ? ex_bru_cmp_eq  :
                          (ex_funct3 == 3'b001) ? ~ex_bru_cmp_eq :
                          (ex_funct3 == 3'b100) ? ex_bru_cmp_lt  :
                          (ex_funct3 == 3'b101) ? ~ex_bru_cmp_lt :
                          (ex_funct3 == 3'b110) ? ex_bru_cmp_ltu :
                          (ex_funct3 == 3'b111) ? ~ex_bru_cmp_ltu :
                                                   1'b0;

    // CSR
    reg [31:0] mstatus;
    reg [31:0] mtvec;
    reg [31:0] mepc;
    reg [31:0] mcause;

    wire        csr_is_imm = ex_funct3[2];
    wire [31:0] csr_wdata = csr_is_imm ? ex_imm : ex_rR1_data;
    wire        csr_priv = ex_is_system && ex_in_valid && ex_out_ready &&
                           (ex_funct3 == 3'b000);
    wire        csr_ecall = csr_priv && (ex_CSRaddr == INST_ECALL);

    always @(*) begin
        case (ex_CSRaddr)
            CSR_MSTATUS:   ex_CSRrdata = mstatus;
            CSR_MTVEC:     ex_CSRrdata = mtvec;
            CSR_MEPC:      ex_CSRrdata = mepc;
            CSR_MCAUSE:    ex_CSRrdata = mcause;
            CSR_MVENDORID: ex_CSRrdata = 32'h7973_7978;
            CSR_MARCHID:   ex_CSRrdata = 32'd26030082;
            default:       ex_CSRrdata = 32'b0;
        endcase
    end

    assign ex_CSRjump = csr_priv;

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

            if (ex_is_system && ex_in_valid && ex_out_ready) begin
                case (ex_funct3)
                    3'b000: begin
                        case (ex_CSRaddr)
                            INST_ECALL: begin
                                mstatus[3] <= 1'b0;
                                mstatus[7] <= mstatus[3];
                                mstatus[12:11] <= 2'b11;
                                mepc <= ex_pc;
                                mcause <= CAUSE_ECALL;
                            end
                            INST_MRET: begin
                                mstatus[3] <= mstatus[7];
                                mstatus[7] <= 1'b1;
                                mstatus[12:11] <= 2'b00;
                            end
                            default: begin
                            end
                        endcase
                    end

                    3'b001,
                    3'b101: begin
                        case (ex_CSRaddr)
                            CSR_MSTATUS: mstatus <= csr_wdata;
                            CSR_MTVEC:   mtvec   <= csr_wdata;
                            CSR_MEPC:    mepc    <= csr_wdata;
                            default: begin
                            end
                        endcase
                    end

                    3'b010,
                    3'b110: begin
                        case (ex_CSRaddr)
                            CSR_MSTATUS: mstatus <= mstatus | csr_wdata;
                            CSR_MTVEC:   mtvec   <= mtvec | csr_wdata;
                            CSR_MEPC:    mepc    <= mepc | csr_wdata;
                            default: begin
                            end
                        endcase
                    end

                    3'b011,
                    3'b111: begin
                        case (ex_CSRaddr)
                            CSR_MSTATUS: mstatus <= mstatus & ~csr_wdata;
                            CSR_MTVEC:   mtvec   <= mtvec & ~csr_wdata;
                            CSR_MEPC:    mepc    <= mepc & ~csr_wdata;
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

    always @(*) begin
        if (csr_ecall) ex_CSRnpc = {mtvec[31:2], 2'b0};
        else           ex_CSRnpc = mepc;
    end

    assign ex_RFwdata = ex_MemToReg[1] ?
                        (ex_MemToReg[0] ? ex_imm : ex_CSRrdata) :
                        (ex_MemToReg[0] ? ex_ALUResult : ex_pc4);
    assign ex_MemRead = ex_MemToReg[2];

endmodule
