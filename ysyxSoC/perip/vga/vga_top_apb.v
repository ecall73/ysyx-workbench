module vga_top_apb(
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

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

  localparam [31:0] FB_BASE = 32'h2100_0000;
  localparam [31:0] FB_END  = 32'h211f_ffff;

  localparam integer H_SYNC   = 96;
  localparam integer H_BACK   = 48;
  localparam integer H_VISIBLE = 640;
  localparam integer H_FRONT  = 16;
  localparam integer H_TOTAL  = H_SYNC + H_BACK + H_VISIBLE + H_FRONT; // 800

  localparam integer V_SYNC   = 2;
  localparam integer V_BACK   = 33;
  localparam integer V_VISIBLE = 480;
  localparam integer V_FRONT  = 10;
  localparam integer V_TOTAL  = V_SYNC + V_BACK + V_VISIBLE + V_FRONT; // 525

  localparam integer H_ACTIVE_START = H_SYNC + H_BACK; // 144
  localparam integer H_ACTIVE_END   = H_ACTIVE_START + H_VISIBLE; // 784
  localparam integer V_ACTIVE_START = V_SYNC + V_BACK; // 35
  localparam integer V_ACTIVE_END   = V_ACTIVE_START + V_VISIBLE; // 515

  localparam integer FB_WORDS = H_VISIBLE * V_VISIBLE; // 307200

  reg [31:0] fb_mem [0:FB_WORDS - 1];

  reg [9:0] h_cnt;
  reg [9:0] v_cnt;
  reg [31:0] apb_rdata_r;
  reg [31:0] scan_pixel_r;
  integer i;

  wire apb_access = in_psel && in_penable;
  wire apb_write  = apb_access && in_pwrite;
  wire apb_read   = apb_access && !in_pwrite;

  wire apb_in_range = (in_paddr >= FB_BASE) && (in_paddr <= FB_END);
  wire [31:0] apb_word_addr_w = (in_paddr - FB_BASE) >> 2;
  wire apb_word_valid = apb_in_range && (apb_word_addr_w < FB_WORDS);
  wire [18:0] apb_word_addr = apb_word_addr_w[18:0];

  wire h_active = (h_cnt >= H_ACTIVE_START) && (h_cnt < H_ACTIVE_END);
  wire v_active = (v_cnt >= V_ACTIVE_START) && (v_cnt < V_ACTIVE_END);
  wire scan_valid = h_active && v_active;

  wire [9:0] scan_x = h_cnt - 10'd144;
  wire [9:0] scan_y = v_cnt - 10'd35;
  wire [19:0] scan_addr_w = (scan_y * 10'd640) + scan_x;
  wire [18:0] scan_addr = scan_addr_w[18:0];

  initial begin
    for (i = 0; i < FB_WORDS; i = i + 1) begin
      fb_mem[i] = 32'h0;
    end
  end

  always @(*) begin
    apb_rdata_r = 32'h0;
    if (apb_read && apb_word_valid) begin
      apb_rdata_r = fb_mem[apb_word_addr];
    end
  end

  always @(*) begin
    scan_pixel_r = 32'h0;
    if (scan_valid) begin
      scan_pixel_r = fb_mem[scan_addr];
    end
  end

  always @(posedge clock or posedge reset) begin
    if (reset) begin
      h_cnt <= 10'd0;
      v_cnt <= 10'd0;
    end else begin
      if (h_cnt == H_TOTAL - 1) begin
        h_cnt <= 10'd0;
        if (v_cnt == V_TOTAL - 1) begin
          v_cnt <= 10'd0;
        end else begin
          v_cnt <= v_cnt + 10'd1;
        end
      end else begin
        h_cnt <= h_cnt + 10'd1;
      end
    end
  end

  always @(posedge clock or posedge reset) begin
    if (reset) begin
    end else if (apb_write && apb_word_valid) begin
      if (in_pstrb[0]) fb_mem[apb_word_addr][7:0]   <= in_pwdata[7:0];
      if (in_pstrb[1]) fb_mem[apb_word_addr][15:8]  <= in_pwdata[15:8];
      if (in_pstrb[2]) fb_mem[apb_word_addr][23:16] <= in_pwdata[23:16];
      if (in_pstrb[3]) fb_mem[apb_word_addr][31:24] <= in_pwdata[31:24];
    end
  end

  assign in_pready  = in_psel && in_penable;
  assign in_prdata  = apb_rdata_r;
  assign in_pslverr = 1'b0;

  // Active-low sync pulses at the beginning of each line/frame.
  assign vga_hsync = !(h_cnt < H_SYNC);
  assign vga_vsync = !(v_cnt < V_SYNC);
  assign vga_valid = scan_valid;

  // Pixel format: 0x00RRGGBB (alpha/high byte ignored).
  assign vga_r = scan_valid ? scan_pixel_r[23:16] : 8'h00;
  assign vga_g = scan_valid ? scan_pixel_r[15:8]  : 8'h00;
  assign vga_b = scan_valid ? scan_pixel_r[7:0]   : 8'h00;

endmodule
