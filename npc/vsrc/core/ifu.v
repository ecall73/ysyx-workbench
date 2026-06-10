module ysyx_26030082_ifu #(
    parameter [31:0] RESET_PC = 32'h3000_0000
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        if_ready,
    input  wire        ex_out_valid,
    input  wire        ex_out_ready,
    input  wire [31:0] ex_pc4,
    input  wire        ex_btype,
    input  wire        ex_jtype,
    input  wire        ex_ijtype,
    input  wire        ex_BRUResult,
    input  wire [31:0] ex_ALUResult,
    input  wire        ex_CSRjump,
    input  wire [31:0] ex_CSRnpc,
    input  wire        ex_FenceI,

    // IF stage request side
    output wire        if_valid,
    output reg  [31:0] if_pc,
    output wire        flush,
    output wire        invalidate
);

    wire        ex_btype_taken;
    wire        redirect_flush;
    wire [31:0] frontend_restart_pc;
    wire [31:0] restart_pc;
    wire req_fire;

    assign ex_btype_taken = ex_btype && ex_BRUResult;
    assign redirect_flush = ex_out_valid && ex_out_ready &&
                            (ex_CSRjump || ex_jtype || ex_ijtype || ex_btype_taken);
    assign invalidate = ex_out_valid && ex_out_ready && ex_FenceI;
    assign flush = redirect_flush || invalidate;
    assign frontend_restart_pc = ex_CSRjump ? ex_CSRnpc :
                                 (ex_btype_taken || ex_jtype || ex_ijtype) ? ex_ALUResult :
                                 ex_pc4;
    assign restart_pc = redirect_flush ? frontend_restart_pc : ex_pc4;

    assign if_valid = !flush;

    assign req_fire = if_valid && if_ready;

    always @(posedge clock) begin
        if (reset) begin
            if_pc <= RESET_PC;
        end else if (flush) begin
            if_pc <= restart_pc;
        end else if (req_fire) begin
            if_pc <= if_pc + 32'd4;
        end
    end

endmodule
