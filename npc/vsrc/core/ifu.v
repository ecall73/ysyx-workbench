module ysyx_26030082_ifu #(
    parameter [31:0] RESET_PC = 32'h3000_0000,
    parameter integer LINE_WORDS = 4,
    parameter integer LINE_COUNT = 4
) (
    input             clock,
    input             reset,

    // EX retire feedback
    input             ex_out_valid,
    input             ex_redirect,
    input      [31:0] ex_redirect_pc,
    input             ex_fence_i,

    // IF output interface
    output            if_out_valid,
    input             if_out_ready,
    output reg [31:0] if_pc,
    output     [31:0] if_inst,

    // AXI4 read master interface
    output     [31:0] ifu_master_araddr,
    output     [ 7:0] ifu_master_arlen,
    output     [ 1:0] ifu_master_arburst,
    output            ifu_master_arvalid,
    input             ifu_master_arready,
    input      [31:0] ifu_master_rdata,
    input      [ 1:0] ifu_master_rresp,
    input             ifu_master_rlast,
    input             ifu_master_rvalid,
    output            ifu_master_rready
);
    localparam integer WORD_OFF_W      = 2;
    localparam integer LINE_ADDR_OFF_W = $clog2(LINE_WORDS);
    localparam integer LINE_WORD_OFF_W = $clog2((LINE_WORDS < 2) ? 2 : LINE_WORDS);
    localparam integer INDEX_W         = $clog2(LINE_COUNT);
    localparam integer OFFSET_W        = WORD_OFF_W + LINE_ADDR_OFF_W;
    localparam integer TAG_W           = 32 - INDEX_W - OFFSET_W;

    localparam S_LOOKUP = 1'd0;
    localparam S_MISS_R = 1'd1;

    reg state;

    localparam integer LINE_DATA_W = LINE_WORDS * 32;
    reg [LINE_DATA_W-1:0] data_array [0:LINE_COUNT-1];
    reg [TAG_W-1:0] tag_array [0:LINE_COUNT-1];
    reg [LINE_COUNT-1:0] valid_array;

    reg [LINE_WORD_OFF_W-1:0] refill_word_idx;
    reg [31:0] refill_line_base;
    reg [INDEX_W-1:0] refill_index;
    reg [TAG_W-1:0] refill_tag;
    reg refill_ar_done;
    reg drop_refill;

    wire [LINE_WORD_OFF_W-1:0] lookup_word_offset =
        if_pc[WORD_OFF_W + LINE_WORD_OFF_W - 1 : WORD_OFF_W];
    wire [INDEX_W-1:0] lookup_index = if_pc[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    wire [TAG_W-1:0] lookup_tag = if_pc[31 : OFFSET_W + INDEX_W];
    wire [LINE_DATA_W-1:0] lookup_line = data_array[lookup_index];

    wire cache_hit = valid_array[lookup_index] && (tag_array[lookup_index] == lookup_tag);
    wire cache_miss = (state == S_LOOKUP) && !cache_hit;

    wire flush = ex_out_valid && ex_redirect;
    wire invalidate = ex_out_valid && ex_fence_i;
    assign if_out_valid = (state == S_LOOKUP) && cache_hit;
    assign if_inst = lookup_line[{lookup_word_offset, 5'b0} +: 32];

    wire req_fire = if_out_valid && if_out_ready;

    wire [31:0] miss_line_base = {if_pc[31:OFFSET_W], {OFFSET_W{1'b0}}};
    wire refill_start = cache_miss && !flush;
    assign ifu_master_araddr = (state == S_LOOKUP) ? miss_line_base : refill_line_base;
    assign ifu_master_arlen = LINE_WORDS[7:0] - 8'd1;
    assign ifu_master_arburst = 2'b01;
    assign ifu_master_arvalid = refill_start ||
                                (state == S_MISS_R && !refill_ar_done);
    assign ifu_master_rready = (state == S_MISS_R) && refill_ar_done;
    wire ar_fire = ifu_master_arvalid && ifu_master_arready;
    wire r_fire = ifu_master_rvalid && ifu_master_rready;
    wire refill_drop = drop_refill || flush;

    always @(posedge clock) begin
        if (reset) begin
            valid_array <= {LINE_COUNT{1'b0}};
        end else if (invalidate) begin
            valid_array <= {LINE_COUNT{1'b0}};
        end else if (refill_start) begin
            valid_array[lookup_index] <= 1'b0;
        end else if ((state == S_MISS_R) && r_fire && ifu_master_rlast && !refill_drop) begin
            valid_array[refill_index] <= 1'b1;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            state <= S_LOOKUP;
            if_pc <= RESET_PC;
            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
            refill_line_base <= RESET_PC;
            refill_index <= {INDEX_W{1'b0}};
            refill_tag <= {TAG_W{1'b0}};
            refill_ar_done <= 1'b0;
            drop_refill <= 1'b0;
        end else begin
            if (flush) begin
                if_pc <= ex_redirect_pc;
            end else if (req_fire) begin
                if_pc <= if_pc + 32'd4;
            end

            case (state)
                S_LOOKUP: begin
                    drop_refill <= 1'b0;
                    if (refill_start) begin
                        refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                        refill_line_base <= miss_line_base;
                        refill_index <= lookup_index;
                        refill_tag <= lookup_tag;
                        refill_ar_done <= ar_fire;
                        state <= S_MISS_R;
                    end
                end

                S_MISS_R: begin
                    if (flush) begin
                        drop_refill <= 1'b1;
                    end

                    if (!refill_ar_done) begin
                        if (ar_fire) begin
                            refill_ar_done <= 1'b1;
                        end
                    end else if (r_fire) begin
                        if (!refill_drop) begin
                            data_array[refill_index][{refill_word_idx, 5'b0} +: 32] <= ifu_master_rdata;
                        end

                        if (ifu_master_rlast) begin
                            if (!refill_drop) begin
                                tag_array[refill_index] <= refill_tag;
                            end
                            state <= S_LOOKUP;
                            refill_ar_done <= 1'b0;
                            drop_refill <= 1'b0;
                        end else begin
                            refill_word_idx <= refill_word_idx + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= S_LOOKUP;
                    refill_ar_done <= 1'b0;
                    drop_refill <= 1'b0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (LINE_WORDS < 1) begin
            $fatal(1, "ifu LINE_WORDS must be at least 1");
        end
        if ((LINE_WORDS & (LINE_WORDS - 1)) != 0) begin
            $fatal(1, "ifu LINE_WORDS must be a power of two");
        end
        if (LINE_COUNT < 2) begin
            $fatal(1, "ifu LINE_COUNT must be at least 2");
        end
        if ((LINE_COUNT & (LINE_COUNT - 1)) != 0) begin
            $fatal(1, "ifu LINE_COUNT must be a power of two");
        end
        if (LINE_WORDS > 256) begin
            $fatal(1, "ifu LINE_WORDS must be <= 256");
        end
        if (OFFSET_W + INDEX_W >= 32) begin
            $fatal(1, "ifu geometry is too large for ADDR_WIDTH");
        end
    end

    always @(posedge clock) begin
        if (!reset && req_fire && (if_pc[1:0] != 2'b00)) begin
            $fatal(1, "unaligned ifu fetch pc=%08x", if_pc);
        end
        if (!reset && (state == S_MISS_R) && r_fire) begin
            if ((refill_word_idx == (LINE_WORDS - 1)) && !ifu_master_rlast) begin
                $fatal(1, "ifu burst refill missing rlast on final beat line=%08x", miss_line_base);
            end
            if ((refill_word_idx != (LINE_WORDS - 1)) && ifu_master_rlast) begin
                $fatal(1, "ifu burst refill saw early rlast line=%08x beat=%0d", miss_line_base, refill_word_idx);
            end
        end
    end

    reg [19:0] debug_wait_cycles;
    always @(posedge clock) begin
        if (reset || req_fire || ar_fire || r_fire || flush) begin
            debug_wait_cycles <= 20'b0;
        end else begin
            debug_wait_cycles <= debug_wait_cycles + 1'b1;
            if (debug_wait_cycles == 20'd50000) begin
                $fatal(1,
                    "ifu watchdog pc=%08x state=%0d hit=%0d miss=%0d arvalid=%0d arready=%0d rvalid=%0d rready=%0d rlast=%0d ar_done=%0d drop=%0d",
                    if_pc, state, cache_hit, cache_miss,
                    ifu_master_arvalid, ifu_master_arready,
                    ifu_master_rvalid, ifu_master_rready, ifu_master_rlast,
                    refill_ar_done, drop_refill);
            end
        end
    end
`endif

    wire _unused_ok = &{1'b0, ifu_master_rresp};

endmodule
