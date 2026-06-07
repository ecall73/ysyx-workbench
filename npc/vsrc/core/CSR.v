`timescale 1ns / 1ps

module CSR (
    input  wire        clock,
    input  wire        reset,

    input  wire        system,
    input  wire [ 2:0] funct3,
    input  wire [11:0] CSRaddr,
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
    localparam [11:0] CSR_mcycle    = 12'hB00;
    localparam [11:0] CSR_mcycleh   = 12'hB80;
    localparam [11:0] CSR_mvendorid = 12'hF11;
    localparam [11:0] CSR_marchid   = 12'hF12;

    reg  [31:0] mstatus, mtvec, mepc, mcause;
    reg  [63:0] mcycle;

    localparam [31:0] CAUSE_ECALL_M = 32'd11;

    wire        csr_rw = system && (funct3[1:0] == 2'b01);
    wire        csr_rs = system && (funct3[1:0] == 2'b10);
    wire        csr_rc = system && (funct3[1:0] == 2'b11);
    wire        csr_sys0 = system && (funct3 == 3'b000);
    wire        ecall = csr_sys0 && (CSRaddr == 12'h000);
    wire        mret  = csr_sys0 && (CSRaddr == 12'h302);
    wire [31:0] CSRwdata = funct3[2] ? imm : rR1_data;  // csrrxi: imm, csrrx: rR1

    wire        sync_trap_req   = ecall;
    wire        trap_taken      = sync_trap_req;
    wire        trap_is_interrupt = 1'b0;
    wire        mret_taken      = mret;
    wire [31:0] trap_cause_code = CAUSE_ECALL_M;
    wire [31:0] trap_vector = {mtvec[31:2], 2'b0};

    // CSR read
    always @(*) begin
        case(CSRaddr)
            CSR_mstatus:   CSRrdata = mstatus;
            CSR_mtvec:     CSRrdata = mtvec;
            CSR_mepc:      CSRrdata = mepc;
            CSR_mcause:    CSRrdata = mcause;
            CSR_mcycle:    CSRrdata = mcycle[31:0];
            CSR_mcycleh:   CSRrdata = mcycle[63:32];
            CSR_mvendorid: CSRrdata = 32'h7973_7978;
            CSR_marchid:   CSRrdata = 32'd26030082;
            default:        CSRrdata = 0;
        endcase
    end

    assign CSRjump = trap_taken || mret_taken;

    // mstatus
    always @(posedge clock) begin
		if (reset) begin
            mstatus <= 32'h1800;
        end else if (trap_taken) begin
            mstatus[3] <= 0;
            mstatus[7] <= mstatus[3];
            mstatus[12:11] <= 3;        // privilege M-mode 3
        end else begin
                if (csr_rw && (CSRaddr == CSR_mstatus)) begin
                    mstatus <= CSRwdata;
                end else if (csr_rs && (CSRaddr == CSR_mstatus)) begin
                    mstatus <= (mstatus | CSRwdata);
                end else if (csr_rc && (CSRaddr == CSR_mstatus)) begin
                    mstatus <= (mstatus & ~CSRwdata);
                end else if (mret) begin
                    mstatus[3] <= mstatus[7];   // MIE <= MPIE
                end else begin
                    mstatus <= mstatus; // 保持原值
                end
			end
		end

    // mcause
    always @(posedge clock) begin
		if (reset) begin
			mcause <= 32'h0;
        end else if (trap_taken) begin
            mcause <= {trap_is_interrupt, trap_cause_code[30:0]};
        end else begin
                mcause <= mcause;
			end
		end

    // mepc
    always @(posedge clock) begin
		if (reset) begin
			mepc <= 32'h0;
        end else if (trap_taken) begin
            mepc <= pc;
        end else begin
                if (csr_rw && (CSRaddr == CSR_mepc)) begin
                    mepc <= CSRwdata;
                end else if (csr_rs && (CSRaddr == CSR_mepc)) begin
                    mepc <= mepc | CSRwdata;
                end else if (csr_rc && (CSRaddr == CSR_mepc)) begin
                    mepc <= mepc & ~CSRwdata;
                end else begin
                    mepc <= mepc;
                end
			end
		end

	// mtvec
	always @(posedge clock) begin
		if (reset) begin
            mtvec <= 1;
        end else if (trap_taken) begin
            mtvec <= mtvec;
		end else begin
                if (csr_rw && (CSRaddr == CSR_mtvec)) begin
                    mtvec <= CSRwdata;
                end else if (csr_rs && (CSRaddr == CSR_mtvec)) begin
                    mtvec <= mtvec | CSRwdata;
                end else if (csr_rc && (CSRaddr == CSR_mtvec)) begin
                    mtvec <= mtvec & ~CSRwdata;
                end else begin
                    mtvec <= mtvec;
                end
			end
		end

    // mcycle/mcycleh
    always @(posedge clock) begin
        if (reset) begin
            mcycle <= 64'b0;
        end else begin
            mcycle <= mcycle + 64'd1;
        end
    end

    // CSRnpc
    always @(*) begin
        if (reset)                                    CSRnpc = 0;
        else if (trap_taken)                        CSRnpc = trap_vector;
        else if (mret_taken)                        CSRnpc = mepc;
        else                                        CSRnpc = mepc;
    end
    
endmodule
