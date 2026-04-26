`timescale 1ns / 1ps

module forward(
    input  wire        id_in_valid,
    input  wire [ 4:0] id_rR1,
    input  wire [ 4:0] id_rR2,
    input  wire [31:0] id_rR1_data,
    input  wire [31:0] id_rR2_data,

    input  wire        ex_out_valid,
    input  wire        ex_MemRead,
    input  wire        ex_RegWrite,
    input  wire [ 4:0] ex_RFwaddr,
    input  wire [31:0] ex_RFwdata,

    input  wire        ls_RegWrite,
    input  wire [ 4:0] ls_RFwaddr,
    input  wire [31:0] ls_RFwdata,

    input  wire        wb_RegWrite,
    input  wire [ 4:0] wb_RFwaddr,
    input  wire [31:0] wb_RFwdata,

    output wire        forward_pending,
    output reg  [31:0] id_rR1_data_forward,
    output reg  [31:0] id_rR2_data_forward
);

    wire forward_ex_A;
    wire forward_ex_B;
    wire forward_ls_A;
    wire forward_ls_B;
    wire forward_wb_A;
    wire forward_wb_B;

    assign forward_ex_A = (id_rR1 == ex_RFwaddr) && ex_RegWrite && ~(ex_RFwaddr == 0);
    assign forward_ex_B = (id_rR2 == ex_RFwaddr) && ex_RegWrite && ~(ex_RFwaddr == 0);

    assign forward_ls_A = (id_rR1 == ls_RFwaddr) && ls_RegWrite && ~(ls_RFwaddr == 0);
    assign forward_ls_B = (id_rR2 == ls_RFwaddr) && ls_RegWrite && ~(ls_RFwaddr == 0);

    assign forward_wb_A = (id_rR1 == wb_RFwaddr) && wb_RegWrite && ~(wb_RFwaddr == 0);
    assign forward_wb_B = (id_rR2 == wb_RFwaddr) && wb_RegWrite && ~(wb_RFwaddr == 0);

    // EX load-use cannot be solved by forwarding in this cycle.
    assign forward_pending = id_in_valid && ex_out_valid && ex_MemRead &&
                             (ex_RFwaddr != 5'b0) &&
                             ((id_rR1 == ex_RFwaddr) || (id_rR2 == ex_RFwaddr));

    always @(*) begin
        if      (forward_ex_A) id_rR1_data_forward = ex_RFwdata;
        else if (forward_ls_A) id_rR1_data_forward = ls_RFwdata;
        else if (forward_wb_A) id_rR1_data_forward = wb_RFwdata;
        else                   id_rR1_data_forward = id_rR1_data;
    end

    always @(*) begin
        if      (forward_ex_B) id_rR2_data_forward = ex_RFwdata;
        else if (forward_ls_B) id_rR2_data_forward = ls_RFwdata;
        else if (forward_wb_B) id_rR2_data_forward = wb_RFwdata;
        else                   id_rR2_data_forward = id_rR2_data;
    end

endmodule
