module ysyx_26030082_exu (
    input  wire        clock,
    input  wire        reset,
    input  wire        ex_in_valid,
    output wire        ex_in_ready,
    output wire        ex_out_valid,
    input  wire        ex_out_ready,
    input  wire        ex_fire,

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
    output wire [31:0] ex_CSRnpc,

    output wire [31:0] ex_WBAltData,
    output wire        ex_WBUseAlt,
    output wire        ex_MemRead
);

    wire [31:0] ex_A;
    wire [31:0] ex_B;
    wire [31:0] CSRrdata;

    assign ex_in_ready = ~ex_in_valid || ex_out_ready;
    assign ex_out_valid = ex_in_valid;

    assign ex_A = ex_ALUSrcA ? ex_pc : ex_rR1_data;
    assign ex_B = ex_ALUSrcB ? ex_imm : ex_rR2_data;
    assign ex_pc4 = ex_pc + 32'd4;

    ysyx_26030082_ALU ALU (
        .A                      (ex_A),
        .B                      (ex_B),
        .BRU_A                  (ex_rR1_data),
        .BRU_B                  (ex_rR2_data),
        .ALUControl             (ex_ALUControl),
        .BRUFunct3              (ex_funct3),

        .Result                 (ex_ALUResult),
        .BRUResult              (ex_BRUResult)
    );

    ysyx_26030082_CSR CSR (
        .clock                    (clock),
        .reset                    (reset),
        .csr_fire                 (ex_fire),

        .is_system              (ex_is_system),
        .CSRaddr                (ex_CSRaddr),
        .funct3                 (ex_funct3),
        .rR1_data               (ex_rR1_data),
        .imm                    (ex_imm),

        .pc                     (ex_pc),

        .CSRrdata               (CSRrdata),
        .CSRjump                (ex_CSRjump),
        .CSRnpc                 (ex_CSRnpc)
    );

    assign ex_WBAltData = ex_MemToReg[1] ?
                              (ex_MemToReg[0] ? ex_imm : CSRrdata) :
                              ex_pc4;
    assign ex_WBUseAlt = ~ex_MemToReg[2] && (ex_MemToReg[1] || ~ex_MemToReg[0]);

    assign ex_MemRead = ex_MemToReg[2];

endmodule
