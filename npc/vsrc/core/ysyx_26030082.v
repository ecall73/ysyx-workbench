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

`ifdef NPC_SIMULATION
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
`endif
`ifdef NPC_SIMULATION
`ifndef SYNTHESIS
`ifndef __ICARUS__
    import "DPI-C" function void npc_commit(
        input int unsigned commit_pc,
        input int unsigned commit_inst,
        input int unsigned pc,
        input int unsigned mstatus,
        input int unsigned mtvec,
        input int unsigned mepc,
        input int unsigned mcause,
        input int unsigned gpr[32]
    );
`ifdef NPC_ENABLE_PERF
    import "DPI-C" function void npc_pmu_event(input int event_mask);
`endif
`endif
`endif
`endif

    // IF
    wire        flush;
    wire        invalidate;

    // ID
    wire        id_valid;
    wire [31:0] id_pc;
    wire [31:0] id_inst;
    wire [ 3:0] id_ALUControl;
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
    wire        id_is_system;
    wire [11:0] id_CSRaddr;
    wire        id_FenceI;

    // EX
    reg         ex_in_valid;
    reg  [31:0] ex_pc;
    reg  [ 3:0] ex_ALUControl;
    reg         ex_RegWrite;
    reg  [ 2:0] ex_MemToReg;
    wire        ex_MemRead;
    reg         ex_MemWrite;
    reg         ex_ALUSrcA;
    reg         ex_ALUSrcB;
    reg  [31:0] ex_imm;
    reg  [31:0] ex_rR1_data;
    reg  [31:0] ex_rR2_data;
    reg  [ 2:0] ex_funct3;
    reg  [ 4:0] ex_RFwaddr;
    wire [31:0] ex_ALUResult;
    wire        ex_BRUResult;
    wire [31:0] ex_pc4;
    wire [31:0] ex_RFwdata;
    reg         ex_btype;
    reg         ex_jtype;
    reg         ex_ijtype;
    reg         ex_is_system;
    reg  [11:0] ex_CSRaddr;
    reg         ex_FenceI;
    wire [31:0] ex_CSRnpc;
    wire        ex_CSRjump;

    // LS
    reg         ls_in_valid;
    reg         ls_RegWrite;
    reg         ls_MemRead;
    reg         ls_MemWrite;
    reg  [31:0] ls_rR2_data;
    reg  [ 2:0] ls_funct3;
    reg  [ 4:0] ls_RFwaddr;
    reg  [31:0] ls_ALUResult;
    reg  [31:0] ls_RFwdata;
    wire        ls_in_ready;
    wire        ls_out_valid;
    wire [31:0] ls_RFwdata_out;

    // Local handshake control
    wire        forward_pending;
    wire        forward_ex_A;
    wire        forward_ex_B;
    wire        forward_ls_A;
    wire        forward_ls_B;
    wire        ls_load_use_hazard;
    wire [4:0]  forward_id_rR1;
    wire [4:0]  forward_id_rR2;
    wire        forward_ex_RegWrite;
    wire        forward_ls_RegWrite;
    wire        forward_ls_load_pending;
    wire        ex_out_ready;
    wire        id_ready;
    wire        ex_in_ready;
    wire        id_issue_valid; // From IDU handshake output
    wire        ex_out_valid;   // From EXU handshake output

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
    `ifdef NPC_SIMULATION
    `ifndef SYNTHESIS
        reg [31:0] pc_EX, pc_LS;
        reg [31:0] inst_EX, inst_LS;
        reg [31:0] commit_next_pc_LS;
        wire        have_inst_ID_decode;
        wire        have_inst_ID;
        reg         have_inst_EX, have_inst_LS;
        assign have_inst_ID = id_valid && have_inst_ID_decode;
        wire commit_is_ebreak = ex_is_system &&
                                (ex_funct3 == 3'b000) &&
                                (ex_CSRaddr == 12'h001);
        wire commit_redirect = ex_CSRjump || ex_jtype || ex_ijtype ||
                               (ex_btype && ex_BRUResult);
        wire [31:0] commit_ex_next_pc =
            (commit_redirect && !commit_is_ebreak) ?
                (ex_CSRjump ? ex_CSRnpc : ex_ALUResult) : ex_pc4;
    `endif
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
        .ex_pc4                 (ex_pc4),
        .ex_btype               (ex_btype),
        .ex_jtype               (ex_jtype),
        .ex_ijtype              (ex_ijtype),
        .ex_BRUResult           (ex_BRUResult),
        .ex_ALUResult           (ex_ALUResult),
        .ex_CSRjump             (ex_CSRjump),
        .ex_CSRnpc              (ex_CSRnpc),
        .ex_FenceI              (ex_FenceI),

        .id_ready               (id_ready),
        .id_valid               (id_valid),
        .id_pc                  (id_pc),
        .id_inst                (id_inst),
        .flush                  (flush),
        .invalidate             (invalidate),

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

    ysyx_26030082_idu idu (
        .clock                  (clock),
        .reset                  (reset),
        .id_valid               (id_valid),
        .id_ready               (id_ready),
        .id_issue_valid         (id_issue_valid),
        .id_issue_ready         (ex_in_ready),
        .id_block               (forward_pending),

        .wen                    (ls_out_valid && ls_RegWrite),
        .waddr                  (ls_RFwaddr),
        .wdata                  (ls_RFwdata_out),
        .rR1_data               (id_rR1_data),
        .rR2_data               (id_rR2_data),

        .id_inst                (id_inst),

        .id_ALUControl          (id_ALUControl),
        .id_RegWrite            (id_RegWrite),
        .id_MemToReg            (id_MemToReg),
        .id_MemWrite            (id_MemWrite),
        .id_ALUSrcA             (id_ALUSrcA),
        .id_ALUSrcB             (id_ALUSrcB),
        .id_imm                 (id_imm),

        .id_btype               (id_btype),
        .id_jtype               (id_jtype),
        .id_ijtype              (id_ijtype),

        .id_is_system           (id_is_system),
        .id_CSRaddr             (id_CSRaddr),
        .id_FenceI              (id_FenceI)

        `ifdef NPC_SIMULATION
        `ifndef SYNTHESIS
        ,   .have_inst_ID       (have_inst_ID_decode)
        `endif
        `endif
    );

    // Forwarding and load-use hazard detection
    assign forward_id_rR1 = id_inst[19:15];
    assign forward_id_rR2 = id_inst[24:20];
    assign forward_ex_RegWrite = ex_in_valid && ex_RegWrite;
    assign forward_ls_RegWrite = ls_out_valid && ls_RegWrite;
    assign forward_ls_load_pending = ls_in_valid && ls_MemRead && ~ls_out_valid;

    assign forward_ex_A = (forward_id_rR1 == ex_RFwaddr) &&
                          forward_ex_RegWrite && ~(ex_RFwaddr == 5'd0);
    assign forward_ex_B = (forward_id_rR2 == ex_RFwaddr) &&
                          forward_ex_RegWrite && ~(ex_RFwaddr == 5'd0);
    assign forward_ls_A = (forward_id_rR1 == ls_RFwaddr) &&
                          forward_ls_RegWrite && ~(ls_RFwaddr == 5'd0);
    assign forward_ls_B = (forward_id_rR2 == ls_RFwaddr) &&
                          forward_ls_RegWrite && ~(ls_RFwaddr == 5'd0);
    assign ls_load_use_hazard = forward_ls_load_pending &&
                                (ls_RFwaddr != 5'b0) &&
                                ((forward_id_rR1 == ls_RFwaddr) ||
                                 (forward_id_rR2 == ls_RFwaddr));
    assign forward_pending = id_valid && (
                                (ex_out_valid && ex_MemRead &&
                                 (ex_RFwaddr != 5'd0) &&
                                 ((forward_id_rR1 == ex_RFwaddr) ||
                                  (forward_id_rR2 == ex_RFwaddr))) ||
                                ls_load_use_hazard
                             );

    assign id_rR1_data_forward = forward_ex_A ? ex_RFwdata :
                                 forward_ls_A ? ls_RFwdata_out : id_rR1_data;
    assign id_rR2_data_forward = forward_ex_B ? ex_RFwdata :
                                 forward_ls_B ? ls_RFwdata_out : id_rR2_data;

    // ================================================================
    // ID -> EX
    // ================================================================
    always @(posedge clock) begin
        if (reset) begin
            ex_in_valid        <= 1'b0;
        end else if (flush) begin
            ex_in_valid        <= 1'b0;
        end else if (ex_in_ready) begin
            ex_in_valid <= id_issue_valid;
            ex_ALUControl   <= id_ALUControl;
            ex_RegWrite     <= id_RegWrite;
            ex_MemWrite     <= id_MemWrite;
            ex_MemToReg     <= id_MemToReg;
            ex_funct3       <= id_inst[14:12];
            ex_imm          <= id_imm;
            ex_pc           <= id_pc;
            ex_RFwaddr      <= id_inst[11:7];
            ex_ALUSrcA      <= id_ALUSrcA;
            ex_ALUSrcB      <= id_ALUSrcB;
            ex_rR1_data     <= id_rR1_data_forward;
            ex_rR2_data     <= id_rR2_data_forward;
            ex_is_system    <= id_is_system;
            ex_CSRaddr      <= id_CSRaddr;
            ex_FenceI       <= id_FenceI;
            ex_btype        <= id_btype;
            ex_jtype        <= id_jtype;
            ex_ijtype       <= id_ijtype;
        end
    end

    //trace
    `ifdef NPC_SIMULATION
    `ifndef SYNTHESIS
        always @(posedge clock) begin
            if (reset) begin
                pc_EX <= 32'b0;
                inst_EX <= 32'b0;
                have_inst_EX <= 1'b0;
            end else if (flush) begin
                pc_EX <= 32'b0;
                inst_EX <= 32'b0;
                have_inst_EX <= 1'b0;
            end else if (ex_in_ready) begin
                if (id_issue_valid) begin
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
    `endif

    // EX -> LS handshake coupling
    assign ex_out_ready = ls_in_ready;

    ysyx_26030082_exu exu (
        .clock                  (clock),
        .reset                  (reset),
        .ex_in_valid            (ex_in_valid),
        .ex_in_ready            (ex_in_ready),
        .ex_out_valid           (ex_out_valid),
        .ex_out_ready           (ex_out_ready),

        .ex_ALUSrcA             (ex_ALUSrcA),
        .ex_ALUSrcB             (ex_ALUSrcB),
        .ex_pc                  (ex_pc),
        .ex_rR1_data            (ex_rR1_data),
        .ex_rR2_data            (ex_rR2_data),
        .ex_funct3              (ex_funct3),
        .ex_imm                 (ex_imm),
        .ex_ALUControl          (ex_ALUControl),

        .ex_is_system           (ex_is_system),
        .ex_CSRaddr             (ex_CSRaddr),

        .ex_MemToReg            (ex_MemToReg),

        .ex_ALUResult           (ex_ALUResult),
        .ex_BRUResult           (ex_BRUResult),
        .ex_pc4                 (ex_pc4),

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
            ls_in_valid <= 1'b0;
        end else if (ex_out_ready) begin
            ls_in_valid <= ex_out_valid;
            ls_RegWrite <= ex_RegWrite;
            ls_MemWrite <= ex_MemWrite;
            ls_ALUResult <= ex_ALUResult;
            ls_rR2_data <= ex_rR2_data;
            ls_funct3   <= ex_funct3;
            ls_RFwaddr  <= ex_RFwaddr;
            ls_RFwdata  <= ex_RFwdata;
            ls_MemRead  <= ex_MemRead;
        end
    end

    //trace
    `ifdef NPC_SIMULATION
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
                    commit_next_pc_LS <= commit_ex_next_pc;
                    have_inst_LS <= have_inst_EX;
                end else begin
                    pc_LS <= 32'b0;
                    inst_LS <= 32'b0;
                    commit_next_pc_LS <= 32'b0;
                    have_inst_LS <= 1'b0;
                end
            end
        end
    `endif
    `endif

    ysyx_26030082_lsu lsu (
        .clock                  (clock),
        .reset                  (reset),
        .ls_in_valid            (ls_in_valid),
        .ls_in_ready            (ls_in_ready),
        .ls_out_valid           (ls_out_valid),

        .ls_ALUResult           (ls_ALUResult),
        .ls_funct3              (ls_funct3),
        .ls_MemWrite            (ls_MemWrite),
        .ls_MemRead             (ls_MemRead),
        .ls_rR2_data            (ls_rR2_data),
        .ls_RFwdata             (ls_RFwdata),

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

        .ls_RFwdata_out         (ls_RFwdata_out)
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

`ifdef NPC_SIMULATION
`ifndef SYNTHESIS
`ifndef __ICARUS__
    int unsigned commit_gpr[32];

    always @(posedge clock) begin
        if (!reset && ls_out_valid && have_inst_LS) begin
            // The RF write below is an NBA update on this same edge.  Build
            // the state visible to DiffTest from the old RF contents, then
            // override the one write that retires on this edge.  CSR updates
            // are also NBAs, so the current CSR values are the state after
            // all older instructions and before any younger EX instruction.
                commit_gpr[0] = 32'b0;
                for (int i = 1; i < 16; i++) begin
                    commit_gpr[i] = idu.reg_bank[i];
                end
                for (int i = 16; i < 32; i++) begin
                    commit_gpr[i] = 32'b0;
                end
                if (ls_RegWrite && (ls_RFwaddr != 5'd0) && !ls_RFwaddr[4]) begin
                    commit_gpr[ls_RFwaddr] = ls_RFwdata_out;
                end
                npc_commit(
                    pc_LS,
                    inst_LS,
                    commit_next_pc_LS,
                    exu.mstatus,
                    exu.mtvec,
                    exu.mepc,
                    exu.mcause,
                    commit_gpr
                );
        end
    end
`endif
`endif
`endif

    // ================================================================
    // PMU hooks (simulation-only, kept at module tail to avoid clutter)
    // ================================================================
`ifdef NPC_SIMULATION
`ifndef SYNTHESIS
`ifndef __ICARUS__
`ifdef NPC_ENABLE_PERF
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
    assign pmu_ifu_r_fire = id_valid && id_ready;
    assign pmu_ifu_nosupply = !pmu_ifu_r_fire;
    assign pmu_lsu_r_fire = lsu.r_fire;
    assign pmu_lsu_load_req = (lsu.state == PMU_LSU_IDLE) && ls_in_valid && lsu.ls_is_load;
    assign pmu_lsu_load_pending = (lsu.state == PMU_LSU_RD_AR) || (lsu.state == PMU_LSU_RD_WAIT_R);
    assign pmu_exu_done_fire = ex_out_valid && ex_out_ready;
    assign pmu_dec_total = !flush && id_issue_valid && ex_in_ready && have_inst_ID;
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
                if (flush || ifu.need_flush) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_REDIRECT_DROP;
                end else if (id_valid && !id_ready) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_ID_BACKPRESSURE;
                end else if (ifu_axi_arvalid && !ifu_axi_arready) begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_WAIT_ARREADY;
                end else begin
                    pmu_event_mask = pmu_event_mask | PMU_EVT_IFU_WAIT_RVALID;
                end
            end
            if (ifu.lookup_resp_valid) begin
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
