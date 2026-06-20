module ysyx_26030082_axi4lite_arbiter (
    input  wire        clock,
    input  wire        reset,
    // IFU master interface
    input  wire [31:0] ifu_axi_araddr,
    input  wire [ 7:0] ifu_axi_arlen,
    input  wire [ 1:0] ifu_axi_arburst,
    input  wire        ifu_axi_arvalid,
    output wire        ifu_axi_arready,
    output wire [31:0] ifu_axi_rdata,
    output wire [ 1:0] ifu_axi_rresp,
    output wire        ifu_axi_rlast,
    output wire        ifu_axi_rvalid,
    input  wire        ifu_axi_rready,
    // MEM master interface
    input  wire [31:0] mem_axi_araddr,
    input  wire [ 2:0] mem_axi_arsize,
    input  wire        mem_axi_arvalid,
    output wire        mem_axi_arready,
    output wire [31:0] mem_axi_rdata,
    output wire [ 1:0] mem_axi_rresp,
    output wire        mem_axi_rvalid,
    input  wire        mem_axi_rready,
    input  wire [31:0] mem_axi_awaddr,
    input  wire [ 2:0] mem_axi_awsize,
    input  wire        mem_axi_awvalid,
    output wire        mem_axi_awready,
    input  wire [31:0] mem_axi_wdata,
    input  wire [ 3:0] mem_axi_wstrb,
    input  wire        mem_axi_wvalid,
    output wire        mem_axi_wready,
    output wire [ 1:0] mem_axi_bresp,
    output wire        mem_axi_bvalid,
    input  wire        mem_axi_bready,
    // Shared IO master interface
    output wire [31:0] io_axi_araddr,
    output wire [ 3:0] io_axi_arid,
    output wire [ 7:0] io_axi_arlen,
    output wire [ 2:0] io_axi_arsize,
    output wire [ 1:0] io_axi_arburst,
    output wire        io_axi_arvalid,
    input  wire        io_axi_arready,
    input  wire [31:0] io_axi_rdata,
    input  wire [ 3:0] io_axi_rid,
    input  wire [ 1:0] io_axi_rresp,
    input  wire        io_axi_rlast,
    input  wire        io_axi_rvalid,
    output wire        io_axi_rready,
    output wire [31:0] io_axi_awaddr,
    output wire [ 3:0] io_axi_awid,
    output wire [ 7:0] io_axi_awlen,
    output wire [ 2:0] io_axi_awsize,
    output wire [ 1:0] io_axi_awburst,
    output wire        io_axi_awvalid,
    input  wire        io_axi_awready,
    output wire [31:0] io_axi_wdata,
    output wire [ 3:0] io_axi_wstrb,
    output wire        io_axi_wlast,
    output wire        io_axi_wvalid,
    input  wire        io_axi_wready,
    input  wire [ 3:0] io_axi_bid,
    input  wire [ 1:0] io_axi_bresp,
    input  wire        io_axi_bvalid,
    output wire        io_axi_bready
);

    localparam R_IDLE = 2'd0;
    localparam R_AR   = 2'd1;
    localparam R_DATA = 2'd2;

    localparam R_OWNER_NONE = 1'b0;
    localparam R_OWNER_MEM  = 1'b0;
    localparam R_OWNER_IFU  = 1'b1;

    reg [1:0] rd_state;
    reg       rd_owner;

    wire req_mem_rd;
    wire req_ifu_rd;
    wire rd_sel_mem;
    wire rd_sel_ifu;
    wire rd_data_mem;
    wire rd_data_ifu;
    wire mem_ar_fire;
    wire mem_r_fire;
    wire ifu_ar_fire;
    wire ifu_r_fire;

    assign req_mem_rd = mem_axi_arvalid;
    assign req_ifu_rd = ifu_axi_arvalid;
    assign rd_sel_mem = ((rd_state == R_IDLE) && req_mem_rd) ||
                        ((rd_state == R_AR) && (rd_owner == R_OWNER_MEM));
    assign rd_sel_ifu = ((rd_state == R_IDLE) && ~req_mem_rd && req_ifu_rd) ||
                        ((rd_state == R_AR) && (rd_owner == R_OWNER_IFU));
    assign rd_data_mem = (rd_state == R_DATA) && (rd_owner == R_OWNER_MEM);
    assign rd_data_ifu = (rd_state == R_DATA) && (rd_owner == R_OWNER_IFU);

    assign mem_ar_fire = rd_sel_mem && mem_axi_arvalid && io_axi_arready;
    assign ifu_ar_fire = rd_sel_ifu && ifu_axi_arvalid && io_axi_arready;
    assign mem_r_fire = rd_data_mem && io_axi_rvalid && mem_axi_rready;
    assign ifu_r_fire = rd_data_ifu && io_axi_rvalid && ifu_axi_rready;

    assign ifu_axi_arready = rd_sel_ifu && io_axi_arready;
    assign ifu_axi_rdata = io_axi_rdata;
    assign ifu_axi_rresp = io_axi_rresp;
    assign ifu_axi_rlast = io_axi_rlast;
    assign ifu_axi_rvalid = rd_data_ifu && io_axi_rvalid;

    assign mem_axi_arready = rd_sel_mem && io_axi_arready;
    assign mem_axi_rdata = io_axi_rdata;
    assign mem_axi_rresp = io_axi_rresp;
    assign mem_axi_rvalid = rd_data_mem && io_axi_rvalid;

    assign mem_axi_awready = io_axi_awready;
    assign mem_axi_wready = io_axi_wready;
    assign mem_axi_bresp = io_axi_bresp;
    assign mem_axi_bvalid = io_axi_bvalid;

    assign io_axi_araddr = rd_sel_ifu ? ifu_axi_araddr : mem_axi_araddr;
    assign io_axi_arid = rd_sel_ifu ? 4'h1 : 4'h0;
    assign io_axi_arlen = rd_sel_ifu ? ifu_axi_arlen : 8'h00;
    assign io_axi_arsize = rd_sel_ifu ? 3'b010 : mem_axi_arsize;
    assign io_axi_arburst = rd_sel_ifu ? ifu_axi_arburst : 2'b00;
    assign io_axi_arvalid = (rd_sel_ifu && ifu_axi_arvalid) ||
                             (rd_sel_mem && mem_axi_arvalid);
    assign io_axi_rready = (rd_owner == R_OWNER_IFU) ?
                            (rd_data_ifu && ifu_axi_rready) :
                            (rd_data_mem && mem_axi_rready);

    assign io_axi_awaddr = mem_axi_awaddr;
    assign io_axi_awid = 4'h0;
    assign io_axi_awlen = 8'h00;
    assign io_axi_awsize = mem_axi_awsize;
    assign io_axi_awburst = 2'b00;
    assign io_axi_awvalid = mem_axi_awvalid;
    assign io_axi_wdata = mem_axi_wdata;
    assign io_axi_wstrb = mem_axi_wstrb;
    assign io_axi_wlast = 1'b1;
    assign io_axi_wvalid = mem_axi_wvalid;
    assign io_axi_bready = mem_axi_bready;

    always @(posedge clock) begin
        if (reset) begin
            rd_state <= R_IDLE;
            rd_owner <= R_OWNER_NONE;
        end else begin
            case (rd_state)
                R_IDLE: begin
                    if (req_mem_rd) begin
                        rd_owner <= R_OWNER_MEM;
                        rd_state <= mem_ar_fire ? R_DATA : R_AR;
                    end else if (req_ifu_rd) begin
                        rd_owner <= R_OWNER_IFU;
                        rd_state <= ifu_ar_fire ? R_DATA : R_AR;
                    end else begin
                        rd_owner <= R_OWNER_NONE;
                    end
                end

                R_AR: begin
                    if (mem_ar_fire || ifu_ar_fire) begin
                        rd_state <= R_DATA;
                    end
                end

                R_DATA: begin
                    if ((mem_r_fire || ifu_r_fire) && io_axi_rlast) begin
                        rd_state <= R_IDLE;
                        rd_owner <= R_OWNER_NONE;
                    end
                end

                default: begin
                    rd_state <= R_IDLE;
                    rd_owner <= R_OWNER_NONE;
                end
            endcase
        end
    end

    wire _unused_ok;
    assign _unused_ok = &{1'b0, io_axi_rid, io_axi_bid};

endmodule
