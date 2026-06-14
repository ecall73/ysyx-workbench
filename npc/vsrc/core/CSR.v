module ysyx_26030082_CSR (
    input  wire        clock,
    input  wire        reset,

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

    localparam [4:0] CCTL_CSRRW = 5'b00001;
    localparam [4:0] CCTL_CSRRS = 5'b00010;
    localparam [4:0] CCTL_CSRRC = 5'b00100;
    localparam [4:0] CCTL_MRET  = 5'b10000;

    localparam [11:0] CSR_mstatus   = 12'h300;
    localparam [11:0] CSR_mtvec     = 12'h305;
    localparam [11:0] CSR_mepc      = 12'h341;
    localparam [11:0] CSR_mcause    = 12'h342;
    localparam [11:0] CSR_mvendorid = 12'hF11;
    localparam [11:0] CSR_marchid   = 12'hF12;

    reg  [31:0] mstatus, mtvec, mepc, mcause;

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
			case (CSRControl)
				CCTL_CSRRW: if (CSRaddr == CSR_mstatus) mstatus <= CSRwdata;
				CCTL_CSRRS: if (CSRaddr == CSR_mstatus) mstatus <= (mstatus | CSRwdata);
                CCTL_CSRRC: if (CSRaddr == CSR_mstatus) mstatus <= (mstatus & ~CSRwdata);

				CCTL_MRET: begin
					mstatus[3]  	<= mstatus[7];  	// MIE <= MPIE
				end
				default: mstatus <= mstatus; // 保持原值
			endcase
		end
	end

    // mcause
    always @(posedge clock) begin
		if (reset) begin
			mcause <= 32'h0;
        end else if (trap_taken) begin
            mcause <= {trap_is_interrupt, trap_cause_code[30:0]};
        end else begin
			case (CSRControl)
				default: mcause <= mcause;
			endcase
		end
	end

    // mepc
    always @(posedge clock) begin
		if (reset) begin
			mepc <= 32'h0;
        end else if (trap_taken) begin
            mepc <= pc;
        end else begin
			case (CSRControl)
                CCTL_CSRRW: if (CSRaddr == CSR_mepc) mepc <= CSRwdata;
				CCTL_CSRRS: if (CSRaddr == CSR_mepc) mepc <= mepc | CSRwdata;
                CCTL_CSRRC: if (CSRaddr == CSR_mepc) mepc <= mepc & ~CSRwdata;

				default: mepc <= mepc;
			endcase
		end
	end

	// mtvec
	always @(posedge clock) begin
		if (reset) begin
            mtvec <= 1;
        end else if (trap_taken) begin
            mtvec <= mtvec;
		end else begin
			case (CSRControl)
                CCTL_CSRRW: if (CSRaddr == CSR_mtvec) mtvec <= CSRwdata;
				CCTL_CSRRS: if (CSRaddr == CSR_mtvec) mtvec <= mtvec | CSRwdata;
                CCTL_CSRRC: if (CSRaddr == CSR_mtvec) mtvec <= mtvec & ~CSRwdata;

				default: mtvec <= mtvec;
			endcase
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
