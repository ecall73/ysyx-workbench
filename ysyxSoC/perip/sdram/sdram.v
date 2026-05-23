module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,
  inout [15:0] dq
);

  // --------------------------------------------------------------------------
  // SDR command encoding (cs is handled separately)
  // --------------------------------------------------------------------------
  localparam CMD_NOP        = 3'b111;
  localparam CMD_ACTIVE     = 3'b011;
  localparam CMD_READ       = 3'b101;
  localparam CMD_WRITE      = 3'b100;
  localparam CMD_BURST_TERM = 3'b110;
  localparam CMD_PRECHARGE  = 3'b010;
  localparam CMD_REFRESH    = 3'b001;
  localparam CMD_LOAD_MODE  = 3'b000;

  // --------------------------------------------------------------------------
  // MT48LC16M16A2-like logical geometry:
  // 4 banks * 8192 rows * 512 columns * 16 bits = 32MB
  // --------------------------------------------------------------------------
  localparam BANKS = 4;
  localparam ROW_BITS = 13;
  localparam COL_BITS = 9;
  localparam MEM_WORDS = BANKS * (1 << ROW_BITS) * (1 << COL_BITS);
  localparam COL_MASK = (1 << COL_BITS) - 1;

  // SDRAM storage array (16-bit words).
  reg [15:0] mem [0:MEM_WORDS-1];

  // Per-bank activated row state.
  reg [ROW_BITS-1:0] active_row [0:BANKS-1];
  reg [BANKS-1:0] row_open;

  // Mode register fields used by this model.
  // mode_bl: burst length encoding, mode_cl: CAS latency.
  reg [2:0] mode_bl;
  reg [2:0] mode_cl;

  // DQ tri-state control:
  // - read path drives dq_out with dq_oe=1
  // - otherwise dq is high-Z and write path samples dq_in
  reg [15:0] dq_out;
  reg dq_oe;
  wire [15:0] dq_in = dq;
  assign dq = dq_oe ? dq_out : 16'hzzzz;

  // Debug counter used in fatal messages.
  reg [31:0] cycle;

  // READ transaction context (burst progression after READ command).
  reg rd_pending;
  reg [2:0] rd_delay;
  reg [1:0] rd_bank;
  reg [ROW_BITS-1:0] rd_row;
  reg [COL_BITS-1:0] rd_col_base;
  reg [3:0] rd_beats_left;
  reg [3:0] rd_beat_idx;

  // WRITE transaction context (remaining beats after WRITE command cycle).
  reg wr_active;
  reg [1:0] wr_bank;
  reg [ROW_BITS-1:0] wr_row;
  reg [COL_BITS-1:0] wr_col_base;
  reg [3:0] wr_beats_left;
  reg [3:0] wr_beat_idx;

  // Decode mode register BL bits to number of beats.
  // Unsupported BL codes return 0 and are rejected by command handling.
  function [3:0] decode_bl;
    input [2:0] bl_bits;
    begin
      case (bl_bits)
        3'b000: decode_bl = 4'd1;
        3'b001: decode_bl = 4'd2;
        3'b010: decode_bl = 4'd4;
        3'b011: decode_bl = 4'd8;
        default: decode_bl = 4'd0; // unsupported
      endcase
    end
  endfunction

  // Compute current burst column from base + beat index.
  // Address wraps within COL_BITS width.
  function [COL_BITS-1:0] burst_col;
    input [COL_BITS-1:0] base;
    input [3:0] idx;
    input [3:0] bl;
    reg [COL_BITS-1:0] offs;
    begin
      case (bl)
        4'd1: offs = idx[0:0];
        4'd2: offs = idx[0:0];
        4'd4: offs = idx[1:0];
        4'd8: offs = idx[2:0];
        default: offs = idx[2:0];
      endcase
      burst_col = (base + offs) & COL_MASK;
    end
  endfunction

  // Flatten bank/row/col tuple to linear memory word index.
  function integer word_index;
    input [1:0] bank_i;
    input [ROW_BITS-1:0] row_i;
    input [COL_BITS-1:0] col_i;
    begin
      word_index = ({bank_i, row_i, col_i});
    end
  endfunction

  wire [2:0] cmd = {ras, cas, we};
  integer wi;
  reg [3:0] bl_decoded;
  reg [COL_BITS-1:0] cur_col;
  reg [15:0] old_word;

  always @(posedge clk) begin
    cycle <= cycle + 1;

    // Default to not driving dq; read path explicitly enables it per beat.
    dq_oe <= 1'b0;

    if (!cke) begin
      // With CKE low, this behavioral model ignores command progression.
    end else begin
      // ----------------------------------------------------------------------
      // WRITE data path:
      // The WRITE command cycle consumes beat#0 separately below.
      // This block handles remaining beats (beat#1 .. beat#N-1).
      // ----------------------------------------------------------------------
      if (wr_active && wr_beats_left != 0) begin
        cur_col = burst_col(wr_col_base, wr_beat_idx, mode_bl);
        wi = word_index(wr_bank, wr_row, cur_col);
        old_word = mem[wi];

        if (!dqm[0]) old_word[7:0]   = dq_in[7:0];
        if (!dqm[1]) old_word[15:8]  = dq_in[15:8];
        mem[wi] = old_word;

        wr_beat_idx = wr_beat_idx + 1;
        wr_beats_left = wr_beats_left - 1;
        if (wr_beats_left == 1) begin
          wr_active <= 1'b0;
        end
      end

      // ----------------------------------------------------------------------
      // READ data path:
      // 1) wait rd_delay cycles (CL alignment),
      // 2) then drive one 16-bit beat per cycle until burst complete.
      // ----------------------------------------------------------------------
      if (rd_pending) begin
        if (rd_delay != 0) begin
          rd_delay <= rd_delay - 1;
        end else if (rd_beats_left != 0) begin
          cur_col = burst_col(rd_col_base, rd_beat_idx, mode_bl);
          wi = word_index(rd_bank, rd_row, cur_col);
          dq_out <= mem[wi];
          dq_oe <= 1'b1;
          rd_beat_idx <= rd_beat_idx + 1;
          rd_beats_left <= rd_beats_left - 1;
          if (rd_beats_left == 1) begin
            rd_pending <= 1'b0;
          end
        end
      end

      // ----------------------------------------------------------------------
      // Command decode
      // ----------------------------------------------------------------------
      if (cs) begin
        // COMMAND INHIBIT
      end else begin
        case (cmd)
          CMD_NOP: begin
            // no operation
          end
          CMD_ACTIVE: begin
            active_row[ba] <= a;
            row_open[ba] <= 1'b1;
          end
          CMD_READ: begin
            // READ requires an already activated row on target bank.
            if (!row_open[ba]) begin
              $fatal(1, "[sdram] READ without ACTIVE at cycle=%0d bank=%0d row=%0d col=%0d", cycle, ba, a, a[8:0]);
            end
            bl_decoded = decode_bl(mode_bl);
            if (bl_decoded == 0) begin
              $fatal(1, "[sdram] Unsupported BL code=%0b at cycle=%0d", mode_bl, cycle);
            end
            if (mode_cl < 1 || mode_cl > 3) begin
              $fatal(1, "[sdram] Unsupported CL=%0d at cycle=%0d", mode_cl, cycle);
            end

            rd_pending <= 1'b1;
            // Align to controller sampling pipeline (sample_data0_q -> sample_data_q).
            rd_delay <= (mode_cl[2:0] > 3'd1) ? (mode_cl[2:0] - 3'd2) : 3'd0;
            rd_bank <= ba;
            rd_row <= active_row[ba];
            // A10 auto-precharge bit is intentionally ignored in this model.
            rd_col_base <= a[8:0];
            rd_beats_left <= bl_decoded;
            rd_beat_idx <= 4'd0;
          end
          CMD_WRITE: begin
            // WRITE requires an already activated row on target bank.
            if (!row_open[ba]) begin
              $fatal(1, "[sdram] WRITE without ACTIVE at cycle=%0d bank=%0d row=%0d col=%0d", cycle, ba, a, a[8:0]);
            end
            bl_decoded = decode_bl(mode_bl);
            if (bl_decoded == 0) begin
              $fatal(1, "[sdram] Unsupported BL code=%0b at cycle=%0d", mode_bl, cycle);
            end
            wr_bank <= ba;
            wr_row <= active_row[ba];
            // A10 auto-precharge bit is intentionally ignored in this model.
            wr_col_base <= a[8:0];

            // In SDR SDRAM, the first write beat is sampled in the WRITE command cycle.
            cur_col = burst_col(a[8:0], 4'd0, bl_decoded);
            wi = word_index(ba, active_row[ba], cur_col);
            old_word = mem[wi];
            if (!dqm[0]) old_word[7:0]  = dq_in[7:0];
            if (!dqm[1]) old_word[15:8] = dq_in[15:8];
            mem[wi] = old_word;

            if (bl_decoded > 1) begin
              wr_active <= 1'b1;
              wr_beats_left <= bl_decoded - 1;
              wr_beat_idx <= 4'd1;
            end else begin
              wr_active <= 1'b0;
              wr_beats_left <= 4'd0;
              wr_beat_idx <= 4'd0;
            end
          end
          CMD_BURST_TERM: begin
            rd_pending <= 1'b0;
            wr_active <= 1'b0;
          end
          CMD_PRECHARGE: begin
            // Functional NOP in this model per lab requirement.
          end
          CMD_REFRESH: begin
            // Functional NOP in this model per lab requirement.
          end
          CMD_LOAD_MODE: begin
            // Only BL and CL are modeled; other mode bits are ignored.
            mode_bl <= a[2:0];
            mode_cl <= a[6:4];
            if (decode_bl(a[2:0]) == 0) begin
              $fatal(1, "[sdram] Unsupported LOAD_MODE BL=%0b at cycle=%0d", a[2:0], cycle);
            end
            if (a[6:4] < 3'd1 || a[6:4] > 3'd3) begin
              $fatal(1, "[sdram] Unsupported LOAD_MODE CL=%0d at cycle=%0d", a[6:4], cycle);
            end
          end
          default: begin
            $fatal(1, "[sdram] Illegal command cs/ras/cas/we=%b%b at cycle=%0d bank=%0d addr=%0h", cs, cmd, cycle, ba, a);
          end
        endcase
      end
    end
  end

  integer b;
  initial begin
    // Defaults aligned with current controller MODE_REG:
    // BL=2 (001), CL=2 (010).
    cycle = 0;
    mode_bl = 3'b001;
    mode_cl = 3'b010;

    row_open = 0;

    rd_pending = 1'b0;
    rd_delay = 3'd0;
    rd_bank = 2'd0;
    rd_row = {ROW_BITS{1'b0}};
    rd_col_base = {COL_BITS{1'b0}};
    rd_beats_left = 4'd0;
    rd_beat_idx = 4'd0;
    wr_active = 1'b0;
    wr_bank = 2'd0;
    wr_row = {ROW_BITS{1'b0}};
    wr_col_base = {COL_BITS{1'b0}};
    wr_beats_left = 4'd0;
    wr_beat_idx = 4'd0;

    dq_out = 16'h0000;
    dq_oe = 1'b0;

    for (b = 0; b < BANKS; b = b + 1) begin
      active_row[b] = {ROW_BITS{1'b0}};
    end
  end

endmodule
