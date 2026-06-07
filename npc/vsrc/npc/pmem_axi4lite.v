`timescale 1ns / 1ps
module pmem_axi4lite (
    input  wire        clock,
    input  wire        reset,
    // AXI read address channel
    input  wire [31:0] pmem_axi_araddr,
    input  wire [ 7:0] pmem_axi_arlen,
    input  wire [ 1:0] pmem_axi_arburst,
    input  wire        pmem_axi_arvalid,
    output wire        pmem_axi_arready,
    // AXI read data channel
    output wire [31:0] pmem_axi_rdata,
    output wire [ 1:0] pmem_axi_rresp,
    output wire        pmem_axi_rlast,
    output wire        pmem_axi_rvalid,
    input  wire        pmem_axi_rready,
    // AXI write address channel
    input  wire [31:0] pmem_axi_awaddr,
    input  wire        pmem_axi_awvalid,
    output wire        pmem_axi_awready,
    // AXI write data channel
    input  wire [31:0] pmem_axi_wdata,
    input  wire [ 3:0] pmem_axi_wstrb,
    input  wire        pmem_axi_wvalid,
    output wire        pmem_axi_wready,
    // AXI write response channel
    output wire [ 1:0] pmem_axi_bresp,
    output wire        pmem_axi_bvalid,
    input  wire        pmem_axi_bready
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    localparam S_IDLE       = 2'd0;
    localparam S_RD_RESP    = 2'd1;
    localparam S_WR_COLLECT = 2'd2;
    localparam S_WR_RESP    = 2'd3;

    reg [1:0] state;

    reg [31:0] rd_data_reg;
    reg [31:0] rd_addr_reg;
    reg [ 7:0] rd_beats_left;
    reg [ 1:0] rd_burst_reg;
    reg [31:0] wr_addr_reg;
    reg [31:0] wr_data_reg;
    reg [ 3:0] wr_strb_reg;
    reg        aw_captured;
    reg        w_captured;

    wire ar_fire;
    wire r_fire;
    wire aw_fire;
    wire w_fire;
    wire b_fire;

    wire wr_complete_now;
    wire [31:0] wr_addr_now;
    wire [31:0] wr_data_now;
    wire [ 3:0] wr_strb_now;

    assign pmem_axi_arready = (state == S_IDLE);
    assign pmem_axi_rvalid  = (state == S_RD_RESP);
    assign pmem_axi_rdata   = rd_data_reg;
    assign pmem_axi_rresp   = 2'b00;
    assign pmem_axi_rlast   = (rd_beats_left == 8'd1);

    // The upstream bridge serializes requests, so IDLE can expose READY directly.
    assign pmem_axi_awready = (state == S_IDLE) || ((state == S_WR_COLLECT) && !aw_captured);
    assign pmem_axi_wready  = (state == S_IDLE) || ((state == S_WR_COLLECT) && !w_captured);
    assign pmem_axi_bvalid  = (state == S_WR_RESP);
    assign pmem_axi_bresp   = 2'b00;

    assign ar_fire = pmem_axi_arvalid && pmem_axi_arready;
    assign r_fire  = pmem_axi_rvalid  && pmem_axi_rready;
    assign aw_fire = pmem_axi_awvalid && pmem_axi_awready;
    assign w_fire  = pmem_axi_wvalid  && pmem_axi_wready;
    assign b_fire  = pmem_axi_bvalid  && pmem_axi_bready;

    assign wr_complete_now = (aw_captured || aw_fire) && (w_captured || w_fire);
    assign wr_addr_now = aw_captured ? wr_addr_reg : pmem_axi_awaddr;
    assign wr_data_now = w_captured ? wr_data_reg : pmem_axi_wdata;
    assign wr_strb_now = w_captured ? wr_strb_reg : pmem_axi_wstrb;

    always @(posedge clock) begin
        if (reset) begin
            state        <= S_IDLE;
            rd_data_reg  <= 32'b0;
            rd_addr_reg  <= 32'b0;
            rd_beats_left <= 8'b0;
            rd_burst_reg <= 2'b0;
            wr_addr_reg  <= 32'b0;
            wr_data_reg  <= 32'b0;
            wr_strb_reg  <= 4'b0;
            aw_captured  <= 1'b0;
            w_captured   <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    aw_captured <= 1'b0;
                    w_captured  <= 1'b0;

                    if (ar_fire) begin
                        rd_data_reg <= pmem_read(pmem_axi_araddr);
                        rd_addr_reg <= pmem_axi_araddr;
                        rd_beats_left <= pmem_axi_arlen + 8'd1;
                        rd_burst_reg <= pmem_axi_arburst;
                        state <= S_RD_RESP;
                    end else if (aw_fire || w_fire) begin
                        if (aw_fire) begin
                            wr_addr_reg <= pmem_axi_awaddr;
                            aw_captured <= 1'b1;
                        end
                        if (w_fire) begin
                            wr_data_reg <= pmem_axi_wdata;
                            wr_strb_reg <= pmem_axi_wstrb;
                            w_captured  <= 1'b1;
                        end

                        if (aw_fire && w_fire) begin
                            pmem_write(pmem_axi_awaddr, pmem_axi_wdata, {4'b0000, pmem_axi_wstrb});
                            state <= S_WR_RESP;
                        end else begin
                            state <= S_WR_COLLECT;
                        end
                    end
                end

                S_RD_RESP: begin
                    if (r_fire) begin
                        if (rd_beats_left == 8'd1) begin
                            state <= S_IDLE;
                        end else begin
                            rd_beats_left <= rd_beats_left - 8'd1;
                            case (rd_burst_reg)
                                2'b00: rd_addr_reg <= rd_addr_reg;
                                2'b01: rd_addr_reg <= rd_addr_reg + 32'd4;
                                default: rd_addr_reg <= rd_addr_reg + 32'd4;
                            endcase
                            case (rd_burst_reg)
                                2'b00: rd_data_reg <= pmem_read(rd_addr_reg);
                                2'b01: rd_data_reg <= pmem_read(rd_addr_reg + 32'd4);
                                default: rd_data_reg <= pmem_read(rd_addr_reg + 32'd4);
                            endcase
                        end
                    end
                end

                S_WR_COLLECT: begin
                    if (aw_fire) begin
                        wr_addr_reg <= pmem_axi_awaddr;
                        aw_captured <= 1'b1;
                    end
                    if (w_fire) begin
                        wr_data_reg <= pmem_axi_wdata;
                        wr_strb_reg <= pmem_axi_wstrb;
                        w_captured  <= 1'b1;
                    end

                    if (wr_complete_now) begin
                        pmem_write(wr_addr_now, wr_data_now, {4'b0000, wr_strb_now});
                        state <= S_WR_RESP;
                    end
                end

                S_WR_RESP: begin
                    if (b_fire) begin
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    aw_captured <= 1'b0;
                    w_captured <= 1'b0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clock) begin
        if (!reset) begin
            if (pmem_axi_arvalid && pmem_axi_arready &&
                (pmem_axi_arburst != 2'b00) && (pmem_axi_arburst != 2'b01)) begin
                $fatal(1, "pmem_axi4lite: unsupported read burst type %0b", pmem_axi_arburst);
            end
        end
    end
`endif
endmodule
