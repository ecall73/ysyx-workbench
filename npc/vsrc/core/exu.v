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
    input  wire        ex_btype,
    input  wire        ex_jtype,
    input  wire        ex_ijtype,

    // CSR inputs
    input  wire        ex_is_system,
    input  wire [11:0] ex_CSRaddr,

    // Control for WB data selection
    input  wire [ 2:0] ex_MemToReg,

    // Outputs
    output wire [31:0] ex_ALUResult,
    output wire        ex_BRUResult,
    output wire [31:0] ex_pc4,
    output wire        ex_Redirect,
    output wire [31:0] ex_RedirectTarget,

    output wire        ex_CSRjump,
    output wire [31:0] ex_CSRnpc,

    output wire [31:0] ex_WBAltData,
    output wire        ex_WBUseAlt,
    output wire        ex_MemRead
);

    wire [31:0] CSRrdata;
    wire [31:0] redirect_base;
    wire [31:0] redirect_target_sum;

    assign ex_in_ready = ~ex_in_valid || ex_out_ready;
    assign ex_out_valid = ex_in_valid;

    assign ex_pc4 = ex_pc + 32'd4;
    assign redirect_base = ex_ijtype ? ex_rR1_data : ex_pc;
    assign redirect_target_sum = redirect_base + ex_imm;
    assign ex_Redirect = ex_jtype || ex_ijtype || (ex_btype && ex_BRUResult);
    assign ex_RedirectTarget = ex_ijtype ? {redirect_target_sum[31:1], 1'b0}
                                         : redirect_target_sum;

    ysyx_26030082_ALU ALU (
        .ALUSrcA                (ex_ALUSrcA),
        .ALUSrcB                (ex_ALUSrcB),
        .pc                     (ex_pc),
        .imm                    (ex_imm),
        .rR1_data               (ex_rR1_data),
        .rR2_data               (ex_rR2_data),
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
