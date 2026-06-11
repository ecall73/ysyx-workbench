module top
(
    input             clock,
    input             reset
);

    // Shared MEM AXI4
    wire [31:0] mem_axi_araddr;
    wire [ 3:0] mem_axi_arid;
    wire [ 7:0] mem_axi_arlen;
    wire [ 2:0] mem_axi_arsize;
    wire [ 1:0] mem_axi_arburst;
    wire        mem_axi_arvalid;
    reg         mem_axi_arready;
    reg  [31:0] mem_axi_rdata;
    reg  [ 3:0] mem_axi_rid;
    reg  [ 1:0] mem_axi_rresp;
    reg         mem_axi_rlast;
    reg         mem_axi_rvalid;
    wire        mem_axi_rready;
    wire [31:0] mem_axi_awaddr;
    wire [ 3:0] mem_axi_awid;
    wire [ 7:0] mem_axi_awlen;
    wire [ 2:0] mem_axi_awsize;
    wire [ 1:0] mem_axi_awburst;
    wire        mem_axi_awvalid;
    reg         mem_axi_awready;
    wire [31:0] mem_axi_wdata;
    wire [ 3:0] mem_axi_wstrb;
    wire        mem_axi_wlast;
    wire        mem_axi_wvalid;
    reg         mem_axi_wready;
    reg  [ 3:0] mem_axi_bid;
    reg  [ 1:0] mem_axi_bresp;
    reg         mem_axi_bvalid;
    wire        mem_axi_bready;

    ysyx_26030082 #(
        .RESET_PC             (32'h8000_0000)
    ) Core_cpu (
        .clock                (clock),
        .reset                (reset),
        .io_interrupt         (1'b0),

        .io_master_araddr     (mem_axi_araddr),
        .io_master_arid       (mem_axi_arid),
        .io_master_arlen      (mem_axi_arlen),
        .io_master_arsize     (mem_axi_arsize),
        .io_master_arburst    (mem_axi_arburst),
        .io_master_arvalid    (mem_axi_arvalid),
        .io_master_arready    (mem_axi_arready),
        .io_master_rdata      (mem_axi_rdata),
        .io_master_rid        (mem_axi_rid),
        .io_master_rresp      (mem_axi_rresp),
        .io_master_rlast      (mem_axi_rlast),
        .io_master_rvalid     (mem_axi_rvalid),
        .io_master_rready     (mem_axi_rready),
        .io_master_awaddr     (mem_axi_awaddr),
        .io_master_awid       (mem_axi_awid),
        .io_master_awlen      (mem_axi_awlen),
        .io_master_awsize     (mem_axi_awsize),
        .io_master_awburst    (mem_axi_awburst),
        .io_master_awvalid    (mem_axi_awvalid),
        .io_master_awready    (mem_axi_awready),
        .io_master_wdata      (mem_axi_wdata),
        .io_master_wstrb      (mem_axi_wstrb),
        .io_master_wlast      (mem_axi_wlast),
        .io_master_wvalid     (mem_axi_wvalid),
        .io_master_wready     (mem_axi_wready),
        .io_master_bid        (mem_axi_bid),
        .io_master_bresp      (mem_axi_bresp),
        .io_master_bvalid     (mem_axi_bvalid),
        .io_master_bready     (mem_axi_bready),

        .io_slave_awready     (),
        .io_slave_awvalid     (1'b0),
        .io_slave_awid        (4'b0),
        .io_slave_awaddr      (32'b0),
        .io_slave_awlen       (8'b0),
        .io_slave_awsize      (3'b0),
        .io_slave_awburst     (2'b0),
        .io_slave_wready      (),
        .io_slave_wvalid      (1'b0),
        .io_slave_wdata       (32'b0),
        .io_slave_wstrb       (4'b0),
        .io_slave_wlast       (1'b0),
        .io_slave_bready      (1'b0),
        .io_slave_bvalid      (),
        .io_slave_bid         (),
        .io_slave_bresp       (),
        .io_slave_arready     (),
        .io_slave_arvalid     (1'b0),
        .io_slave_arid        (4'b0),
        .io_slave_araddr      (32'b0),
        .io_slave_arlen       (8'b0),
        .io_slave_arsize      (3'b0),
        .io_slave_arburst     (2'b0),
        .io_slave_rready      (1'b0),
        .io_slave_rvalid      (),
        .io_slave_rid         (),
        .io_slave_rdata       (),
        .io_slave_rresp       (),
        .io_slave_rlast       ()
    );

`include "top_axi_slave_impl.vh"

endmodule
