`timescale 1ns / 1ps

`include "defines.v"

module top
(
    input             clk,
    input             rst
`ifdef RUN_TRACE
,   output            debug_wb_have_inst,
    output [31:0]     debug_wb_pc,
    output            debug_wb_ena,
    output [ 4:0]     debug_wb_reg,
    output [31:0]     debug_wb_value,
    output            debug_wb_ebreak,
    output [31:0]     debug_reg_file [0:31]
`endif
);

    // IROM
    wire [31:0] irom_addr;
    wire [31:0] irom_data;

    // perip
    wire [31:0] perip_addr, perip_wdata, perip_rdata;
    wire perip_wen, perip_ren;
    wire [3:0] perip_wmask;

    myCPU Core_cpu (
        .clk                (clk),
        .rst                (rst),

        // Interface to IROM
        .irom_addr          (irom_addr),
        .irom_data          (irom_data),

        // Interface to DRAM & periphera
        .perip_addr         (perip_addr),
        .perip_ren          (perip_ren),
        .perip_wen          (perip_wen),
        .perip_wmask        (perip_wmask),
        .perip_wdata        (perip_wdata),
        .perip_rdata        (perip_rdata)

    `ifdef RUN_TRACE
        ,
        .debug_wb_have_inst (debug_wb_have_inst),
        .debug_wb_pc        (debug_wb_pc),
        .debug_wb_ena       (debug_wb_ena),
        .debug_wb_reg       (debug_wb_reg),
        .debug_wb_value     (debug_wb_value),
        .debug_wb_ebreak    (debug_wb_ebreak),
        .debug_reg_file     (debug_reg_file)
    `endif
    );

    irom irom_inst (
        .irom_addr          (irom_addr),
        .irom_data          (irom_data)
    );
    
    perip_bridge bridge_inst (
        .clk				(clk),
        .rst                (rst),
        .perip_addr			(perip_addr),
        .perip_wdata		(perip_wdata),
        .perip_ren          (perip_ren),
        .perip_wen			(perip_wen),
        .perip_wmask			(perip_wmask),
        .perip_rdata		(perip_rdata)
    );

endmodule
