module ysyx_26030082_axi4lite_arbiter (
    input  wire        clock,
    input  wire        reset,
    // IFU master interface
    input  wire [31:0] ifu_master_araddr,
    input  wire [ 7:0] ifu_master_arlen,
    input  wire [ 1:0] ifu_master_arburst,
    input  wire        ifu_master_arvalid,
    output wire        ifu_master_arready,
    output wire [31:0] ifu_master_rdata,
    output wire [ 1:0] ifu_master_rresp,
    output wire        ifu_master_rlast,
    output wire        ifu_master_rvalid,
    input  wire        ifu_master_rready,
    // LSU master interface
    input  wire [31:0] lsu_master_araddr,
    input  wire [ 2:0] lsu_master_arsize,
    input  wire        lsu_master_arvalid,
    output wire        lsu_master_arready,
    output wire [31:0] lsu_master_rdata,
    output wire [ 1:0] lsu_master_rresp,
    output wire        lsu_master_rvalid,
    input  wire        lsu_master_rready,
    input  wire [31:0] lsu_master_awaddr,
    input  wire [ 2:0] lsu_master_awsize,
    input  wire        lsu_master_awvalid,
    output wire        lsu_master_awready,
    input  wire [31:0] lsu_master_wdata,
    input  wire [ 3:0] lsu_master_wstrb,
    input  wire        lsu_master_wvalid,
    output wire        lsu_master_wready,
    output wire [ 1:0] lsu_master_bresp,
    output wire        lsu_master_bvalid,
    input  wire        lsu_master_bready,
    // Shared IO master interface
    output wire [31:0] io_master_araddr,
    output wire [ 3:0] io_master_arid,
    output wire [ 7:0] io_master_arlen,
    output wire [ 2:0] io_master_arsize,
    output wire [ 1:0] io_master_arburst,
    output wire        io_master_arvalid,
    input  wire        io_master_arready,
    input  wire [31:0] io_master_rdata,
    input  wire [ 3:0] io_master_rid,
    input  wire [ 1:0] io_master_rresp,
    input  wire        io_master_rlast,
    input  wire        io_master_rvalid,
    output wire        io_master_rready,
    output wire [31:0] io_master_awaddr,
    output wire [ 3:0] io_master_awid,
    output wire [ 7:0] io_master_awlen,
    output wire [ 2:0] io_master_awsize,
    output wire [ 1:0] io_master_awburst,
    output wire        io_master_awvalid,
    input  wire        io_master_awready,
    output wire [31:0] io_master_wdata,
    output wire [ 3:0] io_master_wstrb,
    output wire        io_master_wlast,
    output wire        io_master_wvalid,
    input  wire        io_master_wready,
    input  wire [ 3:0] io_master_bid,
    input  wire [ 1:0] io_master_bresp,
    input  wire        io_master_bvalid,
    output wire        io_master_bready
);

    localparam R_IDLE = 2'd0;
    localparam R_AR   = 2'd1;
    localparam R_DATA = 2'd2;

    localparam R_OWNER_NONE = 1'b0;
    localparam R_OWNER_LSU  = 1'b0;
    localparam R_OWNER_IFU  = 1'b1;

    reg [1:0] rd_state;
    reg       rd_owner;

    wire req_lsu_rd;
    wire req_ifu_rd;
    wire rd_sel_lsu;
    wire rd_sel_ifu;
    wire rd_data_lsu;
    wire rd_data_ifu;
    wire lsu_ar_fire;
    wire lsu_r_fire;
    wire ifu_ar_fire;
    wire ifu_r_fire;

    assign req_lsu_rd = lsu_master_arvalid;
    assign req_ifu_rd = ifu_master_arvalid;
    assign rd_sel_lsu = ((rd_state == R_IDLE) && req_lsu_rd) ||
                        ((rd_state == R_AR) && (rd_owner == R_OWNER_LSU));
    assign rd_sel_ifu = ((rd_state == R_IDLE) && ~req_lsu_rd && req_ifu_rd) ||
                        ((rd_state == R_AR) && (rd_owner == R_OWNER_IFU));
    assign rd_data_lsu = (rd_state == R_DATA) && (rd_owner == R_OWNER_LSU);
    assign rd_data_ifu = (rd_state == R_DATA) && (rd_owner == R_OWNER_IFU);

    assign lsu_ar_fire = rd_sel_lsu && lsu_master_arvalid && io_master_arready;
    assign ifu_ar_fire = rd_sel_ifu && ifu_master_arvalid && io_master_arready;
    assign lsu_r_fire = rd_data_lsu && io_master_rvalid && lsu_master_rready;
    assign ifu_r_fire = rd_data_ifu && io_master_rvalid && ifu_master_rready;

    assign ifu_master_arready = rd_sel_ifu && io_master_arready;
    assign ifu_master_rdata = io_master_rdata;
    assign ifu_master_rresp = io_master_rresp;
    assign ifu_master_rlast = io_master_rlast;
    assign ifu_master_rvalid = rd_data_ifu && io_master_rvalid;

    assign lsu_master_arready = rd_sel_lsu && io_master_arready;
    assign lsu_master_rdata = io_master_rdata;
    assign lsu_master_rresp = io_master_rresp;
    assign lsu_master_rvalid = rd_data_lsu && io_master_rvalid;

    assign lsu_master_awready = io_master_awready;
    assign lsu_master_wready = io_master_wready;
    assign lsu_master_bresp = io_master_bresp;
    assign lsu_master_bvalid = io_master_bvalid;

    assign io_master_araddr = rd_sel_ifu ? ifu_master_araddr : lsu_master_araddr;
    assign io_master_arid = rd_sel_ifu ? 4'h1 : 4'h0;
    assign io_master_arlen = rd_sel_ifu ? ifu_master_arlen : 8'h00;
    assign io_master_arsize = rd_sel_ifu ? 3'b010 : lsu_master_arsize;
    assign io_master_arburst = rd_sel_ifu ? ifu_master_arburst : 2'b00;
    assign io_master_arvalid = (rd_sel_ifu && ifu_master_arvalid) ||
                             (rd_sel_lsu && lsu_master_arvalid);
    assign io_master_rready = (rd_owner == R_OWNER_IFU) ?
                            (rd_data_ifu && ifu_master_rready) :
                            (rd_data_lsu && lsu_master_rready);

    assign io_master_awaddr = lsu_master_awaddr;
    assign io_master_awid = 4'h0;
    assign io_master_awlen = 8'h00;
    assign io_master_awsize = lsu_master_awsize;
    assign io_master_awburst = 2'b00;
    assign io_master_awvalid = lsu_master_awvalid;
    assign io_master_wdata = lsu_master_wdata;
    assign io_master_wstrb = lsu_master_wstrb;
    assign io_master_wlast = 1'b1;
    assign io_master_wvalid = lsu_master_wvalid;
    assign io_master_bready = lsu_master_bready;

    always @(posedge clock) begin
        if (reset) begin
            rd_state <= R_IDLE;
            rd_owner <= R_OWNER_NONE;
        end else begin
            case (rd_state)
                R_IDLE: begin
                    if (req_lsu_rd) begin
                        rd_owner <= R_OWNER_LSU;
                        rd_state <= lsu_ar_fire ? R_DATA : R_AR;
                    end else if (req_ifu_rd) begin
                        rd_owner <= R_OWNER_IFU;
                        rd_state <= ifu_ar_fire ? R_DATA : R_AR;
                    end else begin
                        rd_owner <= R_OWNER_NONE;
                    end
                end

                R_AR: begin
                    if (lsu_ar_fire || ifu_ar_fire) begin
                        rd_state <= R_DATA;
                    end
                end

                R_DATA: begin
                    if ((lsu_r_fire || ifu_r_fire) && io_master_rlast) begin
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
    assign _unused_ok = &{1'b0, io_master_rid, io_master_bid};

endmodule
