`timescale 1ns / 1ps

`include "defines.v"

module forward(
    input  wire [ 4:0] id_rR1,
    input  wire [ 4:0] id_rR2,
    input  wire [31:0] id_rR1_data,
    input  wire [31:0] id_rR2_data,

    input  wire        ex_RegWrite,
    input  wire [ 4:0] ex_RFwaddr,
    input  wire [31:0] ex_RFwdata,

    input  wire        me1_RegWrite,
    input  wire [ 4:0] me1_RFwaddr,
    input  wire [31:0] me1_RFwdata,

    input  wire        me2_RegWrite,
    input  wire [ 4:0] me2_RFwaddr,
    input  wire [31:0] me2_RFwdata,

    input  wire        wb_RegWrite,
    input  wire [ 4:0] wb_RFwaddr,
    input  wire [31:0] wb_RFwdata,

    output reg  [31:0] id_rR1_data_forward,
    output reg  [31:0] id_rR2_data_forward
);

    wire forward_ex_A;
    wire forward_ex_B;
    wire forward_me1_A;
    wire forward_me1_B;
    wire forward_me2_A;
    wire forward_me2_B;
    wire forward_wb_A;
    wire forward_wb_B;

    assign forward_ex_A = (id_rR1 == ex_RFwaddr) && ex_RegWrite && ~(ex_RFwaddr==0);
    assign forward_ex_B = (id_rR2 == ex_RFwaddr) && ex_RegWrite && ~(ex_RFwaddr==0);

    assign forward_me1_A = (id_rR1 == me1_RFwaddr) && me1_RegWrite && ~(me1_RFwaddr==0);
    assign forward_me1_B = (id_rR2 == me1_RFwaddr) && me1_RegWrite && ~(me1_RFwaddr==0);
    
    assign forward_me2_A = (id_rR1 == me2_RFwaddr) && me2_RegWrite && ~(me2_RFwaddr==0);
    assign forward_me2_B = (id_rR2 == me2_RFwaddr) && me2_RegWrite && ~(me2_RFwaddr==0);

    assign forward_wb_A = (id_rR1 == wb_RFwaddr) && wb_RegWrite && ~(wb_RFwaddr==0);
    assign forward_wb_B = (id_rR2 == wb_RFwaddr) && wb_RegWrite && ~(wb_RFwaddr==0);

    always @(*) begin
        if      (forward_ex_A)  id_rR1_data_forward = ex_RFwdata;
        else if (forward_me1_A) id_rR1_data_forward = me1_RFwdata;
        else if (forward_me2_A) id_rR1_data_forward = me2_RFwdata;
        else if (forward_wb_A)  id_rR1_data_forward = wb_RFwdata;
        else                    id_rR1_data_forward = id_rR1_data;
    end

    always @(*) begin
        if      (forward_ex_B)  id_rR2_data_forward = ex_RFwdata;
        else if (forward_me1_B) id_rR2_data_forward = me1_RFwdata;
        else if (forward_me2_B) id_rR2_data_forward = me2_RFwdata;
        else if (forward_wb_B)  id_rR2_data_forward = wb_RFwdata;
        else                    id_rR2_data_forward = id_rR2_data;
    end

endmodule
