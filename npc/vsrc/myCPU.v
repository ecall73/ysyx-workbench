`timescale 1ns / 1ps

`include "defines.v"

module myCPU (
    input  wire        clk,
    input  wire        rst,

    // Interface to IROM
    output wire [31:0] irom_addr,
    output wire        irom_ren,
    input  wire [31:0] irom_data,
    
    // Interface to Bridge
    output wire [31:0] perip_addr,
    input  wire [31:0] perip_rdata,
    output wire [ 3:0] perip_wmask,
    output wire        perip_ren,
    output wire        perip_wen,
    output wire [31:0] perip_wdata

    // Debug Interface
    `ifdef RUN_TRACE
       ,output wire        debug_wb_have_inst,
        output wire [31:0] debug_wb_pc,
        output wire        debug_wb_ena,
        output wire [ 4:0] debug_wb_reg,
        output wire [31:0] debug_wb_value,
        output wire        debug_wb_ebreak,
        output wire [31:0] debug_reg_file [0:31]
    `endif
);

    wire [31:0] npc;

    // IF
    wire        if_in_valid;
    wire        if_in_ready;
    wire        if_out_valid;
    wire [31:0] if_pc;
    wire [31:0] if_pc4;
    wire [31:0] if_inst;
    wire        if_out_ready;

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
    wire [31:0] ex_CSRnpc;
    wire        ex_CSRjump;

    // LS1
    reg         ls1_in_valid;
    reg         ls1_RegWrite;
    reg         ls1_MemRead; 
    reg         ls1_MemWrite;
    reg  [31:0] ls1_rR2_data;
    reg  [ 2:0] ls1_mask;
    reg  [ 4:0] ls1_RFwaddr;
    reg  [31:0] ls1_ALUResult;
    reg         ls1_ALUisTrue;
    reg  [31:0] ls1_RFwdata; 
    reg  [31:0] ls1_CSRnpc;
    reg         ls1_CSRjump;
    reg         ls1_btype;
    reg         ls1_jtype;
    reg         ls1_ijtype;
    reg  [31:0] ls1_btype_target;

    // LS2
    wire        ls2_out_valid;
    wire        ls2_out_ready;
    wire        ls2_RegWrite;
    wire [ 4:0] ls2_RFwaddr;
    wire [31:0] ls2_RFwdata;

    // WB
    reg         wb_in_valid;
    reg         wb_RegWrite;
    reg  [ 4:0] wb_RFwaddr;
    reg  [31:0] wb_RFwdata;

    // Local handshake control
    wire        waste2;
    wire        redirect_flush;
    wire        lw_ID_EX;
    wire        lw_ID_LS1;
    wire        id_block;
    wire        ex_out_ready;
    wire        id_in_ready;
    wire        ex_in_ready;
    wire        ls1_in_ready;
    wire        id_out_valid;   // From IDU handshake output
    wire        ex_out_valid;   // From EXU handshake output
    wire        ls1_out_valid;

    // Debug Interface
    `ifdef RUN_TRACE
        reg [31:0] pc_EX, pc_LS1, pc_LS2, pc_WB;
        wire        have_inst_ID_decode;
        wire        have_inst_ID;
        reg         have_inst_EX, have_inst_LS1, have_inst_LS2, have_inst_WB;
        wire        id_ebreak;
        reg         ex_ebreak, ls1_ebreak, ls2_ebreak, wb_ebreak;
        assign have_inst_ID = id_in_valid && have_inst_ID_decode;
        assign id_ebreak = id_in_valid && (id_inst == 32'h00100073);
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
    assign redirect_flush = ex_out_valid && waste2;

    // IF stage handshake defaults
    assign if_in_valid = 1'b1;
    assign if_out_ready = id_in_ready;

    ifu u_ifu (
        .clk                    (clk),
        .rst                    (rst),
        .if_in_valid            (if_in_valid),
        .if_in_ready            (if_in_ready),
        .if_out_ready           (if_out_ready),
        .redirect_flush         (redirect_flush),

        .irom_data              (irom_data),
        .irom_addr              (irom_addr),
        .irom_ren               (irom_ren),

        .if_out_valid           (if_out_valid),
        .if_pc                  (if_pc),
        .if_pc4                 (if_pc4),
        .if_inst                (if_inst),

        .npc                    (npc)
    );

    // ================================================================
    // IF -> ID
    // ================================================================
    always @(posedge clk) begin
        if (rst) begin
            id_in_valid <= 1'b0;
            id_pc    <= 32'b0;
            id_pc4   <= 32'b0;
            id_inst  <= 32'b0;
        end else if (redirect_flush) begin
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

    // ID stage RAW(load-use) hazard check
    assign lw_ID_EX = id_in_valid && ex_out_valid && ex_MemRead &&
                      ((id_inst[19:15] == ex_RFwaddr) || (id_inst[24:20] == ex_RFwaddr));
    assign lw_ID_LS1 = id_in_valid && ls1_out_valid && ls1_MemRead &&
                       ((id_inst[19:15] == ls1_RFwaddr) || (id_inst[24:20] == ls1_RFwaddr));
    assign id_block = lw_ID_EX || lw_ID_LS1;

    idu u_idu (
        .clk                    (clk),
        .rst                    (rst),
        .id_in_valid            (id_in_valid),
        .id_in_ready            (id_in_ready),
        .id_out_valid           (id_out_valid),
        .id_out_ready           (ex_in_ready),
        .id_block               (id_block),

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
        .id_CSRControl          (id_CSRControl)

        `ifdef RUN_TRACE
        ,   .have_inst_ID       (have_inst_ID_decode)
        `endif
    );

    RF u_RF (
        .clk                    (clk),
        .rst                    (rst),

        .wen                    (wb_in_valid && wb_RegWrite),
        .waddr                  (wb_RFwaddr),
        .wdata                  (wb_RFwdata),

        .rR1                    (id_inst[19:15]),
        .rR2                    (id_inst[24:20]),

        .rR1_data               (id_rR1_data),
        .rR2_data               (id_rR2_data)

        `ifdef RUN_TRACE
        ,.reg_file              (debug_reg_file)
        `endif
    );

    forward u_forward (
        .id_rR1                 (id_inst[19:15]),
        .id_rR2                 (id_inst[24:20]),
        .id_rR1_data            (id_rR1_data),
        .id_rR2_data            (id_rR2_data),

        .ex_RegWrite            (ex_in_valid && ex_RegWrite),
        .ex_RFwaddr             (ex_RFwaddr),
        .ex_RFwdata             (ex_RFwdata),

        .ls1_RegWrite           (ls1_in_valid && ls1_RegWrite),
        .ls1_RFwaddr            (ls1_RFwaddr),
        .ls1_RFwdata            (ls1_RFwdata),

        .ls2_RegWrite           (ls2_out_valid && ls2_RegWrite),
        .ls2_RFwaddr            (ls2_RFwaddr),
        .ls2_RFwdata            (ls2_RFwdata),

        .wb_RegWrite            (wb_in_valid && wb_RegWrite),
        .wb_RFwaddr             (wb_RFwaddr),
        .wb_RFwdata             (wb_RFwdata),

        .id_rR1_data_forward    (id_rR1_data_forward),
        .id_rR2_data_forward    (id_rR2_data_forward)
    );

    // ================================================================
    // ID -> EX
    // ================================================================
    always @(posedge clk) begin
        if (rst) begin
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
            ex_btype        <= 0;
            ex_jtype        <= 0;
            ex_ijtype       <= 0;
        end else if (redirect_flush) begin
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
                ex_btype        <= 0;
                ex_jtype        <= 0;
                ex_ijtype       <= 0;
            end
        end
    end

    //trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst) begin
                pc_EX <= 32'b0;
                have_inst_EX <= 1'b0;
                ex_ebreak <= 1'b0;
            end else if (redirect_flush) begin
                pc_EX <= 32'b0;
                have_inst_EX <= 1'b0;
                ex_ebreak <= 1'b0;
            end else if (ex_in_ready) begin
                if (id_out_valid) begin
                    pc_EX <= id_pc;
                    have_inst_EX <= have_inst_ID;
                    ex_ebreak <= id_ebreak;
                end else begin
                    pc_EX <= 32'b0;
                    have_inst_EX <= 1'b0;
                    ex_ebreak <= 1'b0;
                end
            end
        end
    `endif

    // EX -> LS1 handshake coupling
    assign ex_out_ready = ls1_in_ready;

    exu u_exu (
        .clk                    (clk),
        .rst                    (rst),
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
    // EX -> LS1
    // ================================================================
    always @(posedge clk) begin
        if (rst) begin
            ls1_in_valid           <= 1'b0;
            ls1_RegWrite        <= 0;
            ls1_MemWrite        <= 0;
            ls1_ALUResult       <= 0;
            ls1_rR2_data        <= 0;
            ls1_mask            <= 0;
            ls1_RFwaddr         <= 0;
            ls1_RFwdata         <= 0;
            ls1_MemRead         <= 0;
            ls1_ALUisTrue       <= 0;
            ls1_CSRjump         <= 0;
            ls1_CSRnpc          <= 0;
            ls1_btype           <= 0;
            ls1_jtype           <= 0;
            ls1_ijtype          <= 0;
            ls1_btype_target    <= 0;
        end else if (ex_out_ready) begin
            ls1_in_valid <= ex_out_valid;
            if (ex_out_valid) begin
                ls1_RegWrite        <= ex_RegWrite;
                ls1_MemWrite        <= ex_MemWrite;
                ls1_ALUResult       <= ex_ALUResult;
                ls1_rR2_data        <= ex_rR2_data;
                ls1_mask            <= ex_mask;
                ls1_RFwaddr         <= ex_RFwaddr;
                ls1_RFwdata         <= ex_RFwdata;
                ls1_MemRead         <= ex_MemRead;
                ls1_ALUisTrue       <= ex_ALUisTrue;
                ls1_CSRjump         <= ex_CSRjump;
                ls1_CSRnpc          <= ex_CSRnpc;
                ls1_btype           <= ex_btype;
                ls1_jtype           <= ex_jtype;
                ls1_ijtype          <= ex_ijtype;
                ls1_btype_target    <= ex_BranchTarget;
            end else begin
                ls1_RegWrite        <= 0;
                ls1_MemWrite        <= 0;
                ls1_ALUResult       <= 0;
                ls1_rR2_data        <= 0;
                ls1_mask            <= 0;
                ls1_RFwaddr         <= 0;
                ls1_RFwdata         <= 0;
                ls1_MemRead         <= 0;
                ls1_ALUisTrue       <= 0;
                ls1_CSRjump         <= 0;
                ls1_CSRnpc          <= 0;
                ls1_btype           <= 0;
                ls1_jtype           <= 0;
                ls1_ijtype          <= 0;
                ls1_btype_target    <= 0;
            end
        end
    end

    //trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst) begin
                pc_LS1 <= 32'b0;
                have_inst_LS1 <= 1'b0;
                ls1_ebreak <= 1'b0;
            end else if (ex_out_ready) begin
                if (ex_out_valid) begin
                    pc_LS1 <= pc_EX;
                    have_inst_LS1 <= have_inst_EX;
                    ls1_ebreak <= ex_ebreak;
                end else begin
                    pc_LS1 <= 32'b0;
                    have_inst_LS1 <= 1'b0;
                    ls1_ebreak <= 1'b0;
                end
            end
        end
    `endif

    // LS2 -> WB handshake coupling (WB always ready in current design)
    assign ls2_out_ready = 1'b1;

    lsu u_lsu (
        .clk                    (clk),
        .rst                    (rst),

        .ls1_in_valid           (ls1_in_valid),
        .ls1_in_ready           (ls1_in_ready),
        .ls1_out_valid          (ls1_out_valid),
        .ls2_out_valid          (ls2_out_valid),
        .ls2_out_ready          (ls2_out_ready),

        .ls1_ALUResult          (ls1_ALUResult),
        .ls1_mask               (ls1_mask),
        .ls1_MemWrite           (ls1_MemWrite),
        .ls1_MemRead            (ls1_MemRead),
        .ls1_rR2_data           (ls1_rR2_data),

        .ls1_RegWrite           (ls1_RegWrite),
        .ls1_RFwaddr            (ls1_RFwaddr),
        .ls1_RFwdata            (ls1_RFwdata),

        .perip_rdata            (perip_rdata),
        .perip_addr             (perip_addr),
        .perip_wmask            (perip_wmask),
        .perip_wen              (perip_wen),
        .perip_ren              (perip_ren),
        .perip_wdata            (perip_wdata),

        .ls2_RegWrite           (ls2_RegWrite), 
        .ls2_RFwaddr            (ls2_RFwaddr),
        .ls2_RFwdata            (ls2_RFwdata)

        `ifdef RUN_TRACE
        ,   .pc_LS1             (pc_LS1),
            .have_inst_LS1      (have_inst_LS1),
            .ls1_ebreak         (ls1_ebreak),
            .pc_LS2             (pc_LS2),
            .have_inst_LS2      (have_inst_LS2),
            .ls2_ebreak         (ls2_ebreak)
        `endif
    );

    // ================================================================
    // LS2 -> WB
    // ================================================================
    always @(posedge clk) begin
        if (rst) begin
            wb_in_valid        <= 1'b0;
            wb_RegWrite     <= 1'b0;
            wb_RFwaddr      <= 5'b0;
            wb_RFwdata      <= 32'b0;
        end else begin
            wb_in_valid <= ls2_out_valid;
            if (ls2_out_valid) begin
                wb_RegWrite     <= ls2_RegWrite;
                wb_RFwaddr      <= ls2_RFwaddr;
                wb_RFwdata      <= ls2_RFwdata;
            end else begin
                wb_RegWrite     <= 1'b0;
                wb_RFwaddr      <= 5'b0;
                wb_RFwdata      <= 32'b0;
            end
        end
    end

    //trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst) begin
                pc_WB <= 32'b0;
                have_inst_WB <= 1'b0;
                wb_ebreak <= 1'b0;
            end else begin
                if (ls2_out_valid) begin
                    pc_WB <= pc_LS2;
                    have_inst_WB <= have_inst_LS2;
                    wb_ebreak <= ls2_ebreak;
                end else begin
                    pc_WB <= 32'b0;
                    have_inst_WB <= 1'b0;
                    wb_ebreak <= 1'b0;
                end
            end
        end
    `endif

    // Debug Interface
    `ifdef RUN_TRACE
        assign debug_wb_have_inst = wb_in_valid && have_inst_WB;
        assign debug_wb_pc        = pc_WB;
        assign debug_wb_ena       = wb_in_valid && wb_RegWrite;
        assign debug_wb_reg       = wb_RFwaddr;
        assign debug_wb_value     = wb_RFwdata;
        assign debug_wb_ebreak    = wb_in_valid && wb_ebreak;
    `endif

endmodule
