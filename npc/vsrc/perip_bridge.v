`timescale 1ns / 1ps
`include "defines.v"

module perip_bridge (
    input  wire        clk,
    input  wire        rst,
    // AXI read address channel
    input  wire [31:0] mem_axi_araddr,
    input  wire        mem_axi_arvalid,
    output reg         mem_axi_arready,
    // AXI read data channel
    output reg  [31:0] mem_axi_rdata,
    output reg  [ 1:0] mem_axi_rresp,
    output reg         mem_axi_rvalid,
    input  wire        mem_axi_rready,
    // AXI write address channel
    input  wire [31:0] mem_axi_awaddr,
    input  wire        mem_axi_awvalid,
    output reg         mem_axi_awready,
    // AXI write data channel
    input  wire [31:0] mem_axi_wdata,
    input  wire [ 3:0] mem_axi_wstrb,
    input  wire        mem_axi_wvalid,
    output reg         mem_axi_wready,
    // AXI write response channel
    output reg  [ 1:0] mem_axi_bresp,
    output reg         mem_axi_bvalid,
    input  wire        mem_axi_bready
);

    localparam X_IDLE      = 2'd0;
    localparam X_RD_WAIT_R = 2'd1;
    localparam X_WR_AW_W   = 2'd2;
    localparam X_WR_WAIT_B = 2'd3;
    localparam X_SEL_PMEM  = 2'd0;
    localparam X_SEL_UART  = 2'd1;
    localparam X_SEL_CLINT = 2'd2;

    reg [1:0] state;
    reg [1:0] rd_sel;
    reg [1:0] wr_sel;
    reg       wr_aw_done;
    reg       wr_w_done;

    wire      ar_to_uart;
    wire      aw_to_uart;
    wire      ar_to_clint;
    wire      aw_to_clint;
    wire      ar_fire;
    wire      aw_fire;
    wire      w_fire;
    wire      r_fire;
    wire      b_fire;

    // Xbar -> PMEM
    reg  [31:0] pmem_axi_araddr;
    reg         pmem_axi_arvalid;
    wire        pmem_axi_arready;
    wire [31:0] pmem_axi_rdata;
    wire [ 1:0] pmem_axi_rresp;
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

    assign ar_to_uart = (mem_axi_araddr >= `UART_BASE_ADDR) && (mem_axi_araddr <= `UART_END_ADDR);
    assign aw_to_uart = (mem_axi_awaddr >= `UART_BASE_ADDR) && (mem_axi_awaddr <= `UART_END_ADDR);
    assign ar_to_clint = (mem_axi_araddr >= `CLINT_BASE_ADDR) && (mem_axi_araddr <= `CLINT_END_ADDR);
    assign aw_to_clint = (mem_axi_awaddr >= `CLINT_BASE_ADDR) && (mem_axi_awaddr <= `CLINT_END_ADDR);

    assign ar_fire = mem_axi_arvalid && mem_axi_arready;
    assign aw_fire = mem_axi_awvalid && mem_axi_awready;
    assign w_fire = mem_axi_wvalid && mem_axi_wready;
    assign r_fire = mem_axi_rvalid && mem_axi_rready;
    assign b_fire = mem_axi_bvalid && mem_axi_bready;

    always @(*) begin
        mem_axi_arready = 1'b0;
        mem_axi_rdata = 32'b0;
        mem_axi_rresp = 2'b00;
        mem_axi_rvalid = 1'b0;
        mem_axi_awready = 1'b0;
        mem_axi_wready = 1'b0;
        mem_axi_bresp = 2'b00;
        mem_axi_bvalid = 1'b0;

        pmem_axi_araddr = 32'b0;
        pmem_axi_arvalid = 1'b0;
        pmem_axi_rready = 1'b0;
        pmem_axi_awaddr = 32'b0;
        pmem_axi_awvalid = 1'b0;
        pmem_axi_wdata = 32'b0;
        pmem_axi_wstrb = 4'b0;
        pmem_axi_wvalid = 1'b0;
        pmem_axi_bready = 1'b0;

        uart_axi_araddr = 32'b0;
        uart_axi_arvalid = 1'b0;
        uart_axi_rready = 1'b0;
        uart_axi_awaddr = 32'b0;
        uart_axi_awvalid = 1'b0;
        uart_axi_wdata = 32'b0;
        uart_axi_wstrb = 4'b0;
        uart_axi_wvalid = 1'b0;
        uart_axi_bready = 1'b0;

        clint_axi_araddr = 32'b0;
        clint_axi_arvalid = 1'b0;
        clint_axi_rready = 1'b0;
        clint_axi_awaddr = 32'b0;
        clint_axi_awvalid = 1'b0;
        clint_axi_wdata = 32'b0;
        clint_axi_wstrb = 4'b0;
        clint_axi_wvalid = 1'b0;
        clint_axi_bready = 1'b0;

        case (state)
            X_IDLE: begin
                if (mem_axi_arvalid) begin
                    if (ar_to_uart) begin
                        uart_axi_araddr = mem_axi_araddr;
                        uart_axi_arvalid = mem_axi_arvalid;
                        mem_axi_arready = uart_axi_arready;
                    end else if (ar_to_clint) begin
                        clint_axi_araddr = mem_axi_araddr;
                        clint_axi_arvalid = mem_axi_arvalid;
                        mem_axi_arready = clint_axi_arready;
                    end else begin
                        pmem_axi_araddr = mem_axi_araddr;
                        pmem_axi_arvalid = mem_axi_arvalid;
                        mem_axi_arready = pmem_axi_arready;
                    end
                end
            end

            X_RD_WAIT_R: begin
                if (rd_sel == X_SEL_UART) begin
                    mem_axi_rdata = uart_axi_rdata;
                    mem_axi_rresp = uart_axi_rresp;
                    mem_axi_rvalid = uart_axi_rvalid;
                    uart_axi_rready = mem_axi_rready;
                end else if (rd_sel == X_SEL_CLINT) begin
                    mem_axi_rdata = clint_axi_rdata;
                    mem_axi_rresp = clint_axi_rresp;
                    mem_axi_rvalid = clint_axi_rvalid;
                    clint_axi_rready = mem_axi_rready;
                end else begin
                    mem_axi_rdata = pmem_axi_rdata;
                    mem_axi_rresp = pmem_axi_rresp;
                    mem_axi_rvalid = pmem_axi_rvalid;
                    pmem_axi_rready = mem_axi_rready;
                end
            end

            X_WR_AW_W: begin
                if (~wr_aw_done && mem_axi_awvalid) begin
                    if (aw_to_uart) begin
                        uart_axi_awaddr = mem_axi_awaddr;
                        uart_axi_awvalid = mem_axi_awvalid;
                        mem_axi_awready = uart_axi_awready;
                    end else if (aw_to_clint) begin
                        clint_axi_awaddr = mem_axi_awaddr;
                        clint_axi_awvalid = mem_axi_awvalid;
                        mem_axi_awready = clint_axi_awready;
                    end else begin
                        pmem_axi_awaddr = mem_axi_awaddr;
                        pmem_axi_awvalid = mem_axi_awvalid;
                        mem_axi_awready = pmem_axi_awready;
                    end
                end

                if (wr_aw_done && ~wr_w_done) begin
                    if (wr_sel == X_SEL_UART) begin
                        uart_axi_wdata = mem_axi_wdata;
                        uart_axi_wstrb = mem_axi_wstrb;
                        uart_axi_wvalid = mem_axi_wvalid;
                        mem_axi_wready = uart_axi_wready;
                    end else if (wr_sel == X_SEL_CLINT) begin
                        clint_axi_wdata = mem_axi_wdata;
                        clint_axi_wstrb = mem_axi_wstrb;
                        clint_axi_wvalid = mem_axi_wvalid;
                        mem_axi_wready = clint_axi_wready;
                    end else begin
                        pmem_axi_wdata = mem_axi_wdata;
                        pmem_axi_wstrb = mem_axi_wstrb;
                        pmem_axi_wvalid = mem_axi_wvalid;
                        mem_axi_wready = pmem_axi_wready;
                    end
                end
            end

            X_WR_WAIT_B: begin
                if (wr_sel == X_SEL_UART) begin
                    mem_axi_bresp = uart_axi_bresp;
                    mem_axi_bvalid = uart_axi_bvalid;
                    uart_axi_bready = mem_axi_bready;
                end else if (wr_sel == X_SEL_CLINT) begin
                    mem_axi_bresp = clint_axi_bresp;
                    mem_axi_bvalid = clint_axi_bvalid;
                    clint_axi_bready = mem_axi_bready;
                end else begin
                    mem_axi_bresp = pmem_axi_bresp;
                    mem_axi_bvalid = pmem_axi_bvalid;
                    pmem_axi_bready = mem_axi_bready;
                end
            end

            default: begin
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= X_IDLE;
            rd_sel <= X_SEL_PMEM;
            wr_sel <= X_SEL_PMEM;
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
        end else begin
            case (state)
                X_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                    if (mem_axi_arvalid) begin
                        if (ar_fire) begin
                            if (ar_to_uart) begin
                                rd_sel <= X_SEL_UART;
                            end else if (ar_to_clint) begin
                                rd_sel <= X_SEL_CLINT;
                            end else begin
                                rd_sel <= X_SEL_PMEM;
                            end
                            state <= X_RD_WAIT_R;
                        end
                    end else if (mem_axi_awvalid || mem_axi_wvalid) begin
                        state <= X_WR_AW_W;
                    end
                end

                X_RD_WAIT_R: begin
                    if (r_fire) begin
                        state <= X_IDLE;
                    end
                end

                X_WR_AW_W: begin
                    if (~wr_aw_done && aw_fire) begin
                        wr_aw_done <= 1'b1;
                        if (aw_to_uart) begin
                            wr_sel <= X_SEL_UART;
                        end else if (aw_to_clint) begin
                            wr_sel <= X_SEL_CLINT;
                        end else begin
                            wr_sel <= X_SEL_PMEM;
                        end
                    end

                    if (wr_aw_done && ~wr_w_done && w_fire) begin
                        wr_w_done <= 1'b1;
                    end

                    if ((wr_aw_done || aw_fire) && (wr_w_done || w_fire)) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= X_WR_WAIT_B;
                    end
                end

                X_WR_WAIT_B: begin
                    if (b_fire) begin
                        state <= X_IDLE;
                    end
                end

                default: begin
                    state <= X_IDLE;
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                end
            endcase
        end
    end

    pmem_axi4lite u_pmem_axi4lite (
        .clk                (clk),
        .rst                (rst),
        .pmem_axi_araddr    (pmem_axi_araddr),
        .pmem_axi_arvalid   (pmem_axi_arvalid),
        .pmem_axi_arready   (pmem_axi_arready),
        .pmem_axi_rdata     (pmem_axi_rdata),
        .pmem_axi_rresp     (pmem_axi_rresp),
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
        .clk                (clk),
        .rst                (rst),
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

    clint_axi4lite u_clint_axi4lite (
        .clk                (clk),
        .rst                (rst),
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
endmodule
