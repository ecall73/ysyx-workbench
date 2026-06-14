module ysyx_26030082_icache #(
    parameter integer LINE_WORDS = 4,
    parameter integer LINE_COUNT = 8
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
    localparam integer TAG_W           = 32 - INDEX_W - OFFSET_W;

    localparam [1:0] S_LOOKUP  = 2'd0;
    localparam [1:0] S_MISS_AR = 2'd1;
    localparam [1:0] S_MISS_R  = 2'd2;

    reg [1:0] state;

    localparam integer DATA_ADDR_W = INDEX_W + LINE_WORD_OFF_W;
    localparam integer DATA_DEPTH = LINE_COUNT * LINE_WORDS;
    reg [31:0] data_array [0:DATA_DEPTH-1];
    reg [TAG_W-1:0] tag_array [0:LINE_COUNT-1];
    reg [LINE_COUNT-1:0] valid_array;

    reg [INDEX_W-1:0] miss_index;
    reg [TAG_W-1:0]   miss_tag;
    reg [LINE_WORD_OFF_W-1:0] refill_word_idx;
    reg         drop_fill;

    wire [LINE_WORD_OFF_W-1:0] lookup_word_offset;
    wire [INDEX_W-1:0]         lookup_index;
    wire [TAG_W-1:0]           lookup_tag;
    wire [DATA_ADDR_W-1:0]     lookup_data_addr;

    wire [DATA_ADDR_W-1:0]     refill_data_addr;

    wire               cache_hit;
    wire               cache_miss;
    wire               lookup_resp_valid;
    wire [TAG_W-1:0]   lookup_rd_tag;
    wire               lookup_rd_valid;
    wire               req_space;
    wire               req_fire;
    wire               ar_fire;
    wire               r_fire;
    wire               pipe_flush;
    wire [31:0] miss_line_base;

    assign lookup_word_offset =
        if_pc[WORD_OFF_W + LINE_WORD_OFF_W - 1 : WORD_OFF_W];
    assign lookup_index = if_pc[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    assign lookup_tag = if_pc[31 : OFFSET_W + INDEX_W];
    assign lookup_data_addr = {lookup_index, lookup_word_offset};

    assign refill_data_addr = {miss_index, refill_word_idx};

    assign lookup_rd_tag = tag_array[lookup_index];
    assign lookup_rd_valid = valid_array[lookup_index];
    assign cache_hit = lookup_rd_valid && (lookup_rd_tag == lookup_tag);
    assign cache_miss = (state == S_LOOKUP) && !pipe_flush && if_valid && !cache_hit;
    assign lookup_resp_valid = (state == S_LOOKUP) && !pipe_flush && if_valid && cache_hit;

    assign pipe_flush = flush || invalidate;
    assign id_valid = lookup_resp_valid;
    assign id_pc = if_pc;
    assign id_inst = data_array[lookup_data_addr];

    assign req_space = lookup_resp_valid && id_ready;
    assign if_ready = req_space;
    assign req_fire = if_valid && if_ready;

    assign miss_line_base = {miss_tag, miss_index, {OFFSET_W{1'b0}}};
    assign ifu_axi_araddr = miss_line_base;
    assign ifu_axi_arlen = LINE_WORDS[7:0] - 8'd1;
    assign ifu_axi_arburst = 2'b01;
    assign ifu_axi_arvalid = (state == S_MISS_AR);
    assign ifu_axi_rready = (state == S_MISS_R);
    assign ar_fire = ifu_axi_arvalid && ifu_axi_arready;
    assign r_fire = ifu_axi_rvalid && ifu_axi_rready;

    always @(posedge clock) begin
        if (reset) begin
            state <= S_LOOKUP;
            miss_index <= {INDEX_W{1'b0}};
            miss_tag <= {TAG_W{1'b0}};
            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
            drop_fill <= 1'b0;
            valid_array <= {LINE_COUNT{1'b0}};
        end else begin
            if (invalidate) begin
                valid_array <= {LINE_COUNT{1'b0}};
            end

            case (state)
                S_LOOKUP: begin
                    if (cache_miss) begin
                        miss_index <= lookup_index;
                        miss_tag <= lookup_tag;
                        refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                        drop_fill <= 1'b0;
                        state <= S_MISS_AR;
                    end
                end

                S_MISS_AR: begin
                    if (invalidate) begin
                        if (ar_fire) begin
                            drop_fill <= 1'b1;
                            state <= S_MISS_R;
                        end else begin
                            drop_fill <= 1'b0;
                            state <= S_LOOKUP;
                        end
                    end else if (ar_fire) begin
                        state <= S_MISS_R;
                    end
                end

                S_MISS_R: begin
                    if (invalidate) begin
                        drop_fill <= 1'b1;
                    end

                    if (r_fire) begin
                        data_array[refill_data_addr] <= ifu_axi_rdata;
                        if (ifu_axi_rlast) begin
                            if (!drop_fill && !invalidate) begin
                                tag_array[miss_index] <= miss_tag;
                                valid_array[miss_index] <= 1'b1;
                            end
                            drop_fill <= 1'b0;
                            state <= S_LOOKUP;
                        end else begin
                            refill_word_idx <= refill_word_idx + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= S_LOOKUP;
                    drop_fill <= 1'b0;
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
        if (OFFSET_W + INDEX_W >= 32) begin
            $fatal(1, "icache geometry is too large for ADDR_WIDTH");
        end
    end

    always @(posedge clock) begin
        if (!reset && req_fire && (if_pc[1:0] != 2'b00)) begin
            $fatal(1, "unaligned icache fetch pc=%08x", if_pc);
        end
        if (!reset && (state == S_MISS_R) && r_fire) begin
            if ((refill_word_idx == (LINE_WORDS - 1)) && !ifu_axi_rlast) begin
                $fatal(1, "icache burst refill missing rlast on final beat line=%08x", miss_line_base);
            end
            if ((refill_word_idx != (LINE_WORDS - 1)) && ifu_axi_rlast) begin
                $fatal(1, "icache burst refill saw early rlast line=%08x beat=%0d", miss_line_base, refill_word_idx);
            end
        end
    end
`endif

    wire _unused_ok;
    assign _unused_ok = &{1'b0, ifu_axi_rresp};

endmodule
