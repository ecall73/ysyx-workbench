module ysyx_26030082 #(
    parameter [31:0] RESET_PC = 32'h3000_0000
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        io_interrupt,
    // AXI4 master interface
    input  wire        io_master_awready,
    output wire        io_master_awvalid,
    output wire [ 3:0] io_master_awid,
    output wire [31:0] io_master_awaddr,
    output wire [ 7:0] io_master_awlen,
    output wire [ 2:0] io_master_awsize,
    output wire [ 1:0] io_master_awburst,
    input  wire        io_master_wready,
    output wire        io_master_wvalid,
    output wire [31:0] io_master_wdata,
    output wire [ 3:0] io_master_wstrb,
    output wire        io_master_wlast,
    output wire        io_master_bready,
    input  wire        io_master_bvalid,
    input  wire [ 3:0] io_master_bid,
    input  wire [ 1:0] io_master_bresp,
    input  wire        io_master_arready,
    output wire        io_master_arvalid,
    output wire [ 3:0] io_master_arid,
    output wire [31:0] io_master_araddr,
    output wire [ 7:0] io_master_arlen,
    output wire [ 2:0] io_master_arsize,
    output wire [ 1:0] io_master_arburst,
    output wire        io_master_rready,
    input  wire        io_master_rvalid,
    input  wire [ 3:0] io_master_rid,
    input  wire [31:0] io_master_rdata,
    input  wire [ 1:0] io_master_rresp,
    input  wire        io_master_rlast,
    // AXI4 slave interface (unused)
    output wire        io_slave_awready,
    input  wire        io_slave_awvalid,
    input  wire [ 3:0] io_slave_awid,
    input  wire [31:0] io_slave_awaddr,
    input  wire [ 7:0] io_slave_awlen,
    input  wire [ 2:0] io_slave_awsize,
    input  wire [ 1:0] io_slave_awburst,
    output wire        io_slave_wready,
    input  wire        io_slave_wvalid,
    input  wire [31:0] io_slave_wdata,
    input  wire [ 3:0] io_slave_wstrb,
    input  wire        io_slave_wlast,
    input  wire        io_slave_bready,
    output wire        io_slave_bvalid,
    output wire [ 3:0] io_slave_bid,
    output wire [ 1:0] io_slave_bresp,
    output wire        io_slave_arready,
    input  wire        io_slave_arvalid,
    input  wire [ 3:0] io_slave_arid,
    input  wire [31:0] io_slave_araddr,
    input  wire [ 7:0] io_slave_arlen,
    input  wire [ 2:0] io_slave_arsize,
    input  wire [ 1:0] io_slave_arburst,
    input  wire        io_slave_rready,
    output wire        io_slave_rvalid,
    output wire [ 3:0] io_slave_rid,
    output wire [31:0] io_slave_rdata,
    output wire [ 1:0] io_slave_rresp,
    output wire        io_slave_rlast
);

    assign io_slave_awready = 1'b0;
    assign io_slave_wready = 1'b0;
    assign io_slave_bvalid = 1'b0;
    assign io_slave_bid = 4'b0;
    assign io_slave_bresp = 2'b00;
    assign io_slave_arready = 1'b0;
    assign io_slave_rvalid = 1'b0;
    assign io_slave_rid = 4'b0;
    assign io_slave_rdata = 32'b0;
    assign io_slave_rresp = 2'b00;
    assign io_slave_rlast = 1'b0;

`ifndef SYNTHESIS
    always @(posedge clock) begin
        if (!reset) begin
            if (io_master_wvalid && io_master_wready && (io_master_wlast != 1'b1)) begin
                $fatal(1, "ysyx_26030082: WLAST must be 1 for single-beat write");
            end
            if (io_master_rvalid && io_master_rready && (io_master_rresp !== 2'b00)) begin
                $fatal(1,
                    "ysyx_26030082: AXI read access fault: resp=%0b rid=%0d",
                    io_master_rresp, io_master_rid);
            end
            if (io_master_bvalid && io_master_bready && (io_master_bresp !== 2'b00)) begin
                $fatal(1,
                    "ysyx_26030082: AXI write access fault: resp=%0b bid=%0d",
                    io_master_bresp, io_master_bid);
            end
        end
    end
`endif
`ifndef SYNTHESIS
`ifndef __ICARUS__
    import "DPI-C" function void npc_commit(input int pc, input int inst);
    import "DPI-C" function void npc_pmu_event(input int event_mask);
    export "DPI-C" function npc_get_gpr;
    function int npc_get_gpr(input int idx);
        begin
            if (idx == 0) begin
                npc_get_gpr = 0;
            end else if (idx > 0 && idx < 16) begin
                npc_get_gpr = exu.reg_bank[idx];
            end else begin
                npc_get_gpr = 0;
            end
        end
    endfunction
`endif
`endif

    // FETCH -> EX
    wire        fetch_valid;
    wire        fetch_ready;
    wire [31:0] fetch_pc;
    wire [31:0] fetch_inst;

    // EX
    wire        ex_rf_wen;
    wire        ex_mem_ren;
    wire        ex_mem_wen;
    wire [ 2:0] ex_funct3;
    wire [ 4:0] ex_rf_waddr;
    wire [31:0] ex_mem_addr;
    wire        ex_redirect;
    wire [31:0] ex_wdata;
    wire        ex_fence_i;
    wire        ex_out_valid;
    wire        ex_out_ready;

    // LS
    reg         ls_in_valid;
    reg         ls_rf_wen;
    reg         ls_mem_ren;
    reg         ls_mem_wen;
    reg  [ 2:0] ls_funct3;
    reg  [ 4:0] ls_rf_waddr;
    reg  [31:0] ls_mem_addr;
    reg  [31:0] ls_wdata;
    wire        ls_in_ready;
    wire        ls_out_valid;
    wire        rf_wen;
    wire [ 4:0] rf_waddr;
    wire [31:0] rf_wdata;
    wire [31:0] ls_mem_rdata;

`ifndef SYNTHESIS
    assign pc_ex = fetch_pc;
    assign inst_ex = fetch_inst;
`endif

    // IFU AXI4 (read-only in practice)
    wire [31:0] ifu_axi_araddr;
    wire [ 7:0] ifu_axi_arlen;
    wire [ 1:0] ifu_axi_arburst;
    wire        ifu_axi_arvalid;
    wire        ifu_axi_arready;
    wire [31:0] ifu_axi_rdata;
    wire [ 1:0] ifu_axi_rresp;
    wire        ifu_axi_rlast;
    wire        ifu_axi_rvalid;
    wire        ifu_axi_rready;

    // LSU AXI4-Lite (internal master)
    wire [31:0] lsu_axi_araddr;
    wire [ 2:0] lsu_axi_arsize;
    wire        lsu_axi_arvalid;
    wire        lsu_axi_arready;
    wire [31:0] lsu_axi_rdata;
    wire [ 1:0] lsu_axi_rresp;
    wire        lsu_axi_rvalid;
    wire        lsu_axi_rready;
    wire [31:0] lsu_axi_awaddr;
    wire [ 2:0] lsu_axi_awsize;
    wire        lsu_axi_awvalid;
    wire        lsu_axi_awready;
    wire [31:0] lsu_axi_wdata;
    wire [ 3:0] lsu_axi_wstrb;
    wire        lsu_axi_wvalid;
    wire        lsu_axi_wready;
    wire [ 1:0] lsu_axi_bresp;
    wire        lsu_axi_bvalid;
    wire        lsu_axi_bready;
    reg  [63:0] mtime;

    // Debug Interface
    `ifndef SYNTHESIS
        wire [31:0] pc_ex;
        reg  [31:0] pc_ls;
        wire [31:0] inst_ex;
        reg  [31:0] inst_ls;
    `endif

////////////////////////////////////////////////////////////////

    always @(posedge clock) begin
        if (reset) begin
            mtime <= 64'b0;
        end else begin
            mtime <= mtime + 64'd1;
        end
    end
    ysyx_26030082_ifu #(
        .RESET_PC               (RESET_PC),
        .LINE_WORDS             (4),
        .LINE_COUNT             (4)
    ) ifu (
        .clock                  (clock),
        .reset                  (reset),

        .ex_out_valid           (ex_out_valid),
        .ex_out_ready           (ex_out_ready),
        .ex_redirect            (ex_redirect),
        .ex_mem_addr            (ex_mem_addr),
        .ex_fence_i             (ex_fence_i),

        .fetch_valid            (fetch_valid),
        .fetch_ready            (fetch_ready),
        .fetch_pc               (fetch_pc),
        .fetch_inst             (fetch_inst),

        .ifu_axi_araddr         (ifu_axi_araddr),
        .ifu_axi_arlen          (ifu_axi_arlen),
        .ifu_axi_arburst        (ifu_axi_arburst),
        .ifu_axi_arvalid        (ifu_axi_arvalid),
        .ifu_axi_arready        (ifu_axi_arready),
        .ifu_axi_rdata          (ifu_axi_rdata),
        .ifu_axi_rresp          (ifu_axi_rresp),
        .ifu_axi_rlast          (ifu_axi_rlast),
        .ifu_axi_rvalid         (ifu_axi_rvalid),
        .ifu_axi_rready         (ifu_axi_rready)
    );

    assign rf_wen = ls_out_valid && ls_rf_wen;
    assign rf_waddr = ls_rf_waddr;
    assign rf_wdata = ls_mem_ren ? ls_mem_rdata : ls_wdata;

    // EX -> LS handshake coupling
    assign ex_out_ready = ls_in_ready;

    ysyx_26030082_exu exu (
        .clock                  (clock),
        .reset                  (reset),
        .fetch_valid            (fetch_valid),
        .fetch_ready            (fetch_ready),
        .fetch_pc               (fetch_pc),
        .fetch_inst             (fetch_inst),

        .ex_out_valid           (ex_out_valid),
        .ex_out_ready           (ex_out_ready),

        .rf_wen                 (rf_wen),
        .rf_waddr               (rf_waddr),
        .rf_wdata               (rf_wdata),
        .ls_load_pending        (ls_in_valid && ls_mem_ren && ~ls_out_valid),

        .ex_rf_wen              (ex_rf_wen),
        .ex_mem_ren             (ex_mem_ren),
        .ex_mem_wen             (ex_mem_wen),
        .ex_funct3              (ex_funct3),
        .ex_rf_waddr            (ex_rf_waddr),
        .ex_mem_addr            (ex_mem_addr),
        .ex_redirect            (ex_redirect),
        .ex_wdata               (ex_wdata),
        .ex_fence_i             (ex_fence_i)
    );

    // ================================================================
    // EX -> LS
    // ================================================================
    always @(posedge clock) begin
        if (reset) begin
            ls_in_valid <= 1'b0;
        end else if (ex_out_ready) begin
            ls_in_valid <= ex_out_valid;
            ls_rf_wen <= ex_rf_wen;
            ls_mem_wen <= ex_mem_wen;
            if (ex_out_valid && (ex_mem_ren || ex_mem_wen)) begin
                ls_mem_addr <= ex_mem_addr;
            end
            ls_funct3 <= ex_funct3;
            ls_rf_waddr <= ex_rf_waddr;
            ls_wdata <= ex_wdata;
            ls_mem_ren <= ex_mem_ren;
        end
    end

    //trace
    `ifndef SYNTHESIS
        always @(posedge clock) begin
            if (reset) begin
                pc_ls <= 32'b0;
                inst_ls <= 32'b0;
            end else if (ex_out_ready) begin
                if (ex_out_valid) begin
                    pc_ls <= pc_ex;
                    inst_ls <= inst_ex;
                end else begin
                    pc_ls <= 32'b0;
                    inst_ls <= 32'b0;
                end
            end
        end
    `endif

    ysyx_26030082_lsu lsu (
        .clock                  (clock),
        .reset                  (reset),
        .ls_in_valid            (ls_in_valid),
        .ls_in_ready            (ls_in_ready),
        .ls_out_valid           (ls_out_valid),

        .ls_mem_addr            (ls_mem_addr),
        .ls_funct3              (ls_funct3),
        .ls_mem_wen             (ls_mem_wen),
        .ls_mem_ren             (ls_mem_ren),
        .ls_wdata               (ls_wdata),

        .ls_mtime               (mtime),

        .lsu_axi_araddr         (lsu_axi_araddr),
        .lsu_axi_arsize         (lsu_axi_arsize),
        .lsu_axi_arvalid        (lsu_axi_arvalid),
        .lsu_axi_arready        (lsu_axi_arready),
        .lsu_axi_rdata          (lsu_axi_rdata),
        .lsu_axi_rresp          (lsu_axi_rresp),
        .lsu_axi_rvalid         (lsu_axi_rvalid),
        .lsu_axi_rready         (lsu_axi_rready),
        .lsu_axi_awaddr         (lsu_axi_awaddr),
        .lsu_axi_awsize         (lsu_axi_awsize),
        .lsu_axi_awvalid        (lsu_axi_awvalid),
        .lsu_axi_awready        (lsu_axi_awready),
        .lsu_axi_wdata          (lsu_axi_wdata),
        .lsu_axi_wstrb          (lsu_axi_wstrb),
        .lsu_axi_wvalid         (lsu_axi_wvalid),
        .lsu_axi_wready         (lsu_axi_wready),
        .lsu_axi_bresp          (lsu_axi_bresp),
        .lsu_axi_bvalid         (lsu_axi_bvalid),
        .lsu_axi_bready         (lsu_axi_bready),

        .ls_mem_rdata           (ls_mem_rdata)
    );

    ysyx_26030082_axi4lite_arbiter axi4lite_arbiter (
        .clock                  (clock),
        .reset                  (reset),

        .ifu_axi_araddr         (ifu_axi_araddr),
        .ifu_axi_arlen          (ifu_axi_arlen),
        .ifu_axi_arburst        (ifu_axi_arburst),
        .ifu_axi_arvalid        (ifu_axi_arvalid),
        .ifu_axi_arready        (ifu_axi_arready),
        .ifu_axi_rdata          (ifu_axi_rdata),
        .ifu_axi_rresp          (ifu_axi_rresp),
        .ifu_axi_rlast          (ifu_axi_rlast),
        .ifu_axi_rvalid         (ifu_axi_rvalid),
        .ifu_axi_rready         (ifu_axi_rready),

        .lsu_axi_araddr         (lsu_axi_araddr),
        .lsu_axi_arsize         (lsu_axi_arsize),
        .lsu_axi_arvalid        (lsu_axi_arvalid),
        .lsu_axi_arready        (lsu_axi_arready),
        .lsu_axi_rdata          (lsu_axi_rdata),
        .lsu_axi_rresp          (lsu_axi_rresp),
        .lsu_axi_rvalid         (lsu_axi_rvalid),
        .lsu_axi_rready         (lsu_axi_rready),
        .lsu_axi_awaddr         (lsu_axi_awaddr),
        .lsu_axi_awsize         (lsu_axi_awsize),
        .lsu_axi_awvalid        (lsu_axi_awvalid),
        .lsu_axi_awready        (lsu_axi_awready),
        .lsu_axi_wdata          (lsu_axi_wdata),
        .lsu_axi_wstrb          (lsu_axi_wstrb),
        .lsu_axi_wvalid         (lsu_axi_wvalid),
        .lsu_axi_wready         (lsu_axi_wready),
        .lsu_axi_bresp          (lsu_axi_bresp),
        .lsu_axi_bvalid         (lsu_axi_bvalid),
        .lsu_axi_bready         (lsu_axi_bready),

        .mem_axi_araddr          (io_master_araddr),
        .mem_axi_arid            (io_master_arid),
        .mem_axi_arlen           (io_master_arlen),
        .mem_axi_arsize          (io_master_arsize),
        .mem_axi_arburst         (io_master_arburst),
        .mem_axi_arvalid         (io_master_arvalid),
        .mem_axi_arready         (io_master_arready),
        .mem_axi_rdata           (io_master_rdata),
        .mem_axi_rid             (io_master_rid),
        .mem_axi_rresp           (io_master_rresp),
        .mem_axi_rlast           (io_master_rlast),
        .mem_axi_rvalid          (io_master_rvalid),
        .mem_axi_rready          (io_master_rready),
        .mem_axi_awaddr          (io_master_awaddr),
        .mem_axi_awid            (io_master_awid),
        .mem_axi_awlen           (io_master_awlen),
        .mem_axi_awsize          (io_master_awsize),
        .mem_axi_awburst         (io_master_awburst),
        .mem_axi_awvalid         (io_master_awvalid),
        .mem_axi_awready         (io_master_awready),
        .mem_axi_wdata           (io_master_wdata),
        .mem_axi_wstrb           (io_master_wstrb),
        .mem_axi_wlast           (io_master_wlast),
        .mem_axi_wvalid          (io_master_wvalid),
        .mem_axi_wready          (io_master_wready),
        .mem_axi_bid             (io_master_bid),
        .mem_axi_bresp           (io_master_bresp),
        .mem_axi_bvalid          (io_master_bvalid),
        .mem_axi_bready          (io_master_bready)
    );

`ifndef SYNTHESIS
`ifndef __ICARUS__
    always @(posedge clock) begin
        if (!reset && ls_out_valid) begin
            npc_commit(pc_ls, inst_ls);
        end
    end
`endif
`endif

    // ================================================================
    // PMU hooks (simulation-only, kept at module tail to avoid clutter)
    // ================================================================
`ifndef SYNTHESIS
`ifndef __ICARUS__
    localparam [31:0] PMU_EVT_IFU_R_FIRE      = 32'h0000_0001;
    localparam [31:0] PMU_EVT_LSU_R_FIRE      = 32'h0000_0004;
    localparam [31:0] PMU_EVT_EXU_DONE_FIRE   = 32'h0000_0008;
    localparam [31:0] PMU_EVT_DEC_TOTAL       = 32'h0000_0010;
    localparam [31:0] PMU_EVT_IFU_NOSUPPLY_TOTAL  = 32'h0000_0800;
    localparam [31:0] PMU_EVT_IFU_WAIT_ARREADY    = 32'h0000_1000;
    localparam [31:0] PMU_EVT_IFU_WAIT_RVALID     = 32'h0000_2000;
    localparam [31:0] PMU_EVT_IFU_ID_BACKPRESSURE = 32'h0000_4000;
    localparam [31:0] PMU_EVT_IFU_REDIRECT_DROP   = 32'h0000_8000;
    localparam [31:0] PMU_EVT_LSU_LOAD_REQ        = 32'h0004_0000;
    localparam [31:0] PMU_EVT_LSU_LOAD_PENDING_CYCLE = 32'h0020_0000;
    localparam [31:0] PMU_EVT_ICACHE_HIT          = 32'h0040_0000;
    localparam [31:0] PMU_EVT_ICACHE_MISS         = 32'h0080_0000;
    localparam [31:0] PMU_EVT_ICACHE_MISS_REFILL_CYCLE = 32'h0100_0000;

    localparam [1:0] PMU_ICACHE_LOOKUP  = 2'd0;
    localparam [1:0] PMU_ICACHE_MISS_AR = 2'd1;
    localparam [1:0] PMU_ICACHE_MISS_R  = 2'd2;

    localparam [2:0] PMU_LSU_IDLE       = 3'd0;
    localparam [2:0] PMU_LSU_RD_AR      = 3'd1;
    localparam [2:0] PMU_LSU_RD_WAIT_R  = 3'd2;

    wire        pmu_ifu_r_fire;
    wire        pmu_ifu_nosupply;
    wire        pmu_lsu_r_fire;
    wire        pmu_lsu_load_req;
    wire        pmu_lsu_load_pending;
    wire        pmu_exu_done_fire;
    wire        pmu_dec_total;
    wire        pmu_icache_miss_refill_busy;
    reg  [31:0] pmu_event_mask;

    // Direct hierarchical reads: simulation-only, no extra submodule ports.
    assign pmu_ifu_r_fire = fetch_valid && fetch_ready;
    assign pmu_ifu_nosupply = !pmu_ifu_r_fire;
    assign pmu_lsu_r_fire = lsu.r_fire;
    assign pmu_lsu_load_req = (lsu.state == PMU_LSU_IDLE) && ls_in_valid && lsu.ls_is_load;
    assign pmu_lsu_load_pending = (lsu.state == PMU_LSU_RD_AR) || (lsu.state == PMU_LSU_RD_WAIT_R);
    assign pmu_exu_done_fire = ex_out_valid && ex_out_ready;
    assign pmu_dec_total = !ifu.flush && ex_out_valid && ex_out_ready;
    assign pmu_icache_miss_refill_busy =
        (ifu.state == PMU_ICACHE_MISS_AR) ||
        (ifu.state == PMU_ICACHE_MISS_R);

    always @(*) begin
        pmu_event_mask = 32'b0;

        if (!reset) begin
            if (pmu_ifu_r_fire) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_R_FIRE;
            end
            if (pmu_ifu_nosupply) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_NOSUPPLY_TOTAL;
                if (ifu.flush || ifu.need_flush) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_REDIRECT_DROP;
                end else if (fetch_valid && !fetch_ready) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_ID_BACKPRESSURE;
                end else if (ifu_axi_arvalid && !ifu_axi_arready) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_WAIT_ARREADY;
                end else begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_WAIT_RVALID;
                end
            end
            if (fetch_valid) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_ICACHE_HIT;
            end
            if ((ifu.state == PMU_ICACHE_LOOKUP) && ifu.cache_miss) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_ICACHE_MISS;
            end
            if (pmu_icache_miss_refill_busy) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_ICACHE_MISS_REFILL_CYCLE;
            end
            if (pmu_lsu_r_fire) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_LSU_R_FIRE;
            end
            if (pmu_lsu_load_req) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_LSU_LOAD_REQ;
            end
            if (pmu_lsu_load_pending) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_LSU_LOAD_PENDING_CYCLE;
            end
            if (pmu_exu_done_fire) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_EXU_DONE_FIRE;
            end

            if (pmu_dec_total) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_DEC_TOTAL;
            end
        end
    end

    always @(posedge clock) begin
        if (!reset && (pmu_event_mask != 32'b0)) begin
            npc_pmu_event(pmu_event_mask);
        end
    end
`endif
`endif


    wire _unused_ok;
    assign _unused_ok = &{1'b0,
        io_interrupt,
        io_slave_awvalid, io_slave_awid, io_slave_awaddr, io_slave_awlen, io_slave_awsize, io_slave_awburst,
        io_slave_wvalid, io_slave_wdata, io_slave_wstrb, io_slave_wlast, io_slave_bready,
        io_slave_arvalid, io_slave_arid, io_slave_araddr, io_slave_arlen, io_slave_arsize, io_slave_arburst,
        io_slave_rready
    };

endmodule
