`timescale 1ns / 1ps

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
    localparam [31:0] CLINT_BASE_ADDR = 32'h0200_0000;
    localparam [31:0] CLINT_END_ADDR  = 32'h0200_ffff;

    localparam SEL_PMEM  = 2'd0;
    localparam SEL_UART  = 2'd1;
    localparam SEL_CLINT = 2'd2;

    localparam R_IDLE   = 1'b0;
    localparam R_WAIT_R = 1'b1;

    localparam W_IDLE   = 2'd0;
    localparam W_AW_W   = 2'd1;
    localparam W_WAIT_B = 2'd2;

    reg        rd_state;
    reg [1:0]  rd_sel;

    reg [1:0]  wr_state;
    reg [1:0]  wr_sel;
    reg        wr_aw_done;
    reg        wr_w_done;

    wire [1:0] ar_sel;
    wire [1:0] aw_sel;

    wire       wr_unknown_target;
    wire       wr_known_target_busy_same_as_ar;

    wire       aw_conflict_rd;
    wire       rd_conflict_new_write_same_target;
    wire       aw_can_issue;

    wire       wr_aw_done_q;
    wire       wr_w_done_q;
    wire       wr_can_send_w;
    wire [1:0] wr_w_sel;
    wire       w_conflict_rd;

    wire       ar_fire;
    wire       r_fire;
    wire       aw_fire;
    wire       w_fire;
    wire       b_fire;

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

    // Xbar -> CLINT
    reg  [31:0] clint_axi_araddr;
    reg         clint_axi_arvalid;
    wire        clint_axi_arready;
    wire [31:0] clint_axi_rdata;
    wire [ 1:0] clint_axi_rresp;
    wire        clint_axi_rvalid;
    reg         clint_axi_rready;
    reg  [31:0] clint_axi_awaddr;
    reg         clint_axi_awvalid;
    wire        clint_axi_awready;
    reg  [31:0] clint_axi_wdata;
    reg  [ 3:0] clint_axi_wstrb;
    reg         clint_axi_wvalid;
    wire        clint_axi_wready;
    wire [ 1:0] clint_axi_bresp;
    wire        clint_axi_bvalid;
    reg         clint_axi_bready;

    assign ar_sel = ((mem_axi_araddr >= UART_BASE_ADDR) && (mem_axi_araddr <= UART_END_ADDR)) ? SEL_UART :
                    ((mem_axi_araddr >= CLINT_BASE_ADDR) && (mem_axi_araddr <= CLINT_END_ADDR)) ? SEL_CLINT :
                    SEL_PMEM;

    assign aw_sel = ((mem_axi_awaddr >= UART_BASE_ADDR) && (mem_axi_awaddr <= UART_END_ADDR)) ? SEL_UART :
                    ((mem_axi_awaddr >= CLINT_BASE_ADDR) && (mem_axi_awaddr <= CLINT_END_ADDR)) ? SEL_CLINT :
                    SEL_PMEM;

    assign wr_unknown_target = (wr_state == W_AW_W) && !wr_aw_done;
    assign wr_known_target_busy_same_as_ar =
        (((wr_state == W_AW_W) && wr_aw_done) || (wr_state == W_WAIT_B)) && (wr_sel == ar_sel);

    assign aw_conflict_rd = (rd_state == R_WAIT_R) && (rd_sel == aw_sel);
    assign aw_can_issue = !aw_conflict_rd;
    // Give pending write a chance when new read/write hit the same target.
    assign rd_conflict_new_write_same_target =
        (wr_state == W_IDLE) && mem_axi_awvalid && (ar_sel == aw_sel);

    assign wr_aw_done_q = (wr_state == W_AW_W) ? wr_aw_done : 1'b0;
    assign wr_w_done_q  = (wr_state == W_AW_W) ? wr_w_done  : 1'b0;
    assign wr_can_send_w = wr_aw_done_q || aw_fire;
    assign wr_w_sel = wr_aw_done_q ? wr_sel : aw_sel;
    assign w_conflict_rd = (rd_state == R_WAIT_R) && (rd_sel == wr_w_sel);

    assign ar_fire = mem_axi_arvalid && mem_axi_arready;
    assign r_fire  = mem_axi_rvalid  && mem_axi_rready;
    assign aw_fire = mem_axi_awvalid && mem_axi_awready;
    assign w_fire  = mem_axi_wvalid  && mem_axi_wready;
    assign b_fire  = mem_axi_bvalid  && mem_axi_bready;

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

        clint_axi_araddr  = 32'b0;
        clint_axi_arvalid = 1'b0;
        clint_axi_rready  = 1'b0;
        clint_axi_awaddr  = 32'b0;
        clint_axi_awvalid = 1'b0;
        clint_axi_wdata   = 32'b0;
        clint_axi_wstrb   = 4'b0;
        clint_axi_wvalid  = 1'b0;
        clint_axi_bready  = 1'b0;

        // Read path
        case (rd_state)
            R_IDLE: begin
                if (mem_axi_arvalid &&
                    !wr_unknown_target &&
                    !wr_known_target_busy_same_as_ar &&
                    !rd_conflict_new_write_same_target) begin
                    case (ar_sel)
                        SEL_UART: begin
                            uart_axi_araddr  = mem_axi_araddr;
                            uart_axi_arvalid = mem_axi_arvalid;
                            mem_axi_arready  = uart_axi_arready;
                        end
                        SEL_CLINT: begin
                            clint_axi_araddr  = mem_axi_araddr;
                            clint_axi_arvalid = mem_axi_arvalid;
                            mem_axi_arready   = clint_axi_arready;
                        end
                        default: begin
                            pmem_axi_araddr  = mem_axi_araddr;
                            pmem_axi_arlen   = mem_axi_arlen;
                            pmem_axi_arburst = mem_axi_arburst;
                            pmem_axi_arvalid = mem_axi_arvalid;
                            mem_axi_arready  = pmem_axi_arready;
                        end
                    endcase
                end
            end

            R_WAIT_R: begin
                case (rd_sel)
                    SEL_UART: begin
                        mem_axi_rid    = 4'b0;
                        mem_axi_rdata  = uart_axi_rdata;
                        mem_axi_rresp  = uart_axi_rresp;
                        mem_axi_rlast  = 1'b1;
                        mem_axi_rvalid = uart_axi_rvalid;
                        uart_axi_rready = mem_axi_rready;
                    end
                    SEL_CLINT: begin
                        mem_axi_rid     = 4'b0;
                        mem_axi_rdata   = clint_axi_rdata;
                        mem_axi_rresp   = clint_axi_rresp;
                        mem_axi_rlast   = 1'b1;
                        mem_axi_rvalid  = clint_axi_rvalid;
                        clint_axi_rready = mem_axi_rready;
                    end
                    default: begin
                        mem_axi_rid    = 4'b0;
                        mem_axi_rdata  = pmem_axi_rdata;
                        mem_axi_rresp  = pmem_axi_rresp;
                        mem_axi_rlast  = pmem_axi_rlast;
                        mem_axi_rvalid = pmem_axi_rvalid;
                        pmem_axi_rready = mem_axi_rready;
                    end
                endcase
            end

            default: begin
            end
        endcase

        // Write path
        case (wr_state)
            W_IDLE,
            W_AW_W: begin
                if ((wr_state == W_AW_W) || mem_axi_awvalid || mem_axi_wvalid) begin
                    if (!wr_aw_done_q && mem_axi_awvalid && aw_can_issue) begin
                        case (aw_sel)
                            SEL_UART: begin
                                uart_axi_awaddr  = mem_axi_awaddr;
                                uart_axi_awvalid = mem_axi_awvalid;
                                mem_axi_awready  = uart_axi_awready;
                            end
                            SEL_CLINT: begin
                                clint_axi_awaddr  = mem_axi_awaddr;
                                clint_axi_awvalid = mem_axi_awvalid;
                                mem_axi_awready   = clint_axi_awready;
                            end
                            default: begin
                                pmem_axi_awaddr  = mem_axi_awaddr;
                                pmem_axi_awvalid = mem_axi_awvalid;
                                mem_axi_awready  = pmem_axi_awready;
                            end
                        endcase
                    end

                    if (!wr_w_done_q && wr_can_send_w && !w_conflict_rd) begin
                        case (wr_w_sel)
                            SEL_UART: begin
                                uart_axi_wdata  = mem_axi_wdata;
                                uart_axi_wstrb  = mem_axi_wstrb;
                                uart_axi_wvalid = mem_axi_wvalid;
                                mem_axi_wready  = uart_axi_wready;
                            end
                            SEL_CLINT: begin
                                clint_axi_wdata  = mem_axi_wdata;
                                clint_axi_wstrb  = mem_axi_wstrb;
                                clint_axi_wvalid = mem_axi_wvalid;
                                mem_axi_wready   = clint_axi_wready;
                            end
                            default: begin
                                pmem_axi_wdata  = mem_axi_wdata;
                                pmem_axi_wstrb  = mem_axi_wstrb;
                                pmem_axi_wvalid = mem_axi_wvalid;
                                mem_axi_wready  = pmem_axi_wready;
                            end
                        endcase
                    end
                end
            end

            W_WAIT_B: begin
                case (wr_sel)
                    SEL_UART: begin
                        mem_axi_bid    = 4'b0;
                        mem_axi_bresp  = uart_axi_bresp;
                        mem_axi_bvalid = uart_axi_bvalid;
                        uart_axi_bready = mem_axi_bready;
                    end
                    SEL_CLINT: begin
                        mem_axi_bid     = 4'b0;
                        mem_axi_bresp   = clint_axi_bresp;
                        mem_axi_bvalid  = clint_axi_bvalid;
                        clint_axi_bready = mem_axi_bready;
                    end
                    default: begin
                        mem_axi_bid    = 4'b0;
                        mem_axi_bresp  = pmem_axi_bresp;
                        mem_axi_bvalid = pmem_axi_bvalid;
                        pmem_axi_bready = mem_axi_bready;
                    end
                endcase
            end

            default: begin
            end
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            rd_state <= R_IDLE;
            rd_sel   <= SEL_PMEM;

            wr_state   <= W_IDLE;
            wr_sel     <= SEL_PMEM;
            wr_aw_done <= 1'b0;
            wr_w_done  <= 1'b0;
        end else begin
            // Read state update
            case (rd_state)
                R_IDLE: begin
                    if (ar_fire) begin
                        rd_sel   <= ar_sel;
                        rd_state <= R_WAIT_R;
                    end
                end

                R_WAIT_R: begin
                    if (r_fire && mem_axi_rlast) begin
                        rd_state <= R_IDLE;
                    end
                end

                default: begin
                    rd_state <= R_IDLE;
                end
            endcase

            // Write state update
            case (wr_state)
                W_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done  <= 1'b0;

                    if (mem_axi_awvalid || mem_axi_wvalid) begin
                        if (aw_fire && w_fire) begin
                            wr_sel   <= aw_sel;
                            wr_state <= W_WAIT_B;
                        end else begin
                            wr_state   <= W_AW_W;
                            wr_aw_done <= aw_fire;
                            wr_w_done  <= w_fire;
                            if (aw_fire) begin
                                wr_sel <= aw_sel;
                            end
                        end
                    end
                end

                W_AW_W: begin
                    if (!wr_aw_done && aw_fire) begin
                        wr_aw_done <= 1'b1;
                        wr_sel <= aw_sel;
                    end
                    if (!wr_w_done && w_fire) begin
                        wr_w_done <= 1'b1;
                    end

                    if ((wr_aw_done || aw_fire) && (wr_w_done || w_fire)) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done  <= 1'b0;
                        wr_state   <= W_WAIT_B;
                        if (!wr_aw_done && aw_fire) begin
                            wr_sel <= aw_sel;
                        end
                    end
                end

                W_WAIT_B: begin
                    if (b_fire) begin
                        wr_state <= W_IDLE;
                    end
                end

                default: begin
                    wr_state   <= W_IDLE;
                    wr_aw_done <= 1'b0;
                    wr_w_done  <= 1'b0;
                end
            endcase
        end
    end

    pmem_axi4lite u_pmem_axi4lite (
        .clock                (clock),
        .reset                (reset),
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
        .clock                (clock),
        .reset                (reset),
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

    clint_axi4lite #(
        .MTIME_ADDR           (32'h0200_bff8),
        .MTIMEH_ADDR          (32'h0200_bffc)
    ) u_clint_axi4lite (
        .clock                (clock),
        .reset                (reset),
        .clint_axi_araddr   (clint_axi_araddr),
        .clint_axi_arvalid  (clint_axi_arvalid),
        .clint_axi_arready  (clint_axi_arready),
        .clint_axi_rdata    (clint_axi_rdata),
        .clint_axi_rresp    (clint_axi_rresp),
        .clint_axi_rvalid   (clint_axi_rvalid),
        .clint_axi_rready   (clint_axi_rready),
        .clint_axi_awaddr   (clint_axi_awaddr),
        .clint_axi_awvalid  (clint_axi_awvalid),
        .clint_axi_awready  (clint_axi_awready),
        .clint_axi_wdata    (clint_axi_wdata),
        .clint_axi_wstrb    (clint_axi_wstrb),
        .clint_axi_wvalid   (clint_axi_wvalid),
        .clint_axi_wready   (clint_axi_wready),
        .clint_axi_bresp    (clint_axi_bresp),
        .clint_axi_bvalid   (clint_axi_bvalid),
        .clint_axi_bready   (clint_axi_bready)
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
endmodule
