module axi4_delayer(
  input         clock,
  input         reset,

  output        in_arready,
  input         in_arvalid,
  input  [3:0]  in_arid,
  input  [31:0] in_araddr,
  input  [7:0]  in_arlen,
  input  [2:0]  in_arsize,
  input  [1:0]  in_arburst,
  input         in_rready,
  output        in_rvalid,
  output [3:0]  in_rid,
  output [31:0] in_rdata,
  output [1:0]  in_rresp,
  output        in_rlast,
  output        in_awready,
  input         in_awvalid,
  input  [3:0]  in_awid,
  input  [31:0] in_awaddr,
  input  [7:0]  in_awlen,
  input  [2:0]  in_awsize,
  input  [1:0]  in_awburst,
  output        in_wready,
  input         in_wvalid,
  input  [31:0] in_wdata,
  input  [3:0]  in_wstrb,
  input         in_wlast,
                in_bready,
  output        in_bvalid,
  output [3:0]  in_bid,
  output [1:0]  in_bresp,

  input         out_arready,
  output        out_arvalid,
  output [3:0]  out_arid,
  output [31:0] out_araddr,
  output [7:0]  out_arlen,
  output [2:0]  out_arsize,
  output [1:0]  out_arburst,
  output        out_rready,
  input         out_rvalid,
  input  [3:0]  out_rid,
  input  [31:0] out_rdata,
  input  [1:0]  out_rresp,
  input         out_rlast,
  input         out_awready,
  output        out_awvalid,
  output [3:0]  out_awid,
  output [31:0] out_awaddr,
  output [7:0]  out_awlen,
  output [2:0]  out_awsize,
  output [1:0]  out_awburst,
  input         out_wready,
  output        out_wvalid,
  output [31:0] out_wdata,
  output [3:0]  out_wstrb,
  output        out_wlast,
                out_bready,
  input         out_bvalid,
  input  [3:0]  out_bid,
  input  [1:0]  out_bresp
);

  // CPU_MHZ can be edited to 100/200/400 when validating calibration.
  localparam integer CPU_MHZ       = 100;
  localparam integer DEV_MHZ       = 100;
  localparam integer R_SHIFT       = 8;
  localparam integer R_SCALED      = (CPU_MHZ << R_SHIFT) / DEV_MHZ;
  localparam integer RD_FIFO_DEPTH = 8;
  localparam integer RD_FIFO_PTR_W = 3;

  localparam [1:0] RD_IDLE    = 2'd0;
  localparam [1:0] RD_WAIT_AR = 2'd1;
  localparam [1:0] RD_WAIT_R  = 2'd2;

  localparam [1:0] WR_IDLE      = 2'd0;
  localparam [1:0] WR_WAIT_AW_W = 2'd1;
  localparam [1:0] WR_WAIT_B    = 2'd2;
  localparam [1:0] WR_HOLD_B    = 2'd3;

  reg [1:0] rd_state;
  reg [1:0] wr_state;

  reg [3:0]  rd_arid_reg;
  reg [31:0] rd_araddr_reg;
  reg [7:0]  rd_arlen_reg;
  reg [2:0]  rd_arsize_reg;
  reg [1:0]  rd_arburst_reg;
  reg [31:0] rd_service_cycles;
  reg [31:0] rd_scaled_accum;

  reg [3:0]  rd_fifo_rid [0:RD_FIFO_DEPTH-1];
  reg [31:0] rd_fifo_rdata [0:RD_FIFO_DEPTH-1];
  reg [1:0]  rd_fifo_rresp [0:RD_FIFO_DEPTH-1];
  reg        rd_fifo_rlast [0:RD_FIFO_DEPTH-1];
  reg [31:0] rd_fifo_target [0:RD_FIFO_DEPTH-1];
  reg [RD_FIFO_PTR_W-1:0] rd_fifo_head;
  reg [RD_FIFO_PTR_W-1:0] rd_fifo_tail;
  reg [3:0]               rd_fifo_count;

  reg [3:0]  wr_awid_reg;
  reg [31:0] wr_awaddr_reg;
  reg [7:0]  wr_awlen_reg;
  reg [2:0]  wr_awsize_reg;
  reg [1:0]  wr_awburst_reg;
  reg        wr_aw_buf_valid;
  reg        wr_aw_done;

  reg [31:0] wr_wdata_reg;
  reg [3:0]  wr_wstrb_reg;
  reg        wr_wlast_reg;
  reg        wr_w_buf_valid;
  reg        wr_w_done;

  reg [31:0] wr_service_cycles;
  reg [31:0] wr_scaled_accum;
  reg [3:0]  wr_bid_reg;
  reg [1:0]  wr_bresp_reg;
  reg [31:0] wr_b_target_cycle;
  reg        wr_b_captured;

  reg [1:0]  dbg_rd_state;
  reg [1:0]  dbg_wr_state;
  reg [31:0] dbg_rd_elapsed_cycles;
  reg [31:0] dbg_wr_elapsed_cycles;
  reg [31:0] dbg_rd_last_target_cycle;
  reg [31:0] dbg_wr_last_target_cycle;
  reg [3:0]  dbg_rd_fifo_occupancy;

  wire rd_start = (rd_state == RD_IDLE) && in_arvalid;
  wire rd_wait_ar = (rd_state == RD_WAIT_AR);
  wire rd_wait_r = (rd_state == RD_WAIT_R);
  wire rd_busy = (rd_state != RD_IDLE);
  wire rd_ar_path_valid = rd_start || rd_wait_ar;
  wire rd_ar_fire = rd_ar_path_valid && out_arready;

  wire [31:0] rd_live_target_cycle = rd_scaled_accum >> R_SHIFT;
  wire rd_live_target_ready = (rd_live_target_cycle <= rd_service_cycles);
  wire rd_fifo_head_valid = (rd_fifo_count != 4'd0);
  wire [31:0] rd_head_target_cycle = rd_fifo_target[rd_fifo_head];
  wire rd_fifo_head_ready = rd_fifo_head_valid && (rd_head_target_cycle <= rd_service_cycles);
  wire rd_live_visible = rd_wait_r && out_rvalid && !rd_fifo_head_valid && rd_live_target_ready;
  wire rd_direct_bypass_fire = rd_live_visible && in_rready;
  wire rd_pop_head = rd_fifo_head_ready && in_rready;
  wire rd_push_beat = rd_wait_r && out_rvalid && out_rready && !rd_direct_bypass_fire;
  wire [RD_FIFO_PTR_W-1:0] rd_fifo_head_next = rd_fifo_head + {{(RD_FIFO_PTR_W-1){1'b0}}, 1'b1};
  wire [RD_FIFO_PTR_W-1:0] rd_fifo_tail_next = rd_fifo_tail + {{(RD_FIFO_PTR_W-1){1'b0}}, 1'b1};
  wire [3:0] rd_fifo_count_after =
    rd_fifo_count +
    (rd_push_beat ? 4'd1 : 4'd0) -
    (rd_pop_head ? 4'd1 : 4'd0);

  wire rd_done_from_fifo = rd_pop_head && rd_fifo_rlast[rd_fifo_head];
  wire rd_done_from_live = rd_direct_bypass_fire && out_rlast;

  wire wr_start = (wr_state == WR_IDLE) && (in_awvalid || in_wvalid);
  wire wr_wait_aw_w = (wr_state == WR_WAIT_AW_W);
  wire wr_wait_b = (wr_state == WR_WAIT_B);
  wire wr_hold_b = (wr_state == WR_HOLD_B);
  wire wr_busy = (wr_state != WR_IDLE);

  wire wr_aw_path_valid =
    ((wr_state == WR_IDLE) || wr_wait_aw_w) &&
    !wr_aw_done &&
    (wr_aw_buf_valid || in_awvalid);
  wire wr_w_path_valid =
    ((wr_state == WR_IDLE) || wr_wait_aw_w) &&
    !wr_w_done &&
    (wr_w_buf_valid || in_wvalid);
  wire wr_aw_fire = wr_aw_path_valid && out_awready;
  wire wr_w_fire = wr_w_path_valid && out_wready;

  wire [31:0] wr_live_target_cycle = wr_scaled_accum >> R_SHIFT;
  wire wr_live_target_ready = (wr_live_target_cycle <= wr_service_cycles);
  wire wr_live_b_visible = wr_wait_b && out_bvalid && !wr_b_captured && wr_live_target_ready;
  wire wr_direct_bypass_fire = wr_live_b_visible && in_bready;

  assign in_arready = rd_ar_path_valid && out_arready;
  assign out_arvalid = rd_ar_path_valid;
  assign out_arid = rd_wait_ar ? rd_arid_reg : in_arid;
  assign out_araddr = rd_wait_ar ? rd_araddr_reg : in_araddr;
  assign out_arlen = rd_wait_ar ? rd_arlen_reg : in_arlen;
  assign out_arsize = rd_wait_ar ? rd_arsize_reg : in_arsize;
  assign out_arburst = rd_wait_ar ? rd_arburst_reg : in_arburst;

  assign out_rready = rd_wait_r && (rd_fifo_count < RD_FIFO_DEPTH);
  assign in_rvalid = rd_fifo_head_valid ? rd_fifo_head_ready : rd_live_visible;
  assign in_rid = rd_fifo_head_valid ? rd_fifo_rid[rd_fifo_head] : out_rid;
  assign in_rdata = rd_fifo_head_valid ? rd_fifo_rdata[rd_fifo_head] : out_rdata;
  assign in_rresp = rd_fifo_head_valid ? rd_fifo_rresp[rd_fifo_head] : out_rresp;
  assign in_rlast = rd_fifo_head_valid ? rd_fifo_rlast[rd_fifo_head] : out_rlast;

  assign in_awready = wr_aw_path_valid && out_awready;
  assign out_awvalid = wr_aw_path_valid;
  assign out_awid = wr_aw_buf_valid ? wr_awid_reg : in_awid;
  assign out_awaddr = wr_aw_buf_valid ? wr_awaddr_reg : in_awaddr;
  assign out_awlen = wr_aw_buf_valid ? wr_awlen_reg : in_awlen;
  assign out_awsize = wr_aw_buf_valid ? wr_awsize_reg : in_awsize;
  assign out_awburst = wr_aw_buf_valid ? wr_awburst_reg : in_awburst;

  assign in_wready = wr_w_path_valid && out_wready;
  assign out_wvalid = wr_w_path_valid;
  assign out_wdata = wr_w_buf_valid ? wr_wdata_reg : in_wdata;
  assign out_wstrb = wr_w_buf_valid ? wr_wstrb_reg : in_wstrb;
  assign out_wlast = wr_w_buf_valid ? wr_wlast_reg : in_wlast;

  assign out_bready = wr_wait_b && !wr_b_captured;
  assign in_bvalid = wr_b_captured ? (wr_b_target_cycle <= wr_service_cycles) : wr_live_b_visible;
  assign in_bid = wr_b_captured ? wr_bid_reg : out_bid;
  assign in_bresp = wr_b_captured ? wr_bresp_reg : out_bresp;

  always @(posedge clock) begin
    if (reset) begin
      rd_state <= RD_IDLE;
      wr_state <= WR_IDLE;

      rd_arid_reg <= 4'b0;
      rd_araddr_reg <= 32'b0;
      rd_arlen_reg <= 8'b0;
      rd_arsize_reg <= 3'b0;
      rd_arburst_reg <= 2'b0;
      rd_service_cycles <= 32'b0;
      rd_scaled_accum <= 32'b0;
      rd_fifo_head <= {RD_FIFO_PTR_W{1'b0}};
      rd_fifo_tail <= {RD_FIFO_PTR_W{1'b0}};
      rd_fifo_count <= 4'b0;

      wr_awid_reg <= 4'b0;
      wr_awaddr_reg <= 32'b0;
      wr_awlen_reg <= 8'b0;
      wr_awsize_reg <= 3'b0;
      wr_awburst_reg <= 2'b0;
      wr_aw_buf_valid <= 1'b0;
      wr_aw_done <= 1'b0;
      wr_wdata_reg <= 32'b0;
      wr_wstrb_reg <= 4'b0;
      wr_wlast_reg <= 1'b0;
      wr_w_buf_valid <= 1'b0;
      wr_w_done <= 1'b0;
      wr_service_cycles <= 32'b0;
      wr_scaled_accum <= 32'b0;
      wr_bid_reg <= 4'b0;
      wr_bresp_reg <= 2'b0;
      wr_b_target_cycle <= 32'b0;
      wr_b_captured <= 1'b0;

      dbg_rd_state <= RD_IDLE;
      dbg_wr_state <= WR_IDLE;
      dbg_rd_elapsed_cycles <= 32'b0;
      dbg_wr_elapsed_cycles <= 32'b0;
      dbg_rd_last_target_cycle <= 32'b0;
      dbg_wr_last_target_cycle <= 32'b0;
      dbg_rd_fifo_occupancy <= 4'b0;
    end else begin
      case (rd_state)
        RD_IDLE: begin
          rd_service_cycles <= 32'b0;
          rd_scaled_accum <= 32'b0;
          rd_fifo_head <= {RD_FIFO_PTR_W{1'b0}};
          rd_fifo_tail <= {RD_FIFO_PTR_W{1'b0}};
          rd_fifo_count <= 4'b0;
          dbg_rd_last_target_cycle <= 32'b0;

          if (rd_start) begin
            rd_service_cycles <= 32'd1;
            rd_scaled_accum <= R_SCALED[31:0];
            if (!out_arready) begin
              rd_arid_reg <= in_arid;
              rd_araddr_reg <= in_araddr;
              rd_arlen_reg <= in_arlen;
              rd_arsize_reg <= in_arsize;
              rd_arburst_reg <= in_arburst;
              rd_state <= RD_WAIT_AR;
            end else begin
              rd_state <= RD_WAIT_R;
            end
          end
        end

        RD_WAIT_AR: begin
          rd_service_cycles <= rd_service_cycles + 32'd1;
          rd_scaled_accum <= rd_scaled_accum + R_SCALED[31:0];
          if (rd_ar_fire) begin
            rd_state <= RD_WAIT_R;
          end
        end

        RD_WAIT_R: begin
          rd_service_cycles <= rd_service_cycles + 32'd1;
          rd_scaled_accum <= rd_scaled_accum + R_SCALED[31:0];

          if (rd_push_beat) begin
            rd_fifo_rid[rd_fifo_tail] <= out_rid;
            rd_fifo_rdata[rd_fifo_tail] <= out_rdata;
            rd_fifo_rresp[rd_fifo_tail] <= out_rresp;
            rd_fifo_rlast[rd_fifo_tail] <= out_rlast;
            rd_fifo_target[rd_fifo_tail] <= rd_live_target_cycle;
            rd_fifo_tail <= rd_fifo_tail_next;
            dbg_rd_last_target_cycle <= rd_live_target_cycle;
          end

          if (rd_pop_head) begin
            rd_fifo_head <= rd_fifo_head_next;
          end

          rd_fifo_count <= rd_fifo_count_after;

          if (rd_done_from_live || rd_done_from_fifo) begin
            rd_state <= RD_IDLE;
          end
        end

        default: begin
          rd_state <= RD_IDLE;
        end
      endcase

      case (wr_state)
        WR_IDLE: begin
          wr_aw_buf_valid <= 1'b0;
          wr_aw_done <= 1'b0;
          wr_w_buf_valid <= 1'b0;
          wr_w_done <= 1'b0;
          wr_service_cycles <= 32'b0;
          wr_scaled_accum <= 32'b0;
          wr_b_captured <= 1'b0;
          wr_b_target_cycle <= 32'b0;
          dbg_wr_last_target_cycle <= 32'b0;

          if (wr_start) begin
            wr_service_cycles <= 32'd1;
            wr_scaled_accum <= R_SCALED[31:0];

            if (in_awvalid && !out_awready) begin
              wr_aw_buf_valid <= 1'b1;
              wr_awid_reg <= in_awid;
              wr_awaddr_reg <= in_awaddr;
              wr_awlen_reg <= in_awlen;
              wr_awsize_reg <= in_awsize;
              wr_awburst_reg <= in_awburst;
            end
            wr_aw_done <= in_awvalid && out_awready;

            if (in_wvalid && !out_wready) begin
              wr_w_buf_valid <= 1'b1;
              wr_wdata_reg <= in_wdata;
              wr_wstrb_reg <= in_wstrb;
              wr_wlast_reg <= in_wlast;
            end
            wr_w_done <= in_wvalid && out_wready;

            if ((in_awvalid && out_awready) && (in_wvalid && out_wready)) begin
              wr_state <= WR_WAIT_B;
            end else begin
              wr_state <= WR_WAIT_AW_W;
            end
          end
        end

        WR_WAIT_AW_W: begin
          wr_service_cycles <= wr_service_cycles + 32'd1;
          wr_scaled_accum <= wr_scaled_accum + R_SCALED[31:0];

          if (!wr_aw_done && !wr_aw_buf_valid && in_awvalid && !out_awready) begin
            wr_aw_buf_valid <= 1'b1;
            wr_awid_reg <= in_awid;
            wr_awaddr_reg <= in_awaddr;
            wr_awlen_reg <= in_awlen;
            wr_awsize_reg <= in_awsize;
            wr_awburst_reg <= in_awburst;
          end
          if (!wr_w_done && !wr_w_buf_valid && in_wvalid && !out_wready) begin
            wr_w_buf_valid <= 1'b1;
            wr_wdata_reg <= in_wdata;
            wr_wstrb_reg <= in_wstrb;
            wr_wlast_reg <= in_wlast;
          end

          if (wr_aw_fire) begin
            wr_aw_done <= 1'b1;
            wr_aw_buf_valid <= 1'b0;
          end
          if (wr_w_fire) begin
            wr_w_done <= 1'b1;
            wr_w_buf_valid <= 1'b0;
          end

          if ((wr_aw_done || wr_aw_fire) && (wr_w_done || wr_w_fire)) begin
            wr_state <= WR_WAIT_B;
          end
        end

        WR_WAIT_B: begin
          wr_service_cycles <= wr_service_cycles + 32'd1;
          wr_scaled_accum <= wr_scaled_accum + R_SCALED[31:0];

          if (out_bvalid && !wr_b_captured) begin
            dbg_wr_last_target_cycle <= wr_live_target_cycle;
            if (wr_direct_bypass_fire) begin
              wr_state <= WR_IDLE;
            end else begin
              wr_bid_reg <= out_bid;
              wr_bresp_reg <= out_bresp;
              wr_b_target_cycle <= wr_live_target_cycle;
              wr_b_captured <= 1'b1;
              wr_state <= WR_HOLD_B;
            end
          end
        end

        WR_HOLD_B: begin
          wr_service_cycles <= wr_service_cycles + 32'd1;
          wr_scaled_accum <= wr_scaled_accum + R_SCALED[31:0];

          if ((wr_b_target_cycle <= wr_service_cycles) && in_bready) begin
            wr_state <= WR_IDLE;
          end
        end

        default: begin
          wr_state <= WR_IDLE;
        end
      endcase

      dbg_rd_state <= rd_state;
      dbg_wr_state <= wr_state;
      dbg_rd_elapsed_cycles <= rd_service_cycles;
      dbg_wr_elapsed_cycles <= wr_service_cycles;
      dbg_rd_fifo_occupancy <= rd_fifo_count;
    end
  end

`ifndef SYNTHESIS
  always @(posedge clock) begin
    if (!reset) begin
      if (DEV_MHZ <= 0) begin
        $fatal(1, "axi4_delayer DEV_MHZ must be > 0");
      end
      if (CPU_MHZ <= 0) begin
        $fatal(1, "axi4_delayer CPU_MHZ must be > 0");
      end
      if (rd_start && (in_arlen > 8'd7)) begin
        $fatal(1, "axi4_delayer only supports read burst beats <= 8");
      end
      if ((rd_state == RD_WAIT_R) && in_arvalid) begin
        $fatal(1, "axi4_delayer does not support multiple in-flight read transactions");
      end
      if (rd_push_beat && (rd_fifo_count == RD_FIFO_DEPTH)) begin
        $fatal(1, "axi4_delayer read beat buffer overflow");
      end
      if ((wr_start || (!wr_aw_done && in_awvalid)) && (in_awlen != 8'h00)) begin
        $fatal(1, "axi4_delayer does not support write burst calibration");
      end
      if (wr_w_fire && !out_wlast) begin
        $fatal(1, "axi4_delayer single-beat write requires wlast=1");
      end
      if ((wr_state == WR_WAIT_B || wr_state == WR_HOLD_B) && (in_awvalid || in_wvalid)) begin
        $fatal(1, "axi4_delayer does not support overlapping write transactions");
      end
      if ((R_SCALED == (1 << R_SHIFT)) && rd_wait_r && out_rvalid && !rd_fifo_head_valid && !rd_live_visible) begin
        $fatal(1, "axi4_delayer inserted unexpected read delay at ratio 1");
      end
      if ((R_SCALED == (1 << R_SHIFT)) && wr_wait_b && out_bvalid && !wr_live_target_ready) begin
        $fatal(1, "axi4_delayer inserted unexpected write-response delay at ratio 1");
      end
    end
  end
`endif

endmodule
