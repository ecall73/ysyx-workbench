`timescale 1ns / 1ps

module icache #(
    parameter integer LINE_WORDS = 1,
    parameter integer LINE_COUNT = 16,
    parameter integer ADDR_WIDTH = 32,
    parameter integer TARGET_NPC = 0
) (
    input  wire        clock,
    input  wire        reset,

    // IFU request/response interface
    input  wire        ic_req_valid,
    output wire        ic_req_ready,
    input  wire [31:0] ic_req_pc,
    output wire        ic_resp_valid,
    input  wire        ic_resp_ready,
    output wire [31:0] ic_resp_pc,
    output wire [31:0] ic_resp_inst,
    input  wire        ic_flush,
    input  wire        ic_invalidate,

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
    output wire        ifu_axi_rready,

    // AXI4-Lite write channels are unused by ICache
    output wire [31:0] ifu_axi_awaddr,
    output wire        ifu_axi_awvalid,
    input  wire        ifu_axi_awready,
    output wire [31:0] ifu_axi_wdata,
    output wire [ 3:0] ifu_axi_wstrb,
    output wire        ifu_axi_wvalid,
    input  wire        ifu_axi_wready,
    input  wire [ 1:0] ifu_axi_bresp,
    input  wire        ifu_axi_bvalid,
    output wire        ifu_axi_bready
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

    reg [31:0] data_array [0:LINE_COUNT-1][0:LINE_WORDS-1];
    reg [TAG_W-1:0] tag_array [0:LINE_COUNT-1];
    reg valid_array [0:LINE_COUNT-1];

    reg               lookup_valid;
    reg [31:0]        lookup_pc;
    reg [INDEX_W-1:0] lookup_index;
    reg [TAG_W-1:0]   lookup_tag;
    reg               lookup_cacheable;
    reg [LINE_WORD_OFF_W-1:0] lookup_word_offset;
    reg [31:0]        rd_line_data [0:LINE_WORDS-1];
    reg [TAG_W-1:0]   rd_tag;
    reg               rd_valid;

    reg               hold_valid;
    reg [31:0]        hold_pc;
    reg [31:0]        hold_inst;

    reg [31:0]        miss_pc;
    reg [INDEX_W-1:0] miss_index;
    reg [TAG_W-1:0]   miss_tag;
    reg [LINE_WORD_OFF_W-1:0] miss_word_offset;
    reg [LINE_WORD_OFF_W-1:0] refill_word_idx;
    reg               miss_bypass;
    reg               need_flush;
    reg               kill_miss_refill;

    wire [LINE_WORD_OFF_W-1:0] req_word_offset;
    wire [INDEX_W-1:0] req_index;
    wire [TAG_W-1:0]   req_tag;
    wire               req_cacheable;
    wire               cache_hit;
    wire               cache_miss;
    wire               cache_bypass;
    wire               lookup_resp_valid;
    wire               refill_is_last_word;
    wire               resp_from_hold;
    wire               resp_from_lookup;
    wire               req_space;
    wire               req_fire;
    wire               ar_fire;
    wire               r_fire;
    wire               discard_resp;
    wire               pipe_flush;
    wire               kill_refill_now;

    reg [31:0] lookup_inst;
    reg [31:0] refill_inst;

    wire [31:0] miss_line_base;
    localparam [31:0] LINE_WORD_MASK_FULL = LINE_WORDS - 1;
    integer i;
    integer j;
    integer k;

    function is_cacheable;
        input [31:0] addr;
        begin
            if (TARGET_NPC == 1) begin
                is_cacheable =
                    ((addr >= 32'h8000_0000) && (addr < 32'h8800_0000));
            end else begin
                is_cacheable =
                    ((addr >= 32'ha000_0000) && (addr < 32'ha200_0000));
            end
        end
    endfunction

    assign req_word_offset =
        ic_req_pc[WORD_OFF_W + LINE_WORD_OFF_W - 1 : WORD_OFF_W] &
        LINE_WORD_MASK_FULL[LINE_WORD_OFF_W - 1 : 0];
    assign req_index = ic_req_pc[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    assign req_tag = ic_req_pc[ADDR_WIDTH - 1 : OFFSET_W + INDEX_W];
    assign req_cacheable = is_cacheable(ic_req_pc);

    assign cache_hit = lookup_valid && lookup_cacheable && rd_valid && (rd_tag == lookup_tag);
    assign cache_miss = lookup_valid && lookup_cacheable && !cache_hit;
    assign cache_bypass = lookup_valid && !lookup_cacheable;
    assign lookup_resp_valid = (state == S_LOOKUP) && cache_hit;

    assign refill_is_last_word = (refill_word_idx == (LINE_WORDS - 1));
    assign pipe_flush = ic_flush || ic_invalidate;
    assign discard_resp = need_flush || pipe_flush;
    assign kill_refill_now = kill_miss_refill || ic_invalidate;
    assign resp_from_hold = hold_valid;
    assign resp_from_lookup = !hold_valid && lookup_resp_valid;
    assign ic_resp_valid = resp_from_hold || resp_from_lookup;
    assign ic_resp_pc = resp_from_hold ? hold_pc :
                        lookup_pc;
    assign ic_resp_inst = resp_from_hold ? hold_inst :
                          lookup_inst;

    assign req_space =
        (state == S_LOOKUP) &&
        !pipe_flush &&
        (hold_valid ? ic_resp_ready :
         lookup_valid ? (cache_hit && ic_resp_ready) :
         1'b1);
    assign ic_req_ready = req_space;
    assign req_fire = ic_req_valid && ic_req_ready;

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

    assign ifu_axi_awaddr = 32'b0;
    assign ifu_axi_awvalid = 1'b0;
    assign ifu_axi_wdata = 32'b0;
    assign ifu_axi_wstrb = 4'b0000;
    assign ifu_axi_wvalid = 1'b0;
    assign ifu_axi_bready = 1'b0;

    always @(*) begin
        lookup_inst = 32'b0;
        for (i = 0; i < LINE_WORDS; i = i + 1) begin
            if (lookup_word_offset == i) begin
                lookup_inst = rd_line_data[i];
            end
        end
    end

    always @(*) begin
        refill_inst = ifu_axi_rdata;
        for (j = 0; j < LINE_WORDS; j = j + 1) begin
            if (miss_word_offset == j) begin
                if (refill_word_idx == j) begin
                    refill_inst = ifu_axi_rdata;
                end else begin
                    refill_inst = data_array[miss_index][j];
                end
            end
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            state <= S_LOOKUP;
            lookup_valid <= 1'b0;
            lookup_pc <= 32'b0;
            lookup_index <= {INDEX_W{1'b0}};
            lookup_tag <= {TAG_W{1'b0}};
            lookup_cacheable <= 1'b0;
            lookup_word_offset <= {LINE_WORD_OFF_W{1'b0}};
            rd_tag <= {TAG_W{1'b0}};
            rd_valid <= 1'b0;
            hold_valid <= 1'b0;
            hold_pc <= 32'b0;
            hold_inst <= 32'b0;
            miss_pc <= 32'b0;
            miss_index <= {INDEX_W{1'b0}};
            miss_tag <= {TAG_W{1'b0}};
            miss_word_offset <= {LINE_WORD_OFF_W{1'b0}};
            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
            miss_bypass <= 1'b0;
            need_flush <= 1'b0;
            kill_miss_refill <= 1'b0;
            for (i = 0; i < LINE_COUNT; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i] <= {TAG_W{1'b0}};
                for (j = 0; j < LINE_WORDS; j = j + 1) begin
                    data_array[i][j] <= 32'b0;
                end
            end
            for (k = 0; k < LINE_WORDS; k = k + 1) begin
                rd_line_data[k] <= 32'b0;
            end
        end else begin
            if (ic_invalidate) begin
                lookup_valid <= 1'b0;
                hold_valid <= 1'b0;
                rd_valid <= 1'b0;
                for (i = 0; i < LINE_COUNT; i = i + 1) begin
                    valid_array[i] <= 1'b0;
                end
            end

            case (state)
                S_LOOKUP: begin
                    if (ic_flush) begin
                        lookup_valid <= 1'b0;
                        hold_valid <= 1'b0;
                    end else if (!pipe_flush) begin
                        if (hold_valid && ic_resp_ready) begin
                            hold_valid <= 1'b0;
                        end

                        if (!hold_valid && cache_hit) begin
                            if (ic_resp_ready) begin
                                lookup_valid <= 1'b0;
                            end else begin
                                hold_valid <= 1'b1;
                                hold_pc <= lookup_pc;
                                hold_inst <= lookup_inst;
                                lookup_valid <= 1'b0;
                            end
                        end else if (!hold_valid && cache_miss) begin
                            miss_pc <= lookup_pc;
                            miss_index <= lookup_index;
                            miss_tag <= lookup_tag;
                            miss_word_offset <= lookup_word_offset;
                            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                            miss_bypass <= 1'b0;
                            lookup_valid <= 1'b0;
                            state <= S_MISS_AR;
                        end else if (!hold_valid && cache_bypass) begin
                            miss_pc <= lookup_pc;
                            miss_index <= lookup_index;
                            miss_tag <= lookup_tag;
                            miss_word_offset <= lookup_word_offset;
                            refill_word_idx <= {LINE_WORD_OFF_W{1'b0}};
                            miss_bypass <= 1'b1;
                            lookup_valid <= 1'b0;
                            state <= S_MISS_AR;
                        end

                        if (req_fire) begin
                            lookup_valid <= 1'b1;
                            lookup_pc <= ic_req_pc;
                            lookup_index <= req_index;
                            lookup_tag <= req_tag;
                            lookup_cacheable <= req_cacheable;
                            lookup_word_offset <= req_word_offset;
                            rd_tag <= tag_array[req_index];
                            rd_valid <= valid_array[req_index];
                            for (i = 0; i < LINE_WORDS; i = i + 1) begin
                                rd_line_data[i] <= data_array[req_index][i];
                            end
                        end
                    end
                end

                S_MISS_AR: begin
                    if (ic_invalidate) begin
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
                        if (ic_flush) begin
                            lookup_valid <= 1'b0;
                            hold_valid <= 1'b0;
                            need_flush <= 1'b1;
                        end

                        if (ar_fire) begin
                            state <= S_MISS_R;
                        end
                    end
                end

                S_MISS_R: begin
                    if (ic_invalidate) begin
                        need_flush <= 1'b1;
                        kill_miss_refill <= !miss_bypass;
                    end else if (ic_flush) begin
                        lookup_valid <= 1'b0;
                        hold_valid <= 1'b0;
                        need_flush <= 1'b1;
                    end

                    if (r_fire) begin
                        if (!miss_bypass && !kill_refill_now) begin
                            data_array[miss_index][refill_word_idx] <= ifu_axi_rdata;
                        end

                        if (miss_bypass) begin
                            if (discard_resp) begin
                                need_flush <= 1'b0;
                            end else begin
                                hold_valid <= 1'b1;
                                hold_pc <= miss_pc;
                                hold_inst <= ifu_axi_rdata;
                            end
                            kill_miss_refill <= 1'b0;
                            state <= S_LOOKUP;
                        end else begin
                            if (refill_is_last_word) begin
                                if (!kill_refill_now) begin
                                    tag_array[miss_index] <= miss_tag;
                                    valid_array[miss_index] <= 1'b1;
                                end
                                if (discard_resp || kill_refill_now) begin
                                    need_flush <= 1'b0;
                                end else begin
                                    hold_valid <= 1'b1;
                                    hold_pc <= miss_pc;
                                    hold_inst <= refill_inst;
                                end
                                kill_miss_refill <= 1'b0;
                                state <= S_LOOKUP;
                            end else begin
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
        if (!reset && req_fire && (ic_req_pc[1:0] != 2'b00)) begin
            $fatal(1, "unaligned icache fetch pc=%08x", ic_req_pc);
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
    assign _unused_ok = &{1'b0, ifu_axi_rresp, ifu_axi_awready, ifu_axi_wready, ifu_axi_bresp, ifu_axi_bvalid};

endmodule
