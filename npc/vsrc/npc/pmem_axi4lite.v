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
`ifdef __ICARUS__
    localparam [31:0] PMEM_BASE_ADDR = 32'h8000_0000;
    localparam integer PMEM_BYTES = 32'h0800_0000;

    reg [7:0] pmem [0:PMEM_BYTES-1];
    reg [8*256-1:0] img_file;
    integer img_load_status;
    integer img_bytes;

    function [31:0] pmem_model_read;
        input [31:0] raddr;
        integer byte_addr;
        begin
            byte_addr = {raddr[31:2], 2'b00} - PMEM_BASE_ADDR;
            if ((raddr < PMEM_BASE_ADDR) || (byte_addr < 0) || (byte_addr > (PMEM_BYTES - 4))) begin
                pmem_model_read = 32'hxxxx_xxxx;
            end else begin
                pmem_model_read = {
                    pmem[byte_addr + 3],
                    pmem[byte_addr + 2],
                    pmem[byte_addr + 1],
                    pmem[byte_addr + 0]
                };
            end
        end
    endfunction

    task pmem_model_write;
        input [31:0] waddr;
        input [31:0] wdata;
        input [7:0]  wmask;
        integer byte_addr;
        begin
            byte_addr = {waddr[31:2], 2'b00} - PMEM_BASE_ADDR;
            if ((waddr < PMEM_BASE_ADDR) || (byte_addr < 0) || (byte_addr > (PMEM_BYTES - 4))) begin
                $display("pmem_axi4lite: write out of range addr=0x%08x", waddr);
            end else begin
                if (wmask[0]) begin
                    pmem[byte_addr + 0] = wdata[7:0];
                end
                if (wmask[1]) begin
                    pmem[byte_addr + 1] = wdata[15:8];
                end
                if (wmask[2]) begin
                    pmem[byte_addr + 2] = wdata[23:16];
                end
                if (wmask[3]) begin
                    pmem[byte_addr + 3] = wdata[31:24];
                end
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("IMG=%s", img_file)) begin
            $display("pmem_axi4lite: missing +IMG=<image.hex> plusarg");
            $finish;
        end
        img_load_status = $fopen(img_file, "r");
        if (img_load_status == 0) begin
            $display("pmem_axi4lite: failed to open image %0s", img_file);
            $finish;
        end
        $fclose(img_load_status);
        if ($value$plusargs("IMG_BYTES=%d", img_bytes)) begin
            $readmemh(img_file, pmem, 0, img_bytes - 1);
        end else begin
            $readmemh(img_file, pmem);
        end
    end
`else
    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);
`endif

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
`ifdef __ICARUS__
                        rd_data_reg <= pmem_model_read(pmem_axi_araddr);
`else
                        rd_data_reg <= pmem_read(pmem_axi_araddr);
`endif
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
`ifdef __ICARUS__
                            pmem_model_write(pmem_axi_awaddr, pmem_axi_wdata, {4'b0000, pmem_axi_wstrb});
`else
                            pmem_write(pmem_axi_awaddr, pmem_axi_wdata, {4'b0000, pmem_axi_wstrb});
`endif
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
`ifdef __ICARUS__
                                2'b00: rd_data_reg <= pmem_model_read(rd_addr_reg);
                                2'b01: rd_data_reg <= pmem_model_read(rd_addr_reg + 32'd4);
                                default: rd_data_reg <= pmem_model_read(rd_addr_reg + 32'd4);
`else
                                2'b00: rd_data_reg <= pmem_read(rd_addr_reg);
                                2'b01: rd_data_reg <= pmem_read(rd_addr_reg + 32'd4);
                                default: rd_data_reg <= pmem_read(rd_addr_reg + 32'd4);
`endif
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
`ifdef __ICARUS__
                        pmem_model_write(wr_addr_now, wr_data_now, {4'b0000, wr_strb_now});
`else
                        pmem_write(wr_addr_now, wr_data_now, {4'b0000, wr_strb_now});
`endif
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
