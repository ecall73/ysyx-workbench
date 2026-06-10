module perip_bridge (
    input  wire        clock,
    input  wire        reset,
    // AXI read address channel
    input  wire [31:0] mem_axi_araddr,
    input  wire [ 3:0] mem_axi_arid,
    input  wire [ 7:0] mem_axi_arlen,
    input  wire [ 2:0] mem_axi_arsize,
    input  wire [ 1:0] mem_axi_arburst,
    input  wire        mem_axi_arvalid,
    output reg         mem_axi_arready,
    // AXI read data channel
    output reg  [ 3:0] mem_axi_rid,
    output reg  [31:0] mem_axi_rdata,
    output reg  [ 1:0] mem_axi_rresp,
    output reg         mem_axi_rlast,
    output reg         mem_axi_rvalid,
    input  wire        mem_axi_rready,
    // AXI write address channel
    input  wire [31:0] mem_axi_awaddr,
    input  wire [ 3:0] mem_axi_awid,
    input  wire [ 7:0] mem_axi_awlen,
    input  wire [ 2:0] mem_axi_awsize,
    input  wire [ 1:0] mem_axi_awburst,
    input  wire        mem_axi_awvalid,
    output reg         mem_axi_awready,
    // AXI write data channel
    input  wire [31:0] mem_axi_wdata,
    input  wire [ 3:0] mem_axi_wstrb,
    input  wire        mem_axi_wlast,
    input  wire        mem_axi_wvalid,
    output reg         mem_axi_wready,
    // AXI write response channel
    output reg  [ 3:0] mem_axi_bid,
    output reg  [ 1:0] mem_axi_bresp,
    output reg         mem_axi_bvalid,
    input  wire        mem_axi_bready
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

    reg [2:0] state;

    reg        rd_sel;
    reg [31:0] rd_addr_reg;
    reg [ 7:0] rd_len_reg;
    reg [ 1:0] rd_burst_reg;
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

    wire ar_sel;
    wire aw_sel;
    wire ar_fire;
    wire r_fire;
    wire aw_fire;
    wire w_fire;
    wire b_fire;
    wire rd_buf_take;

    // Xbar -> PMEM
    reg  [31:0] pmem_axi_araddr;
    reg  [ 7:0] pmem_axi_arlen;
    reg  [ 1:0] pmem_axi_arburst;
    reg         pmem_axi_arvalid;
    wire        pmem_axi_arready;
    wire [31:0] pmem_axi_rdata;
    wire [ 1:0] pmem_axi_rresp;
    wire        pmem_axi_rlast;
    wire        pmem_axi_rvalid;
    reg         pmem_axi_rready;
    reg  [31:0] pmem_axi_awaddr;
    reg         pmem_axi_awvalid;
    wire        pmem_axi_awready;
    reg  [31:0] pmem_axi_wdata;
    reg  [ 3:0] pmem_axi_wstrb;
    reg         pmem_axi_wvalid;
    wire        pmem_axi_wready;
    wire [ 1:0] pmem_axi_bresp;
    wire        pmem_axi_bvalid;
    reg         pmem_axi_bready;

    // Xbar -> UART
    reg  [31:0] uart_axi_araddr;
    reg         uart_axi_arvalid;
    wire        uart_axi_arready;
    wire [31:0] uart_axi_rdata;
    wire [ 1:0] uart_axi_rresp;
    wire        uart_axi_rvalid;
    reg         uart_axi_rready;
    reg  [31:0] uart_axi_awaddr;
    reg         uart_axi_awvalid;
    wire        uart_axi_awready;
    reg  [31:0] uart_axi_wdata;
    reg  [ 3:0] uart_axi_wstrb;
    reg         uart_axi_wvalid;
    wire        uart_axi_wready;
    wire [ 1:0] uart_axi_bresp;
    wire        uart_axi_bvalid;
    reg         uart_axi_bready;

    wire        selected_rvalid;
    wire [31:0] selected_rdata;
    wire [ 1:0] selected_rresp;
    wire        selected_rlast;
    wire        selected_arready;
    wire        selected_awready;
    wire        selected_wready;
    wire        selected_bvalid;
    wire [ 1:0] selected_bresp;

    assign ar_sel = ((mem_axi_araddr >= UART_BASE_ADDR) && (mem_axi_araddr <= UART_END_ADDR)) ? SEL_UART : SEL_PMEM;
    assign aw_sel = ((mem_axi_awaddr >= UART_BASE_ADDR) && (mem_axi_awaddr <= UART_END_ADDR)) ? SEL_UART : SEL_PMEM;

    assign selected_rvalid  = rd_sel ? uart_axi_rvalid  : pmem_axi_rvalid;
    assign selected_rdata   = rd_sel ? uart_axi_rdata   : pmem_axi_rdata;
    assign selected_rresp   = rd_sel ? uart_axi_rresp   : pmem_axi_rresp;
    assign selected_rlast   = rd_sel ? 1'b1             : pmem_axi_rlast;
    assign selected_arready = rd_sel ? uart_axi_arready : pmem_axi_arready;
    assign selected_awready = wr_sel ? uart_axi_awready : pmem_axi_awready;
    assign selected_wready  = wr_sel ? uart_axi_wready  : pmem_axi_wready;
    assign selected_bvalid  = wr_sel ? uart_axi_bvalid  : pmem_axi_bvalid;
    assign selected_bresp   = wr_sel ? uart_axi_bresp   : pmem_axi_bresp;

    assign ar_fire = mem_axi_arvalid && mem_axi_arready;
    assign r_fire  = mem_axi_rvalid  && mem_axi_rready;
    assign aw_fire = mem_axi_awvalid && mem_axi_awready;
    assign w_fire  = mem_axi_wvalid  && mem_axi_wready;
    assign b_fire  = mem_axi_bvalid  && mem_axi_bready;
    assign rd_buf_take = rd_buf_valid && mem_axi_rready;

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

        pmem_axi_araddr  = 32'b0;
        pmem_axi_arlen   = 8'b0;
        pmem_axi_arburst = 2'b0;
        pmem_axi_arvalid = 1'b0;
        pmem_axi_rready  = 1'b0;
        pmem_axi_awaddr  = 32'b0;
        pmem_axi_awvalid = 1'b0;
        pmem_axi_wdata   = 32'b0;
        pmem_axi_wstrb   = 4'b0;
        pmem_axi_wvalid  = 1'b0;
        pmem_axi_bready  = 1'b0;

        uart_axi_araddr  = 32'b0;
        uart_axi_arvalid = 1'b0;
        uart_axi_rready  = 1'b0;
        uart_axi_awaddr  = 32'b0;
        uart_axi_awvalid = 1'b0;
        uart_axi_wdata   = 32'b0;
        uart_axi_wstrb   = 4'b0;
        uart_axi_wvalid  = 1'b0;
        uart_axi_bready  = 1'b0;

        case (state)
            S_IDLE: begin
                mem_axi_arready = 1'b1;
                mem_axi_awready = 1'b1;
                mem_axi_wready  = 1'b1;
            end

            S_RD_AR: begin
                if (rd_sel == SEL_UART) begin
                    uart_axi_araddr  = rd_addr_reg;
                    uart_axi_arvalid = 1'b1;
                end else begin
                    pmem_axi_araddr  = rd_addr_reg;
                    pmem_axi_arlen   = rd_len_reg;
                    pmem_axi_arburst = rd_burst_reg;
                    pmem_axi_arvalid = 1'b1;
                end
            end

            S_RD_R: begin
                mem_axi_rid    = 4'b0;
                mem_axi_rdata  = rd_buf_data;
                mem_axi_rresp  = rd_buf_resp;
                mem_axi_rlast  = rd_buf_last;
                mem_axi_rvalid = rd_buf_valid;
                if (rd_sel == SEL_UART) begin
                    uart_axi_rready = !rd_buf_valid;
                end else begin
                    pmem_axi_rready = !rd_buf_valid;
                end
            end

            S_WR_COLLECT: begin
                mem_axi_awready = !wr_have_aw;
                mem_axi_wready  = !wr_have_w;
            end

            S_WR_ISSUE: begin
                if (wr_sel == SEL_UART) begin
                    uart_axi_awaddr  = wr_addr_reg;
                    uart_axi_awvalid = 1'b1;
                end else begin
                    pmem_axi_awaddr  = wr_addr_reg;
                    pmem_axi_awvalid = 1'b1;
                end
            end

            S_WR_DATA: begin
                if (wr_sel == SEL_UART) begin
                    uart_axi_wdata   = wr_data_reg;
                    uart_axi_wstrb   = wr_strb_reg;
                    uart_axi_wvalid  = 1'b1;
                end else begin
                    pmem_axi_wdata   = wr_data_reg;
                    pmem_axi_wstrb   = wr_strb_reg;
                    pmem_axi_wvalid  = 1'b1;
                end
            end

            S_WR_B: begin
                mem_axi_bid    = 4'b0;
                mem_axi_bresp  = wr_buf_resp;
                mem_axi_bvalid = wr_buf_valid;
                if (wr_sel == SEL_UART) begin
                    uart_axi_bready = !wr_buf_valid;
                end else begin
                    pmem_axi_bready = !wr_buf_valid;
                end
            end

            default: begin
            end
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            state       <= S_IDLE;
            rd_sel      <= SEL_PMEM;
            rd_addr_reg <= 32'b0;
            rd_len_reg  <= 8'b0;
            rd_burst_reg <= 2'b0;
            rd_buf_valid <= 1'b0;
            rd_buf_data  <= 32'b0;
            rd_buf_resp  <= 2'b0;
            rd_buf_last  <= 1'b0;
            wr_sel      <= SEL_PMEM;
            wr_have_aw  <= 1'b0;
            wr_have_w   <= 1'b0;
            wr_buf_valid <= 1'b0;
            wr_buf_resp  <= 2'b0;
            wr_addr_reg <= 32'b0;
            wr_data_reg <= 32'b0;
            wr_strb_reg <= 4'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    rd_buf_valid <= 1'b0;
                    wr_have_aw <= 1'b0;
                    wr_have_w  <= 1'b0;
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
                    if (selected_arready) begin
                        state <= S_RD_R;
                    end
                end

                S_RD_R: begin
                    if (!rd_buf_valid && selected_rvalid) begin
                        rd_buf_valid <= 1'b1;
                        rd_buf_data  <= selected_rdata;
                        rd_buf_resp  <= selected_rresp;
                        rd_buf_last  <= selected_rlast;
                    end else if (rd_buf_take) begin
                        rd_buf_valid <= 1'b0;
                    end

                    if (rd_buf_take && rd_buf_last) begin
                        state <= S_IDLE;
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
                        state      <= S_WR_ISSUE;
                    end
                end

                S_WR_ISSUE: begin
                    if (selected_awready) begin
                        state <= S_WR_DATA;
                    end
                end

                S_WR_DATA: begin
                    if (selected_wready) begin
                        state <= S_WR_B;
                    end
                end

                S_WR_B: begin
                    if (!wr_buf_valid && selected_bvalid) begin
                        wr_buf_valid <= 1'b1;
                        wr_buf_resp  <= selected_bresp;
                    end else if (b_fire) begin
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

    pmem_axi4lite u_pmem_axi4lite (
        .clock              (clock),
        .reset              (reset),
        .pmem_axi_araddr    (pmem_axi_araddr),
        .pmem_axi_arlen     (pmem_axi_arlen),
        .pmem_axi_arburst   (pmem_axi_arburst),
        .pmem_axi_arvalid   (pmem_axi_arvalid),
        .pmem_axi_arready   (pmem_axi_arready),
        .pmem_axi_rdata     (pmem_axi_rdata),
        .pmem_axi_rresp     (pmem_axi_rresp),
        .pmem_axi_rlast     (pmem_axi_rlast),
        .pmem_axi_rvalid    (pmem_axi_rvalid),
        .pmem_axi_rready    (pmem_axi_rready),
        .pmem_axi_awaddr    (pmem_axi_awaddr),
        .pmem_axi_awvalid   (pmem_axi_awvalid),
        .pmem_axi_awready   (pmem_axi_awready),
        .pmem_axi_wdata     (pmem_axi_wdata),
        .pmem_axi_wstrb     (pmem_axi_wstrb),
        .pmem_axi_wvalid    (pmem_axi_wvalid),
        .pmem_axi_wready    (pmem_axi_wready),
        .pmem_axi_bresp     (pmem_axi_bresp),
        .pmem_axi_bvalid    (pmem_axi_bvalid),
        .pmem_axi_bready    (pmem_axi_bready)
    );

    uart_axi4lite u_uart_axi4lite (
        .clock              (clock),
        .reset              (reset),
        .uart_axi_araddr    (uart_axi_araddr),
        .uart_axi_arvalid   (uart_axi_arvalid),
        .uart_axi_arready   (uart_axi_arready),
        .uart_axi_rdata     (uart_axi_rdata),
        .uart_axi_rresp     (uart_axi_rresp),
        .uart_axi_rvalid    (uart_axi_rvalid),
        .uart_axi_rready    (uart_axi_rready),
        .uart_axi_awaddr    (uart_axi_awaddr),
        .uart_axi_awvalid   (uart_axi_awvalid),
        .uart_axi_awready   (uart_axi_awready),
        .uart_axi_wdata     (uart_axi_wdata),
        .uart_axi_wstrb     (uart_axi_wstrb),
        .uart_axi_wvalid    (uart_axi_wvalid),
        .uart_axi_wready    (uart_axi_wready),
        .uart_axi_bresp     (uart_axi_bresp),
        .uart_axi_bvalid    (uart_axi_bvalid),
        .uart_axi_bready    (uart_axi_bready)
    );

`ifndef SYNTHESIS
    always @(posedge clock) begin
        if (!reset) begin
            if (mem_axi_arvalid && mem_axi_arready && (ar_sel != SEL_PMEM) &&
                ((mem_axi_arlen != 8'h00) || (mem_axi_arburst != 2'b00))) begin
                $fatal(1, "perip_bridge: MMIO burst read is not supported addr=%08x", mem_axi_araddr);
            end
            if (mem_axi_awvalid && mem_axi_awready &&
                ((mem_axi_awlen != 8'h00) || (mem_axi_awburst != 2'b00))) begin
                $fatal(1, "perip_bridge: burst write is not supported addr=%08x", mem_axi_awaddr);
            end
            if (mem_axi_wvalid && mem_axi_wready && (mem_axi_wlast != 1'b1)) begin
                $fatal(1, "perip_bridge: WLAST must be 1 for single-beat write");
            end
        end
    end
`endif

    wire _unused_ok;
    assign _unused_ok = &{1'b0, clock, mem_axi_arid, mem_axi_arsize, mem_axi_awid, mem_axi_awsize};

endmodule
