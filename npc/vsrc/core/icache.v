module ysyx_26030082_icache #(
    parameter integer LINE_WORDS = 4,
    parameter integer LINE_COUNT = 4,
    parameter integer ADDR_WIDTH = 32,
    parameter integer TARGET_NPC = 0
) (
    input  wire        clock,
    input  wire        reset,

    // IFU request/response interface
    input  wire        if_valid,
    output wire        if_ready,
    input  wire [31:0] if_pc,
    output wire        id_valid,
    input  wire        id_ready,
    output wire [31:0] id_pc,
    output wire [31:0] id_inst,
    input  wire        flush,
    input  wire        invalidate,

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

    localparam [1:0] S_LOOKUP  = 2'd0;
    localparam [1:0] S_MISS_AR = 2'd1;
    localparam [1:0] S_MISS_R  = 2'd2;

    reg [1:0] state;

    localparam integer DATA_ADDR_W = INDEX_W + LINE_WORD_OFF_W;
    localparam integer DATA_DEPTH = LINE_COUNT * LINE_WORDS;
    localparam USE_TARGET_NPC = (TARGET_NPC != 0);

    reg [31:0] data_array [0:DATA_DEPTH-1];
    reg [TAG_W-1:0] tag_array [0:LINE_COUNT-1];
    reg [LINE_COUNT-1:0] valid_array;

    reg         lookup_valid;
    reg [31:0]  lookup_pc;

    reg         hold_valid;
    reg [31:0]  hold_inst;

    reg [31:0]  miss_pc;
    reg [LINE_WORD_OFF_W-1:0] refill_word_idx;
    wire        miss_bypass;
    reg         need_flush;
    reg         kill_miss_refill;

    wire [LINE_WORD_OFF_W-1:0] lookup_word_offset;
    wire [INDEX_W-1:0]         lookup_index;
    wire [TAG_W-1:0]           lookup_tag;
    wire                       lookup_cacheable;
    wire [DATA_ADDR_W-1:0]     lookup_data_addr;

    wire [LINE_WORD_OFF_W-1:0] miss_word_offset;
    wire [INDEX_W-1:0]         miss_index;
    wire [TAG_W-1:0]           miss_tag;
    wire [DATA_ADDR_W-1:0]     refill_data_addr;

    wire               cache_hit;
    wire               cache_miss;
    wire               cache_bypass;
    wire               lookup_resp_valid;
    wire [TAG_W-1:0]   lookup_rd_tag;
    wire               lookup_rd_valid;
    wire               refill_is_last_word;
    wire               refill_is_target_word;
    wire               resp_from_hold;
    wire               resp_from_lookup;
    wire               req_space;
    wire               req_fire;
    wire               ar_fire;
    wire               r_fire;
    wire               discard_resp;
    wire               pipe_flush;
    wire               kill_refill_now;

    wire [31:0] miss_line_base;

    assign lookup_word_offset =
        lookup_pc[WORD_OFF_W + LINE_WORD_OFF_W - 1 : WORD_OFF_W];
    assign lookup_index = lookup_pc[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    assign lookup_tag = lookup_pc[ADDR_WIDTH - 1 : OFFSET_W + INDEX_W];
    assign lookup_cacheable = USE_TARGET_NPC ?
        (lookup_pc[31:27] == 5'b10000) :
        (lookup_pc[31:25] == 7'b1010000);
    assign lookup_data_addr = {lookup_index, lookup_word_offset};

    assign miss_word_offset =
        miss_pc[WORD_OFF_W + LINE_WORD_OFF_W - 1 : WORD_OFF_W];
    assign miss_index = miss_pc[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    assign miss_tag = miss_pc[ADDR_WIDTH - 1 : OFFSET_W + INDEX_W];
    assign miss_bypass = !(USE_TARGET_NPC ?
        (miss_pc[31:27] == 5'b10000) :
        (miss_pc[31:25] == 7'b1010000));
    assign refill_data_addr = {miss_index, refill_word_idx};

    assign lookup_rd_tag = tag_array[lookup_index];
    assign lookup_rd_valid = valid_array[lookup_index];
    assign cache_hit = lookup_valid && lookup_cacheable && lookup_rd_valid && (lookup_rd_tag == lookup_tag);
    assign cache_miss = lookup_valid && lookup_cacheable && !cache_hit;
    assign cache_bypass = lookup_valid && !lookup_cacheable;
    assign lookup_resp_valid = (state == S_LOOKUP) && cache_hit;

    assign refill_is_last_word = (refill_word_idx == (LINE_WORDS - 1));
    assign refill_is_target_word = (refill_word_idx == miss_word_offset);
    assign pipe_flush = flush || invalidate;
    assign discard_resp = need_flush || pipe_flush;
    assign kill_refill_now = kill_miss_refill || invalidate;
    assign resp_from_hold = hold_valid;
    assign resp_from_lookup = !hold_valid && lookup_resp_valid;
    assign id_valid = resp_from_hold || resp_from_lookup;
    assign id_pc = resp_from_hold ? miss_pc : lookup_pc;
    assign id_inst = resp_from_hold ? hold_inst : data_array[lookup_data_addr];

    assign req_space =
        (state == S_LOOKUP) &&
        !pipe_flush &&
        !hold_valid &&
        (!lookup_valid || (cache_hit && id_ready));
    assign if_ready = req_space;
    assign req_fire = if_valid && if_ready;

    assign miss_line_base = {miss_pc[ADDR_WIDTH - 1 : OFFSET_W], {OFFSET_W{1'b0}}};
    assign ifu_axi_araddr = miss_bypass ?
        {miss_pc[ADDR_WIDTH - 1 : WORD_OFF_W], {WORD_OFF_W{1'b0}}} :
        miss_line_base;
    assign ifu_axi_arlen = miss_bypass ? 8'h00 : (LINE_WORDS[7:0] - 8'd1);
    assign ifu_axi_arburst = miss_bypass ? 2'b00 : 2'b01;
    assign ifu_axi_arvalid = (state == S_MISS_AR);
    assign ifu_axi_rready = (state == S_MISS_R);
    assign ar_fire = ifu_axi_arvalid && ifu_axi_arready;
    assign r_fire = ifu_axi_rvalid && ifu_axi_rready;

    always @(posedge clock) begin
        if (reset) begin
            state <= S_LOOKUP;
            lookup_valid <= 1'b0;
            lookup_pc <= 32'b0;
            hold_valid <= 1'b0;
            hold_inst <= 32'b0;
            miss_pc <= 32'b0;
            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
            need_flush <= 1'b0;
            kill_miss_refill <= 1'b0;
            valid_array <= {LINE_COUNT{1'b0}};
        end else begin
            if (invalidate) begin
                lookup_valid <= 1'b0;
                hold_valid <= 1'b0;
                valid_array <= {LINE_COUNT{1'b0}};
            end

            case (state)
                S_LOOKUP: begin
                    if (flush) begin
                        lookup_valid <= 1'b0;
                        hold_valid <= 1'b0;
                    end else if (!pipe_flush) begin
                        if (hold_valid && id_ready) begin
                            hold_valid <= 1'b0;
                        end

                        if (!hold_valid) begin
                            if (lookup_valid && cache_hit && id_ready) begin
                                lookup_valid <= 1'b0;
                            end else if (lookup_valid && cache_miss) begin
                                miss_pc <= lookup_pc;
                                refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                                need_flush <= 1'b0;
                                kill_miss_refill <= 1'b0;
                                lookup_valid <= 1'b0;
                                state <= S_MISS_AR;
                            end else if (lookup_valid && cache_bypass) begin
                                miss_pc <= lookup_pc;
                                refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                                need_flush <= 1'b0;
                                kill_miss_refill <= 1'b0;
                                lookup_valid <= 1'b0;
                                state <= S_MISS_AR;
                            end
                        end

                        if (req_fire) begin
                            lookup_valid <= 1'b1;
                            lookup_pc <= if_pc;
                        end
                    end
                end

                S_MISS_AR: begin
                    if (invalidate) begin
                        if (ar_fire) begin
                            need_flush <= 1'b1;
                            kill_miss_refill <= !miss_bypass;
                            state <= S_MISS_R;
                        end else begin
                            need_flush <= 1'b0;
                            kill_miss_refill <= 1'b0;
                            state <= S_LOOKUP;
                        end
                    end else begin
                        if (flush) begin
                            need_flush <= 1'b1;
                        end

                        if (ar_fire) begin
                            state <= S_MISS_R;
                        end
                    end
                end

                S_MISS_R: begin
                    if (invalidate) begin
                        need_flush <= 1'b1;
                        kill_miss_refill <= !miss_bypass;
                    end else if (flush) begin
                        need_flush <= 1'b1;
                    end

                    if (r_fire) begin
                        if (refill_is_target_word) begin
                            hold_inst <= ifu_axi_rdata;
                        end

                        if (miss_bypass) begin
                            if (discard_resp) begin
                                need_flush <= 1'b0;
                            end else begin
                                hold_valid <= 1'b1;
                                hold_inst <= ifu_axi_rdata;
                            end
                            kill_miss_refill <= 1'b0;
                            state <= S_LOOKUP;
                        end else begin
                            if (refill_is_last_word) begin
                                if (!kill_refill_now) begin
                                    data_array[refill_data_addr] <= ifu_axi_rdata;
                                    tag_array[miss_index] <= miss_tag;
                                    valid_array[miss_index] <= 1'b1;
                                end
                                if (discard_resp || kill_refill_now) begin
                                    need_flush <= 1'b0;
                                end else begin
                                    hold_valid <= 1'b1;
                                    if (refill_is_target_word) begin
                                        hold_inst <= ifu_axi_rdata;
                                    end
                                end
                                kill_miss_refill <= 1'b0;
                                state <= S_LOOKUP;
                            end else begin
                                if (!kill_refill_now) begin
                                    data_array[refill_data_addr] <= ifu_axi_rdata;
                                end
                                refill_word_idx <= refill_word_idx + 1'b1;
                            end
                        end
                    end
                end

                default: begin
                    state <= S_LOOKUP;
                    lookup_valid <= 1'b0;
                    hold_valid <= 1'b0;
                    need_flush <= 1'b0;
                    kill_miss_refill <= 1'b0;
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
        if (!reset && req_fire && (if_pc[1:0] != 2'b00)) begin
            $fatal(1, "unaligned icache fetch pc=%08x", if_pc);
        end
        if (!reset && (state == S_MISS_R) && !miss_bypass && r_fire) begin
            if (refill_is_last_word && !ifu_axi_rlast) begin
                $fatal(1, "icache burst refill missing rlast on final beat pc=%08x", miss_pc);
            end
            if (!refill_is_last_word && ifu_axi_rlast) begin
                $fatal(1, "icache burst refill saw early rlast pc=%08x beat=%0d", miss_pc, refill_word_idx);
            end
        end
    end
`endif

    wire _unused_ok;
    assign _unused_ok = &{1'b0, ifu_axi_rresp};

endmodule
