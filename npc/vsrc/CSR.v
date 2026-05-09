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

    input  wire [ 4:0] CSRControl, // one-hot CCTL
    input  wire [11:0] CSRaddr,
    input  wire        CSRSrc,     // CSR写入选择
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

    wire        ecall = CSRControl[3];
    wire        mret  = CSRControl[4];
    wire [31:0] CSRwdata = CSRSrc ? imm : rR1_data;  // csrrxi: imm, csrrx: rR1

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
    always @(posedge clk) begin
		if (rst) begin
            mstatus <= 32'h1800;
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

	// mtvec
	always @(posedge clk) begin
		if (rst) begin
            mtvec <= 1;
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
