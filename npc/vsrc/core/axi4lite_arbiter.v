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
    // LSU master interface
    input  wire [31:0] lsu_axi_araddr,
    input  wire [ 2:0] lsu_axi_arsize,
    input  wire        lsu_axi_arvalid,
    output wire        lsu_axi_arready,
    output wire [31:0] lsu_axi_rdata,
    output wire [ 1:0] lsu_axi_rresp,
    output wire        lsu_axi_rvalid,
    input  wire        lsu_axi_rready,
    input  wire [31:0] lsu_axi_awaddr,
    input  wire [ 2:0] lsu_axi_awsize,
    input  wire        lsu_axi_awvalid,
    output wire        lsu_axi_awready,
    input  wire [31:0] lsu_axi_wdata,
    input  wire [ 3:0] lsu_axi_wstrb,
    input  wire        lsu_axi_wvalid,
    output wire        lsu_axi_wready,
    output wire [ 1:0] lsu_axi_bresp,
    output wire        lsu_axi_bvalid,
    input  wire        lsu_axi_bready,
    // Shared MEM slave interface
    output wire [31:0] mem_axi_araddr,
    output wire [ 3:0] mem_axi_arid,
    output wire [ 7:0] mem_axi_arlen,
    output wire [ 2:0] mem_axi_arsize,
    output wire [ 1:0] mem_axi_arburst,
    output wire        mem_axi_arvalid,
    input  wire        mem_axi_arready,
    input  wire [31:0] mem_axi_rdata,
    input  wire [ 3:0] mem_axi_rid,
    input  wire [ 1:0] mem_axi_rresp,
    input  wire        mem_axi_rlast,
    input  wire        mem_axi_rvalid,
    output wire        mem_axi_rready,
    output wire [31:0] mem_axi_awaddr,
    output wire [ 3:0] mem_axi_awid,
    output wire [ 7:0] mem_axi_awlen,
    output wire [ 2:0] mem_axi_awsize,
    output wire [ 1:0] mem_axi_awburst,
    output wire        mem_axi_awvalid,
    input  wire        mem_axi_awready,
    output wire [31:0] mem_axi_wdata,
    output wire [ 3:0] mem_axi_wstrb,
    output wire        mem_axi_wlast,
    output wire        mem_axi_wvalid,
    input  wire        mem_axi_wready,
    input  wire [ 3:0] mem_axi_bid,
    input  wire [ 1:0] mem_axi_bresp,
    input  wire        mem_axi_bvalid,
    output wire        mem_axi_bready
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

    assign req_lsu_rd = lsu_axi_arvalid;
    assign req_ifu_rd = ifu_axi_arvalid;
    assign rd_sel_lsu = (rd_state == R_AR) && (rd_owner == R_OWNER_LSU);
    assign rd_sel_ifu = (rd_state == R_AR) && (rd_owner == R_OWNER_IFU);
    assign rd_data_lsu = (rd_state == R_DATA) && (rd_owner == R_OWNER_LSU);
    assign rd_data_ifu = (rd_state == R_DATA) && (rd_owner == R_OWNER_IFU);

    assign lsu_ar_fire = rd_sel_lsu && lsu_axi_arvalid && mem_axi_arready;
    assign ifu_ar_fire = rd_sel_ifu && ifu_axi_arvalid && mem_axi_arready;
    assign lsu_r_fire = rd_data_lsu && mem_axi_rvalid && lsu_axi_rready;
    assign ifu_r_fire = rd_data_ifu && mem_axi_rvalid && ifu_axi_rready;

    assign ifu_axi_arready = rd_sel_ifu && mem_axi_arready;
    assign ifu_axi_rdata = mem_axi_rdata;
    assign ifu_axi_rresp = mem_axi_rresp;
    assign ifu_axi_rlast = mem_axi_rlast;
    assign ifu_axi_rvalid = rd_data_ifu && mem_axi_rvalid;

    assign lsu_axi_arready = rd_sel_lsu && mem_axi_arready;
    assign lsu_axi_rdata = mem_axi_rdata;
    assign lsu_axi_rresp = mem_axi_rresp;
    assign lsu_axi_rvalid = rd_data_lsu && mem_axi_rvalid;

    assign lsu_axi_awready = mem_axi_awready;
    assign lsu_axi_wready = mem_axi_wready;
    assign lsu_axi_bresp = mem_axi_bresp;
    assign lsu_axi_bvalid = mem_axi_bvalid;

    assign mem_axi_araddr = (rd_owner == R_OWNER_IFU) ? ifu_axi_araddr : lsu_axi_araddr;
    assign mem_axi_arid = (rd_owner == R_OWNER_IFU) ? 4'h1 : 4'h0;
    assign mem_axi_arlen = (rd_owner == R_OWNER_IFU) ? ifu_axi_arlen : 8'h00;
    assign mem_axi_arsize = (rd_owner == R_OWNER_IFU) ? 3'b010 : lsu_axi_arsize;
    assign mem_axi_arburst = (rd_owner == R_OWNER_IFU) ? ifu_axi_arburst : 2'b00;
    assign mem_axi_arvalid = (rd_owner == R_OWNER_IFU) ?
                             (rd_sel_ifu && ifu_axi_arvalid) :
                             (rd_sel_lsu && lsu_axi_arvalid);
    assign mem_axi_rready = (rd_owner == R_OWNER_IFU) ?
                            (rd_data_ifu && ifu_axi_rready) :
                            (rd_data_lsu && lsu_axi_rready);

    assign mem_axi_awaddr = lsu_axi_awaddr;
    assign mem_axi_awid = 4'h0;
    assign mem_axi_awlen = 8'h00;
    assign mem_axi_awsize = lsu_axi_awsize;
    assign mem_axi_awburst = 2'b00;
    assign mem_axi_awvalid = lsu_axi_awvalid;
    assign mem_axi_wdata = lsu_axi_wdata;
    assign mem_axi_wstrb = lsu_axi_wstrb;
    assign mem_axi_wlast = 1'b1;
    assign mem_axi_wvalid = lsu_axi_wvalid;
    assign mem_axi_bready = lsu_axi_bready;

    always @(posedge clock) begin
        if (reset) begin
            rd_state <= R_IDLE;
            rd_owner <= R_OWNER_NONE;
        end else begin
            case (rd_state)
                R_IDLE: begin
                    if (req_lsu_rd) begin
                        rd_state <= R_AR;
                        rd_owner <= R_OWNER_LSU;
                    end else if (req_ifu_rd) begin
                        rd_state <= R_AR;
                        rd_owner <= R_OWNER_IFU;
                    end
                end

                R_AR: begin
                    if (lsu_ar_fire || ifu_ar_fire) begin
                        rd_state <= R_DATA;
                    end
                end

                R_DATA: begin
                    if ((lsu_r_fire || ifu_r_fire) && mem_axi_rlast) begin
                        if (req_lsu_rd) begin
                            rd_state <= R_AR;
                            rd_owner <= R_OWNER_LSU;
                        end else if (req_ifu_rd) begin
                            rd_state <= R_AR;
                            rd_owner <= R_OWNER_IFU;
                        end else begin
                            rd_state <= R_IDLE;
                            rd_owner <= R_OWNER_NONE;
                        end
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
    assign _unused_ok = &{1'b0, mem_axi_rid, mem_axi_bid};

endmodule
