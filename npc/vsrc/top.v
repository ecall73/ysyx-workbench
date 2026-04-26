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

    // IFU SimpleBus
    wire        ifu_reqValid;
    wire        ifu_reqReady;
    wire [31:0] ifu_addr;
    wire        ifu_respValid;
    wire        ifu_respReady;
    wire [31:0] ifu_rdata;

    // LSU SimpleBus
    wire        lsu_reqValid;
    wire        lsu_reqReady;
    wire [31:0] lsu_addr;
    wire        lsu_wen;
    wire [31:0] lsu_wdata;
    wire [ 3:0] lsu_wmask;
    wire        lsu_respValid;
    wire        lsu_respReady;
    wire [31:0] lsu_rdata;

    myCPU Core_cpu (
        .clk                (clk),
        .rst                (rst),

        // Interface to IFU SimpleBus
        .ifu_reqValid       (ifu_reqValid),
        .ifu_reqReady       (ifu_reqReady),
        .ifu_addr           (ifu_addr),
        .ifu_respValid      (ifu_respValid),
        .ifu_respReady      (ifu_respReady),
        .ifu_rdata          (ifu_rdata),

        // Interface to LSU SimpleBus
        .lsu_reqValid       (lsu_reqValid),
        .lsu_reqReady       (lsu_reqReady),
        .lsu_addr           (lsu_addr),
        .lsu_wen            (lsu_wen),
        .lsu_wdata          (lsu_wdata),
        .lsu_wmask          (lsu_wmask),
        .lsu_respValid      (lsu_respValid),
        .lsu_respReady      (lsu_respReady),
        .lsu_rdata          (lsu_rdata)

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
        .clk                (clk),
        .rst                (rst),
        .ifu_reqValid       (ifu_reqValid),
        .ifu_reqReady       (ifu_reqReady),
        .ifu_addr           (ifu_addr),
        .ifu_respValid      (ifu_respValid),
        .ifu_respReady      (ifu_respReady),
        .ifu_rdata          (ifu_rdata)
    );
    
    perip_bridge bridge_inst (
        .clk				(clk),
        .rst                (rst),
        .lsu_reqValid       (lsu_reqValid),
        .lsu_reqReady       (lsu_reqReady),
        .lsu_addr           (lsu_addr),
        .lsu_wen            (lsu_wen),
        .lsu_wdata          (lsu_wdata),
        .lsu_wmask          (lsu_wmask),
        .lsu_respValid      (lsu_respValid),
        .lsu_respReady      (lsu_respReady),
        .lsu_rdata          (lsu_rdata)
    );

endmodule
