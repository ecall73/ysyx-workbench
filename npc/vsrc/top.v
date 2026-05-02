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

    // IFU AXI4-Lite
    wire [31:0] ifu_axi_araddr;
    wire        ifu_axi_arvalid;
    wire        ifu_axi_arready;
    wire [31:0] ifu_axi_rdata;
    wire [ 1:0] ifu_axi_rresp;
    wire        ifu_axi_rvalid;
    wire        ifu_axi_rready;
    wire [31:0] ifu_axi_awaddr;
    wire        ifu_axi_awvalid;
    wire        ifu_axi_awready;
    wire [31:0] ifu_axi_wdata;
    wire [ 3:0] ifu_axi_wstrb;
    wire        ifu_axi_wvalid;
    wire        ifu_axi_wready;
    wire [ 1:0] ifu_axi_bresp;
    wire        ifu_axi_bvalid;
    wire        ifu_axi_bready;

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

        // Interface to IFU AXI4-Lite
        .ifu_axi_araddr     (ifu_axi_araddr),
        .ifu_axi_arvalid    (ifu_axi_arvalid),
        .ifu_axi_arready    (ifu_axi_arready),
        .ifu_axi_rdata      (ifu_axi_rdata),
        .ifu_axi_rresp      (ifu_axi_rresp),
        .ifu_axi_rvalid     (ifu_axi_rvalid),
        .ifu_axi_rready     (ifu_axi_rready),
        .ifu_axi_awaddr     (ifu_axi_awaddr),
        .ifu_axi_awvalid    (ifu_axi_awvalid),
        .ifu_axi_awready    (ifu_axi_awready),
        .ifu_axi_wdata      (ifu_axi_wdata),
        .ifu_axi_wstrb      (ifu_axi_wstrb),
        .ifu_axi_wvalid     (ifu_axi_wvalid),
        .ifu_axi_wready     (ifu_axi_wready),
        .ifu_axi_bresp      (ifu_axi_bresp),
        .ifu_axi_bvalid     (ifu_axi_bvalid),
        .ifu_axi_bready     (ifu_axi_bready),

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
        .ifu_axi_araddr     (ifu_axi_araddr),
        .ifu_axi_arvalid    (ifu_axi_arvalid),
        .ifu_axi_arready    (ifu_axi_arready),
        .ifu_axi_rdata      (ifu_axi_rdata),
        .ifu_axi_rresp      (ifu_axi_rresp),
        .ifu_axi_rvalid     (ifu_axi_rvalid),
        .ifu_axi_rready     (ifu_axi_rready),
        .ifu_axi_awaddr     (ifu_axi_awaddr),
        .ifu_axi_awvalid    (ifu_axi_awvalid),
        .ifu_axi_awready    (ifu_axi_awready),
        .ifu_axi_wdata      (ifu_axi_wdata),
        .ifu_axi_wstrb      (ifu_axi_wstrb),
        .ifu_axi_wvalid     (ifu_axi_wvalid),
        .ifu_axi_wready     (ifu_axi_wready),
        .ifu_axi_bresp      (ifu_axi_bresp),
        .ifu_axi_bvalid     (ifu_axi_bvalid),
        .ifu_axi_bready     (ifu_axi_bready)
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
