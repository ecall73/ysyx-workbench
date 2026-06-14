module ysyx_26030082_CSR (
    input  wire        clock,
    input  wire        reset,

    input  wire [ 2:0] CSRControl,
    input  wire [ 2:0] CSRaddr,
    input  wire        CSRSrc,     // CSR写入选择
    input  wire [31:0] rR1_data,   // CSR写入寄存器值(csrrx),已递进
    input  wire [31:0] imm,        // CSR写入立即数(csrrxi)

    input  wire [31:0] pc,         // CSR所在EX段的pc

    output reg  [31:0] CSRrdata,   // CSR读出数据
    output wire        CSRjump,    // CSR触发跳转 PCTrap
    output reg  [31:0] CSRnpc      // CSR跳转pc
);

    localparam [2:0] CCTL_CSRRW = 3'd1;
    localparam [2:0] CCTL_CSRRS = 3'd2;
    localparam [2:0] CCTL_CSRRC = 3'd3;
    localparam [2:0] CCTL_ECALL = 3'd4;
    localparam [2:0] CCTL_MRET  = 3'd5;

    localparam [2:0] CSR_mstatus   = 3'd0;
    localparam [2:0] CSR_mtvec     = 3'd1;
    localparam [2:0] CSR_mepc      = 3'd2;
    localparam [2:0] CSR_mcause    = 3'd3;
    localparam [2:0] CSR_mvendorid = 3'd4;
    localparam [2:0] CSR_marchid   = 3'd5;

    reg  [31:0] mstatus, mtvec, mepc, mcause;

    localparam [31:0] CAUSE_ECALL_M = 32'd11;

    wire        ecall = (CSRControl == CCTL_ECALL);
    wire        mret  = (CSRControl == CCTL_MRET);
    wire [31:0] CSRwdata = CSRSrc ? imm : rR1_data;  // csrrxi: imm, csrrx: rR1

    wire        sync_trap_req   = ecall;
    wire        trap_taken      = sync_trap_req;
    wire        trap_is_interrupt = 1'b0;
    wire        mret_taken      = mret;
    wire [31:0] trap_cause_code = CAUSE_ECALL_M;
    wire [31:0] trap_vector = {mtvec[31:2], 2'b0};
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

    always @(posedge clock) begin
        if (reset) begin
            mstatus <= 32'h1800;
        end else if (trap_taken) begin
            mstatus[3] <= 0;
            mstatus[7] <= mstatus[3];
            mstatus[12:11] <= 3;
        end else if (mret_taken) begin
            mstatus[3] <= mstatus[7];
        end else begin
            case (CSRControl)
                CCTL_CSRRW: if (CSRaddr == CSR_mstatus) mstatus <= CSRwdata;
                CCTL_CSRRS: if (CSRaddr == CSR_mstatus) mstatus <= mstatus | CSRwdata;
                CCTL_CSRRC: if (CSRaddr == CSR_mstatus) mstatus <= mstatus & ~CSRwdata;
                default: mstatus <= mstatus;
            endcase
        end
    end

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

    always @(posedge clock) begin
        if (reset) begin
            mtvec <= 32'h0000_0001;
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
