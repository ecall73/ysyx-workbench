module top
(
    input             clock,
    input             reset
);

`ifdef NETLIST_SIM
`define TOP_WRITE_OOR_FMT "top(netlist): write out of range addr=0x%08x"
`define TOP_MISSING_IMG_FMT "top(netlist): missing +IMG=<image.hex> plusarg"
`define TOP_OPEN_IMG_FMT "top(netlist): failed to open image %0s"
`define TOP_MMIO_BURST_FMT "top(netlist): MMIO burst read is not supported addr=%08x"
`define TOP_WR_BURST_FMT "top(netlist): burst write is not supported addr=%08x"
`define TOP_WLAST_FMT "top(netlist): WLAST must be 1 for single-beat write"
`define TOP_RD_BURST_FMT "top(netlist): unsupported read burst type %0b"
`else
`define TOP_WRITE_OOR_FMT "top: write out of range addr=0x%08x"
`define TOP_MISSING_IMG_FMT "top: missing +IMG=<image.hex> plusarg"
`define TOP_OPEN_IMG_FMT "top: failed to open image %0s"
`define TOP_MMIO_BURST_FMT "top: MMIO burst read is not supported addr=%08x"
`define TOP_WR_BURST_FMT "top: burst write is not supported addr=%08x"
`define TOP_WLAST_FMT "top: WLAST must be 1 for single-beat write"
`define TOP_RD_BURST_FMT "top: unsupported read burst type %0b"
`endif

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

    localparam [31:0] UART_BASE_ADDR = 32'h1000_0000;
    localparam [31:0] UART_END_ADDR  = 32'h1000_0fff;

    localparam SEL_PMEM = 1'b0;
    localparam SEL_UART = 1'b1;

    localparam [2:0] S_IDLE       = 3'd0;
    localparam [2:0] S_RD_AR      = 3'd1;
    localparam [2:0] S_RD_R       = 3'd2;
    localparam [2:0] S_WR_COLLECT = 3'd3;
    localparam [2:0] S_WR_ISSUE   = 3'd4;
    localparam [2:0] S_WR_DATA    = 3'd5;
    localparam [2:0] S_WR_B       = 3'd6;

`ifdef __ICARUS__
    localparam [31:0] PMEM_BASE_ADDR = 32'h8000_0000;
    localparam [31:0] PMEM_BOOT_ALIAS_ADDR = 32'h3000_0000;
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
            if ((raddr >= PMEM_BOOT_ALIAS_ADDR) && (raddr < (PMEM_BOOT_ALIAS_ADDR + 32'h40))) begin
                case (raddr - PMEM_BOOT_ALIAS_ADDR)
                    32'h0000_0000: pmem_model_read = 32'h8000_02b7;
                    32'h0000_0004: pmem_model_read = 32'h0002_8067;
                    default:       pmem_model_read = 32'h0000_0013;
                endcase
            end else if ((raddr < PMEM_BASE_ADDR) || (byte_addr < 0) || (byte_addr > (PMEM_BYTES - 4))) begin
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
                $display(`TOP_WRITE_OOR_FMT, waddr);
            end else begin
                if (wmask[0]) pmem[byte_addr + 0] = wdata[7:0];
                if (wmask[1]) pmem[byte_addr + 1] = wdata[15:8];
                if (wmask[2]) pmem[byte_addr + 2] = wdata[23:16];
                if (wmask[3]) pmem[byte_addr + 3] = wdata[31:24];
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("IMG=%s", img_file)) begin
            $display(`TOP_MISSING_IMG_FMT);
            $finish;
        end
        img_load_status = $fopen(img_file, "r");
        if (img_load_status == 0) begin
            $display(`TOP_OPEN_IMG_FMT, img_file);
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

    reg [2:0] state;
    reg        rd_sel;
    reg [31:0] rd_addr_reg;
    reg [ 7:0] rd_len_reg;
    reg [ 1:0] rd_burst_reg;
    reg [ 7:0] rd_beats_left;
    reg        rd_buf_valid;
    reg [31:0] rd_buf_data;
    reg [ 1:0] rd_buf_resp;
    reg        rd_buf_last;
    reg        wr_sel;
    reg        wr_have_aw;
    reg        wr_have_w;
    reg        wr_buf_valid;
    reg [ 1:0] wr_buf_resp;
    reg [31:0] wr_addr_reg;
    reg [31:0] wr_data_reg;
    reg [ 3:0] wr_strb_reg;
    reg [31:0] uart_reg;
    reg [31:0] rd_next_addr;
    reg [31:0] rd_next_data;
    reg [31:0] uart_after_write;

    wire ar_sel;
    wire aw_sel;
    wire ar_fire;
    wire r_fire;
    wire aw_fire;
    wire w_fire;
    wire b_fire;
    wire rd_buf_take;

    assign ar_sel = ((mem_axi_araddr >= UART_BASE_ADDR) && (mem_axi_araddr <= UART_END_ADDR)) ? SEL_UART : SEL_PMEM;
    assign aw_sel = ((mem_axi_awaddr >= UART_BASE_ADDR) && (mem_axi_awaddr <= UART_END_ADDR)) ? SEL_UART : SEL_PMEM;
    assign ar_fire = mem_axi_arvalid && mem_axi_arready;
    assign r_fire  = mem_axi_rvalid  && mem_axi_rready;
    assign aw_fire = mem_axi_awvalid && mem_axi_awready;
    assign w_fire  = mem_axi_wvalid  && mem_axi_wready;
    assign b_fire  = mem_axi_bvalid  && mem_axi_bready;
    assign rd_buf_take = rd_buf_valid && mem_axi_rready;

    always @(*) begin
        rd_next_addr = rd_addr_reg;
        case (rd_burst_reg)
            2'b00: rd_next_addr = rd_addr_reg;
            2'b01: rd_next_addr = rd_addr_reg + 32'd4;
            default: rd_next_addr = rd_addr_reg + 32'd4;
        endcase
    end

    always @(*) begin
        uart_after_write = uart_reg;
        if (wr_strb_reg[0]) uart_after_write[7:0]   = wr_data_reg[7:0];
        if (wr_strb_reg[1]) uart_after_write[15:8]  = wr_data_reg[15:8];
        if (wr_strb_reg[2]) uart_after_write[23:16] = wr_data_reg[23:16];
        if (wr_strb_reg[3]) uart_after_write[31:24] = wr_data_reg[31:24];
    end

    always @(*) begin
`ifdef __ICARUS__
        rd_next_data = pmem_model_read(rd_next_addr);
`else
        rd_next_data = pmem_read(rd_next_addr);
`endif
    end

    always @(*) begin
        mem_axi_arready = 1'b0;
        mem_axi_rid     = 4'b0;
        mem_axi_rdata   = 32'b0;
        mem_axi_rresp   = 2'b00;
        mem_axi_rlast   = 1'b0;
        mem_axi_rvalid  = 1'b0;
        mem_axi_awready = 1'b0;
        mem_axi_wready  = 1'b0;
        mem_axi_bid     = 4'b0;
        mem_axi_bresp   = 2'b00;
        mem_axi_bvalid  = 1'b0;

        case (state)
            S_IDLE: begin
                mem_axi_arready = 1'b1;
                mem_axi_awready = 1'b1;
                mem_axi_wready  = 1'b1;
            end
            S_WR_COLLECT: begin
                mem_axi_awready = !wr_have_aw;
                mem_axi_wready  = !wr_have_w;
            end
            S_RD_R: begin
                mem_axi_rdata  = rd_buf_data;
                mem_axi_rresp  = rd_buf_resp;
                mem_axi_rlast  = rd_buf_last;
                mem_axi_rvalid = rd_buf_valid;
            end
            S_WR_B: begin
                mem_axi_bresp  = wr_buf_resp;
                mem_axi_bvalid = wr_buf_valid;
            end
            default: begin
            end
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            state         <= S_IDLE;
            rd_sel        <= SEL_PMEM;
            rd_addr_reg   <= 32'b0;
            rd_len_reg    <= 8'b0;
            rd_burst_reg  <= 2'b0;
            rd_beats_left <= 8'b0;
            rd_buf_valid  <= 1'b0;
            rd_buf_data   <= 32'b0;
            rd_buf_resp   <= 2'b0;
            rd_buf_last   <= 1'b0;
            wr_sel        <= SEL_PMEM;
            wr_have_aw    <= 1'b0;
            wr_have_w     <= 1'b0;
            wr_buf_valid  <= 1'b0;
            wr_buf_resp   <= 2'b0;
            wr_addr_reg   <= 32'b0;
            wr_data_reg   <= 32'b0;
            wr_strb_reg   <= 4'b0;
            uart_reg      <= 32'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    rd_buf_valid <= 1'b0;
                    wr_have_aw   <= 1'b0;
                    wr_have_w    <= 1'b0;
                    wr_buf_valid <= 1'b0;

                    if (ar_fire) begin
                        rd_sel       <= ar_sel;
                        rd_addr_reg  <= mem_axi_araddr;
                        rd_len_reg   <= mem_axi_arlen;
                        rd_burst_reg <= mem_axi_arburst;
                        state        <= S_RD_AR;
                    end else if (aw_fire || w_fire) begin
                        if (aw_fire) begin
                            wr_sel      <= aw_sel;
                            wr_addr_reg <= mem_axi_awaddr;
                        end
                        if (w_fire) begin
                            wr_data_reg <= mem_axi_wdata;
                            wr_strb_reg <= mem_axi_wstrb;
                        end
                        wr_have_aw <= aw_fire;
                        wr_have_w  <= w_fire;
                        state      <= (aw_fire && w_fire) ? S_WR_ISSUE : S_WR_COLLECT;
                    end
                end
                S_RD_AR: begin
                    if (rd_sel == SEL_UART) begin
                        rd_beats_left <= 8'd1;
                        rd_buf_valid  <= 1'b1;
                        rd_buf_data   <= uart_reg;
                        rd_buf_resp   <= 2'b00;
                        rd_buf_last   <= 1'b1;
                    end else begin
                        rd_beats_left <= rd_len_reg + 8'd1;
                        rd_buf_valid  <= 1'b1;
`ifdef __ICARUS__
                        rd_buf_data   <= pmem_model_read(rd_addr_reg);
`else
                        rd_buf_data   <= pmem_read(rd_addr_reg);
`endif
                        rd_buf_resp   <= 2'b00;
                        rd_buf_last   <= (rd_len_reg == 8'd0);
                    end
                    state <= S_RD_R;
                end
                S_RD_R: begin
                    if (rd_buf_take) begin
                        if (rd_buf_last) begin
                            rd_buf_valid <= 1'b0;
                            state <= S_IDLE;
                        end else begin
                            rd_beats_left <= rd_beats_left - 8'd1;
                            rd_addr_reg   <= rd_next_addr;
                            rd_buf_valid  <= 1'b1;
                            rd_buf_data   <= rd_next_data;
                            rd_buf_resp   <= 2'b00;
                            rd_buf_last   <= (rd_beats_left == 8'd2);
                        end
                    end
                end
                S_WR_COLLECT: begin
                    if (!wr_have_aw && aw_fire) begin
                        wr_sel      <= aw_sel;
                        wr_addr_reg <= mem_axi_awaddr;
                        wr_have_aw  <= 1'b1;
                    end
                    if (!wr_have_w && w_fire) begin
                        wr_data_reg <= mem_axi_wdata;
                        wr_strb_reg <= mem_axi_wstrb;
                        wr_have_w   <= 1'b1;
                    end
                    if ((wr_have_aw || aw_fire) && (wr_have_w || w_fire)) begin
                        state <= S_WR_ISSUE;
                    end
                end
                S_WR_ISSUE: begin
                    state <= S_WR_DATA;
                end
                S_WR_DATA: begin
                    if (wr_sel == SEL_UART) begin
                        uart_reg <= uart_after_write;
                        $write("%c", wr_data_reg[7:0]);
                        $fflush();
                    end else begin
`ifdef __ICARUS__
                        pmem_model_write(wr_addr_reg, wr_data_reg, {4'b0000, wr_strb_reg});
`else
                        pmem_write(wr_addr_reg, wr_data_reg, {4'b0000, wr_strb_reg});
`endif
                    end
                    wr_buf_valid <= 1'b1;
                    wr_buf_resp  <= 2'b00;
                    state <= S_WR_B;
                end
                S_WR_B: begin
                    if (b_fire) begin
                        wr_buf_valid <= 1'b0;
                        state <= S_IDLE;
                    end
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clock) begin
        if (!reset) begin
            if (mem_axi_arvalid && mem_axi_arready && (ar_sel != SEL_PMEM) &&
                ((mem_axi_arlen != 8'h00) || (mem_axi_arburst != 2'b00))) begin
                $fatal(1, `TOP_MMIO_BURST_FMT, mem_axi_araddr);
            end
            if (mem_axi_awvalid && mem_axi_awready &&
                ((mem_axi_awlen != 8'h00) || (mem_axi_awburst != 2'b00))) begin
                $fatal(1, `TOP_WR_BURST_FMT, mem_axi_awaddr);
            end
            if (mem_axi_wvalid && mem_axi_wready && (mem_axi_wlast != 1'b1)) begin
                $fatal(1, `TOP_WLAST_FMT);
            end
            if (mem_axi_arvalid && mem_axi_arready && (ar_sel == SEL_PMEM) &&
                (mem_axi_arburst != 2'b00) && (mem_axi_arburst != 2'b01)) begin
                $fatal(1, `TOP_RD_BURST_FMT, mem_axi_arburst);
            end
        end
    end
`endif

    wire _unused_ok;
    assign _unused_ok = &{1'b0, clock, mem_axi_arid, mem_axi_arsize, mem_axi_awid, mem_axi_awsize};

`undef TOP_WRITE_OOR_FMT
`undef TOP_MISSING_IMG_FMT
`undef TOP_OPEN_IMG_FMT
`undef TOP_MMIO_BURST_FMT
`undef TOP_WR_BURST_FMT
`undef TOP_WLAST_FMT
`undef TOP_RD_BURST_FMT

endmodule
