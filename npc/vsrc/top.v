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

    // Shared MEM AXI4-Lite
    wire [31:0] mem_axi_araddr;
    wire        mem_axi_arvalid;
    wire        mem_axi_arready;
    wire [31:0] mem_axi_rdata;
    wire [ 1:0] mem_axi_rresp;
    wire        mem_axi_rvalid;
    wire        mem_axi_rready;
    wire [31:0] mem_axi_awaddr;
    wire        mem_axi_awvalid;
    wire        mem_axi_awready;
    wire [31:0] mem_axi_wdata;
    wire [ 3:0] mem_axi_wstrb;
    wire        mem_axi_wvalid;
    wire        mem_axi_wready;
    wire [ 1:0] mem_axi_bresp;
    wire        mem_axi_bvalid;
    wire        mem_axi_bready;

    myCPU Core_cpu (
        .clk                (clk),
        .rst                (rst),

        // Interface to shared MEM AXI4-Lite
        .mem_axi_araddr     (mem_axi_araddr),
        .mem_axi_arvalid    (mem_axi_arvalid),
        .mem_axi_arready    (mem_axi_arready),
        .mem_axi_rdata      (mem_axi_rdata),
        .mem_axi_rresp      (mem_axi_rresp),
        .mem_axi_rvalid     (mem_axi_rvalid),
        .mem_axi_rready     (mem_axi_rready),
        .mem_axi_awaddr     (mem_axi_awaddr),
        .mem_axi_awvalid    (mem_axi_awvalid),
        .mem_axi_awready    (mem_axi_awready),
        .mem_axi_wdata      (mem_axi_wdata),
        .mem_axi_wstrb      (mem_axi_wstrb),
        .mem_axi_wvalid     (mem_axi_wvalid),
        .mem_axi_wready     (mem_axi_wready),
        .mem_axi_bresp      (mem_axi_bresp),
        .mem_axi_bvalid     (mem_axi_bvalid),
        .mem_axi_bready     (mem_axi_bready)

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
    
    perip_bridge bridge_inst (
        .clk				(clk),
        .rst                (rst),
        .mem_axi_araddr     (mem_axi_araddr),
        .mem_axi_arvalid    (mem_axi_arvalid),
        .mem_axi_arready    (mem_axi_arready),
        .mem_axi_rdata      (mem_axi_rdata),
        .mem_axi_rresp      (mem_axi_rresp),
        .mem_axi_rvalid     (mem_axi_rvalid),
        .mem_axi_rready     (mem_axi_rready),
        .mem_axi_awaddr     (mem_axi_awaddr),
        .mem_axi_awvalid    (mem_axi_awvalid),
        .mem_axi_awready    (mem_axi_awready),
        .mem_axi_wdata      (mem_axi_wdata),
        .mem_axi_wstrb      (mem_axi_wstrb),
        .mem_axi_wvalid     (mem_axi_wvalid),
        .mem_axi_wready     (mem_axi_wready),
        .mem_axi_bresp      (mem_axi_bresp),
        .mem_axi_bvalid     (mem_axi_bvalid),
        .mem_axi_bready     (mem_axi_bready)
    );
endmodule
