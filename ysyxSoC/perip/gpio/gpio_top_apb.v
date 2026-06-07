module gpio_top_apb(
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

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

  localparam [3:0] GPIO_LED_OFS = 4'h0;
  localparam [3:0] GPIO_SW_OFS  = 4'h4;
  localparam [3:0] GPIO_SEG_OFS = 4'h8;
  localparam [3:0] GPIO_RSV_OFS = 4'hc;

  reg [15:0] led_reg;
  reg [31:0] seg_reg;

  wire       apb_write = in_psel && in_penable && in_pwrite;
  wire [3:0] reg_ofs   = in_paddr[3:0];
  reg  [31:0] prdata_r;

  function [7:0] seg_lut_active_low;
    input [3:0] hex;
    begin
      // Bit order matches NVBoard vector binding:
      // bit7..0 = A B C D E F G DP, active-low (0 lights).
      case (hex)
        4'h0: seg_lut_active_low = 8'h03;
        4'h1: seg_lut_active_low = 8'h9f;
        4'h2: seg_lut_active_low = 8'h25;
        4'h3: seg_lut_active_low = 8'h0d;
        4'h4: seg_lut_active_low = 8'h99;
        4'h5: seg_lut_active_low = 8'h49;
        4'h6: seg_lut_active_low = 8'h41;
        4'h7: seg_lut_active_low = 8'h1f;
        4'h8: seg_lut_active_low = 8'h01;
        4'h9: seg_lut_active_low = 8'h09;
        4'ha: seg_lut_active_low = 8'h11;
        4'hb: seg_lut_active_low = 8'hc1;
        4'hc: seg_lut_active_low = 8'h63;
        4'hd: seg_lut_active_low = 8'h85;
        4'he: seg_lut_active_low = 8'h61;
        4'hf: seg_lut_active_low = 8'h71;
        default: seg_lut_active_low = 8'hff;
      endcase
    end
  endfunction

  always @(*) begin
    case (reg_ofs)
      GPIO_LED_OFS: prdata_r = {16'h0, led_reg};
      GPIO_SW_OFS:  prdata_r = {16'h0, gpio_in};
      GPIO_SEG_OFS: prdata_r = seg_reg;
      GPIO_RSV_OFS: prdata_r = 32'h0;
      default:      prdata_r = 32'h0;
    endcase
  end

  always @(posedge clock or posedge reset) begin
    if (reset) begin
      led_reg <= 16'h0000;
      seg_reg <= 32'h0000_0000;
    end else if (apb_write) begin
      case (reg_ofs)
        GPIO_LED_OFS: begin
          if (in_pstrb[0]) led_reg[7:0]  <= in_pwdata[7:0];
          if (in_pstrb[1]) led_reg[15:8] <= in_pwdata[15:8];
        end
        GPIO_SEG_OFS: begin
          if (in_pstrb[0]) seg_reg[7:0]   <= in_pwdata[7:0];
          if (in_pstrb[1]) seg_reg[15:8]  <= in_pwdata[15:8];
          if (in_pstrb[2]) seg_reg[23:16] <= in_pwdata[23:16];
          if (in_pstrb[3]) seg_reg[31:24] <= in_pwdata[31:24];
        end
        default: begin
        end
      endcase
    end
  end

  assign in_pready  = in_psel && in_penable;
  assign in_prdata  = prdata_r;
  assign in_pslverr = 1'b0;

  assign gpio_out   = led_reg;

  assign gpio_seg_0 = seg_lut_active_low(seg_reg[3:0]);
  assign gpio_seg_1 = seg_lut_active_low(seg_reg[7:4]);
  assign gpio_seg_2 = seg_lut_active_low(seg_reg[11:8]);
  assign gpio_seg_3 = seg_lut_active_low(seg_reg[15:12]);
  assign gpio_seg_4 = seg_lut_active_low(seg_reg[19:16]);
  assign gpio_seg_5 = seg_lut_active_low(seg_reg[23:20]);
  assign gpio_seg_6 = seg_lut_active_low(seg_reg[27:24]);
  assign gpio_seg_7 = seg_lut_active_low(seg_reg[31:28]);

endmodule
