module apb_delayer(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

  assign out_paddr   = in_paddr;
  assign out_psel    = in_psel;
  assign out_penable = in_penable;
  assign out_pprot   = in_pprot;
  assign out_pwrite  = in_pwrite;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;
  assign in_pready   = out_pready;
  assign in_prdata   = out_prdata;
  assign in_pslverr  = out_pslverr;

endmodule

/*
module apb_delayer(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

  // CPU_MHZ can be edited to 100/200/400 when validating calibration.
  localparam integer CPU_MHZ  = 100;
  localparam integer DEV_MHZ  = 100;
  localparam integer R_SHIFT  = 8;
  localparam integer R_SCALED = (CPU_MHZ << R_SHIFT) / DEV_MHZ;

  localparam [1:0] ST_IDLE   = 2'd0;
  localparam [1:0] ST_ACCESS = 2'd1;
  localparam [1:0] ST_DELAY  = 2'd2;

  reg [1:0]  state;
  reg [31:0] req_paddr;
  reg [2:0]  req_pprot;
  reg        req_pwrite;
  reg [31:0] req_pwdata;
  reg [3:0]  req_pstrb;

  reg [31:0] resp_prdata;
  reg        resp_pslverr;
  reg        resp_captured;

  reg [31:0] service_scaled_accum;
  reg [31:0] service_cycles;
  reg [31:0] delay_cycles_left;

  // Waveform-facing debug registers.
  reg [1:0]  dbg_state;
  reg [31:0] dbg_service_cycles;
  reg [31:0] dbg_target_cycles;
  reg [31:0] dbg_extra_cycles;
  reg        dbg_resp_captured;

  wire new_req_fire = (state == ST_IDLE) && in_psel && !in_penable;

  wire [31:0] access_scaled_accum_next = service_scaled_accum + R_SCALED[31:0];
  wire [31:0] access_service_cycles_next = service_cycles + 32'd1;
  wire [31:0] access_target_cycles_next = access_scaled_accum_next >> R_SHIFT;
  wire [31:0] access_extra_cycles_next =
    (access_target_cycles_next > access_service_cycles_next) ?
      (access_target_cycles_next - access_service_cycles_next) : 32'd0;
  wire access_done = (state == ST_ACCESS) && out_pready;
  wire access_reply_now = access_done && (access_extra_cycles_next == 32'd0);
  wire delay_done = (state == ST_DELAY) && (delay_cycles_left == 32'd0) && resp_captured;

  assign out_paddr = (state == ST_IDLE) ? in_paddr : req_paddr;
  assign out_pprot = (state == ST_IDLE) ? in_pprot : req_pprot;
  assign out_pwrite = (state == ST_IDLE) ? in_pwrite : req_pwrite;
  assign out_pwdata = (state == ST_IDLE) ? in_pwdata : req_pwdata;
  assign out_pstrb = (state == ST_IDLE) ? in_pstrb : req_pstrb;

  // Forward the setup phase immediately, then hold the access phase locally.
  assign out_psel =
    ((state == ST_IDLE) && in_psel && !in_penable) ||
    (state == ST_ACCESS);
  assign out_penable = (state == ST_ACCESS);

  assign in_pready = access_reply_now || delay_done;
  assign in_prdata = access_reply_now ? out_prdata : resp_prdata;
  assign in_pslverr = access_reply_now ? out_pslverr : resp_pslverr;

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      req_paddr <= 32'b0;
      req_pprot <= 3'b0;
      req_pwrite <= 1'b0;
      req_pwdata <= 32'b0;
      req_pstrb <= 4'b0;
      resp_prdata <= 32'b0;
      resp_pslverr <= 1'b0;
      resp_captured <= 1'b0;
      service_scaled_accum <= 32'b0;
      service_cycles <= 32'b0;
      delay_cycles_left <= 32'b0;
      dbg_state <= ST_IDLE;
      dbg_service_cycles <= 32'b0;
      dbg_target_cycles <= 32'b0;
      dbg_extra_cycles <= 32'b0;
      dbg_resp_captured <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          service_scaled_accum <= 32'b0;
          service_cycles <= 32'b0;
          delay_cycles_left <= 32'b0;
          resp_captured <= 1'b0;
          dbg_service_cycles <= 32'b0;
          dbg_target_cycles <= 32'b0;
          dbg_extra_cycles <= 32'b0;
          dbg_resp_captured <= 1'b0;
          if (new_req_fire) begin
            req_paddr <= in_paddr;
            req_pprot <= in_pprot;
            req_pwrite <= in_pwrite;
            req_pwdata <= in_pwdata;
            req_pstrb <= in_pstrb;
            state <= ST_ACCESS;
          end
        end

        ST_ACCESS: begin
          service_scaled_accum <= access_scaled_accum_next;
          service_cycles <= access_service_cycles_next;
          dbg_service_cycles <= access_service_cycles_next;
          dbg_target_cycles <= access_target_cycles_next;
          dbg_extra_cycles <= access_extra_cycles_next;

          if (out_pready) begin
            resp_prdata <= out_prdata;
            resp_pslverr <= out_pslverr;
            resp_captured <= 1'b1;
            dbg_resp_captured <= 1'b1;

            if (access_extra_cycles_next == 32'd0) begin
              state <= ST_IDLE;
            end else begin
              delay_cycles_left <= access_extra_cycles_next - 32'd1;
              state <= ST_DELAY;
            end
          end
        end

        ST_DELAY: begin
          if (delay_cycles_left != 32'd0) begin
            delay_cycles_left <= delay_cycles_left - 32'd1;
          end else begin
            state <= ST_IDLE;
          end
        end

        default: begin
          state <= ST_IDLE;
        end
      endcase

      dbg_state <= state;
      if (state == ST_DELAY) begin
        dbg_extra_cycles <= delay_cycles_left;
      end
    end
  end

endmodule
*/
