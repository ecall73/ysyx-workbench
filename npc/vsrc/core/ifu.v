module ysyx_26030082_ifu #(
    parameter [31:0] RESET_PC = 32'h3000_0000,
    parameter integer LINE_WORDS = 4,
    parameter integer LINE_COUNT = 4
) (
    input  wire        clock,
    input  wire        reset,

    // EX retire feedback
    input  wire        ex_out_valid,
    input  wire        ex_redirect,
    input  wire [31:0] ex_redirect_pc,
    input  wire        ex_fence_i,

    // IF output interface
    output wire        if_out_valid,
    input  wire        if_out_ready,
    output wire [31:0] if_pc,
    output wire [31:0] if_inst,

    // AXI4 read master interface
    output wire [31:0] ifu_master_araddr,
    output wire [ 7:0] ifu_master_arlen,
    output wire [ 1:0] ifu_master_arburst,
    output wire        ifu_master_arvalid,
    input  wire        ifu_master_arready,
    input  wire [31:0] ifu_master_rdata,
    input  wire [ 1:0] ifu_master_rresp,
    input  wire        ifu_master_rlast,
    input  wire        ifu_master_rvalid,
    output wire        ifu_master_rready
);
    localparam integer WORD_OFF_W      = 2;
    localparam integer LINE_ADDR_OFF_W = $clog2(LINE_WORDS);
    localparam integer LINE_WORD_OFF_W = $clog2((LINE_WORDS < 2) ? 2 : LINE_WORDS);
    localparam integer INDEX_W         = $clog2(LINE_COUNT);
    localparam integer OFFSET_W        = WORD_OFF_W + LINE_ADDR_OFF_W;
    localparam integer TAG_W           = 32 - INDEX_W - OFFSET_W;

    localparam [1:0] S_LOOKUP  = 2'd0;
    localparam [1:0] S_MISS_AR = 2'd1;
    localparam [1:0] S_MISS_R  = 2'd2;
    localparam [1:0] S_DROP_R  = 2'd3;

    reg [1:0] state;
    reg [31:0] pc_r;

    localparam integer LINE_DATA_W = LINE_WORDS * 32;
    reg [LINE_DATA_W-1:0] data_array [0:LINE_COUNT-1];
    reg [TAG_W-1:0] tag_array [0:LINE_COUNT-1];
    reg [LINE_COUNT-1:0] valid_array;

    reg [LINE_WORD_OFF_W-1:0] refill_word_idx;

    wire [LINE_WORD_OFF_W-1:0] lookup_word_offset;
    wire [INDEX_W-1:0]         lookup_index;
    wire [TAG_W-1:0]           lookup_tag;
    wire [LINE_DATA_W-1:0]     lookup_line;

    wire               cache_hit;
    wire               cache_miss;
    wire               req_fire;
    wire               ar_fire;
    wire               r_fire;
    wire               commit_fire;
    wire               flush;
    wire               invalidate;
    wire [31:0] miss_line_base;

    assign lookup_word_offset =
        pc_r[WORD_OFF_W + LINE_WORD_OFF_W - 1 : WORD_OFF_W];
    assign lookup_index = pc_r[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    assign lookup_tag = pc_r[31 : OFFSET_W + INDEX_W];
    assign lookup_line = data_array[lookup_index];

    assign cache_hit = valid_array[lookup_index] && (tag_array[lookup_index] == lookup_tag);
    assign cache_miss = (state == S_LOOKUP) && !cache_hit;

    assign commit_fire = ex_out_valid;
    assign flush = commit_fire && ex_redirect;
    assign invalidate = commit_fire && ex_fence_i;
    assign if_out_valid = (state == S_LOOKUP) && cache_hit;
    assign if_pc = pc_r;
    assign if_inst = lookup_line[{lookup_word_offset, 5'b0} +: 32];

    assign req_fire = if_out_valid && if_out_ready;

    assign miss_line_base = {pc_r[31:OFFSET_W], {OFFSET_W{1'b0}}};
    assign ifu_master_araddr = miss_line_base;
    assign ifu_master_arlen = LINE_WORDS[7:0] - 8'd1;
    assign ifu_master_arburst = 2'b01;
    assign ifu_master_arvalid = (state == S_MISS_AR);
    assign ifu_master_rready = (state == S_MISS_R) || (state == S_DROP_R);
    assign ar_fire = ifu_master_arvalid && ifu_master_arready;
    assign r_fire = ifu_master_rvalid && ifu_master_rready;

    always @(posedge clock) begin
        if (reset) begin
            valid_array <= {LINE_COUNT{1'b0}};
        end else if (invalidate) begin
            valid_array <= {LINE_COUNT{1'b0}};
        end else if ((state == S_MISS_R) && flush) begin
            valid_array[lookup_index] <= 1'b0;
        end else if ((state == S_MISS_R) && r_fire && ifu_master_rlast && !flush) begin
            valid_array[lookup_index] <= 1'b1;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            state <= S_LOOKUP;
            pc_r <= RESET_PC;
            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
        end else begin
            if (flush) begin
                pc_r <= ex_redirect_pc;
            end else if (req_fire) begin
                pc_r <= pc_r + 32'd4;
            end

            case (state)
                S_LOOKUP: begin
                    if (cache_miss && !flush) begin
                        refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                        state <= S_MISS_AR;
                    end
                end

                S_MISS_AR: begin
                    if (ar_fire) begin
                        state <= flush ? S_DROP_R : S_MISS_R;
                    end else if (flush) begin
                        state <= S_LOOKUP;
                    end
                end

                S_MISS_R: begin
                    if (r_fire && !flush) begin
                        data_array[lookup_index][{refill_word_idx, 5'b0} +: 32] <= ifu_master_rdata;
                    end

                    if (r_fire) begin
                        if (ifu_master_rlast) begin
                            if (!flush) begin
                                tag_array[lookup_index] <= lookup_tag;
                            end
                            state <= S_LOOKUP;
                        end else begin
                            refill_word_idx <= refill_word_idx + 1'b1;
                            if (flush) begin
                                state <= S_DROP_R;
                            end
                        end
                    end else if (flush) begin
                        state <= S_DROP_R;
                    end
                end

                S_DROP_R: begin
                    if (r_fire && ifu_master_rlast) begin
                        state <= S_LOOKUP;
                    end
                end

                default: begin
                    state <= S_LOOKUP;
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
        if (!reset && req_fire && (pc_r[1:0] != 2'b00)) begin
            $fatal(1, "unaligned ifu fetch pc=%08x", pc_r);
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
`endif

    wire _unused_ok;
    assign _unused_ok = &{1'b0, ifu_master_rresp};

endmodule
