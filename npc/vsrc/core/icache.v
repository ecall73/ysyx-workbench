module ysyx_26030082_icache #(
    parameter integer LINE_WORDS = 4,
    parameter integer LINE_COUNT = 4,
    parameter integer ADDR_WIDTH = 32,
    parameter integer TARGET_NPC = 0
) (
    input  wire        clock,
    input  wire        reset,

    input  wire [31:0] if_pc,
    input  wire        invalidate,
    output wire        if_hit,
    output wire [31:0] if_inst,

    // AXI4 read master interface
    output wire [31:0] ifu_axi_araddr,
    output wire [ 7:0] ifu_axi_arlen,
    output wire [ 1:0] ifu_axi_arburst,
    output wire        ifu_axi_arvalid,
    input  wire        ifu_axi_arready,
    input  wire [31:0] ifu_axi_rdata,
    input  wire [ 1:0] ifu_axi_rresp,
    input  wire        ifu_axi_rlast,
    input  wire        ifu_axi_rvalid,
    output wire        ifu_axi_rready
);
    localparam integer WORD_OFF_W      = 2;
    localparam integer LINE_ADDR_OFF_W = $clog2(LINE_WORDS);
    localparam integer LINE_WORD_OFF_W = $clog2((LINE_WORDS < 2) ? 2 : LINE_WORDS);
    localparam integer INDEX_W         = $clog2(LINE_COUNT);
    localparam integer OFFSET_W        = WORD_OFF_W + LINE_ADDR_OFF_W;
    localparam integer TAG_W           = ADDR_WIDTH - INDEX_W - OFFSET_W;

    localparam [1:0] S_LOOKUP = 2'd0;
    localparam [1:0] S_MISS_AR = 2'd1;
    localparam [1:0] S_MISS_R = 2'd2;

    localparam integer DATA_ADDR_W = INDEX_W + LINE_WORD_OFF_W;
    localparam integer DATA_DEPTH = LINE_COUNT * LINE_WORDS;

    reg [1:0] state;
    reg [LINE_WORD_OFF_W-1:0] refill_word_idx;
    reg invalidate_pending;

    reg [31:0] data_array [0:DATA_DEPTH-1];
    reg [TAG_W-1:0] tag_array [0:LINE_COUNT-1];
    reg [LINE_COUNT-1:0] valid_array;

    wire [LINE_WORD_OFF_W-1:0] lookup_word_offset;
    wire [INDEX_W-1:0]         lookup_index;
    wire [TAG_W-1:0]           lookup_tag;
    wire [DATA_ADDR_W-1:0]     lookup_data_addr;
    wire [DATA_ADDR_W-1:0]     refill_data_addr;
    wire [31:0]                miss_line_base;
    wire                       refill_is_last_word;
    wire                       r_fire;

    // Keep these names for top-level PMU hierarchical reads.
    wire cache_hit;
    wire cache_miss;
    wire lookup_resp_valid;
    wire need_flush;

    assign lookup_word_offset = if_pc[WORD_OFF_W + LINE_WORD_OFF_W - 1 : WORD_OFF_W];
    assign lookup_index = if_pc[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    assign lookup_tag = if_pc[ADDR_WIDTH - 1 : OFFSET_W + INDEX_W];
    assign lookup_data_addr = {lookup_index, lookup_word_offset};
    assign refill_data_addr = {lookup_index, refill_word_idx};

    assign cache_hit = valid_array[lookup_index] && (tag_array[lookup_index] == lookup_tag);
    assign cache_miss = (state == S_LOOKUP) && !cache_hit;
    assign lookup_resp_valid = (state == S_LOOKUP) && cache_hit;
    assign need_flush = 1'b0;

    assign if_hit = lookup_resp_valid;
    assign if_inst = data_array[lookup_data_addr];

    assign miss_line_base = {if_pc[ADDR_WIDTH - 1 : OFFSET_W], {OFFSET_W{1'b0}}};
    assign ifu_axi_araddr = miss_line_base;
    assign ifu_axi_arlen = LINE_WORDS[7:0] - 8'd1;
    assign ifu_axi_arburst = 2'b01;
    assign ifu_axi_arvalid = (state == S_MISS_AR);
    assign ifu_axi_rready = (state == S_MISS_R);

    assign refill_is_last_word = (refill_word_idx == (LINE_WORDS - 1));
    assign r_fire = ifu_axi_rvalid && ifu_axi_rready;

    always @(posedge clock) begin
        if (reset) begin
            state <= S_LOOKUP;
            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
            invalidate_pending <= 1'b0;
            valid_array <= {LINE_COUNT{1'b0}};
        end else begin
            if (invalidate) begin
                valid_array <= {LINE_COUNT{1'b0}};
            end

            case (state)
                S_LOOKUP: begin
                    refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                    invalidate_pending <= 1'b0;
                    if (cache_miss) begin
                        state <= S_MISS_AR;
                    end
                end

                S_MISS_AR: begin
                    if (invalidate) begin
                        invalidate_pending <= 1'b1;
                    end
                    if (ifu_axi_arready) begin
                        state <= S_MISS_R;
                    end
                end

                S_MISS_R: begin
                    if (invalidate) begin
                        invalidate_pending <= 1'b1;
                    end

                    if (r_fire) begin
                        data_array[refill_data_addr] <= ifu_axi_rdata;
                        if (refill_is_last_word) begin
                            tag_array[lookup_index] <= lookup_tag;
                            if (!invalidate_pending && !invalidate) begin
                                valid_array[lookup_index] <= 1'b1;
                            end
                            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                            invalidate_pending <= 1'b0;
                            state <= S_LOOKUP;
                        end else begin
                            refill_word_idx <= refill_word_idx + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= S_LOOKUP;
                    refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                    invalidate_pending <= 1'b0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (LINE_WORDS < 1) begin
            $fatal(1, "icache LINE_WORDS must be at least 1");
        end
        if ((LINE_WORDS & (LINE_WORDS - 1)) != 0) begin
            $fatal(1, "icache LINE_WORDS must be a power of two");
        end
        if (LINE_COUNT < 2) begin
            $fatal(1, "icache LINE_COUNT must be at least 2");
        end
        if ((LINE_COUNT & (LINE_COUNT - 1)) != 0) begin
            $fatal(1, "icache LINE_COUNT must be a power of two");
        end
        if (LINE_WORDS > 256) begin
            $fatal(1, "icache LINE_WORDS must be <= 256");
        end
        if (ADDR_WIDTH != 32) begin
            $fatal(1, "icache first version only supports ADDR_WIDTH=32");
        end
        if (ADDR_WIDTH <= (OFFSET_W + INDEX_W)) begin
            $fatal(1, "icache geometry is too large for ADDR_WIDTH");
        end
        if ((TARGET_NPC != 0) && (TARGET_NPC != 1)) begin
            $fatal(1, "icache TARGET_NPC must be 0 or 1");
        end
    end

    always @(posedge clock) begin
        if (!reset && (if_pc[1:0] != 2'b00)) begin
            $fatal(1, "unaligned icache fetch pc=%08x", if_pc);
        end
        if (!reset && (state == S_MISS_R) && r_fire) begin
            if (refill_is_last_word && !ifu_axi_rlast) begin
                $fatal(1, "icache burst refill missing rlast on final beat pc=%08x", if_pc);
            end
            if (!refill_is_last_word && ifu_axi_rlast) begin
                $fatal(1, "icache burst refill saw early rlast pc=%08x beat=%0d", if_pc, refill_word_idx);
            end
        end
    end
`endif

    wire _unused_ok;
    assign _unused_ok = &{1'b0, ifu_axi_rresp};

endmodule
