`timescale 1ns / 1ps

`include "defines.v"

// CSRControl
`define CCTL_csrrw      5'b00001
`define CCTL_csrrs      5'b00010
`define CCTL_csrrc      5'b00100
`define CCTL_ecall      5'b01000
`define CCTL_mret       5'b10000

module CSR (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,     // me1段触发跳转，后续csr写入操作无效，保证原子性

    input  wire [ 4:0] CSRControl, // one-hot CCTL
    input  wire [11:0] CSRaddr,
    input  wire        CSRSrc,     // CSR写入选择
    input  wire [31:0] rR1_data,   // CSR写入寄存器值(csrrx),已递进
    input  wire [31:0] imm,        // CSR写入立即数(csrrxi)

    input  wire [31:0] pc,         // CSR所在EX段的pc
    input  wire [ 3:0] exception,  // 异常
    input  wire [ 3:0] interrupt,  // 中断

    output reg  [31:0] CSRrdata,   // CSR读出数据
    output wire        CSRjump,    // CSR触发跳转 PCTrap
    output reg  [31:0] CSRnpc      // CSR跳转pc
);

    localparam [11:0] CSR_mstatus   = 12'h300;
    localparam [11:0] CSR_mtvec     = 12'h305;
    localparam [11:0] CSR_mscratch  = 12'h340;
    localparam [11:0] CSR_mepc      = 12'h341;
    localparam [11:0] CSR_mcause    = 12'h342;
    localparam [11:0] CSR_mtval     = 12'h343;
    localparam [11:0] CSR_mcycle    = 12'hB00;
    localparam [11:0] CSR_mcycleh   = 12'hB80;
    localparam [11:0] CSR_mvendorid = 12'hF11;
    localparam [11:0] CSR_marchid   = 12'hF12;

    reg  [31:0] mstatus, mtvec;
    reg  [31:0] mscratch, mepc, mcause, mtval;
    reg  [63:0] mcycle;

    localparam [3:0]  EXC_NONE      = 4'd10;
    localparam [31:0] CAUSE_NONE    = 32'd10;
    localparam [31:0] CAUSE_ECALL_M = 32'd11;

    wire        ecall = CSRControl[3];
    wire        mret  = CSRControl[4];
    wire [31:0] CSRwdata = CSRSrc ? imm : rR1_data;  // csrrxi: imm, csrrx: rR1

    wire        has_exception   = (exception != EXC_NONE);
    wire        has_interrupt   = (interrupt != 0);
    wire        sync_trap_req   = (ecall || has_exception) && !flush;
    wire        irq_trap_req    = has_interrupt && mstatus[3] && (pc != 0) && !flush;
    wire        trap_taken      = sync_trap_req || irq_trap_req;
    wire        trap_is_interrupt = irq_trap_req && !sync_trap_req;
    wire        mret_taken      = mret && !flush;
    wire [31:0] trap_cause_code = ecall ? CAUSE_ECALL_M :
                                   has_exception ? {28'b0, exception} :
                                   has_interrupt ? {28'b0, interrupt} :
                                                   CAUSE_NONE;
    wire [31:0] trap_vector_base = {mtvec[31:2], 2'b0};
    wire [31:0] trap_vector = (mtvec[0] && trap_is_interrupt) ?
                               (trap_vector_base + (trap_cause_code << 2)) :
                               trap_vector_base;

    // CSR read
    always @(*) begin
        case(CSRaddr)
            CSR_mstatus:   CSRrdata = mstatus;
            CSR_mtvec:     CSRrdata = mtvec;
            CSR_mscratch:  CSRrdata = mscratch;
            CSR_mepc:      CSRrdata = mepc;
            CSR_mcause:    CSRrdata = mcause;
			CSR_mtval:		CSRrdata = mtval;
            CSR_mcycle:    CSRrdata = mcycle[31:0];
            CSR_mcycleh:   CSRrdata = mcycle[63:32];
            CSR_mvendorid: CSRrdata = 32'h7973_7978;
            CSR_marchid:   CSRrdata = 32'd26030082;
            default:        CSRrdata = 0;
        endcase
    end

    assign CSRjump = trap_taken || mret_taken;

    // mstatus
    always @(posedge clk) begin
		if (rst) begin
            mstatus <= 32'b1010;
		end else if (flush) begin
			mstatus <= mstatus;
        end else if (trap_taken) begin
            mstatus[3] <= 0;
            mstatus[7] <= mstatus[3];
            mstatus[12:11] <= 3;        // privilege M-mode 3
        end else begin
			case (CSRControl)
				`CCTL_csrrw: if (CSRaddr == CSR_mstatus) mstatus <= CSRwdata;
				`CCTL_csrrs: if (CSRaddr == CSR_mstatus) mstatus <= (mstatus | CSRwdata);
                `CCTL_csrrc: if (CSRaddr == CSR_mstatus) mstatus <= (mstatus & ~CSRwdata);

				/*`CCTL_ecall: begin
					mstatus[7]  	<= mstatus[3];  	// MPIE <= 当前 MIE
					mstatus[3]  	<= 1'b0;        	// MIE <= 0
					mstatus[12:11] 	<= 2'b11;    		// MPP <= M模式
				end*/
				`CCTL_mret: begin
					mstatus[3]  	<= mstatus[7];  	// MIE <= MPIE
				end
				default: mstatus <= mstatus; // 保持原值
			endcase
		end
	end

    // mcause
    always @(posedge clk) begin
		if (rst) begin
			mcause <= 32'h0;
		end else if (flush) begin
			mcause <= mcause;
        end else if (trap_taken) begin
            mcause <= {trap_is_interrupt, trap_cause_code[30:0]};
        end else begin
			case (CSRControl)
                /*`CCTL_csrrw: if (CSRaddr == CSR_mcause) mcause <= CSRwdata;
				`CCTL_csrrs: if (CSRaddr == CSR_mcause) mcause <= mcause | CSRwdata;
                `CCTL_csrrc: if (CSRaddr == CSR_mcause) mcause <= mcause & ~CSRwdata;*/

				/*`CCTL_ecall: mcause <= 32'h0b;  // environment call from M-mode*/
				default: mcause <= mcause;
			endcase
		end
	end

    // mepc
    always @(posedge clk) begin
		if (rst) begin
			mepc <= 32'h0;
		end else if (flush) begin
			mepc <= mepc;
        end else if (trap_taken) begin
            mepc <= pc;
        end else begin
			case (CSRControl)
                `CCTL_csrrw: if (CSRaddr == CSR_mepc) mepc <= CSRwdata;
				`CCTL_csrrs: if (CSRaddr == CSR_mepc) mepc <= mepc | CSRwdata;
                `CCTL_csrrc: if (CSRaddr == CSR_mepc) mepc <= mepc & ~CSRwdata;

				/*`CCTL_ecall: mepc <= pc;*/
				default: mepc <= mepc;
			endcase
		end
	end

    // mscratch
    always @(posedge clk) begin
        if (rst) begin
            mscratch <= 0;
		end else if (flush) begin
			mscratch <= mscratch;
        end else if (trap_taken) begin
            mscratch <= mscratch;
        end else begin
            case (CSRControl)
                `CCTL_csrrw: if (CSRaddr == CSR_mscratch) mscratch <= CSRwdata;              // CSRRW
                `CCTL_csrrs: if (CSRaddr == CSR_mscratch) mscratch <= mscratch | CSRwdata;   // CSRRS
                `CCTL_csrrc: if (CSRaddr == CSR_mscratch) mscratch <= mscratch & ~CSRwdata;  // CSRRC

                default: mscratch <= mscratch;
            endcase
        end
    end


	// mtvec
	always @(posedge clk) begin
		if (rst) begin
            mtvec <= 1;
		end else if (flush) begin
			mtvec <= mtvec;
        end else if (trap_taken) begin
            mtvec <= mtvec;
		end else begin
			case (CSRControl)
                `CCTL_csrrw: if (CSRaddr == CSR_mtvec) mtvec <= CSRwdata;
				`CCTL_csrrs: if (CSRaddr == CSR_mtvec) mtvec <= mtvec | CSRwdata;
                `CCTL_csrrc: if (CSRaddr == CSR_mtvec) mtvec <= mtvec & ~CSRwdata;

				default: mtvec <= mtvec;
			endcase
		end
	end

    // mtval
    always @(posedge clk) begin
        if (rst) begin
            mtval <= 32'b0;
		end else if (flush) begin
			mtval <= mtval;
        end else if (trap_taken) begin
            mtval <= mtval;
        end else begin
            case (CSRControl)
                `CCTL_csrrw: if (CSRaddr == CSR_mtval) mtval <= CSRwdata;
                `CCTL_csrrs: if (CSRaddr == CSR_mtval) mtval <= mtval | CSRwdata;
                `CCTL_csrrc: if (CSRaddr == CSR_mtval) mtval <= mtval & ~CSRwdata;

				/*`CCTL_ecall: mtval <= '0;*/
                default: mtval <= mtval;
            endcase
        end
    end

    // mcycle/mcycleh
    always @(posedge clk) begin
        if (rst) begin
            mcycle <= 64'b0;
        end else begin
            mcycle <= mcycle + 64'd1;
        end
    end

    // CSRnpc
    always @(*) begin
        if (rst)                                    CSRnpc = 0;
        else if (trap_taken)                        CSRnpc = trap_vector;
        else if (mret_taken)                        CSRnpc = mepc;
        else                                        CSRnpc = mepc;
    end
    
endmodule
