module ysyx_26030082_forward(
    input  wire        id_in_valid,
    input  wire [ 4:0] id_rR1,
    input  wire [ 4:0] id_rR2,

    input  wire        ex_out_valid,
    input  wire        ex_MemRead,
    input  wire [ 4:0] ex_RFwaddr,

    input  wire [ 4:0] ls_RFwaddr,
    input  wire        ls_load_pending,

    output wire        forward_pending
);

    wire ls_load_use_hazard;

    assign ls_load_use_hazard = ls_load_pending &&
                                (ls_RFwaddr != 5'b0) &&
                                ((id_rR1 == ls_RFwaddr) || (id_rR2 == ls_RFwaddr));

    // A load in EX or a pending (not-yet-returned) load in LS must block ID
    // when ID needs that destination register.
    assign forward_pending = id_in_valid && (
                                (ex_out_valid && ex_MemRead &&
                                 (ex_RFwaddr != 5'b0) &&
                                 ((id_rR1 == ex_RFwaddr) || (id_rR2 == ex_RFwaddr))) ||
                                ls_load_use_hazard
                             );

endmodule
