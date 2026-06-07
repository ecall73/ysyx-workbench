module ps2_top_apb(
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

  input         ps2_clk,
  input         ps2_data
);

  localparam [3:0] REG_DATA_OFS = 4'h0;
  localparam integer FIFO_DEPTH = 8;
  localparam integer FIFO_PTR_W = 3;

  reg [2:0] ps2_clk_sync;
  reg [3:0] bit_count;
  reg [9:0] frame_buf;
  reg       frame_valid;
  reg [7:0] frame_data;

  reg [7:0] fifo [0:FIFO_DEPTH-1];
  reg [FIFO_PTR_W-1:0] w_ptr;
  reg [FIFO_PTR_W-1:0] r_ptr;
  reg [3:0] fifo_count;

  reg [31:0] prdata_r;

  wire ps2_fall = ps2_clk_sync[2] & ~ps2_clk_sync[1];

  wire fifo_empty = (fifo_count == 4'd0);
  wire fifo_full  = (fifo_count == FIFO_DEPTH);

  wire apb_access = in_psel && in_penable;
  wire apb_read_data = apb_access && !in_pwrite && (in_paddr[3:0] == REG_DATA_OFS);
  wire pop_fire = apb_read_data && !fifo_empty;
  wire push_fire = frame_valid && (!fifo_full || pop_fire);

  always @(*) begin
    if ((in_paddr[3:0] == REG_DATA_OFS) && !fifo_empty) begin
      prdata_r = {24'h0, fifo[r_ptr]};
    end else begin
      prdata_r = 32'h0;
    end
  end

  always @(posedge clock or posedge reset) begin
    if (reset) begin
      // Align synchronizer state to the external line level to avoid
      // false edge detection right after reset.
      ps2_clk_sync <= {3{ps2_clk}};
      bit_count <= 4'd0;
      frame_buf <= 10'b0;
      frame_valid <= 1'b0;
      frame_data <= 8'h00;
    end else begin
      ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
      frame_valid <= 1'b0;

      if (ps2_fall) begin
        if (bit_count == 4'd0) begin
          // Start collecting only when a valid start bit (0) arrives.
          if (ps2_data == 1'b0) begin
            frame_buf[0] <= 1'b0;
            bit_count <= 4'd1;
          end
        end else if (bit_count == 4'd10) begin
          // Verify: start=0, stop=1, odd parity over {parity,data[7:0]}.
          if ((frame_buf[0] == 1'b0) && (ps2_data == 1'b1) && (^frame_buf[9:1])) begin
            frame_valid <= 1'b1;
            frame_data <= frame_buf[8:1];
          end
          bit_count <= 4'd0;
        end else begin
          frame_buf[bit_count] <= ps2_data;
          bit_count <= bit_count + 4'd1;
        end
      end
    end
  end

  always @(posedge clock or posedge reset) begin
    if (reset) begin
      w_ptr <= {FIFO_PTR_W{1'b0}};
      r_ptr <= {FIFO_PTR_W{1'b0}};
      fifo_count <= 4'd0;
    end else begin
      if (push_fire) begin
        fifo[w_ptr] <= frame_data;
        w_ptr <= w_ptr + {{(FIFO_PTR_W-1){1'b0}}, 1'b1};
      end

      if (pop_fire) begin
        r_ptr <= r_ptr + {{(FIFO_PTR_W-1){1'b0}}, 1'b1};
      end

      case ({push_fire, pop_fire})
        2'b10: fifo_count <= fifo_count + 4'd1;
        2'b01: fifo_count <= fifo_count - 4'd1;
        default: begin
        end
      endcase
    end
  end

  assign in_pready  = in_psel && in_penable;
  assign in_prdata  = prdata_r;
  assign in_pslverr = 1'b0;

endmodule
