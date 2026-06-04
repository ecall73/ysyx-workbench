`timescale 1ns / 1ps

module top
(
    input             clock,
    input             reset
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

    myCPU #(
        .RESET_PC             (32'h8000_0000),
        .TARGET_NPC           (1)
    ) Core_cpu (
        .clock                (clock),
        .reset                (reset),

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
    );
    
    perip_bridge bridge_inst (
        .clock				(clock),
        .reset                (reset),
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
