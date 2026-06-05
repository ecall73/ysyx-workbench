`timescale 1ns / 1ps

module myCPU #(
    parameter [31:0] RESET_PC = 32'h3000_0000,
    parameter integer TARGET_NPC = 0
) (
    input  wire        clock,
    input  wire        reset,

    // Shared MEM AXI4 Interface
    // Read address channel
    output wire [31:0] mem_axi_araddr,
    output wire [ 3:0] mem_axi_arid,
    output wire [ 7:0] mem_axi_arlen,
    output wire [ 2:0] mem_axi_arsize,
    output wire [ 1:0] mem_axi_arburst,
    output wire        mem_axi_arvalid,
    input  wire        mem_axi_arready,
    // Read data channel
    input  wire [31:0] mem_axi_rdata,
    input  wire [ 3:0] mem_axi_rid,
    input  wire [ 1:0] mem_axi_rresp,
    input  wire        mem_axi_rlast,
    input  wire        mem_axi_rvalid,
    output wire        mem_axi_rready,
    // Write address channel
    output wire [31:0] mem_axi_awaddr,
    output wire [ 3:0] mem_axi_awid,
    output wire [ 7:0] mem_axi_awlen,
    output wire [ 2:0] mem_axi_awsize,
    output wire [ 1:0] mem_axi_awburst,
    output wire        mem_axi_awvalid,
    input  wire        mem_axi_awready,
    // Write data channel
    output wire [31:0] mem_axi_wdata,
    output wire [ 3:0] mem_axi_wstrb,
    output wire        mem_axi_wlast,
    output wire        mem_axi_wvalid,
    input  wire        mem_axi_wready,
    // Write response channel
    input  wire [ 3:0] mem_axi_bid,
    input  wire [ 1:0] mem_axi_bresp,
    input  wire        mem_axi_bvalid,
    output wire        mem_axi_bready

);

`ifndef SYNTHESIS
    import "DPI-C" function void npc_commit(input int pc, input int inst);
    import "DPI-C" function void npc_pmu_event(input int event_mask);
    export "DPI-C" function npc_get_gpr;
    function int npc_get_gpr(input int idx);
        begin
            if (idx >= 0 && idx < 32) begin
                npc_get_gpr = u_RF.reg_bank[idx];
            end else begin
                npc_get_gpr = 0;
            end
        end
    endfunction
`endif

    wire [31:0] npc;

    // IF
    wire        if_in_valid;
    wire        if_in_ready;
    wire        if_out_valid;
    wire [31:0] if_pc;
    wire [31:0] if_pc4;
    wire [31:0] if_inst;
    wire        if_out_ready;

    // IFU <-> ICache
    wire        ic_req_valid;
    wire        ic_req_ready;
    wire [31:0] ic_req_pc;
    wire        ic_resp_valid;
    wire        ic_resp_ready;
    wire [31:0] ic_resp_pc;
    wire [31:0] ic_resp_inst;
    wire        ic_flush;
    wire        ic_invalidate;

    // ID
    reg         id_in_valid;
    reg  [31:0] id_pc;
    reg  [31:0] id_pc4;
    reg  [31:0] id_inst;
    wire [13:0] id_ALUControl;
    wire        id_RegWrite;
    wire [ 2:0] id_MemToReg;
    wire        id_MemWrite;
    wire        id_ALUSrcA;
    wire        id_ALUSrcB;
    wire [31:0] id_imm;
    wire [31:0] id_rR1_data;
    wire [31:0] id_rR2_data;
    wire [31:0] id_rR1_data_forward;
    wire [31:0] id_rR2_data_forward;
    wire        id_btype;
    wire        id_jtype;
    wire        id_ijtype;
    wire        id_CSRSrc;
    wire [11:0] id_CSRaddr;
    wire [ 4:0] id_CSRControl;
    wire        id_FenceI;

    // EX
    reg         ex_in_valid;
    reg  [31:0] ex_pc;
    reg  [31:0] ex_pc4;
    reg  [13:0] ex_ALUControl;
    reg         ex_RegWrite;
    reg  [ 2:0] ex_MemToReg;
    wire        ex_MemRead;
    reg         ex_MemWrite;
    reg         ex_ALUSrcA;
    reg         ex_ALUSrcB;
    reg  [31:0] ex_imm;
    reg  [31:0] ex_rR1_data;
    reg  [31:0] ex_rR2_data;
    reg  [ 2:0] ex_mask;
    reg  [ 4:0] ex_RFwaddr;
    wire [31:0] ex_ALUResult;
    wire [31:0] ex_BranchTarget;
    wire        ex_ALUisTrue;
    wire [31:0] ex_RFwdata;
    reg         ex_btype;
    reg         ex_jtype;
    reg         ex_ijtype;
    reg         ex_CSRSrc;
    reg  [11:0] ex_CSRaddr;
    reg  [ 4:0] ex_CSRControl;
    reg         ex_FenceI;
    wire [31:0] ex_CSRnpc;
    wire        ex_CSRjump;

    // LS
    reg         ls_in_valid;
    reg         ls_RegWrite;
    reg         ls_MemRead;
    reg         ls_MemWrite;
    reg  [31:0] ls_rR2_data;
    reg  [ 2:0] ls_mask;
    reg  [ 4:0] ls_RFwaddr;
    reg  [31:0] ls_ALUResult;
    reg  [31:0] ls_RFwdata;
    wire        ls_in_ready;
    wire        ls_out_valid;
    wire        ls_out_ready;
    wire [31:0] ls_RFwdata_out;

    // WB
    reg         wb_in_valid;
    reg         wb_RegWrite;
    reg  [ 4:0] wb_RFwaddr;
    reg  [31:0] wb_RFwdata;

    // Local handshake control
    wire        waste2;
    wire        redirect_flush;
    wire        fencei_flush;
    wire        frontend_flush;
    wire        forward_pending;
    wire        ex_out_ready;
    wire        id_in_ready;
    wire        ex_in_ready;
    wire        id_out_valid;   // From IDU handshake output
    wire        ex_out_valid;   // From EXU handshake output
    wire [31:0] frontend_npc;

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

    // Debug Interface
    `ifndef SYNTHESIS
        reg [31:0] pc_EX, pc_LS, pc_WB;
        reg [31:0] inst_EX, inst_LS, inst_WB;
        wire        have_inst_ID_decode;
        wire        have_inst_ID;
        reg         have_inst_EX, have_inst_LS, have_inst_WB;
        assign have_inst_ID = id_in_valid && have_inst_ID_decode;
    `endif

////////////////////////////////////////////////////////////////

    npc u_npc (
        .if_pc4                 (if_pc4),

        .ex_btype               (ex_btype),
        .ex_jtype               (ex_jtype),
        .ex_ijtype              (ex_ijtype),
        .ex_btype_target        (ex_BranchTarget),

        .ex_ALUisTrue           (ex_ALUisTrue),
        .ex_ALUResult           (ex_ALUResult),
        .ex_CSRjump             (ex_CSRjump),
        .ex_CSRnpc              (ex_CSRnpc),

        .npc                    (npc),
        .waste2                 (waste2)
    );

    // EX stage redirect decision (flush IF/ID and ID/EX)
    // Redirect only when EX really handshakes out; otherwise a stalled EX jump
    // could be flushed away before it reaches commit order.
    assign redirect_flush = ex_out_valid && ex_out_ready && waste2;
    assign fencei_flush = ex_out_valid && ex_out_ready && ex_FenceI;
    assign frontend_flush = redirect_flush || fencei_flush;
    assign frontend_npc = redirect_flush ? npc : ex_pc4;
    assign ic_invalidate = fencei_flush;

    // IF stage handshake defaults
    assign if_in_valid = 1'b1;
    assign if_out_ready = id_in_ready;

    ifu #(
        .RESET_PC               (RESET_PC)
    ) u_ifu (
        .clock                    (clock),
        .reset                    (reset),
        .if_in_valid            (if_in_valid),
        .if_in_ready            (if_in_ready),
        .if_out_ready           (if_out_ready),
        .redirect_flush         (frontend_flush),

        .ic_req_valid           (ic_req_valid),
        .ic_req_ready           (ic_req_ready),
        .ic_req_pc              (ic_req_pc),
        .ic_resp_valid          (ic_resp_valid),
        .ic_resp_ready          (ic_resp_ready),
        .ic_resp_pc             (ic_resp_pc),
        .ic_resp_inst           (ic_resp_inst),
        .ic_flush               (ic_flush),

        .if_out_valid           (if_out_valid),
        .if_pc                  (if_pc),
        .if_pc4                 (if_pc4),
        .if_inst                (if_inst),

        .npc                    (frontend_npc)
    );

    icache #(
        .LINE_WORDS             (4),
        .LINE_COUNT             (4),
        .ADDR_WIDTH             (32),
        .TARGET_NPC             (TARGET_NPC)
    ) u_icache (
        .clock                  (clock),
        .reset                  (reset),

        .ic_req_valid           (ic_req_valid),
        .ic_req_ready           (ic_req_ready),
        .ic_req_pc              (ic_req_pc),
        .ic_resp_valid          (ic_resp_valid),
        .ic_resp_ready          (ic_resp_ready),
        .ic_resp_pc             (ic_resp_pc),
        .ic_resp_inst           (ic_resp_inst),
        .ic_flush               (ic_flush),
        .ic_invalidate          (ic_invalidate),

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

    // ================================================================
    // IF -> ID
    // ================================================================
    always @(posedge clock) begin
        if (reset) begin
            id_in_valid <= 1'b0;
            id_pc    <= 32'b0;
            id_pc4   <= 32'b0;
            id_inst  <= 32'b0;
        end else if (frontend_flush) begin
            id_in_valid <= 1'b0;
            id_pc    <= 32'b0;
            id_pc4   <= 32'b0;
            id_inst  <= 32'b0;
        end else if (id_in_ready) begin
            id_in_valid <= if_out_valid;
            if (if_out_valid) begin
                id_pc   <= if_pc;
                id_pc4  <= if_pc4;
                id_inst <= if_inst;
            end else begin
                id_pc   <= 32'b0;
                id_pc4  <= 32'b0;
                id_inst <= 32'b0;
            end
        end
    end

    idu u_idu (
        .clock                    (clock),
        .reset                    (reset),
        .id_in_valid            (id_in_valid),
        .id_in_ready            (id_in_ready),
        .id_out_valid           (id_out_valid),
        .id_out_ready           (ex_in_ready),
        .id_block               (forward_pending),

        .id_inst                (id_inst),

        .id_ALUControl          (id_ALUControl),
        .id_RegWrite            (id_RegWrite),
        .id_MemToReg            (id_MemToReg),
        .id_MemWrite            (id_MemWrite),
        .id_ALUSrcA             (id_ALUSrcA),
        .id_ALUSrcB             (id_ALUSrcB),
        .id_imm                 (id_imm),
        .id_rR1_data            (id_rR1_data),
        .id_rR2_data            (id_rR2_data),

        .id_btype               (id_btype),
        .id_jtype               (id_jtype),
        .id_ijtype              (id_ijtype),

        .id_CSRSrc              (id_CSRSrc),
        .id_CSRaddr             (id_CSRaddr),
        .id_CSRControl          (id_CSRControl),
        .id_FenceI              (id_FenceI)

        `ifndef SYNTHESIS
        ,   .have_inst_ID       (have_inst_ID_decode)
        `endif
    );

    RF u_RF (
        .clock                    (clock),
        .reset                    (reset),

        .wen                    (wb_in_valid && wb_RegWrite),
        .waddr                  (wb_RFwaddr),
        .wdata                  (wb_RFwdata),

        .rR1                    (id_inst[19:15]),
        .rR2                    (id_inst[24:20]),

        .rR1_data               (id_rR1_data),
        .rR2_data               (id_rR2_data)
    );

    forward u_forward (
        .id_in_valid            (id_in_valid),
        .id_rR1                 (id_inst[19:15]),
        .id_rR2                 (id_inst[24:20]),
        .id_rR1_data            (id_rR1_data),
        .id_rR2_data            (id_rR2_data),

        .ex_out_valid           (ex_out_valid),
        .ex_MemRead             (ex_MemRead),
        .ex_RegWrite            (ex_in_valid && ex_RegWrite),
        .ex_RFwaddr             (ex_RFwaddr),
        .ex_RFwdata             (ex_RFwdata),

        .ls_RegWrite            (ls_out_valid && ls_RegWrite),
        .ls_RFwaddr             (ls_RFwaddr),
        .ls_RFwdata             (ls_RFwdata_out),
        .ls_load_pending        (ls_in_valid && ls_MemRead && ~ls_out_valid),

        .wb_RegWrite            (wb_in_valid && wb_RegWrite),
        .wb_RFwaddr             (wb_RFwaddr),
        .wb_RFwdata             (wb_RFwdata),

        .forward_pending        (forward_pending),
        .id_rR1_data_forward    (id_rR1_data_forward),
        .id_rR2_data_forward    (id_rR2_data_forward)
    );

    // ================================================================
    // ID -> EX
    // ================================================================
    always @(posedge clock) begin
        if (reset) begin
            ex_in_valid        <= 1'b0;
            ex_ALUControl   <= 0;
            ex_RegWrite     <= 0;
            ex_MemWrite     <= 0;
            ex_MemToReg     <= 0;
            ex_mask         <= 0;
            ex_imm          <= 0;
            ex_pc           <= 0;
            ex_pc4          <= 0;
            ex_RFwaddr      <= 0;
            ex_ALUSrcA      <= 0;
            ex_ALUSrcB      <= 0;
            ex_rR1_data     <= 0;
            ex_rR2_data     <= 0;
            ex_CSRSrc       <= 0;
            ex_CSRaddr      <= 0;
            ex_CSRControl   <= 0;
            ex_FenceI       <= 0;
            ex_btype        <= 0;
            ex_jtype        <= 0;
            ex_ijtype       <= 0;
        end else if (frontend_flush) begin
            ex_in_valid        <= 1'b0;
            ex_ALUControl   <= 0;
            ex_RegWrite     <= 0;
            ex_MemWrite     <= 0;
            ex_MemToReg     <= 0;
            ex_mask         <= 0;
            ex_imm          <= 0;
            ex_pc           <= 0;
            ex_pc4          <= 0;
            ex_RFwaddr      <= 0;
            ex_ALUSrcA      <= 0;
            ex_ALUSrcB      <= 0;
            ex_rR1_data     <= 0;
            ex_rR2_data     <= 0;
            ex_CSRSrc       <= 0;
            ex_CSRaddr      <= 0;
            ex_CSRControl   <= 0;
            ex_FenceI       <= 0;
            ex_btype        <= 0;
            ex_jtype        <= 0;
            ex_ijtype       <= 0;
        end else if (ex_in_ready) begin
            ex_in_valid <= id_out_valid;
            if (id_out_valid) begin
                ex_ALUControl   <= id_ALUControl;
                ex_RegWrite     <= id_RegWrite;
                ex_MemWrite     <= id_MemWrite;
                ex_MemToReg     <= id_MemToReg;
                ex_mask         <= id_inst[14:12];
                ex_imm          <= id_imm;
                ex_pc           <= id_pc;
                ex_pc4          <= id_pc4;
                ex_RFwaddr      <= id_inst[11:7];
                ex_ALUSrcA      <= id_ALUSrcA;
                ex_ALUSrcB      <= id_ALUSrcB;
                ex_rR1_data     <= id_rR1_data_forward;
                ex_rR2_data     <= id_rR2_data_forward;
                ex_CSRSrc       <= id_CSRSrc;
                ex_CSRaddr      <= id_CSRaddr;
                ex_CSRControl   <= id_CSRControl;
                ex_FenceI       <= id_FenceI;
                ex_btype        <= id_btype;
                ex_jtype        <= id_jtype;
                ex_ijtype       <= id_ijtype;
            end else begin
                ex_ALUControl   <= 0;
                ex_RegWrite     <= 0;
                ex_MemWrite     <= 0;
                ex_MemToReg     <= 0;
                ex_mask         <= 0;
                ex_imm          <= 0;
                ex_pc           <= 0;
                ex_pc4          <= 0;
                ex_RFwaddr      <= 0;
                ex_ALUSrcA      <= 0;
                ex_ALUSrcB      <= 0;
                ex_rR1_data     <= 0;
                ex_rR2_data     <= 0;
                ex_CSRSrc       <= 0;
                ex_CSRaddr      <= 0;
                ex_CSRControl   <= 0;
                ex_FenceI       <= 0;
                ex_btype        <= 0;
                ex_jtype        <= 0;
                ex_ijtype       <= 0;
            end
        end
    end

    //trace
    `ifndef SYNTHESIS
        always @(posedge clock) begin
            if (reset) begin
                pc_EX <= 32'b0;
                inst_EX <= 32'b0;
                have_inst_EX <= 1'b0;
            end else if (frontend_flush) begin
                pc_EX <= 32'b0;
                inst_EX <= 32'b0;
                have_inst_EX <= 1'b0;
            end else if (ex_in_ready) begin
                if (id_out_valid) begin
                    pc_EX <= id_pc;
                    inst_EX <= id_inst;
                    have_inst_EX <= have_inst_ID;
                end else begin
                    pc_EX <= 32'b0;
                    inst_EX <= 32'b0;
                    have_inst_EX <= 1'b0;
                end
            end
        end
    `endif

    // EX -> LS handshake coupling
    assign ex_out_ready = ls_in_ready;

    exu u_exu (
        .clock                    (clock),
        .reset                    (reset),
        .ex_in_valid            (ex_in_valid),
        .ex_in_ready            (ex_in_ready),
        .ex_out_valid           (ex_out_valid),
        .ex_out_ready           (ex_out_ready),

        .ex_ALUSrcA             (ex_ALUSrcA),
        .ex_ALUSrcB             (ex_ALUSrcB),
        .ex_pc                  (ex_pc),
        .ex_pc4                 (ex_pc4),
        .ex_rR1_data            (ex_rR1_data),
        .ex_rR2_data            (ex_rR2_data),
        .ex_imm                 (ex_imm),
        .ex_ALUControl          (ex_ALUControl),

        .ex_CSRSrc              (ex_CSRSrc),
        .ex_CSRaddr             (ex_CSRaddr),
        .ex_CSRControl          (ex_CSRControl),

        .ex_MemToReg            (ex_MemToReg),

        .ex_ALUResult           (ex_ALUResult),
        .ex_BranchTarget        (ex_BranchTarget),
        .ex_ALUisTrue           (ex_ALUisTrue),

        .ex_CSRjump             (ex_CSRjump),
        .ex_CSRnpc              (ex_CSRnpc),

        .ex_RFwdata             (ex_RFwdata),
        .ex_MemRead             (ex_MemRead)
    );

    // ================================================================
    // EX -> LS
    // ================================================================
    always @(posedge clock) begin
        if (reset) begin
            ls_in_valid   <= 1'b0;
            ls_RegWrite   <= 1'b0;
            ls_MemWrite   <= 1'b0;
            ls_ALUResult  <= 32'b0;
            ls_rR2_data   <= 32'b0;
            ls_mask       <= 3'b0;
            ls_RFwaddr    <= 5'b0;
            ls_RFwdata    <= 32'b0;
            ls_MemRead    <= 1'b0;
        end else if (ex_out_ready) begin
            ls_in_valid <= ex_out_valid;
            if (ex_out_valid) begin
                ls_RegWrite   <= ex_RegWrite;
                ls_MemWrite   <= ex_MemWrite;
                ls_ALUResult  <= ex_ALUResult;
                ls_rR2_data   <= ex_rR2_data;
                ls_mask       <= ex_mask;
                ls_RFwaddr    <= ex_RFwaddr;
                ls_RFwdata    <= ex_RFwdata;
                ls_MemRead    <= ex_MemRead;
            end else begin
                ls_RegWrite   <= 1'b0;
                ls_MemWrite   <= 1'b0;
                ls_ALUResult  <= 32'b0;
                ls_rR2_data   <= 32'b0;
                ls_mask       <= 3'b0;
                ls_RFwaddr    <= 5'b0;
                ls_RFwdata    <= 32'b0;
                ls_MemRead    <= 1'b0;
            end
        end
    end

    //trace
    `ifndef SYNTHESIS
        always @(posedge clock) begin
            if (reset) begin
                pc_LS <= 32'b0;
                inst_LS <= 32'b0;
                have_inst_LS <= 1'b0;
            end else if (ex_out_ready) begin
                if (ex_out_valid) begin
                    pc_LS <= pc_EX;
                    inst_LS <= inst_EX;
                    have_inst_LS <= have_inst_EX;
                end else begin
                    pc_LS <= 32'b0;
                    inst_LS <= 32'b0;
                    have_inst_LS <= 1'b0;
                end
            end
        end
    `endif

    // LS -> WB handshake coupling (WB always ready in current design)
    assign ls_out_ready = 1'b1;

    lsu u_lsu (
        .clock                     (clock),
        .reset                     (reset),
        .ls_in_valid             (ls_in_valid),
        .ls_in_ready             (ls_in_ready),
        .ls_out_valid            (ls_out_valid),
        .ls_out_ready            (ls_out_ready),

        .ls_ALUResult            (ls_ALUResult),
        .ls_mask                 (ls_mask),
        .ls_MemWrite             (ls_MemWrite),
        .ls_MemRead              (ls_MemRead),
        .ls_rR2_data             (ls_rR2_data),

        .ls_RFwdata              (ls_RFwdata),

        .lsu_axi_araddr          (lsu_axi_araddr),
        .lsu_axi_arsize          (lsu_axi_arsize),
        .lsu_axi_arvalid         (lsu_axi_arvalid),
        .lsu_axi_arready         (lsu_axi_arready),
        .lsu_axi_rdata           (lsu_axi_rdata),
        .lsu_axi_rresp           (lsu_axi_rresp),
        .lsu_axi_rvalid          (lsu_axi_rvalid),
        .lsu_axi_rready          (lsu_axi_rready),
        .lsu_axi_awaddr          (lsu_axi_awaddr),
        .lsu_axi_awsize          (lsu_axi_awsize),
        .lsu_axi_awvalid         (lsu_axi_awvalid),
        .lsu_axi_awready         (lsu_axi_awready),
        .lsu_axi_wdata           (lsu_axi_wdata),
        .lsu_axi_wstrb           (lsu_axi_wstrb),
        .lsu_axi_wvalid          (lsu_axi_wvalid),
        .lsu_axi_wready          (lsu_axi_wready),
        .lsu_axi_bresp           (lsu_axi_bresp),
        .lsu_axi_bvalid          (lsu_axi_bvalid),
        .lsu_axi_bready          (lsu_axi_bready),

        .ls_RFwdata_out          (ls_RFwdata_out)
    );

    axi4lite_arbiter u_axi4lite_arbiter (
        .clock                     (clock),
        .reset                     (reset),

        .ifu_axi_araddr          (ifu_axi_araddr),
        .ifu_axi_arlen           (ifu_axi_arlen),
        .ifu_axi_arburst         (ifu_axi_arburst),
        .ifu_axi_arvalid         (ifu_axi_arvalid),
        .ifu_axi_arready         (ifu_axi_arready),
        .ifu_axi_rdata           (ifu_axi_rdata),
        .ifu_axi_rresp           (ifu_axi_rresp),
        .ifu_axi_rlast           (ifu_axi_rlast),
        .ifu_axi_rvalid          (ifu_axi_rvalid),
        .ifu_axi_rready          (ifu_axi_rready),

        .lsu_axi_araddr          (lsu_axi_araddr),
        .lsu_axi_arsize          (lsu_axi_arsize),
        .lsu_axi_arvalid         (lsu_axi_arvalid),
        .lsu_axi_arready         (lsu_axi_arready),
        .lsu_axi_rdata           (lsu_axi_rdata),
        .lsu_axi_rresp           (lsu_axi_rresp),
        .lsu_axi_rvalid          (lsu_axi_rvalid),
        .lsu_axi_rready          (lsu_axi_rready),
        .lsu_axi_awaddr          (lsu_axi_awaddr),
        .lsu_axi_awsize          (lsu_axi_awsize),
        .lsu_axi_awvalid         (lsu_axi_awvalid),
        .lsu_axi_awready         (lsu_axi_awready),
        .lsu_axi_wdata           (lsu_axi_wdata),
        .lsu_axi_wstrb           (lsu_axi_wstrb),
        .lsu_axi_wvalid          (lsu_axi_wvalid),
        .lsu_axi_wready          (lsu_axi_wready),
        .lsu_axi_bresp           (lsu_axi_bresp),
        .lsu_axi_bvalid          (lsu_axi_bvalid),
        .lsu_axi_bready          (lsu_axi_bready),

        .mem_axi_araddr          (mem_axi_araddr),
        .mem_axi_arid            (mem_axi_arid),
        .mem_axi_arlen           (mem_axi_arlen),
        .mem_axi_arsize          (mem_axi_arsize),
        .mem_axi_arburst         (mem_axi_arburst),
        .mem_axi_arvalid         (mem_axi_arvalid),
        .mem_axi_arready         (mem_axi_arready),
        .mem_axi_rdata           (mem_axi_rdata),
        .mem_axi_rid             (mem_axi_rid),
        .mem_axi_rresp           (mem_axi_rresp),
        .mem_axi_rlast           (mem_axi_rlast),
        .mem_axi_rvalid          (mem_axi_rvalid),
        .mem_axi_rready          (mem_axi_rready),
        .mem_axi_awaddr          (mem_axi_awaddr),
        .mem_axi_awid            (mem_axi_awid),
        .mem_axi_awlen           (mem_axi_awlen),
        .mem_axi_awsize          (mem_axi_awsize),
        .mem_axi_awburst         (mem_axi_awburst),
        .mem_axi_awvalid         (mem_axi_awvalid),
        .mem_axi_awready         (mem_axi_awready),
        .mem_axi_wdata           (mem_axi_wdata),
        .mem_axi_wstrb           (mem_axi_wstrb),
        .mem_axi_wlast           (mem_axi_wlast),
        .mem_axi_wvalid          (mem_axi_wvalid),
        .mem_axi_wready          (mem_axi_wready),
        .mem_axi_bid             (mem_axi_bid),
        .mem_axi_bresp           (mem_axi_bresp),
        .mem_axi_bvalid          (mem_axi_bvalid),
        .mem_axi_bready          (mem_axi_bready)
    );

    // ================================================================
    // LS -> WB
    // ================================================================
    always @(posedge clock) begin
        if (reset) begin
            wb_in_valid  <= 1'b0;
            wb_RegWrite  <= 1'b0;
            wb_RFwaddr   <= 5'b0;
            wb_RFwdata   <= 32'b0;
        end else begin
            wb_in_valid <= ls_out_valid;
            if (ls_out_valid) begin
                wb_RegWrite <= ls_RegWrite;
                wb_RFwaddr  <= ls_RFwaddr;
                wb_RFwdata  <= ls_RFwdata_out;
            end else begin
                wb_RegWrite <= 1'b0;
                wb_RFwaddr  <= 5'b0;
                wb_RFwdata  <= 32'b0;
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clock) begin
        if (!reset && wb_in_valid && have_inst_WB) begin
            npc_commit(pc_WB, inst_WB);
        end
    end
`endif

    //trace
    `ifndef SYNTHESIS
        always @(posedge clock) begin
            if (reset) begin
                pc_WB <= 32'b0;
                inst_WB <= 32'b0;
                have_inst_WB <= 1'b0;
            end else begin
                if (ls_out_valid) begin
                    pc_WB <= pc_LS;
                    inst_WB <= inst_LS;
                    have_inst_WB <= have_inst_LS;
                end else begin
                    pc_WB <= 32'b0;
                    inst_WB <= 32'b0;
                    have_inst_WB <= 1'b0;
                end
            end
        end
    `endif

    // ================================================================
    // PMU hooks (simulation-only, kept at module tail to avoid clutter)
    // ================================================================
`ifndef SYNTHESIS
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
    assign pmu_ifu_r_fire = if_out_valid && if_out_ready;
    assign pmu_ifu_nosupply = !pmu_ifu_r_fire;
    assign pmu_lsu_r_fire = u_lsu.r_fire;
    assign pmu_lsu_load_req = (u_lsu.state == PMU_LSU_IDLE) && ls_in_valid && u_lsu.ls_is_load;
    assign pmu_lsu_load_pending = (u_lsu.state == PMU_LSU_RD_AR) || (u_lsu.state == PMU_LSU_RD_WAIT_R);
    assign pmu_exu_done_fire = ex_out_valid && ex_out_ready;
    assign pmu_dec_total = !frontend_flush && u_idu.id_out_valid && ex_in_ready && have_inst_ID;
    assign pmu_icache_miss_refill_busy =
        ((u_icache.state == PMU_ICACHE_MISS_AR) ||
         (u_icache.state == PMU_ICACHE_MISS_R)) && !u_icache.miss_bypass;

    always @(*) begin
        pmu_event_mask = 32'b0;

        if (!reset) begin
            if (pmu_ifu_r_fire) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_R_FIRE;
            end
            if (pmu_ifu_nosupply) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_NOSUPPLY_TOTAL;
                if (frontend_flush || u_icache.need_flush) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_REDIRECT_DROP;
                end else if (if_out_valid && !if_out_ready) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_ID_BACKPRESSURE;
                end else if (ifu_axi_arvalid && !ifu_axi_arready) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_WAIT_ARREADY;
                end else begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_WAIT_RVALID;
                end
            end
            if (u_icache.lookup_resp_valid) begin
                pmu_event_mask = pmu_event_mask | PMU_EVT_ICACHE_HIT;
            end
            if ((u_icache.state == PMU_ICACHE_LOOKUP) && u_icache.cache_miss) begin
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

endmodule
