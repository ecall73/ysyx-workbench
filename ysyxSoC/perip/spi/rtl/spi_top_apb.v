// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
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

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

wire is_flash_xip = (in_paddr >= flash_addr_start) && (in_paddr <= flash_addr_end);
wire apb_setup = in_psel && !in_penable;
wire apb_fire = in_psel && in_penable;
wire is_xip_read_setup = apb_setup && is_flash_xip && !in_pwrite;
wire is_xip_read_req = apb_fire && is_flash_xip && !in_pwrite;
wire is_xip_write_req = apb_fire && is_flash_xip && in_pwrite;

wire [4:0] wb_adr_i;
wire [31:0] wb_dat_i;
wire [31:0] wb_dat_o;
wire [3:0] wb_sel_i;
wire wb_we_i;
wire wb_stb_i;
wire wb_cyc_i;
wire wb_ack_o;
wire wb_err_o;

wire apb_passthrough = !is_flash_xip;

wire [31:0] xip_data;
flash_cmd xip_flash_cmd_i(
  .clock(clock),
  .valid(is_xip_read_setup),
  .cmd(8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b00}),
  .data(xip_data)
);

assign wb_adr_i = in_paddr[4:0];
assign wb_dat_i = in_pwdata;
assign wb_sel_i = in_pstrb;
assign wb_we_i  = in_pwrite;
assign wb_stb_i = in_psel;
assign wb_cyc_i = in_penable;

assign in_pready  = apb_passthrough ? wb_ack_o : (is_xip_read_req || is_xip_write_req);
assign in_prdata  = apb_passthrough ? wb_dat_o : xip_data;
assign in_pslverr = apb_passthrough ? wb_err_o : is_xip_write_req;

`ifndef SYNTHESIS
always @(posedge clock) begin
  if (!reset && is_xip_write_req) begin
    $fwrite(32'h80000002, "Assertion failed: write to flash XIP space addr=%x data=%x\n", in_paddr, in_pwdata);
    $fatal;
  end
end
`endif

spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(wb_adr_i),
  .wb_dat_i(wb_dat_i),
  .wb_dat_o(wb_dat_o),
  .wb_sel_i(wb_sel_i),
  .wb_we_i (wb_we_i),
  .wb_stb_i(wb_stb_i),
  .wb_cyc_i(wb_cyc_i),
  .wb_ack_o(wb_ack_o),
  .wb_err_o(wb_err_o),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

`endif // FAST_FLASH

endmodule
