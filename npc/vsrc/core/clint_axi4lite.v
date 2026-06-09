module ysyx_26030082_clint_axi4lite #(
    parameter [31:0] MTIME_ADDR  = 32'h0200_bff8,
    parameter [31:0] MTIMEH_ADDR = 32'h0200_bffc
) (
    input  wire        clock,
    input  wire        reset,
    // AXI read address channel
    input  wire [31:0] clint_axi_araddr,
    input  wire        clint_axi_arvalid,
    output wire        clint_axi_arready,
    // AXI read data channel
    output wire [31:0] clint_axi_rdata,
    output wire [ 1:0] clint_axi_rresp,
    output wire        clint_axi_rvalid,
    input  wire        clint_axi_rready,
    // AXI write address channel
    input  wire [31:0] clint_axi_awaddr,
    input  wire        clint_axi_awvalid,
    output wire        clint_axi_awready,
    // AXI write data channel
    input  wire [31:0] clint_axi_wdata,
    input  wire [ 3:0] clint_axi_wstrb,
    input  wire        clint_axi_wvalid,
    output wire        clint_axi_wready,
    // AXI write response channel
    output wire [ 1:0] clint_axi_bresp,
    output wire        clint_axi_bvalid,
    input  wire        clint_axi_bready
);
    localparam C_IDLE       = 2'd0;
    localparam C_RD_RESP    = 2'd1;
    localparam C_WR_COLLECT = 2'd2;
    localparam C_WR_RESP    = 2'd3;

    reg [1:0]  state;
    reg [63:0] mtime;
    reg [31:0] rdata_reg;
    reg        aw_captured;
    reg        w_captured;

    wire ar_fire;
    wire r_fire;
    wire aw_fire;
    wire w_fire;
    wire b_fire;
    wire wr_complete_now;

    assign clint_axi_arready = (state == C_IDLE);
    assign clint_axi_rvalid  = (state == C_RD_RESP);
    assign clint_axi_rdata   = rdata_reg;
    assign clint_axi_rresp   = 2'b00;

    // Keep AW/W ready in IDLE to accept writes with minimum latency.
    assign clint_axi_awready = (state == C_IDLE) || ((state == C_WR_COLLECT) && !aw_captured);
    assign clint_axi_wready  = (state == C_IDLE) || ((state == C_WR_COLLECT) && !w_captured);
    assign clint_axi_bvalid  = (state == C_WR_RESP);
    assign clint_axi_bresp   = 2'b00;

    assign ar_fire = clint_axi_arvalid && clint_axi_arready;
    assign r_fire = clint_axi_rvalid && clint_axi_rready;
    assign aw_fire = clint_axi_awvalid && clint_axi_awready;
    assign w_fire = clint_axi_wvalid && clint_axi_wready;
    assign b_fire = clint_axi_bvalid && clint_axi_bready;
    assign wr_complete_now = (aw_captured || aw_fire) && (w_captured || w_fire);

    always @(posedge clock) begin
        if (reset) begin
            mtime <= 64'b0;
        end else begin
            mtime <= mtime + 64'd1;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            state <= C_IDLE;
            rdata_reg <= 32'b0;
            aw_captured <= 1'b0;
            w_captured <= 1'b0;
        end else begin
            case (state)
                C_IDLE: begin
                    aw_captured <= 1'b0;
                    w_captured <= 1'b0;
                    if (ar_fire) begin
                        if (clint_axi_araddr == MTIME_ADDR) begin
                            rdata_reg <= mtime[31:0];
                        end else if (clint_axi_araddr == MTIMEH_ADDR) begin
                            rdata_reg <= mtime[63:32];
                        end else begin
                            rdata_reg <= 32'b0;
                        end
                        state <= C_RD_RESP;
                    end else if (aw_fire || w_fire) begin
                        if (aw_fire) begin
                            aw_captured <= 1'b1;
                        end
                        if (w_fire) begin
                            w_captured <= 1'b1;
                        end

                        if (aw_fire && w_fire) begin
                            state <= C_WR_RESP;
                        end else begin
                            state <= C_WR_COLLECT;
                        end
                    end
                end

                C_RD_RESP: begin
                    if (r_fire) begin
                        state <= C_IDLE;
                    end
                end

                C_WR_COLLECT: begin
                    if (aw_fire) begin
                        aw_captured <= 1'b1;
                    end
                    if (w_fire) begin
                        w_captured <= 1'b1;
                    end

                    if (wr_complete_now) begin
                        state <= C_WR_RESP;
                    end
                end

                C_WR_RESP: begin
                    if (b_fire) begin
                        state <= C_IDLE;
                    end
                end

                default: begin
                    state <= C_IDLE;
                    aw_captured <= 1'b0;
                    w_captured <= 1'b0;
                end
            endcase
        end
    end

    wire _unused_ok;
    assign _unused_ok = &{1'b0, clint_axi_awaddr, clint_axi_wdata, clint_axi_wstrb};
endmodule
