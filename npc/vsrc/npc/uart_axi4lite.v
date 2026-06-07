`timescale 1ns / 1ps

module uart_axi4lite (
    input  wire        clock,
    input  wire        reset,
    // AXI read address channel
    input  wire [31:0] uart_axi_araddr,
    input  wire        uart_axi_arvalid,
    output wire        uart_axi_arready,
    // AXI read data channel
    output wire [31:0] uart_axi_rdata,
    output wire [ 1:0] uart_axi_rresp,
    output wire        uart_axi_rvalid,
    input  wire        uart_axi_rready,
    // AXI write address channel
    input  wire [31:0] uart_axi_awaddr,
    input  wire        uart_axi_awvalid,
    output wire        uart_axi_awready,
    // AXI write data channel
    input  wire [31:0] uart_axi_wdata,
    input  wire [ 3:0] uart_axi_wstrb,
    input  wire        uart_axi_wvalid,
    output wire        uart_axi_wready,
    // AXI write response channel
    output wire [ 1:0] uart_axi_bresp,
    output wire        uart_axi_bvalid,
    input  wire        uart_axi_bready
);
    localparam U_IDLE       = 2'd0;
    localparam U_RD_RESP    = 2'd1;
    localparam U_WR_COLLECT = 2'd2;
    localparam U_WR_RESP    = 2'd3;

    reg [1:0]  state;
    reg [31:0] uart_reg;
    reg [31:0] wr_data_reg;
    reg [3:0]  wr_strb_reg;
    reg        aw_captured;
    reg        w_captured;

    wire ar_fire;
    wire r_fire;
    wire aw_fire;
    wire w_fire;
    wire b_fire;
    wire wr_complete_now;
    wire [31:0] wr_data_now;
    wire [3:0]  wr_strb_now;
    reg [31:0] uart_after_write;

    assign uart_axi_arready = (state == U_IDLE);
    assign uart_axi_rvalid  = (state == U_RD_RESP);
    assign uart_axi_rdata   = uart_reg;
    assign uart_axi_rresp   = 2'b00;

    // Allow write channel handshakes in IDLE to minimize write latency.
    assign uart_axi_awready = (state == U_IDLE) || ((state == U_WR_COLLECT) && !aw_captured);
    assign uart_axi_wready  = (state == U_IDLE) || ((state == U_WR_COLLECT) && !w_captured);
    assign uart_axi_bvalid  = (state == U_WR_RESP);
    assign uart_axi_bresp   = 2'b00;

    assign ar_fire = uart_axi_arvalid && uart_axi_arready;
    assign r_fire  = uart_axi_rvalid  && uart_axi_rready;
    assign aw_fire = uart_axi_awvalid && uart_axi_awready;
    assign w_fire  = uart_axi_wvalid  && uart_axi_wready;
    assign b_fire  = uart_axi_bvalid  && uart_axi_bready;

    assign wr_complete_now = (aw_captured || aw_fire) && (w_captured || w_fire);
    assign wr_data_now = w_captured ? wr_data_reg : uart_axi_wdata;
    assign wr_strb_now = w_captured ? wr_strb_reg : uart_axi_wstrb;

    always @(*) begin
        uart_after_write = uart_reg;
        if (wr_strb_now[0]) uart_after_write[7:0]   = wr_data_now[7:0];
        if (wr_strb_now[1]) uart_after_write[15:8]  = wr_data_now[15:8];
        if (wr_strb_now[2]) uart_after_write[23:16] = wr_data_now[23:16];
        if (wr_strb_now[3]) uart_after_write[31:24] = wr_data_now[31:24];
    end

    always @(posedge clock) begin
        if (reset) begin
            state <= U_IDLE;
            uart_reg <= 32'b0;
            wr_data_reg <= 32'b0;
            wr_strb_reg <= 4'b0;
            aw_captured <= 1'b0;
            w_captured <= 1'b0;
        end else begin
            case (state)
                U_IDLE: begin
                    aw_captured <= 1'b0;
                    w_captured <= 1'b0;
                    if (ar_fire) begin
                        state <= U_RD_RESP;
                    end else if (aw_fire || w_fire) begin
                        if (aw_fire) begin
                            aw_captured <= 1'b1;
                        end
                        if (w_fire) begin
                            wr_data_reg <= uart_axi_wdata;
                            wr_strb_reg <= uart_axi_wstrb;
                            w_captured <= 1'b1;
                        end

                        if (aw_fire && w_fire) begin
                            uart_reg <= uart_after_write;
                            $write("%c", uart_axi_wdata[7:0]);
                            state <= U_WR_RESP;
                        end else begin
                            state <= U_WR_COLLECT;
                        end
                    end
                end

                U_RD_RESP: begin
                    if (r_fire) begin
                        state <= U_IDLE;
                    end
                end

                U_WR_COLLECT: begin
                    if (aw_fire) begin
                        aw_captured <= 1'b1;
                    end
                    if (w_fire) begin
                        wr_data_reg <= uart_axi_wdata;
                        wr_strb_reg <= uart_axi_wstrb;
                        w_captured <= 1'b1;
                    end

                    if (wr_complete_now) begin
                        uart_reg <= uart_after_write;
                        $write("%c", wr_data_now[7:0]);
                        state <= U_WR_RESP;
                    end
                end

                U_WR_RESP: begin
                    if (b_fire) begin
                        state <= U_IDLE;
                    end
                end

                default: begin
                    state <= U_IDLE;
                    aw_captured <= 1'b0;
                    w_captured <= 1'b0;
                end
            endcase
        end
    end

    wire _unused_ok;
    assign _unused_ok = &{1'b0, uart_axi_araddr, uart_axi_awaddr};
endmodule
