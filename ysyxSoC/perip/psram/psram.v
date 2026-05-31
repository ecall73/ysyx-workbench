module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

  localparam [2:0] ST_CMD       = 3'd0;
  localparam [2:0] ST_ADDR      = 3'd1;
  localparam [2:0] ST_RD_DUMMY  = 3'd2;
  localparam [2:0] ST_RD_DATA   = 3'd3;
  localparam [2:0] ST_WR_DATA   = 3'd4;
  localparam [2:0] ST_WAIT_END  = 3'd5;
  localparam [2:0] ST_ERR       = 3'd6;

  localparam [7:0] CMD_ENTER_QPI = 8'h35;
  localparam [7:0] CMD_QIOR = 8'heb;
  localparam [7:0] CMD_QIOW = 8'h38;
  localparam [2:0] READ_DUMMY_NIBBLES = 3'd6;

  reg [2:0] state;
  reg qpi_mode;

  reg [7:0] cmd;
  reg [2:0] cmd_cnt;
  reg       qpi_cmd_phase;

  reg [23:0] addr;
  reg [2:0] addr_nib_cnt;
  reg [21:0] byte_addr;

  reg [2:0] dummy_cnt;
  reg nibble_phase;
  reg [7:0] byte_buf;
  reg seen_ce_high_clk;

  reg [3:0] dio_out;
  reg dio_oe;
  wire [3:0] dio_in = dio;

  // 4MB PSRAM storage (byte-addressable)
  reg [7:0] mem [0:(1 << 22) - 1];

  wire [7:0] cmd_spi_next = {cmd[6:0], dio_in[0]};
  wire [7:0] cmd_qpi_next = {cmd[7:4], dio_in};
  wire [23:0] addr_next = {addr[19:0], dio_in};

  assign dio = dio_oe ? dio_out : 4'bz;

  initial begin
    state = ST_CMD;
    qpi_mode = 1'b0;
    cmd = 8'h00;
    cmd_cnt = 3'd0;
    qpi_cmd_phase = 1'b0;
    addr = 24'h000000;
    addr_nib_cnt = 3'd0;
    byte_addr = 22'd0;
    dummy_cnt = 3'd0;
    nibble_phase = 1'b0;
    byte_buf = 8'h00;
    dio_out = 4'h0;
    dio_oe = 1'b0;
    seen_ce_high_clk = 1'b0;
  end

  // Datasheet requirement: at least one clock pulse with CE# HIGH before operations.
  always @(posedge sck) begin
    if (ce_n) seen_ce_high_clk <= 1'b1;
  end

  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      // ce_n is the transaction boundary; keep qpi_mode sticky.
      state <= ST_CMD;
      cmd <= 8'h00;
      cmd_cnt <= 3'd0;
      qpi_cmd_phase <= 1'b0;
      addr <= 24'h000000;
      addr_nib_cnt <= 3'd0;
      byte_addr <= 22'd0;
      dummy_cnt <= 3'd0;
      nibble_phase <= 1'b0;
      byte_buf <= 8'h00;
      dio_out <= 4'h0;
      dio_oe <= 1'b0;
    end else begin
      case (state)
        ST_CMD: begin
          if (!seen_ce_high_clk) begin
            state <= ST_ERR;
            $fwrite(32'h80000002,
                    "Assertion failed: require at least one clock pulse while CE# is HIGH before operation\n");
            $fatal;
          end else
          if (!qpi_mode) begin
            cmd <= cmd_spi_next;
            if (cmd_cnt == 3'd7) begin
              cmd_cnt <= 3'd0;
              if (cmd_spi_next == CMD_ENTER_QPI) begin
                qpi_mode <= 1'b1;
                state <= ST_WAIT_END;
              end else begin
                state <= ST_ERR;
                $fwrite(32'h80000002,
                        "Assertion failed: Unsupported PSRAM SPI command 0x%02x (expect 0x35 enter-QPI)\n",
                        cmd_spi_next);
                $fatal;
              end
            end else begin
              cmd_cnt <= cmd_cnt + 3'd1;
            end
          end else begin
            if (!qpi_cmd_phase) begin
              cmd[7:4] <= dio_in;
              qpi_cmd_phase <= 1'b1;
            end else begin
              cmd[3:0] <= dio_in;
              qpi_cmd_phase <= 1'b0;
              if (cmd_qpi_next == CMD_QIOR || cmd_qpi_next == CMD_QIOW) begin
                state <= ST_ADDR;
                addr <= 24'h000000;
                addr_nib_cnt <= 3'd0;
              end else begin
                state <= ST_ERR;
                $fwrite(32'h80000002,
                        "Assertion failed: Unsupported PSRAM QPI command 0x%02x (only 0xEB/0x38)\n",
                        cmd_qpi_next);
                $fatal;
              end
            end
          end
        end

        ST_ADDR: begin
          addr <= addr_next;
          if (addr_nib_cnt == 3'd5) begin
            byte_addr <= addr_next[21:0];
            nibble_phase <= 1'b0;
            byte_buf <= 8'h00;
            if (cmd == CMD_QIOR) begin
              state <= ST_RD_DUMMY;
              dummy_cnt <= 3'd0;
              dio_oe <= 1'b0;
            end else begin
              state <= ST_WR_DATA;
              dio_oe <= 1'b0;
            end
          end else begin
            addr_nib_cnt <= addr_nib_cnt + 3'd1;
          end
        end

        ST_RD_DUMMY: begin
          if (dummy_cnt == (READ_DUMMY_NIBBLES - 1'b1)) begin
            state <= ST_RD_DATA;
            dummy_cnt <= 3'd0;
            nibble_phase <= 1'b0;
            dio_oe <= 1'b1;
          end else begin
            dummy_cnt <= dummy_cnt + 3'd1;
          end
        end

        ST_RD_DATA: begin
          dio_oe <= 1'b1;
          if (!nibble_phase) begin
            byte_buf <= mem[byte_addr];
            dio_out <= mem[byte_addr][7:4];
            nibble_phase <= 1'b1;
          end else begin
            dio_out <= byte_buf[3:0];
            nibble_phase <= 1'b0;
            // Wrap inside 1024-byte page: keep [21:10], increment [9:0].
            byte_addr <= {byte_addr[21:10], byte_addr[9:0] + 10'd1};
          end
        end

        ST_WR_DATA: begin
          if (!nibble_phase) begin
            byte_buf[7:4] <= dio_in;
            nibble_phase <= 1'b1;
          end else begin
            byte_buf[3:0] <= dio_in;
            mem[byte_addr] <= {byte_buf[7:4], dio_in};
            nibble_phase <= 1'b0;
            // Wrap inside 1024-byte page: keep [21:10], increment [9:0].
            byte_addr <= {byte_addr[21:10], byte_addr[9:0] + 10'd1};
          end
        end

        ST_WAIT_END: begin
          // Keep idle until ce_n goes high and resets the per-transaction state.
          dio_oe <= 1'b0;
        end

        default: begin
          state <= ST_ERR;
          $fwrite(32'h80000002, "Assertion failed: PSRAM entered invalid state\n");
          $fatal;
        end
      endcase
    end
  end

endmodule
