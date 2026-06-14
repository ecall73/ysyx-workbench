module ysyx_26030082_forward(
    input  wire        id_in_valid,
    input  wire [ 4:0] id_rR1,
    input  wire [ 4:0] id_rR2,
    input  wire [31:0] id_rR1_data,
    input  wire [31:0] id_rR2_data,

    input  wire        ex_out_valid,
    input  wire        ex_MemRead,
    input  wire        ex_RegWrite,
    input  wire [ 3:0] ex_RFwaddr,
    input  wire [31:0] ex_RFwdata,

    input  wire        ls_RegWrite,
    input  wire [ 3:0] ls_RFwaddr,
    input  wire        ls_load_pending,

    output wire        forward_pending,
    output reg  [31:0] id_rR1_data_forward,
    output reg  [31:0] id_rR2_data_forward
);

    wire forward_ex_A;
    wire forward_ex_B;
    wire ls_load_use_hazard;

    assign forward_ex_A = (id_rR1 == {1'b0, ex_RFwaddr}) && ex_RegWrite && ~(ex_RFwaddr == 0);
    assign forward_ex_B = (id_rR2 == {1'b0, ex_RFwaddr}) && ex_RegWrite && ~(ex_RFwaddr == 0);

    assign ls_load_use_hazard = ls_load_pending && ls_RegWrite &&
                                (ls_RFwaddr != 4'b0) &&
                                ((id_rR1 == {1'b0, ls_RFwaddr}) || (id_rR2 == {1'b0, ls_RFwaddr}));

    // A load in EX or a pending (not-yet-returned) load in LS must block ID
    // when ID needs that destination register.
    assign forward_pending = id_in_valid && (
                                (ex_out_valid && ex_MemRead &&
                                 (ex_RFwaddr != 4'b0) &&
                                 ((id_rR1 == {1'b0, ex_RFwaddr}) || (id_rR2 == {1'b0, ex_RFwaddr}))) ||
                                ls_load_use_hazard
                             );

    always @(*) begin
        if      (forward_ex_A) id_rR1_data_forward = ex_RFwdata;
        else                   id_rR1_data_forward = id_rR1_data;
    end

    always @(*) begin
        if      (forward_ex_B) id_rR2_data_forward = ex_RFwdata;
        else                   id_rR2_data_forward = id_rR2_data;
    end

endmodule
