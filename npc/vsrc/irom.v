`timescale 1ns / 1ps
`include "defines.v"

module irom (
    input  wire        clk,
    input  wire        rst,
    // IFU AXI4-Lite slave interface
    // Read address channel
    input  wire [31:0] ifu_axi_araddr,
    input  wire        ifu_axi_arvalid,
    output wire        ifu_axi_arready,
    // Read data channel
    output wire [31:0] ifu_axi_rdata,
    output wire [ 1:0] ifu_axi_rresp,
    output wire        ifu_axi_rvalid,
    input  wire        ifu_axi_rready,
    // Write address channel (unused by IFU)
    input  wire [31:0] ifu_axi_awaddr,
    input  wire        ifu_axi_awvalid,
    output wire        ifu_axi_awready,
    // Write data channel (unused by IFU)
    input  wire [31:0] ifu_axi_wdata,
    input  wire [ 3:0] ifu_axi_wstrb,
    input  wire        ifu_axi_wvalid,
    output wire        ifu_axi_wready,
    // Write response channel (unused by IFU)
    output wire [ 1:0] ifu_axi_bresp,
    output wire        ifu_axi_bvalid,
    input  wire        ifu_axi_bready
);

    import "DPI-C" function int pmem_read(input int raddr);

    localparam I_WAIT_ARVALID = 3'd0;
    localparam I_WAIT_ARREADY = 3'd1;
    localparam I_ARREADY      = 3'd2;
    localparam I_WAIT_R       = 3'd3;
    localparam I_RVALID       = 3'd4;

    reg [2:0]  state;
    reg [31:0] req_addr_reg;
    reg [31:0] resp_data_reg;
    reg [3:0]  arready_wait_cnt;
    reg [3:0]  r_wait_cnt;

    wire [3:0] lfsr_resp_random;
    wire [3:0] lfsr_arready_random;
    wire [3:0] arready_delay_sampled;
    wire [3:0] rvalid_delay_sampled;
    wire       ar_fire;
    wire       r_fire;

    assign ifu_axi_arready = (state == I_ARREADY);
    assign ifu_axi_rvalid = (state == I_RVALID);
    assign ifu_axi_rdata = resp_data_reg;
    assign ifu_axi_rresp = 2'b00;

    assign ifu_axi_awready = 1'b0;
    assign ifu_axi_wready = 1'b0;
    assign ifu_axi_bresp = 2'b00;
    assign ifu_axi_bvalid = 1'b0;

    assign ar_fire = ifu_axi_arvalid && ifu_axi_arready;
    assign r_fire = ifu_axi_rvalid && ifu_axi_rready;

    assign arready_delay_sampled = (lfsr_arready_random % `IFU_ARREADY_MAX_DELAY) + 4'd1;
    assign rvalid_delay_sampled  = (lfsr_resp_random % `IFU_RVALID_MAX_DELAY) + 4'd1;

    lfsr4 u_lfsr4_resp (
        .clk                    (clk),
        .rst                    (rst),
        .en                     (ar_fire),
        .random                 (lfsr_resp_random)
    );

    lfsr4 u_lfsr4_arready (
        .clk                    (clk),
        .rst                    (rst),
        .en                     (ifu_axi_arvalid && (state == I_WAIT_ARVALID)),
        .random                 (lfsr_arready_random)
    );

    always @(posedge clk) begin
        if (rst) begin
            state             <= I_WAIT_ARVALID;
            req_addr_reg       <= 32'b0;
            resp_data_reg      <= 32'b0;
            arready_wait_cnt   <= 4'b0;
            r_wait_cnt         <= 4'b0;
        end else begin
            case (state)
                I_WAIT_ARVALID: begin
                    if (ifu_axi_arvalid) begin
                        if (arready_delay_sampled == 4'd1) begin
                            state <= I_ARREADY;
                        end else begin
                            arready_wait_cnt <= arready_delay_sampled - 4'd1;
                            state <= I_WAIT_ARREADY;
                        end
                    end
                end

                I_WAIT_ARREADY: begin
                    if (arready_wait_cnt > 4'd1) begin
                        arready_wait_cnt <= arready_wait_cnt - 4'd1;
                    end else begin
                        state <= I_ARREADY;
                    end
                end

                I_ARREADY: begin
                    if (ar_fire) begin
                        req_addr_reg <= ifu_axi_araddr;
                        if (rvalid_delay_sampled == 4'd1) begin
                            resp_data_reg <= pmem_read(ifu_axi_araddr);
                            state <= I_RVALID;
                        end else begin
                            r_wait_cnt <= rvalid_delay_sampled - 4'd1;
                            state <= I_WAIT_R;
                        end
                    end
                end

                I_WAIT_R: begin
                    if (r_wait_cnt > 4'd1) begin
                        r_wait_cnt <= r_wait_cnt - 4'd1;
                    end else begin
                        resp_data_reg <= pmem_read(req_addr_reg);
                        state <= I_RVALID;
                    end
                end

                I_RVALID: begin
                    if (r_fire) begin
                        state <= I_WAIT_ARVALID;
                    end
                end

                default: begin
                    state <= I_WAIT_ARVALID;
                end
            endcase
        end
    end

    // IFU is read-only on AXI4-Lite.
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!rst) begin
            if (ifu_axi_awvalid !== 1'b0) begin
                $fatal(1, "IFU AXI violation: AWVALID must stay 0");
            end
            if (ifu_axi_wvalid !== 1'b0) begin
                $fatal(1, "IFU AXI violation: WVALID must stay 0");
            end
            if (ifu_axi_bready !== 1'b0) begin
                $fatal(1, "IFU AXI violation: BREADY must stay 0");
            end
        end
    end
`endif

    wire _unused_ok;
    assign _unused_ok = &{1'b0, ifu_axi_awaddr, ifu_axi_wdata, ifu_axi_wstrb};

endmodule
