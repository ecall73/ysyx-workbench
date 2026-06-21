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

    // IF -> IF/EX
    wire        if_out_valid;
    wire        if_out_ready;
    wire [31:0] if_pc;
    wire [31:0] if_inst;

    // IF/EX
    reg         ex_in_valid;
    wire        ex_in_ready;
    reg  [31:0] ex_pc;
    reg  [31:0] ex_inst;

    // EX
    wire        ex_redirect;
    wire [31:0] ex_redirect_pc;
    wire        ex_fence_i;
    wire        ex_out_valid;

    // IFU AXI4 (read-only in practice)
    wire [31:0] ifu_master_araddr;
    wire [ 7:0] ifu_master_arlen;
    wire [ 1:0] ifu_master_arburst;
    wire        ifu_master_arvalid;
    wire        ifu_master_arready;
    wire [31:0] ifu_master_rdata;
    wire [ 1:0] ifu_master_rresp;
    wire        ifu_master_rlast;
    wire        ifu_master_rvalid;
    wire        ifu_master_rready;

    // EXU LSU AXI4-Lite master
    wire [31:0] lsu_master_araddr;
    wire [ 2:0] lsu_master_arsize;
    wire        lsu_master_arvalid;
    wire        lsu_master_arready;
    wire [31:0] lsu_master_rdata;
    wire [ 1:0] lsu_master_rresp;
    wire        lsu_master_rvalid;
    wire        lsu_master_rready;
    wire [31:0] lsu_master_awaddr;
    wire [ 2:0] lsu_master_awsize;
    wire        lsu_master_awvalid;
    wire        lsu_master_awready;
    wire [31:0] lsu_master_wdata;
    wire [ 3:0] lsu_master_wstrb;
    wire        lsu_master_wvalid;
    wire        lsu_master_wready;
    wire [ 1:0] lsu_master_bresp;
    wire        lsu_master_bvalid;
    wire        lsu_master_bready;
    reg  [63:0] mtime;

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
        .ex_redirect            (ex_redirect),
        .ex_redirect_pc         (ex_redirect_pc),
        .ex_fence_i             (ex_fence_i),

        .if_out_valid           (if_out_valid),
        .if_out_ready           (if_out_ready),
        .if_pc                  (if_pc),
        .if_inst                (if_inst),

        .ifu_master_araddr         (ifu_master_araddr),
        .ifu_master_arlen          (ifu_master_arlen),
        .ifu_master_arburst        (ifu_master_arburst),
        .ifu_master_arvalid        (ifu_master_arvalid),
        .ifu_master_arready        (ifu_master_arready),
        .ifu_master_rdata          (ifu_master_rdata),
        .ifu_master_rresp          (ifu_master_rresp),
        .ifu_master_rlast          (ifu_master_rlast),
        .ifu_master_rvalid         (ifu_master_rvalid),
        .ifu_master_rready         (ifu_master_rready)
    );
    
    assign if_out_ready = ex_in_ready;

    // ================================================================
    // IF -> EX
    // ================================================================
    always @(posedge clock) begin
        if (reset) begin
            ex_in_valid <= 1'b0;
            ex_pc <= 32'b0;
            ex_inst <= 32'b0;
        end else if (ex_redirect && ex_out_valid) begin
            ex_in_valid <= 1'b0;
            ex_pc <= 32'b0;
            ex_inst <= 32'b0;
        end else if (if_out_ready) begin
            ex_in_valid <= if_out_valid;
            ex_pc <= if_pc;
            ex_inst <= if_inst;
        end
    end

    ysyx_26030082_exu exu (
        .clock                  (clock),
        .reset                  (reset),
        .ex_in_valid            (ex_in_valid),
        .ex_in_ready            (ex_in_ready),
        .ex_pc                  (ex_pc),
        .ex_inst                (ex_inst),

        .ex_out_valid           (ex_out_valid),

        .ex_mtime               (mtime),

        .ex_redirect            (ex_redirect),
        .ex_redirect_pc         (ex_redirect_pc),
        .ex_fence_i             (ex_fence_i),

        .lsu_master_araddr         (lsu_master_araddr),
        .lsu_master_arsize         (lsu_master_arsize),
        .lsu_master_arvalid        (lsu_master_arvalid),
        .lsu_master_arready        (lsu_master_arready),
        .lsu_master_rdata          (lsu_master_rdata),
        .lsu_master_rresp          (lsu_master_rresp),
        .lsu_master_rvalid         (lsu_master_rvalid),
        .lsu_master_rready         (lsu_master_rready),
        .lsu_master_awaddr         (lsu_master_awaddr),
        .lsu_master_awsize         (lsu_master_awsize),
        .lsu_master_awvalid        (lsu_master_awvalid),
        .lsu_master_awready        (lsu_master_awready),
        .lsu_master_wdata          (lsu_master_wdata),
        .lsu_master_wstrb          (lsu_master_wstrb),
        .lsu_master_wvalid         (lsu_master_wvalid),
        .lsu_master_wready         (lsu_master_wready),
        .lsu_master_bresp          (lsu_master_bresp),
        .lsu_master_bvalid         (lsu_master_bvalid),
        .lsu_master_bready         (lsu_master_bready)
    );

    ysyx_26030082_axi4lite_arbiter axi4lite_arbiter (
        .clock                  (clock),
        .reset                  (reset),

        .ifu_master_araddr         (ifu_master_araddr),
        .ifu_master_arlen          (ifu_master_arlen),
        .ifu_master_arburst        (ifu_master_arburst),
        .ifu_master_arvalid        (ifu_master_arvalid),
        .ifu_master_arready        (ifu_master_arready),
        .ifu_master_rdata          (ifu_master_rdata),
        .ifu_master_rresp          (ifu_master_rresp),
        .ifu_master_rlast          (ifu_master_rlast),
        .ifu_master_rvalid         (ifu_master_rvalid),
        .ifu_master_rready         (ifu_master_rready),

        .lsu_master_araddr         (lsu_master_araddr),
        .lsu_master_arsize         (lsu_master_arsize),
        .lsu_master_arvalid        (lsu_master_arvalid),
        .lsu_master_arready        (lsu_master_arready),
        .lsu_master_rdata          (lsu_master_rdata),
        .lsu_master_rresp          (lsu_master_rresp),
        .lsu_master_rvalid         (lsu_master_rvalid),
        .lsu_master_rready         (lsu_master_rready),
        .lsu_master_awaddr         (lsu_master_awaddr),
        .lsu_master_awsize         (lsu_master_awsize),
        .lsu_master_awvalid        (lsu_master_awvalid),
        .lsu_master_awready        (lsu_master_awready),
        .lsu_master_wdata          (lsu_master_wdata),
        .lsu_master_wstrb          (lsu_master_wstrb),
        .lsu_master_wvalid         (lsu_master_wvalid),
        .lsu_master_wready         (lsu_master_wready),
        .lsu_master_bresp          (lsu_master_bresp),
        .lsu_master_bvalid         (lsu_master_bvalid),
        .lsu_master_bready         (lsu_master_bready),

        .io_master_araddr           (io_master_araddr),
        .io_master_arid             (io_master_arid),
        .io_master_arlen            (io_master_arlen),
        .io_master_arsize           (io_master_arsize),
        .io_master_arburst          (io_master_arburst),
        .io_master_arvalid          (io_master_arvalid),
        .io_master_arready          (io_master_arready),
        .io_master_rdata            (io_master_rdata),
        .io_master_rid              (io_master_rid),
        .io_master_rresp            (io_master_rresp),
        .io_master_rlast            (io_master_rlast),
        .io_master_rvalid           (io_master_rvalid),
        .io_master_rready           (io_master_rready),
        .io_master_awaddr           (io_master_awaddr),
        .io_master_awid             (io_master_awid),
        .io_master_awlen            (io_master_awlen),
        .io_master_awsize           (io_master_awsize),
        .io_master_awburst          (io_master_awburst),
        .io_master_awvalid          (io_master_awvalid),
        .io_master_awready          (io_master_awready),
        .io_master_wdata            (io_master_wdata),
        .io_master_wstrb            (io_master_wstrb),
        .io_master_wlast            (io_master_wlast),
        .io_master_wvalid           (io_master_wvalid),
        .io_master_wready           (io_master_wready),
        .io_master_bid              (io_master_bid),
        .io_master_bresp            (io_master_bresp),
        .io_master_bvalid           (io_master_bvalid),
        .io_master_bready           (io_master_bready)
    );

`ifndef SYNTHESIS
`ifndef __ICARUS__
    always @(posedge clock) begin
        if (!reset && ex_out_valid) begin
            npc_commit(ex_pc, ex_inst);
        end
    end
`endif
`endif

    // ================================================================
    // PMU hooks (simulation-only, kept at module tail to avoid clutter)
    // ================================================================
`ifndef SYNTHESIS
`ifndef __ICARUS__
    localparam [31:0] PMU_EVT_IFETCH_FIRE       = 32'h0000_0001;
    localparam [31:0] PMU_EVT_ICACHE_MISS       = 32'h0000_0002;
    localparam [31:0] PMU_EVT_ICACHE_MISS_CYCLE = 32'h0000_0004;
    localparam [31:0] PMU_EVT_DCACHE_ACCESS     = 32'h0000_0008;
    localparam [31:0] PMU_EVT_DCACHE_STORE      = 32'h0000_0010;
    localparam [31:0] PMU_EVT_DCACHE_MISS       = 32'h0000_0020;
    localparam [31:0] PMU_EVT_DCACHE_MISS_CYCLE = 32'h0000_0040;
    localparam [31:0] PMU_EVT_REDIRECT          = 32'h0000_0080;

    localparam PMU_ICACHE_LOOKUP = 1'b0;
    localparam PMU_ICACHE_MISS_R = 1'b1;

    localparam [2:0] PMU_LSU_IDLE = 3'd0;

    wire        pmu_ifetch_fire;
    wire        pmu_icache_miss;
    wire        pmu_icache_miss_cycle;
    wire        pmu_dcache_access;
    wire        pmu_dcache_store;
    wire        pmu_dcache_miss_cycle;
    wire        pmu_redirect;
    reg  [31:0] pmu_event_mask;

    // Direct hierarchical reads: simulation-only, no extra submodule ports.
    assign pmu_ifetch_fire = if_out_valid && if_out_ready;
    assign pmu_icache_miss = (ifu.state == PMU_ICACHE_LOOKUP) && ifu.cache_miss;
    assign pmu_icache_miss_cycle =
        ((ifu.state == PMU_ICACHE_LOOKUP) && (ifu.cache_miss || ifu.ar_pending)) ||
        (ifu.state == PMU_ICACHE_MISS_R);
    assign pmu_dcache_access = (exu.mem_state == PMU_LSU_IDLE) &&
                               ex_in_valid && exu.is_mem && !exu.is_local;
    assign pmu_dcache_store = pmu_dcache_access && exu.mem_wen;
    assign pmu_dcache_miss_cycle = ex_in_valid && !ex_in_ready &&
                                   exu.is_mem && !exu.is_local;
    assign pmu_redirect = ex_out_valid && ex_redirect;

    always @(*) begin
        pmu_event_mask = 32'b0;

        if (!reset) begin
            if (pmu_ifetch_fire) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_IFETCH_FIRE;
            end
            if (pmu_icache_miss) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_ICACHE_MISS;
            end
            if (pmu_icache_miss_cycle) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_ICACHE_MISS_CYCLE;
            end
            if (pmu_dcache_access) begin
                pmu_event_mask = pmu_event_mask |
                                 PMU_EVT_DCACHE_ACCESS |
                                 PMU_EVT_DCACHE_MISS;
            end
            if (pmu_dcache_store) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_DCACHE_STORE;
            end
            if (pmu_dcache_miss_cycle) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_DCACHE_MISS_CYCLE;
            end
            if (pmu_redirect) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_REDIRECT;
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
