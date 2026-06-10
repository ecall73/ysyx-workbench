module ysyx_26030082_ifu #(
    parameter [31:0] RESET_PC = 32'h3000_0000
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        cache_hit,
    input  wire [31:0] cache_inst,
    input  wire        id_ready,
    output wire        id_valid,
    output reg  [31:0] id_pc,
    output reg  [31:0] id_inst,
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

    output reg  [31:0] if_pc,
    output wire        flush,
    output wire        invalidate
);

    wire        ex_btype_taken;
    wire        redirect_flush;
    wire [31:0] frontend_restart_pc;
    wire [31:0] restart_pc;
    wire        flush_w;
    wire        out_step_en;

    reg         out_valid_r;
    reg         flush_r;
    reg  [31:0] restart_pc_r;

    reg         out_valid_r_next;
    reg         flush_r_next;
    reg  [31:0] if_pc_next;
    reg  [31:0] id_pc_next;
    reg  [31:0] id_inst_next;
    reg  [31:0] restart_pc_r_next;

    assign ex_btype_taken = ex_btype && ex_BRUResult;
    assign redirect_flush = ex_out_valid && ex_out_ready &&
                            (ex_CSRjump || ex_jtype || ex_ijtype || ex_btype_taken);
    assign invalidate = ex_out_valid && ex_out_ready && ex_FenceI;
    assign flush = redirect_flush || invalidate;
    assign frontend_restart_pc = ex_CSRjump ? ex_CSRnpc :
                                 (ex_btype_taken || ex_jtype || ex_ijtype) ? ex_ALUResult :
                                 ex_pc4;
    assign restart_pc = redirect_flush ? frontend_restart_pc : ex_pc4;
    assign flush_w = flush || flush_r;
    assign out_step_en = !out_valid_r || id_ready;
    assign id_valid = out_valid_r && !flush;

    always @(*) begin
        out_valid_r_next = out_valid_r;
        flush_r_next = flush_w && !cache_hit;
        if_pc_next = if_pc;
        id_pc_next = id_pc;
        id_inst_next = id_inst;
        restart_pc_r_next = (flush && !cache_hit) ? restart_pc : restart_pc_r;

        if (!flush_w && cache_hit && out_step_en) begin
            id_pc_next = if_pc;
            id_inst_next = cache_inst;
        end

        if (flush) begin
            out_valid_r_next = 1'b0;
        end else if (!flush_r) begin
            if (out_valid_r) begin
                if (id_ready) begin
                    out_valid_r_next = cache_hit;
                end
            end else if (cache_hit) begin
                out_valid_r_next = 1'b1;
            end
        end

        if (flush_r) begin
            if (cache_hit) begin
                if_pc_next = restart_pc_r;
            end
        end else if (out_valid_r) begin
            if (id_ready && cache_hit) begin
                if_pc_next = if_pc + 32'd4;
            end
        end else if (cache_hit) begin
            if_pc_next = if_pc + 32'd4;
        end

        if (flush && cache_hit) begin
            if_pc_next = restart_pc;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            out_valid_r <= 1'b0;
            flush_r <= 1'b0;
            if_pc <= RESET_PC;
            id_pc <= 32'b0;
            id_inst <= 32'b0;
            restart_pc_r <= 32'b0;
        end else begin
            out_valid_r <= out_valid_r_next;
            flush_r <= flush_r_next;
            if_pc <= if_pc_next;
            id_pc <= id_pc_next;
            id_inst <= id_inst_next;
            restart_pc_r <= restart_pc_r_next;
        end
    end

endmodule
