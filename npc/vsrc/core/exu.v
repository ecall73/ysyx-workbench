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
    input  wire        ex_CSRSrc,
    input  wire [11:0] ex_CSRaddr,
    input  wire [ 4:0] ex_CSRControl,

    // Control for WB data selection
    input  wire [ 2:0] ex_MemToReg,

    // Outputs
    output wire [31:0] ex_ALUResult,
    output wire        ex_BRUResult,
    output wire [31:0] ex_pc4,

    output wire        ex_CSRjump,
    output wire [31:0] ex_CSRnpc,

    output wire [31:0] ex_RFwdata,
    output wire        ex_MemRead
);

    wire [31:0] CSRrdata;

    assign ex_in_ready = ~ex_in_valid || ex_out_ready;
    assign ex_out_valid = ex_in_valid;

    assign ex_pc4 = ex_pc + 32'd4;

    ysyx_26030082_ALU ALU (
        .ALUSrcA                (ex_ALUSrcA),
        .ALUSrcB                (ex_ALUSrcB),
        .pc                     (ex_pc),
        .imm                    (ex_imm),
        .rR1_data               (ex_rR1_data),
        .rR2_data               (ex_rR2_data),
        .ALUControl             (ex_ALUControl),
        .BRUFunct3              (ex_funct3),

        .Result                 (ex_ALUResult),
        .BRUResult              (ex_BRUResult)
    );

    ysyx_26030082_CSR CSR (
        .clock                    (clock),
        .reset                    (reset),

        .CSRControl             (ex_CSRControl),
        .CSRaddr                (ex_CSRaddr),
        .CSRSrc                 (ex_CSRSrc),
        .rR1_data               (ex_rR1_data),
        .imm                    (ex_imm),

        .pc                     (ex_pc),

        .CSRrdata               (CSRrdata),
        .CSRjump                (ex_CSRjump),
        .CSRnpc                 (ex_CSRnpc)
    );

    assign ex_RFwdata = ex_MemToReg[1] ?
                            (ex_MemToReg[0] ? ex_imm : CSRrdata) :
                            (ex_MemToReg[0] ? ex_ALUResult : ex_pc4);

    assign ex_MemRead = ex_MemToReg[2];

endmodule
