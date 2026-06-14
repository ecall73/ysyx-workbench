module ysyx_26030082_ifu #(
    parameter [31:0] RESET_PC = 32'h3000_0000
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        if_ready,
    input  wire        ex_out_valid,
    input  wire        ex_out_ready,
    input  wire [31:0] ex_pc4,
    input  wire        ex_Redirect,
    input  wire [31:0] ex_RedirectTarget,
    input  wire        ex_CSRjump,
    input  wire [31:0] ex_CSRnpc,
    input  wire        ex_FenceI,

    // IF stage request side
    output wire        if_valid,
    output reg  [31:0] if_pc,
    output wire        flush,
    output wire        invalidate
);

    wire        ex_commit_fire;
    wire req_fire;

    assign ex_commit_fire = ex_out_valid && ex_out_ready;
    assign invalidate = ex_commit_fire && ex_FenceI;
    assign flush = ex_commit_fire && (ex_CSRjump || ex_Redirect || ex_FenceI);

    assign if_valid = 1'b1;

    assign req_fire = if_ready;

    always @(posedge clock) begin
        if (reset) begin
            if_pc <= RESET_PC;
        end else if (flush) begin
            if_pc <= ex_CSRjump ? ex_CSRnpc :
                     ex_Redirect ? ex_RedirectTarget :
                     ex_pc4;
        end else if (req_fire) begin
            if_pc <= if_pc + 32'd4;
        end
    end

endmodule
