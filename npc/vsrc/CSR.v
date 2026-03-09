`timescale 1ns / 1ps

`include "defines.v"

// 机器状态寄存器
`define CSR_mstatus     12'h300
`define CSR_medeleg     12'h302
`define CSR_mideleg     12'h303
`define CSR_mie         12'h304
`define CSR_mtvec       12'h305

// 机器模式异常/中断管理
`define CSR_mscratch    12'h340
`define CSR_mepc        12'h341
`define CSR_mcause      12'h342
`define CSR_mtval       12'h343
`define CSR_mip         12'h344

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

    reg  [31:0] mstatus, mtvec;
    reg  [31:0] mscratch, mepc, mcause, mtval;

    reg  [31:0] cause;
    wire        interrupt_valid;

    wire [31:0] CSRwdata;

    wire        ecall, mret;
    assign ecall = CSRControl[3];
    assign mret = CSRControl[4];

    // csrrwi/csrrsi/csrrci写入imm，csrrw/csrrs/csrrc写入rR1_data
    assign CSRwdata = CSRSrc ? imm : rR1_data;

    // CSR read
    always @(*) begin
        case(CSRaddr)
            `CSR_mstatus:   CSRrdata = mstatus;
            `CSR_mtvec:     CSRrdata = mtvec;
            `CSR_mscratch:  CSRrdata = mscratch;
            `CSR_mepc:      CSRrdata = mepc;
            `CSR_mcause:    CSRrdata = mcause;
			`CSR_mtval:		CSRrdata = mtval;
            default:        CSRrdata = 0;
        endcase
    end

    // cause
    always @(*) begin
        if (ecall)                  cause = 11;         // ecall
        else if (exception != 10)   cause = {28'b0, exception};
        else if (interrupt != 0)    cause = {28'b0, interrupt};
        else                        cause = 10;
    end

    // interrupt_valid
    assign interrupt_valid = (interrupt != 0) && mstatus[3] && (pc != 0) && ~flush;

    assign CSRjump = (cause != 10 && exception != 10) || interrupt_valid || mret;

    // mstatus
    always @(posedge clk) begin
		if (rst) begin
            mstatus <= 32'b1010;
		end else if (flush) begin
			mstatus <= mstatus;
        end else if ((cause != 10 && exception != 10) || (interrupt_valid)) begin
            mstatus[3] <= 0;
            mstatus[7] <= mstatus[3];
            mstatus[12:11] <= 3;        // privilege M-mode 3
        end else begin
			case (CSRControl)
				`CCTL_csrrw: if (CSRaddr == `CSR_mstatus) mstatus <= CSRwdata;
				`CCTL_csrrs: if (CSRaddr == `CSR_mstatus) mstatus <= (mstatus | CSRwdata);
                `CCTL_csrrc: if (CSRaddr == `CSR_mstatus) mstatus <= (mstatus & ~CSRwdata);

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
        end else if ((cause != 10 && exception != 10) || (interrupt_valid)) begin
            mcause <= {((interrupt != 0) && !(exception != 10 || ecall)) ? 1'b1 : 1'b0, cause[30:0]};
        end else begin
			case (CSRControl)
                /*`CCTL_csrrw: if (CSRaddr == `CSR_mcause) mcause <= CSRwdata;
				`CCTL_csrrs: if (CSRaddr == `CSR_mcause) mcause <= mcause | CSRwdata;
                `CCTL_csrrc: if (CSRaddr == `CSR_mcause) mcause <= mcause & ~CSRwdata;*/

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
        end else if ((cause != 10 && exception != 10) || (interrupt_valid)) begin
            mepc <= pc;
        end else begin
			case (CSRControl)
                `CCTL_csrrw: if (CSRaddr == `CSR_mepc) mepc <= CSRwdata;
				`CCTL_csrrs: if (CSRaddr == `CSR_mepc) mepc <= mepc | CSRwdata;
                `CCTL_csrrc: if (CSRaddr == `CSR_mepc) mepc <= mepc & ~CSRwdata;

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
        end else if ((cause != 10 && exception != 10) || (interrupt_valid)) begin
            mscratch <= mscratch;
        end else begin
            case (CSRControl)
                `CCTL_csrrw: if (CSRaddr == `CSR_mscratch) mscratch <= CSRwdata;              // CSRRW
                `CCTL_csrrs: if (CSRaddr == `CSR_mscratch) mscratch <= mscratch | CSRwdata;   // CSRRS
                `CCTL_csrrc: if (CSRaddr == `CSR_mscratch) mscratch <= mscratch & ~CSRwdata;  // CSRRC

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
        end else if ((cause != 10 && exception != 10) || (interrupt_valid)) begin
            mtvec <= mtvec;
		end else begin
			case (CSRControl)
                `CCTL_csrrw: if (CSRaddr == `CSR_mtvec) mtvec <= CSRwdata;
				`CCTL_csrrs: if (CSRaddr == `CSR_mtvec) mtvec <= mtvec | CSRwdata;
                `CCTL_csrrc: if (CSRaddr == `CSR_mtvec) mtvec <= mtvec & ~CSRwdata;

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
        end else if ((cause != 10 && exception != 10) || (interrupt_valid)) begin
            mtval <= mtval;
        end else begin
            case (CSRControl)
                `CCTL_csrrw: if (CSRaddr == `CSR_mtval) mtval <= CSRwdata;
                `CCTL_csrrs: if (CSRaddr == `CSR_mtval) mtval <= mtval | CSRwdata;
                `CCTL_csrrc: if (CSRaddr == `CSR_mtval) mtval <= mtval & ~CSRwdata;

				/*`CCTL_ecall: mtval <= '0;*/
                default: mtval <= mtval;
            endcase
        end
    end

    // CSRnpc
    always @(*) begin
        if (rst)                                    CSRnpc = 0;
        else if ((cause != 10 && exception != 10) || (interrupt_valid))  CSRnpc = (mtvec[0] && (interrupt != 0) && !(exception != 10 || ecall)) ? ({mtvec[31:2], 2'b0} + 4 * cause) : {mtvec[31:2], 2'b0};
        else if (mret)                              CSRnpc = mepc;
        else                                        CSRnpc = mepc;
    end
    
endmodule
