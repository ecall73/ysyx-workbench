module ysyx_26030082_ifu #(
    parameter [31:0] RESET_PC = 32'h3000_0000
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        if_ready,
    input  wire        flush,
    input  wire        invalidate,
    input  wire [31:0] flush_target,

    // IF stage request side
    output wire        if_valid,
    output reg  [31:0] if_pc
);

    wire req_fire;

    assign if_valid = 1'b1;

    assign req_fire = if_ready;

    always @(posedge clock) begin
        if (reset) begin
            if_pc <= RESET_PC;
        end else if (flush) begin
            if_pc <= flush_target;
        end else if (req_fire) begin
            if_pc <= if_pc + 32'd4;
        end
    end

endmodule
