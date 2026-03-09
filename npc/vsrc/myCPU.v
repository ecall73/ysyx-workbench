`timescale 1ns / 1ps

`include "defines.v"

module myCPU (
    input  wire        clk,
    input  wire        rst,
    input  wire        external_stall,

    input  wire [ 3:0] exception,
    input  wire [ 3:0] interrupt,

    // Interface to IROM
    output wire [31:0] irom_addr,
    output wire        irom_ren,
    input  wire [31:0] irom_data,
    
    // Interface to Bridge
    output wire [31:0] perip_addr,
    input  wire [31:0] perip_rdata,
    output wire [ 2:0] perip_mask,
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
    wire [31:0] if_pc;
    wire [31:0] if_pc4;
    wire [31:0] if_inst;
    // ID
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
    wire        id_m_en;
    wire [ 2:0] id_MDUControl;
    wire        id_CSRSrc;
    wire [11:0] id_CSRaddr;
    wire [ 4:0] id_CSRControl;
    // EX
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
    wire        ex_ALUisTrue;
    wire [31:0] ex_RFwdata;
    reg         ex_m_en;
    reg  [ 2:0] ex_MDUControl;
    reg         ex_CSRSrc;
    reg  [11:0] ex_CSRaddr;
    reg  [ 4:0] ex_CSRControl;
    wire [31:0] ex_CSRnpc;
    wire        ex_CSRjump;
    // ME1
    reg         me1_RegWrite;
    reg         me1_MemRead; 
    reg         me1_MemWrite;
    reg  [31:0] me1_rR2_data;
    reg  [ 2:0] me1_mask;
    reg  [ 4:0] me1_RFwaddr;
    reg  [31:0] me1_ALUResult;
    reg         me1_ALUisTrue;
    reg  [31:0] me1_RFwdata; 
    reg  [31:0] me1_CSRnpc;
    reg         me1_CSRjump;
    // ME2
    wire        me2_RegWrite;
    wire [ 4:0] me2_RFwaddr;
    wire [31:0] me2_RFwdata;
    // WB
    reg         wb_RegWrite;
    reg  [ 4:0] wb_RFwaddr;
    reg  [31:0] wb_RFwdata;

    // Hazard
    wire        waste1, waste3;
    wire        MDUStall;
    wire        stall_PC, stall_IF_ID, stall_ID_EX;
    wire        flush_IF_ID, flush_ID_EX, flush_EX_ME1;

    // Debug Interface
    `ifdef RUN_TRACE
        reg [31:0] pc_EX, pc_ME1, pc_ME2, pc_WB;
        wire        have_inst_ID;
        reg         have_inst_EX, have_inst_ME1, have_inst_ME2, have_inst_WB;
        wire        id_ebreak = (id_inst == 32'h00100073);
        reg         ex_ebreak, me1_ebreak, me2_ebreak, wb_ebreak;
    `endif

    
////////////////////////////////////////////////////////////////

    predict u_predict (
        .clk                    (clk),
        .rst                    (rst),

        .flush_ID_EX            (flush_ID_EX),
        .flush_EX_ME1           (flush_EX_ME1),
        .stall_ID_EX            (stall_ID_EX),

        .if_pc4                 (if_pc4),
        
        .id_pc                  (id_pc),
        .id_pc4                 (id_pc4),
        .id_inst                (id_inst),

        .me1_ALUisTrue          (me1_ALUisTrue),
        .me1_ALUResult          (me1_ALUResult),
        .me1_CSRjump            (me1_CSRjump),
        .me1_CSRnpc             (me1_CSRnpc),

        .npc                    (npc),
        .waste1                 (waste1),
        .waste3                 (waste3)
    );

    ifu u_ifu (
        .clk                    (clk),
        .rst                    (rst),
        .stall_PC               (stall_PC),

        .irom_data              (irom_data),
        .irom_addr              (irom_addr),
        .irom_ren               (irom_ren),

        .if_pc                  (if_pc),
        .if_pc4                 (if_pc4),
        .if_inst                (if_inst),

        .npc                    (npc)
    );

    // IF: Instruction Fetch

    // IF - IROM
    // (Handled inside ifu)

    // ID: Instruction Decode

    // Expanded IF_ID register logic
    always @(posedge clk) begin
        if(rst) begin
            id_pc   <= 0;
            id_pc4  <= 0;
            id_inst <= 0;
        end else if(flush_IF_ID) begin
            id_pc   <= 0;
            id_pc4  <= 0;
            id_inst <= 0;
        end else if(stall_IF_ID) begin
            id_pc   <= id_pc;
            id_pc4  <= id_pc4;
            id_inst <= id_inst;
        end else begin
            id_pc   <= if_pc;
            id_pc4  <= if_pc4;
            id_inst <= if_inst;
        end
    end

    idu u_idu (
        .clk                    (clk),
        .rst                    (rst),

        .id_inst                (id_inst),

        .wb_RegWrite            (wb_RegWrite),
        .wb_RFwaddr             (wb_RFwaddr),
        .wb_RFwdata             (wb_RFwdata),

        .id_ALUControl          (id_ALUControl),
        .id_RegWrite            (id_RegWrite),
        .id_MemToReg            (id_MemToReg),
        .id_MemWrite            (id_MemWrite),
        .id_ALUSrcA             (id_ALUSrcA),
        .id_ALUSrcB             (id_ALUSrcB),
        .id_imm                 (id_imm),
        .id_rR1_data            (id_rR1_data),
        .id_rR2_data            (id_rR2_data),

        .id_m_en                (id_m_en),
        .id_MDUControl          (id_MDUControl),

        .id_CSRSrc              (id_CSRSrc),
        .id_CSRaddr             (id_CSRaddr),
        .id_CSRControl          (id_CSRControl)

        `ifdef RUN_TRACE
        ,   .have_inst_ID       (have_inst_ID)
        ,   .id_reg_file        (debug_reg_file)
        `endif
    );

    forward u_forward (
        .id_rR1                 (id_inst[19:15]),
        .id_rR2                 (id_inst[24:20]),
        .id_rR1_data            (id_rR1_data),
        .id_rR2_data            (id_rR2_data),

        .ex_RegWrite            (ex_RegWrite),
        .ex_RFwaddr             (ex_RFwaddr),
        .ex_RFwdata             (ex_RFwdata),

        .me1_RegWrite           (me1_RegWrite),
        .me1_RFwaddr            (me1_RFwaddr),
        .me1_RFwdata            (me1_RFwdata),

        .me2_RegWrite           (me2_RegWrite),
        .me2_RFwaddr            (me2_RFwaddr),
        .me2_RFwdata            (me2_RFwdata),

        .wb_RegWrite            (wb_RegWrite),
        .wb_RFwaddr             (wb_RFwaddr),
        .wb_RFwdata             (wb_RFwdata),

        .id_rR1_data_forward    (id_rR1_data_forward),
        .id_rR2_data_forward    (id_rR2_data_forward)
    );

    // EX: Execute

    // Expanded ID_EX register logic
    always @(posedge clk) begin
        if(rst) begin
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

            ex_CSRSrc      <= 0;
            ex_CSRaddr      <= 0;
            ex_CSRControl   <= 0;

            ex_m_en         <= 0;
            ex_MDUControl   <= 0;
        end else if(flush_ID_EX) begin
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

            ex_CSRSrc      <= 0;
            ex_CSRaddr      <= 0;
            ex_CSRControl   <= 0;

            ex_m_en         <= 0;
            ex_MDUControl   <= 0;
        end else if(stall_ID_EX) begin
            ex_ALUControl   <= ex_ALUControl;
            ex_RegWrite     <= ex_RegWrite;
            ex_MemWrite     <= ex_MemWrite;
            ex_MemToReg     <= ex_MemToReg;
            ex_mask         <= ex_mask;
            ex_imm          <= ex_imm;
            ex_pc           <= ex_pc;
            ex_pc4          <= ex_pc4;
            ex_RFwaddr      <= ex_RFwaddr;
            ex_ALUSrcA      <= ex_ALUSrcA;
            ex_ALUSrcB      <= ex_ALUSrcB;
            ex_rR1_data     <= ex_rR1_data;
            ex_rR2_data     <= ex_rR2_data;

            ex_CSRSrc      <= ex_CSRSrc;
            ex_CSRaddr      <= ex_CSRaddr;
            ex_CSRControl   <= ex_CSRControl;

            ex_m_en         <= ex_m_en;
            ex_MDUControl   <= ex_MDUControl;
        end else begin
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

            ex_CSRSrc      <= id_CSRSrc;
            ex_CSRaddr      <= id_CSRaddr;
            ex_CSRControl   <= id_CSRControl;

            ex_m_en         <= id_m_en;
            ex_MDUControl   <= id_MDUControl;
        end
    end

    //trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst)        pc_EX <= 32'b0;
            else if (flush_ID_EX) pc_EX <= 32'b0;
            else if (stall_ID_EX) pc_EX <= pc_EX;
            else            pc_EX <= id_pc;
        end
        always @(posedge clk) begin
            if (rst)        have_inst_EX <= 1'b0;
            else if(flush_ID_EX)  have_inst_EX <= 1'b0;
            else if(stall_ID_EX)  have_inst_EX <= have_inst_EX;
            else            have_inst_EX <= have_inst_ID;
        end
        always @(posedge clk) begin
            if (rst)        ex_ebreak <= 1'b0;
            else if(flush_ID_EX)  ex_ebreak <= 1'b0;
            else if(stall_ID_EX)  ex_ebreak <= ex_ebreak;
            else            ex_ebreak <= id_ebreak;
        end
    `endif

    exu u_exu (
        .clk                    (clk),
        .rst                    (rst),

        .flush_ID_EX            (flush_ID_EX),
        .flush_EX_ME1           (flush_EX_ME1),

        .exception              (exception),
        .interrupt              (interrupt),

        .ex_ALUSrcA             (ex_ALUSrcA),
        .ex_ALUSrcB             (ex_ALUSrcB),
        .ex_pc                  (ex_pc),
        .ex_pc4                 (ex_pc4),
        .ex_rR1_data            (ex_rR1_data),
        .ex_rR2_data            (ex_rR2_data),
        .ex_imm                 (ex_imm),
        .ex_ALUControl          (ex_ALUControl),

        .ex_m_en                (ex_m_en),
        .ex_MDUControl          (ex_MDUControl),

        .ex_CSRSrc              (ex_CSRSrc),
        .ex_CSRaddr             (ex_CSRaddr),
        .ex_CSRControl          (ex_CSRControl),

        .ex_MemToReg            (ex_MemToReg),

        .ex_ALUResult           (ex_ALUResult),
        .ex_ALUisTrue           (ex_ALUisTrue),
        .MDUStall               (MDUStall),

        .ex_CSRjump             (ex_CSRjump),
        .ex_CSRnpc              (ex_CSRnpc),

        .ex_RFwdata             (ex_RFwdata),
        .ex_MemRead             (ex_MemRead)
    );

    // MEM: DRAM

    // Expanded EX_ME1 register logic
    always @(posedge clk) begin
        if (rst) begin
            me1_RegWrite        <= 0;
            me1_MemWrite        <= 0;
            me1_ALUResult       <= 0;
            me1_rR2_data        <= 0;
            me1_mask            <= 0;
            me1_RFwaddr         <= 0;
            me1_RFwdata         <= 0;
            me1_MemRead         <= 0;
            me1_ALUisTrue       <= 0;

            me1_CSRjump        <= 0;
            me1_CSRnpc         <= 0;
        end else if(flush_EX_ME1) begin
            me1_RegWrite        <= 0;
            me1_MemWrite        <= 0;
            me1_ALUResult       <= 0;
            me1_rR2_data        <= 0;
            me1_mask            <= 0;
            me1_RFwaddr         <= 0;
            me1_RFwdata         <= 0;
            me1_MemRead         <= 0;
            me1_ALUisTrue       <= 0;

            me1_CSRjump         <= 0;
            me1_CSRnpc          <= 0;
        end else begin
            me1_RegWrite        <= ex_RegWrite && ~ex_CSRjump;
            me1_MemWrite        <= ex_MemWrite && ~ex_CSRjump;
            me1_ALUResult       <= ex_ALUResult;
            me1_rR2_data        <= ex_rR2_data;
            me1_mask            <= ex_mask;
            me1_RFwaddr         <= ex_RFwaddr;
            me1_RFwdata         <= ex_RFwdata;
            me1_MemRead         <= ex_MemRead;
            me1_ALUisTrue       <= ex_ALUisTrue;

            me1_CSRjump         <= ex_CSRjump;
            me1_CSRnpc          <= ex_CSRnpc;
        end
    end

    //trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst)        pc_ME1 <= 32'b0;
            else if (flush_EX_ME1) pc_ME1 <= 32'b0;
            else            pc_ME1 <= pc_EX;
        end
        always @(posedge clk) begin
            if (rst)        have_inst_ME1 <= 1'b0;
            else if(flush_EX_ME1)  have_inst_ME1 <= 1'b0;
            else            have_inst_ME1 <= have_inst_EX;
        end
        always @(posedge clk) begin
            if (rst)        me1_ebreak <= 1'b0;
            else if(flush_EX_ME1)  me1_ebreak <= 1'b0;
            else            me1_ebreak <= ex_ebreak;
        end
    `endif

    // MEM - DRAM
    // Handled inside lsu

    lsu u_lsu (
        .clk                    (clk),
        .rst                    (rst),

        .me1_ALUResult          (me1_ALUResult),
        .me1_mask               (me1_mask),
        .me1_MemWrite           (me1_MemWrite),
        .me1_MemRead            (me1_MemRead),
        .me1_rR2_data           (me1_rR2_data),

        .me1_RegWrite           (me1_RegWrite),
        .me1_RFwaddr            (me1_RFwaddr),
        .me1_RFwdata            (me1_RFwdata),

        .perip_rdata            (perip_rdata),
        .perip_addr             (perip_addr),
        .perip_mask             (perip_mask),
        .perip_wen              (perip_wen),
        .perip_ren              (perip_ren),
        .perip_wdata            (perip_wdata),

        .me2_RegWrite           (me2_RegWrite), 
        .me2_RFwaddr            (me2_RFwaddr),
        .me2_RFwdata            (me2_RFwdata)

        `ifdef RUN_TRACE
        ,   .pc_ME1             (pc_ME1),
            .have_inst_ME1      (have_inst_ME1),
            .me1_ebreak         (me1_ebreak),
            .pc_ME2             (pc_ME2),
            .have_inst_ME2      (have_inst_ME2),
            .me2_ebreak         (me2_ebreak)
        `endif
    );

    // WB: Write Back

    // Expanded ME2_WB register logic
    always @(posedge clk) begin
        if(rst) begin
            wb_RegWrite     <= 0;
            wb_RFwaddr      <= 0;
            wb_RFwdata      <= 0;
        end else begin
            wb_RegWrite     <= me2_RegWrite;
            wb_RFwaddr      <= me2_RFwaddr;
            wb_RFwdata      <= me2_RFwdata;
        end
    end


    //trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst)    pc_WB <= 32'b0;
            else        pc_WB <= pc_ME2;
        end
        always @(posedge clk) begin
            if (rst)    have_inst_WB <= 1'b0;
            else        have_inst_WB <= have_inst_ME2;
        end
        always @(posedge clk) begin
            if (rst)    wb_ebreak <= 1'b0;
            else        wb_ebreak <= me2_ebreak;
        end
    `endif

    Hazard u_Hazard (
        .MDUStall               (MDUStall),
        .external_stall         (external_stall),

        .id_rR1                 (id_inst[19:15]),
        .id_rR2                 (id_inst[24:20]),
        
        .ex_MemRead             (ex_MemRead),
        .ex_RFwaddr             (ex_RFwaddr),
        
        .me1_MemRead            (me1_MemRead),
        .me1_RFwaddr            (me1_RFwaddr),

        .waste1                 (waste1),
        .waste3                 (waste3),

        .stall_PC               (stall_PC),
        .stall_IF_ID            (stall_IF_ID),
        .stall_ID_EX            (stall_ID_EX),

        .flush_IF_ID            (flush_IF_ID),
        .flush_ID_EX            (flush_ID_EX),
        .flush_EX_ME1           (flush_EX_ME1)
    );

    // Debug Interface
    `ifdef RUN_TRACE
        assign debug_wb_have_inst = have_inst_WB;
        assign debug_wb_pc        = pc_WB;
        assign debug_wb_ena       = wb_RegWrite;
        assign debug_wb_reg       = wb_RFwaddr;
        assign debug_wb_value     = wb_RFwdata;
        assign debug_wb_ebreak    = wb_ebreak;
    `endif

endmodule
