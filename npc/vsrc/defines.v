// run sel
`define RUN_TRACE

// IFU SimpleBus delay config (1~15)
`ifndef IFU_MAX_DELAY
`define IFU_MAX_DELAY 4
`endif

// IFU reqReady delay config (1~15)
`ifndef IFU_REQREADY_MAX_DELAY
`define IFU_REQREADY_MAX_DELAY 4
`endif

// opcode
`define R_TYPE   7'b011_0011
`define I_TYPE   7'b001_0011
`define IL_TYPE  7'b000_0011 // I lw
`define IJ_TYPE  7'b110_0111 // I jalr
`define S_TYPE   7'b010_0011
`define B_TYPE   7'b110_0011
`define U_TYPE   7'b011_0111 // U lui
`define UA_TYPE  7'b001_0111 // U auipc
`define J_TYPE   7'b110_1111
`define CSR_TYPE 7'b111_0011 // CSR

`define OPCODE_LEN 7

`define WIDTH_RFaddr 5

// ALUControl
`define WIDTH_ACTL 14
`define ACTL_add   14'b00_0000_0000_0001
`define ACTL_sub   14'b00_0000_0000_0010
`define ACTL_and   14'b00_0000_0000_0100
`define ACTL_or    14'b00_0000_0000_1000
`define ACTL_xor   14'b00_0000_0001_0000
`define ACTL_sll   14'b00_0000_0010_0000
`define ACTL_srl   14'b00_0000_0100_0000
`define ACTL_sra   14'b00_0000_1000_0000
`define ACTL_beq   14'b00_0001_0000_0000
`define ACTL_bne   14'b00_0010_0000_0000
`define ACTL_blt   14'b00_0100_0000_0000
`define ACTL_bge   14'b00_1000_0000_0000
`define ACTL_bgeu  14'b01_0000_0000_0000
`define ACTL_bltu  14'b10_0000_0000_0000

// MemToReg
`define WIDTH_MemToReg 3
`define MemToReg_PC4    3'b000
`define MemToReg_ALU    3'b001
`define MemToReg_DRAM   3'b100
`define MemToReg_IMM    3'b011
`define MemToReg_CSR    3'b010

// NpcOp
`define WIDTH_NpcOp     3
`define NpcOp_NEXT      0
`define NpcOp_BRANCH    1
`define NpcOp_JAL       2
`define NpcOp_JALR      3
`define NpcOp_CSR       4

// MCTL
`define MCTL_mul    3'b000
`define MCTL_mulh   3'b001
`define MCTL_mulhsu 3'b010
`define MCTL_mulhu  3'b011
`define MCTL_div    3'b100
`define MCTL_divu   3'b101
`define MCTL_rem    3'b110
`define MCTL_remu   3'b111

// CCTL
`define CCTL_csrrw  5'b00001
`define CCTL_csrrs  5'b00010
`define CCTL_csrrc  5'b00100

`define CCTL_ecall  5'b01000
`define CCTL_mret   5'b10000

// CSR reg addr
// 机器状态寄存器
`define CSR_mstatus     12'h300
`define CSR_misa        12'h301
`define CSR_medeleg     12'h302
`define CSR_mideleg     12'h303
`define CSR_mie         12'h304
`define CSR_mtvec       12'h305
`define CSR_mcounteren  12'h306

// 机器模式计数器
`define CSR_mcycle      12'hB00
`define CSR_mcycleh     12'hB80
`define CSR_minstret    12'hB02
`define CSR_minstreth   12'hB82

// 机器模式异常/中断管理
`define CSR_mscratch    12'h340
`define CSR_mepc        12'h341
`define CSR_mcause      12'h342
`define CSR_mtval       12'h343
`define CSR_mip         12'h344

// 机器模式时间寄存器（有些实现用这些寄存器支持定时器中断）
`define CSR_cycle       12'hC00
`define CSR_time        12'hC01
`define CSR_instret     12'hC02

// 机器信息寄存器
`define CSR_mvendorid   12'hF11
`define CSR_marchid     12'hF12

// 软件中断、定时器中断、外部中断相关位定义(用于mie、mip寄存器)
`define MIP_MSIP        (1 << 3)
`define MIP_MTIP        (1 << 7)
`define MIP_MEIP        (1 << 11)

// 机器状态寄存器mstatus相关位定义
`define MSTATUS_MIE     (1 << 3)   // 全局中断使能位
`define MSTATUS_MPIE    (1 << 7)   // 中断使能前一个状态
`define MSTATUS_MPP     (3 << 11)  // 特权模式位（2位）

