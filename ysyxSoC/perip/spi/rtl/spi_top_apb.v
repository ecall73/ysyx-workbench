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

localparam [4:0] SPI_TX0_OFS  = 5'h00;
localparam [4:0] SPI_TX1_OFS  = 5'h04;
localparam [4:0] SPI_RX0_OFS  = 5'h00;
localparam [4:0] SPI_RX1_OFS  = 5'h04;
localparam [4:0] SPI_CTRL_OFS = 5'h10;
localparam [4:0] SPI_DIV_OFS  = 5'h14;
localparam [4:0] SPI_SS_OFS   = 5'h18;

localparam [31:0] SPI_CTRL_GO       = 32'h0000_0100;
localparam [31:0] SPI_CTRL_XIP_CFG  = 32'h0000_2440; // ASS | TX_NEG | CHAR_LEN(64)
localparam [31:0] SPI_FLASH_CMD     = 32'h0300_0000;
localparam [31:0] SPI_FLASH_DUMMY   = 32'h0000_0000;
localparam [31:0] SPI_FLASH_SS      = 32'h0000_0001;
localparam [31:0] SPI_DIV_FAST      = 32'h0000_0000;

localparam [3:0] XIP_IDLE           = 4'd0;
localparam [3:0] XIP_WR_DIV         = 4'd1;
localparam [3:0] XIP_WR_SS          = 4'd2;
localparam [3:0] XIP_WR_TX1         = 4'd3;
localparam [3:0] XIP_WR_TX0         = 4'd4;
localparam [3:0] XIP_WR_CTRL_GO     = 4'd5;
localparam [3:0] XIP_RD_CTRL_POLL   = 4'd6;
localparam [3:0] XIP_RD_RX1         = 4'd7;
localparam [3:0] XIP_RD_RX0         = 4'd8;
localparam [3:0] XIP_DONE           = 4'd9;

wire is_flash_xip = (in_paddr >= flash_addr_start) && (in_paddr <= flash_addr_end);
wire apb_access = in_psel && in_penable;
wire is_xip_read_req = apb_access && is_flash_xip && !in_pwrite;
wire is_xip_write_req = apb_access && is_flash_xip && in_pwrite;

reg [3:0] xip_state;
reg [23:0] xip_addr;
reg [31:0] xip_rdata;
reg [31:0] xip_req_addr;
reg        xip_req_valid;

reg  [4:0] xip_wb_adr;
reg [31:0] xip_wb_dat_w;
reg  [3:0] xip_wb_sel;
reg        xip_wb_we;
reg        xip_wb_stb;
reg        xip_wb_cyc;

wire [4:0] wb_adr_i;
wire [31:0] wb_dat_i;
wire [31:0] wb_dat_o;
wire [3:0] wb_sel_i;
wire wb_we_i;
wire wb_stb_i;
wire wb_cyc_i;
wire wb_ack_o;
wire wb_err_o;

wire xip_busy = (xip_state != XIP_IDLE) && (xip_state != XIP_DONE);
wire xip_resp_phase = (xip_state == XIP_DONE) && xip_req_valid;
wire xip_master_sel = xip_busy || xip_resp_phase;
wire apb_passthrough = !xip_master_sel && !is_flash_xip;

assign wb_adr_i = xip_master_sel ? xip_wb_adr   : in_paddr[4:0];
assign wb_dat_i = xip_master_sel ? xip_wb_dat_w : in_pwdata;
assign wb_sel_i = xip_master_sel ? xip_wb_sel   : in_pstrb;
assign wb_we_i  = xip_master_sel ? xip_wb_we    : in_pwrite;
assign wb_stb_i = xip_master_sel ? xip_wb_stb   : in_psel;
assign wb_cyc_i = xip_master_sel ? xip_wb_cyc   : in_penable;

wire [31:0] xip_resp_data = xip_rdata;
wire xip_resp_valid = xip_resp_phase;
wire xip_resp_ready = apb_access && is_flash_xip && !in_pwrite &&
                      xip_req_valid && (in_paddr == xip_req_addr);

assign in_pready = apb_passthrough ? wb_ack_o :
                   (is_xip_write_req ? 1'b1 :
                   (xip_resp_valid && xip_resp_ready));
assign in_prdata = apb_passthrough ? wb_dat_o :
                   ((xip_resp_valid && xip_resp_ready) ? xip_resp_data : 32'b0);
assign in_pslverr = apb_passthrough ? wb_err_o : is_xip_write_req;

function [31:0] bswap32;
  input [31:0] data;
  begin
    bswap32 = {data[7:0], data[15:8], data[23:16], data[31:24]};
  end
endfunction

function [31:0] xip_align32;
  input [31:0] data;
  input [1:0]  byte_off;
  begin
    case (byte_off)
      2'b00: xip_align32 = data;
      2'b01: xip_align32 = {8'b0,  data[31:8]};
      2'b10: xip_align32 = {16'b0, data[31:16]};
      2'b11: xip_align32 = {24'b0, data[31:24]};
      default: xip_align32 = data;
    endcase
  end
endfunction

always @(*) begin
  xip_wb_adr   = 5'b0;
  xip_wb_dat_w = 32'b0;
  xip_wb_sel   = 4'hf;
  xip_wb_we    = 1'b0;
  xip_wb_stb   = 1'b0;
  xip_wb_cyc   = 1'b0;

  case (xip_state)
    XIP_WR_DIV: begin
      xip_wb_adr   = SPI_DIV_OFS;
      xip_wb_dat_w = SPI_DIV_FAST;
      xip_wb_we    = 1'b1;
      xip_wb_stb   = 1'b1;
      xip_wb_cyc   = 1'b1;
    end
    XIP_WR_SS: begin
      xip_wb_adr   = SPI_SS_OFS;
      xip_wb_dat_w = SPI_FLASH_SS;
      xip_wb_we    = 1'b1;
      xip_wb_stb   = 1'b1;
      xip_wb_cyc   = 1'b1;
    end
    XIP_WR_TX1: begin
      xip_wb_adr   = SPI_TX1_OFS;
      xip_wb_dat_w = SPI_FLASH_CMD | {8'b0, xip_addr};
      xip_wb_we    = 1'b1;
      xip_wb_stb   = 1'b1;
      xip_wb_cyc   = 1'b1;
    end
    XIP_WR_TX0: begin
      xip_wb_adr   = SPI_TX0_OFS;
      xip_wb_dat_w = SPI_FLASH_DUMMY;
      xip_wb_we    = 1'b1;
      xip_wb_stb   = 1'b1;
      xip_wb_cyc   = 1'b1;
    end
    XIP_WR_CTRL_GO: begin
      xip_wb_adr   = SPI_CTRL_OFS;
      xip_wb_dat_w = SPI_CTRL_XIP_CFG | SPI_CTRL_GO;
      xip_wb_we    = 1'b1;
      xip_wb_stb   = 1'b1;
      xip_wb_cyc   = 1'b1;
    end
    XIP_RD_CTRL_POLL: begin
      xip_wb_adr = SPI_CTRL_OFS;
      xip_wb_we  = 1'b0;
      xip_wb_stb = 1'b1;
      xip_wb_cyc = 1'b1;
    end
    XIP_RD_RX1: begin
      xip_wb_adr = SPI_RX1_OFS;
      xip_wb_we  = 1'b0;
      xip_wb_stb = 1'b1;
      xip_wb_cyc = 1'b1;
    end
    XIP_RD_RX0: begin
      xip_wb_adr = SPI_RX0_OFS;
      xip_wb_we  = 1'b0;
      xip_wb_stb = 1'b1;
      xip_wb_cyc = 1'b1;
    end
    default: begin
    end
  endcase
end

always @(posedge clock or posedge reset) begin
  if (reset) begin
    xip_state <= XIP_IDLE;
    xip_addr <= 24'b0;
    xip_rdata <= 32'b0;
    xip_req_addr <= 32'b0;
    xip_req_valid <= 1'b0;
  end else begin
    case (xip_state)
      XIP_IDLE: begin
        if (is_xip_read_req && !xip_req_valid) begin
          xip_req_addr <= in_paddr;
          xip_req_valid <= 1'b1;
          xip_addr <= in_paddr[23:0];
          xip_state <= XIP_WR_DIV;
        end
      end
      XIP_WR_DIV: begin
        if (wb_ack_o) xip_state <= XIP_WR_SS;
      end
      XIP_WR_SS: begin
        if (wb_ack_o) xip_state <= XIP_WR_TX1;
      end
      XIP_WR_TX1: begin
        if (wb_ack_o) xip_state <= XIP_WR_TX0;
      end
      XIP_WR_TX0: begin
        if (wb_ack_o) xip_state <= XIP_WR_CTRL_GO;
      end
      XIP_WR_CTRL_GO: begin
        if (wb_ack_o) xip_state <= XIP_RD_CTRL_POLL;
      end
      XIP_RD_CTRL_POLL: begin
        if (wb_ack_o) begin
          if (wb_dat_o[8]) xip_state <= XIP_RD_CTRL_POLL;
          else xip_state <= XIP_RD_RX1;
        end
      end
      XIP_RD_RX1: begin
        if (wb_ack_o) begin
          xip_state <= XIP_RD_RX0;
        end
      end
      XIP_RD_RX0: begin
        if (wb_ack_o) begin
          xip_rdata <= xip_align32(bswap32(wb_dat_o), xip_req_addr[1:0]);
          xip_state <= XIP_DONE;
        end
      end
      XIP_DONE: begin
        if (xip_resp_ready) begin
          xip_req_valid <= 1'b0;
          xip_state <= XIP_IDLE;
        end
      end
      default: begin
        xip_state <= XIP_IDLE;
      end
    endcase
  end
end

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
