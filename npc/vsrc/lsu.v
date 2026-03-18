`timescale 1ns / 1ps
`include "defines.v"

module lsu (
    input  wire        clk,
    input  wire        rst,

    // ME1 Stage inputs
    input  wire [31:0] me1_ALUResult,
    input  wire [ 2:0] me1_mask,
    input  wire        me1_MemWrite,
    input  wire        me1_MemRead,
    input  wire [31:0] me1_rR2_data,

    input  wire        me1_RegWrite,
    input  wire [ 4:0] me1_RFwaddr,
    input  wire [31:0] me1_RFwdata,

    // Peripheral Interface
    input  wire [31:0] perip_rdata,
    output wire [31:0] perip_addr,
    output wire [ 3:0] perip_wmask,
    output wire        perip_wen,
    output wire        perip_ren,
    output wire [31:0] perip_wdata,

    // ME2 Stage outputs
    output reg         me2_RegWrite,
    output reg  [ 4:0] me2_RFwaddr,
    output wire [31:0] me2_RFwdata

    `ifdef RUN_TRACE
    ,   input  wire [31:0] pc_ME1,
        input  wire        have_inst_ME1,
        input  wire        me1_ebreak,
        output reg  [31:0] pc_ME2,
        output reg         have_inst_ME2,
        output reg         me2_ebreak
    `endif
);

    reg [31:0] me2_RFwdata_tmp;
    reg        me2_MemRead;
    reg [ 2:0] me2_mask;
    reg [ 1:0] me2_offset;

    // ================================================================
    // ME1: Write masking and address preparation
    // ================================================================
    wire [ 1:0] me1_offset;
    reg  [ 3:0] me1_wmask;
    reg  [31:0] me1_wdata_aligned;

    assign me1_offset  = me1_ALUResult[1:0];
    assign perip_addr  = {me1_ALUResult[31:2], 2'b0};  // Word-aligned address
    assign perip_wmask = me1_wmask;
    assign perip_wen   = me1_MemWrite;
    assign perip_ren   = me1_MemRead;
    assign perip_wdata = me1_wdata_aligned;

    // Generate write mask and aligned data based on mask type and offset
    always @(*) begin
        me1_wmask = 4'b0000;
        me1_wdata_aligned = me1_rR2_data;
        case (me1_mask)
            3'b000: begin // sb
                case (me1_offset)
                    2'b00: begin
                        me1_wmask = 4'b0001;
                        me1_wdata_aligned = {24'b0, me1_rR2_data[7:0]};
                    end
                    2'b01: begin
                        me1_wmask = 4'b0010;
                        me1_wdata_aligned = {16'b0, me1_rR2_data[7:0], 8'b0};
                    end
                    2'b10: begin
                        me1_wmask = 4'b0100;
                        me1_wdata_aligned = {8'b0, me1_rR2_data[7:0], 16'b0};
                    end
                    2'b11: begin
                        me1_wmask = 4'b1000;
                        me1_wdata_aligned = {me1_rR2_data[7:0], 24'b0};
                    end
                endcase
            end
            3'b001: begin // sh
                case (me1_offset[1])
                    1'b0: begin
                        me1_wmask = 4'b0011;
                        me1_wdata_aligned = {16'b0, me1_rR2_data[15:0]};
                    end
                    1'b1: begin
                        me1_wmask = 4'b1100;
                        me1_wdata_aligned = {me1_rR2_data[15:0], 16'b0};
                    end
                endcase
            end
            default: begin // sw
                me1_wmask = 4'b1111;
                me1_wdata_aligned = me1_rR2_data;
            end
        endcase
    end
    // ================================================================
    // ME1_ME2 Pipeline Register
    // ================================================================
    always @(posedge clk) begin
        if (rst) begin
            me2_RegWrite    <= 0;
            me2_RFwaddr     <= 0;
            me2_MemRead     <= 0;
            me2_RFwdata_tmp <= 0;
            me2_mask        <= 3'b0;
            me2_offset      <= 2'b0;
        end else begin
            me2_RegWrite    <= me1_RegWrite;
            me2_RFwaddr     <= me1_RFwaddr;
            me2_MemRead     <= me1_MemRead;
            me2_RFwdata_tmp <= me1_RFwdata;
            me2_mask        <= me1_mask;
            me2_offset      <= me1_offset;
        end
    end

    // trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst)    pc_ME2 <= 32'b0;
            else        pc_ME2 <= pc_ME1;
        end
        always @(posedge clk) begin
            if (rst)    have_inst_ME2 <= 1'b0;
            else        have_inst_ME2 <= have_inst_ME1;
        end
        always @(posedge clk) begin
            if (rst)    me2_ebreak <= 1'b0;
            else        me2_ebreak <= me1_ebreak;
        end
    `endif

    // ================================================================
    // ME2: Read masking and sign extension
    // ================================================================
    reg [31:0] me2_rdata_decoded;

    always @(*) begin
        me2_rdata_decoded = perip_rdata;  // Default: lw
        case (me2_mask)
            3'b000: begin   // lb
                case (me2_offset)
                    2'b00: me2_rdata_decoded = {{24{perip_rdata[7]}}, perip_rdata[7:0]};
                    2'b01: me2_rdata_decoded = {{24{perip_rdata[15]}}, perip_rdata[15:8]};
                    2'b10: me2_rdata_decoded = {{24{perip_rdata[23]}}, perip_rdata[23:16]};
                    2'b11: me2_rdata_decoded = {{24{perip_rdata[31]}}, perip_rdata[31:24]};
                    default: me2_rdata_decoded = 32'b0;
                endcase
            end
            3'b001: begin   // lh
                case (me2_offset[1])
                    1'b0: me2_rdata_decoded = {{16{perip_rdata[15]}}, perip_rdata[15:0]};
                    1'b1: me2_rdata_decoded = {{16{perip_rdata[31]}}, perip_rdata[31:16]};
                    default: me2_rdata_decoded = 32'b0;
                endcase
            end
            3'b100: begin   // lbu
                case (me2_offset)
                    2'b00: me2_rdata_decoded = {24'b0, perip_rdata[7:0]};
                    2'b01: me2_rdata_decoded = {24'b0, perip_rdata[15:8]};
                    2'b10: me2_rdata_decoded = {24'b0, perip_rdata[23:16]};
                    2'b11: me2_rdata_decoded = {24'b0, perip_rdata[31:24]};
                    default: me2_rdata_decoded = 32'b0;
                endcase
            end
            3'b101: begin   // lhu
                case (me2_offset[1])
                    1'b0: me2_rdata_decoded = {16'b0, perip_rdata[15:0]};
                    1'b1: me2_rdata_decoded = {16'b0, perip_rdata[31:16]};
                    default: me2_rdata_decoded = 32'b0;
                endcase
            end
            default: me2_rdata_decoded = perip_rdata; // lw
        endcase
    end

    assign me2_RFwdata = me2_MemRead ? me2_rdata_decoded : me2_RFwdata_tmp;

endmodule
