`timescale 1ns / 1ps

`include "defines.v"

module predict(
    input  wire        clk,
    input  wire        rst,

    input  wire        flush_ID_EX,
    input  wire        flush_EX_ME1,
    input  wire        stall_ID_EX,

    input  wire [31:0] if_pc4,

    input  wire [31:0] id_pc,
    input  wire [31:0] id_pc4,
    input  wire [31:0] id_inst,

    input  wire        me1_ALUisTrue,
    input  wire [31:0] me1_ALUResult,
    input  wire        me1_CSRjump,
    input  wire [31:0] me1_CSRnpc,

    output reg  [31:0] npc,
    output wire        waste1,
    output wire        waste3
);

    wire        id_btype;  // branch
    wire        id_jtype;  // jal
    wire        id_ijtype; // jalr

    reg         ex_btype;
    reg         ex_ijtype;

    reg         me1_btype;
    reg         me1_ijtype;

    wire [31:0] id_btype_imm;
    wire [31:0] id_jtype_imm;
    wire [31:0] id_btype_pcjump;
    wire [31:0] id_jtype_pcjump;

    wire        id_predict_taken;
    reg         ex_predict_taken;
    reg         me1_predict_taken;
    wire [31:0] id_restore_npc;
    reg  [31:0] ex_restore_npc;
    reg  [31:0] me1_restore_npc;

    wire        me1_predict_fail;

    assign id_btype     = id_inst[6:0] == `B_TYPE;
    assign id_jtype     = id_inst[6:0] == `J_TYPE;
    assign id_ijtype    = id_inst[6:0] == `IJ_TYPE;

    assign id_btype_imm = {{20{id_inst[31]}}, id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
    assign id_jtype_imm = {{12{id_inst[31]}}, id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};

    assign id_btype_pcjump = id_pc + id_btype_imm;
    assign id_jtype_pcjump = id_pc + id_jtype_imm;

    // TODO: predict
    assign id_predict_taken = id_inst[31] && id_btype;
    //assign id_predict_taken = id_btype;
    //assign id_predict_taken = 0;

    // save another possible npc in case prediction failed
    assign id_restore_npc = id_predict_taken ? id_pc4 : id_btype_pcjump;


    // ID-EX
    always @(posedge clk) begin
        if (rst) begin
            ex_predict_taken    <= 0;
            ex_restore_npc      <= 0;
            ex_btype            <= 0;
            ex_ijtype           <= 0;
        end else if (flush_ID_EX) begin
            ex_predict_taken    <= 0;
            ex_restore_npc      <= 0;
            ex_btype            <= 0;
            ex_ijtype           <= 0;
        end else if (stall_ID_EX) begin
            ex_predict_taken    <= ex_predict_taken;
            ex_restore_npc      <= ex_restore_npc;
            ex_btype            <= ex_btype;
            ex_ijtype           <= ex_ijtype;
        end else begin
            ex_predict_taken    <= id_predict_taken;
            ex_restore_npc      <= id_restore_npc;
            ex_btype            <= id_btype;
            ex_ijtype           <= id_ijtype;
        end
    end

    //EX-ME1
    always @(posedge clk) begin
        if(rst) begin
            me1_predict_taken   <= 0;
            me1_restore_npc     <= 0;
            me1_btype           <= 0;
            me1_ijtype          <= 0;
        end else if(flush_EX_ME1) begin
            me1_predict_taken   <= 0;
            me1_restore_npc     <= 0;
            me1_btype           <= 0;
            me1_ijtype          <= 0;
        end else begin
            me1_predict_taken   <= ex_predict_taken;
            me1_restore_npc     <= ex_restore_npc;
            me1_btype           <= ex_btype;
            me1_ijtype          <= ex_ijtype;
        end
    end

    // check whether prediction succeeded or failed
    assign me1_predict_fail = me1_btype & (me1_ALUisTrue ^ me1_predict_taken);

    // control NPC to do branch jumps
    assign waste3 = me1_CSRjump || me1_ijtype || me1_predict_fail;
    assign waste1 = id_jtype || id_predict_taken;

    always @(*) begin
        if (me1_CSRjump)            npc = me1_CSRnpc;
        else if (me1_predict_fail)  npc = me1_restore_npc;
        else if (me1_ijtype)        npc = me1_ALUResult;
        else if (id_predict_taken)  npc = id_btype_pcjump;
        else if (id_jtype)          npc = id_jtype_pcjump;
        else                        npc = if_pc4;
    end

endmodule
