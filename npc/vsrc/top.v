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

    // LSU AXI4-Lite (no PROT)
    wire [31:0] lsu_axi_araddr;
    wire        lsu_axi_arvalid;
    wire        lsu_axi_arready;
    wire [31:0] lsu_axi_rdata;
    wire [ 1:0] lsu_axi_rresp;
    wire        lsu_axi_rvalid;
    wire        lsu_axi_rready;
    wire [31:0] lsu_axi_awaddr;
    wire        lsu_axi_awvalid;
    wire        lsu_axi_awready;
    wire [31:0] lsu_axi_wdata;
    wire [ 3:0] lsu_axi_wstrb;
    wire        lsu_axi_wvalid;
    wire        lsu_axi_wready;
    wire [ 1:0] lsu_axi_bresp;
    wire        lsu_axi_bvalid;
    wire        lsu_axi_bready;

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

        // Interface to LSU AXI4-Lite
        .lsu_axi_araddr     (lsu_axi_araddr),
        .lsu_axi_arvalid    (lsu_axi_arvalid),
        .lsu_axi_arready    (lsu_axi_arready),
        .lsu_axi_rdata      (lsu_axi_rdata),
        .lsu_axi_rresp      (lsu_axi_rresp),
        .lsu_axi_rvalid     (lsu_axi_rvalid),
        .lsu_axi_rready     (lsu_axi_rready),
        .lsu_axi_awaddr     (lsu_axi_awaddr),
        .lsu_axi_awvalid    (lsu_axi_awvalid),
        .lsu_axi_awready    (lsu_axi_awready),
        .lsu_axi_wdata      (lsu_axi_wdata),
        .lsu_axi_wstrb      (lsu_axi_wstrb),
        .lsu_axi_wvalid     (lsu_axi_wvalid),
        .lsu_axi_wready     (lsu_axi_wready),
        .lsu_axi_bresp      (lsu_axi_bresp),
        .lsu_axi_bvalid     (lsu_axi_bvalid),
        .lsu_axi_bready     (lsu_axi_bready)

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
        .lsu_axi_araddr     (lsu_axi_araddr),
        .lsu_axi_arvalid    (lsu_axi_arvalid),
        .lsu_axi_arready    (lsu_axi_arready),
        .lsu_axi_rdata      (lsu_axi_rdata),
        .lsu_axi_rresp      (lsu_axi_rresp),
        .lsu_axi_rvalid     (lsu_axi_rvalid),
        .lsu_axi_rready     (lsu_axi_rready),
        .lsu_axi_awaddr     (lsu_axi_awaddr),
        .lsu_axi_awvalid    (lsu_axi_awvalid),
        .lsu_axi_awready    (lsu_axi_awready),
        .lsu_axi_wdata      (lsu_axi_wdata),
        .lsu_axi_wstrb      (lsu_axi_wstrb),
        .lsu_axi_wvalid     (lsu_axi_wvalid),
        .lsu_axi_wready     (lsu_axi_wready),
        .lsu_axi_bresp      (lsu_axi_bresp),
        .lsu_axi_bvalid     (lsu_axi_bvalid),
        .lsu_axi_bready     (lsu_axi_bready)
    );

endmodule
