module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);
  reg [7:0] rx_data;
  reg [7:0] tx_data;
  reg [4:0] bit_cnt;
  reg       miso_reg;

  assign miso = miso_reg;

  // Sample MOSI on SCK falling edge when slave is selected.
  always @(negedge sck or posedge ss) begin
    if (ss) begin
      rx_data <= 8'h00;
      tx_data <= 8'h00;
      bit_cnt <= 5'd0;
    end else begin
      if (bit_cnt < 5'd8) begin
        rx_data[bit_cnt[2:0]] <= mosi;
      end
      if (bit_cnt == 5'd7) begin
        tx_data <= {rx_data[0], rx_data[1], rx_data[2], rx_data[3], rx_data[4], rx_data[5], rx_data[6], mosi};
      end
      if (bit_cnt < 5'd16) begin
        bit_cnt <= bit_cnt + 5'd1;
      end
    end
  end

  // Drive MISO on SCK rising edge; idle high when not selected.
  always @(posedge sck or posedge ss) begin
    if (ss) begin
      miso_reg <= 1'b1;
    end else if (bit_cnt < 5'd8) begin
      miso_reg <= 1'b1;
    end else if (bit_cnt < 5'd16) begin
      miso_reg <= tx_data[bit_cnt[2:0]];
    end else begin
      miso_reg <= 1'b1;
    end
  end
endmodule
