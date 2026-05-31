`timescale 1ns / 1ps

module npc(
    input  wire [31:0] if_pc4,

    input  wire        ex_btype,
    input  wire        ex_jtype,
    input  wire        ex_ijtype,
    input  wire [31:0] ex_btype_target,

    input  wire        ex_ALUisTrue,
    input  wire [31:0] ex_ALUResult,
    input  wire        ex_CSRjump,
    input  wire [31:0] ex_CSRnpc,

    output reg  [31:0] npc,
    output wire        waste2
);

    wire        ex_btype_taken;

    // No branch prediction: branch redirects only when condition is true.
    assign ex_btype_taken = ex_btype & ex_ALUisTrue;

    // control NPC to do branch jumps
    assign waste2 = ex_CSRjump || ex_jtype || ex_ijtype || ex_btype_taken;

    always @(*) begin
        if (ex_CSRjump)             npc = ex_CSRnpc;
        else if (ex_btype_taken)    npc = ex_btype_target;
        else if (ex_jtype)          npc = ex_ALUResult;
        else if (ex_ijtype)         npc = ex_ALUResult;
        else                        npc = if_pc4;
    end

endmodule
