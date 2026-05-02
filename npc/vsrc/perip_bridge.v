`timescale 1ns / 1ps
`include "defines.v"

module perip_bridge (
    input  wire        clk,
    input  wire        rst,
    // AXI read address channel
    input  wire [31:0] lsu_axi_araddr,
    input  wire        lsu_axi_arvalid,
    output wire        lsu_axi_arready,
    // AXI read data channel
    output wire [31:0] lsu_axi_rdata,
    output wire [ 1:0] lsu_axi_rresp,
    output wire        lsu_axi_rvalid,
    input  wire        lsu_axi_rready,
    // AXI write address channel
    input  wire [31:0] lsu_axi_awaddr,
    input  wire        lsu_axi_awvalid,
    output wire        lsu_axi_awready,
    // AXI write data channel
    input  wire [31:0] lsu_axi_wdata,
    input  wire [ 3:0] lsu_axi_wstrb,
    input  wire        lsu_axi_wvalid,
    output wire        lsu_axi_wready,
    // AXI write response channel
    output wire [ 1:0] lsu_axi_bresp,
    output wire        lsu_axi_bvalid,
    input  wire        lsu_axi_bready
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    localparam B_IDLE            = 4'd0;
    localparam B_RD_WAIT_ARREADY = 4'd1;
    localparam B_RD_ARREADY      = 4'd2;
    localparam B_RD_WAIT_R       = 4'd3;
    localparam B_RD_RVALID       = 4'd4;
    localparam B_WR_WAIT_AW_W    = 4'd5;
    localparam B_WR_WAIT_B       = 4'd6;
    localparam B_WR_BVALID       = 4'd7;

    localparam C_WAIT_VALID = 2'd0;
    localparam C_WAIT_DELAY = 2'd1;
    localparam C_READY      = 2'd2;
    localparam C_DONE       = 2'd3;

    reg  [3:0]  state;
    reg  [31:0] rd_addr_reg;
    reg  [31:0] rd_data_reg;
    reg  [31:0] wr_addr_reg;
    reg  [31:0] wr_data_reg;
    reg  [ 3:0] wr_strb_reg;

    reg  [3:0]  ar_wait_cnt;
    reg  [3:0]  r_wait_cnt;
    reg  [3:0]  b_wait_cnt;
    reg  [3:0]  aw_wait_cnt;
    reg  [3:0]  w_wait_cnt;
    reg  [1:0]  aw_ch_state;
    reg  [1:0]  w_ch_state;
    reg         wr_commit_pending;

    wire [3:0] lfsr_ar_random;
    wire [3:0] lfsr_aw_random;
    wire [3:0] lfsr_w_random;
    wire [3:0] lfsr_r_random;
    wire [3:0] lfsr_b_random;

    wire [3:0] ar_delay_sampled;
    wire [3:0] aw_delay_sampled;
    wire [3:0] w_delay_sampled;
    wire [3:0] r_delay_sampled;
    wire [3:0] b_delay_sampled;

    wire       ar_fire;
    wire       r_fire;
    wire       aw_fire;
    wire       w_fire;
    wire       b_fire;

    wire       aw_done_next;
    wire       w_done_next;
    wire       wr_req_done_now;

    assign lsu_axi_arready = (state == B_RD_ARREADY);
    assign lsu_axi_rvalid = (state == B_RD_RVALID);
    assign lsu_axi_rdata = rd_data_reg;
    assign lsu_axi_rresp = 2'b00;

    assign lsu_axi_awready = (state == B_WR_WAIT_AW_W) && (aw_ch_state == C_READY);
    assign lsu_axi_wready = (state == B_WR_WAIT_AW_W) && (w_ch_state == C_READY);
    assign lsu_axi_bvalid = (state == B_WR_BVALID);
    assign lsu_axi_bresp = 2'b00;

    assign ar_fire = lsu_axi_arvalid && lsu_axi_arready;
    assign r_fire = lsu_axi_rvalid && lsu_axi_rready;
    assign aw_fire = lsu_axi_awvalid && lsu_axi_awready;
    assign w_fire = lsu_axi_wvalid && lsu_axi_wready;
    assign b_fire = lsu_axi_bvalid && lsu_axi_bready;

    assign ar_delay_sampled = (lfsr_ar_random % `LSU_ARREADY_MAX_DELAY) + 4'd1;
    assign aw_delay_sampled = (lfsr_aw_random % `LSU_AWREADY_MAX_DELAY) + 4'd1;
    assign w_delay_sampled = (lfsr_w_random % `LSU_WREADY_MAX_DELAY) + 4'd1;
    assign r_delay_sampled = (lfsr_r_random % `LSU_RVALID_MAX_DELAY) + 4'd1;
    assign b_delay_sampled = (lfsr_b_random % `LSU_BVALID_MAX_DELAY) + 4'd1;

    assign aw_done_next = (aw_ch_state == C_DONE) || aw_fire;
    assign w_done_next = (w_ch_state == C_DONE) || w_fire;
    assign wr_req_done_now = (state == B_WR_WAIT_AW_W) && aw_done_next && w_done_next;

    lfsr4 u_lfsr4_ar (
        .clk                    (clk),
        .rst                    (rst),
        .en                     ((state == B_IDLE) && lsu_axi_arvalid),
        .random                 (lfsr_ar_random)
    );

    lfsr4 u_lfsr4_aw (
        .clk                    (clk),
        .rst                    (rst),
        .en                     ((state == B_WR_WAIT_AW_W) && (aw_ch_state == C_WAIT_VALID) && lsu_axi_awvalid),
        .random                 (lfsr_aw_random)
    );

    lfsr4 u_lfsr4_w (
        .clk                    (clk),
        .rst                    (rst),
        .en                     ((state == B_WR_WAIT_AW_W) && (w_ch_state == C_WAIT_VALID) && lsu_axi_wvalid),
        .random                 (lfsr_w_random)
    );

    lfsr4 u_lfsr4_r (
        .clk                    (clk),
        .rst                    (rst),
        .en                     (ar_fire),
        .random                 (lfsr_r_random)
    );

    lfsr4 u_lfsr4_b (
        .clk                    (clk),
        .rst                    (rst),
        .en                     (wr_req_done_now),
        .random                 (lfsr_b_random)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= B_IDLE;
            rd_addr_reg <= 32'b0;
            rd_data_reg <= 32'b0;
            wr_addr_reg <= 32'b0;
            wr_data_reg <= 32'b0;
            wr_strb_reg <= 4'b0;
            ar_wait_cnt <= 4'b0;
            r_wait_cnt <= 4'b0;
            b_wait_cnt <= 4'b0;
            aw_wait_cnt <= 4'b0;
            w_wait_cnt <= 4'b0;
            aw_ch_state <= C_WAIT_VALID;
            w_ch_state <= C_WAIT_VALID;
            wr_commit_pending <= 1'b0;
        end else begin
            case (state)
                B_IDLE: begin
                    aw_ch_state <= C_WAIT_VALID;
                    w_ch_state <= C_WAIT_VALID;
                    wr_commit_pending <= 1'b0;
                    if (lsu_axi_arvalid) begin
                        if (ar_delay_sampled == 4'd1) begin
                            state <= B_RD_ARREADY;
                        end else begin
                            ar_wait_cnt <= ar_delay_sampled - 4'd1;
                            state <= B_RD_WAIT_ARREADY;
                        end
                    end else if (lsu_axi_awvalid || lsu_axi_wvalid) begin
                        state <= B_WR_WAIT_AW_W;
                    end
                end

                B_RD_WAIT_ARREADY: begin
                    if (ar_wait_cnt > 4'd1) begin
                        ar_wait_cnt <= ar_wait_cnt - 4'd1;
                    end else begin
                        state <= B_RD_ARREADY;
                    end
                end

                B_RD_ARREADY: begin
                    if (ar_fire) begin
                        rd_addr_reg <= lsu_axi_araddr;
                        if (r_delay_sampled == 4'd1) begin
                            rd_data_reg <= pmem_read(lsu_axi_araddr);
                            state <= B_RD_RVALID;
                        end else begin
                            r_wait_cnt <= r_delay_sampled - 4'd1;
                            state <= B_RD_WAIT_R;
                        end
                    end
                end

                B_RD_WAIT_R: begin
                    if (r_wait_cnt > 4'd1) begin
                        r_wait_cnt <= r_wait_cnt - 4'd1;
                    end else begin
                        rd_data_reg <= pmem_read(rd_addr_reg);
                        state <= B_RD_RVALID;
                    end
                end

                B_RD_RVALID: begin
                    if (r_fire) begin
                        state <= B_IDLE;
                    end
                end

                B_WR_WAIT_AW_W: begin
                    if ((aw_ch_state == C_WAIT_VALID) && lsu_axi_awvalid) begin
                        if (aw_delay_sampled == 4'd1) begin
                            aw_ch_state <= C_READY;
                        end else begin
                            aw_wait_cnt <= aw_delay_sampled - 4'd1;
                            aw_ch_state <= C_WAIT_DELAY;
                        end
                    end else if (aw_ch_state == C_WAIT_DELAY) begin
                        if (aw_wait_cnt > 4'd1) begin
                            aw_wait_cnt <= aw_wait_cnt - 4'd1;
                        end else begin
                            aw_ch_state <= C_READY;
                        end
                    end else if (aw_fire) begin
                        wr_addr_reg <= lsu_axi_awaddr;
                        aw_ch_state <= C_DONE;
                    end

                    if ((w_ch_state == C_WAIT_VALID) && lsu_axi_wvalid) begin
                        if (w_delay_sampled == 4'd1) begin
                            w_ch_state <= C_READY;
                        end else begin
                            w_wait_cnt <= w_delay_sampled - 4'd1;
                            w_ch_state <= C_WAIT_DELAY;
                        end
                    end else if (w_ch_state == C_WAIT_DELAY) begin
                        if (w_wait_cnt > 4'd1) begin
                            w_wait_cnt <= w_wait_cnt - 4'd1;
                        end else begin
                            w_ch_state <= C_READY;
                        end
                    end else if (w_fire) begin
                        wr_data_reg <= lsu_axi_wdata;
                        wr_strb_reg <= lsu_axi_wstrb;
                        w_ch_state <= C_DONE;
                    end

                    if (aw_done_next && w_done_next) begin
                        wr_commit_pending <= 1'b1;
                        if (b_delay_sampled == 4'd1) begin
                            state <= B_WR_BVALID;
                        end else begin
                            b_wait_cnt <= b_delay_sampled - 4'd1;
                            state <= B_WR_WAIT_B;
                        end
                    end
                end

                B_WR_WAIT_B: begin
                    if (wr_commit_pending) begin
                        pmem_write(wr_addr_reg, wr_data_reg, {4'b0000, wr_strb_reg});
                        wr_commit_pending <= 1'b0;
                    end
                    if (b_wait_cnt > 4'd1) begin
                        b_wait_cnt <= b_wait_cnt - 4'd1;
                    end else begin
                        state <= B_WR_BVALID;
                    end
                end

                B_WR_BVALID: begin
                    if (wr_commit_pending) begin
                        pmem_write(wr_addr_reg, wr_data_reg, {4'b0000, wr_strb_reg});
                        wr_commit_pending <= 1'b0;
                    end
                    if (b_fire) begin
                        state <= B_IDLE;
                    end
                end

                default: begin
                    state <= B_IDLE;
                    aw_ch_state <= C_WAIT_VALID;
                    w_ch_state <= C_WAIT_VALID;
                    wr_commit_pending <= 1'b0;
                end
            endcase
        end
    end

endmodule
