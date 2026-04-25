`timescale 1ns / 1ps
`include "defines.v"

module lsu (
    input  wire        clk,
    input  wire        rst,

    // Handshake
    input  wire        ls1_in_valid,
    output wire        ls1_in_ready,
    output wire        ls1_out_valid,
    output reg         ls2_out_valid,
    input  wire        ls2_out_ready,

    // LS1 Stage payload inputs
    input  wire [31:0] ls1_ALUResult,
    input  wire [ 2:0] ls1_mask,
    input  wire        ls1_MemWrite,
    input  wire        ls1_MemRead,
    input  wire [31:0] ls1_rR2_data,

    input  wire        ls1_RegWrite,
    input  wire [ 4:0] ls1_RFwaddr,
    input  wire [31:0] ls1_RFwdata,

    // Peripheral Interface
    input  wire [31:0] perip_rdata,
    output wire [31:0] perip_addr,
    output wire [ 3:0] perip_wmask,
    output wire        perip_wen,
    output wire        perip_ren,
    output wire [31:0] perip_wdata,

    // LS2 Stage payload outputs
    output reg         ls2_RegWrite,
    output reg  [ 4:0] ls2_RFwaddr,
    output wire [31:0] ls2_RFwdata

    `ifdef RUN_TRACE
    ,   input  wire [31:0] pc_LS1,
        input  wire        have_inst_LS1,
        input  wire        ls1_ebreak,
        output reg  [31:0] pc_LS2,
        output reg         have_inst_LS2,
        output reg         ls2_ebreak
    `endif
);

    reg [31:0] ls2_RFwdata_tmp;
    reg        ls2_MemRead;
    reg [ 2:0] ls2_mask;
    reg [ 1:0] ls2_offset;

    // LSU has 2 stages, so keep full local handshake semantics:
    // ls1_in -> ls1_out -> ls2_in -> ls2_out
    wire       ls1_out_ready;
    wire       ls2_in_valid;
    wire       ls2_in_ready;

    assign ls1_out_valid = ls1_in_valid;
    assign ls1_in_ready  = ~ls1_in_valid || ls1_out_ready;

    // ================================================================
    // LS1: Write masking and address preparation
    // ================================================================
    wire [ 1:0] ls1_offset;
    reg  [ 3:0] ls1_wmask;
    reg  [31:0] ls1_wdata_aligned;

    assign ls1_offset  = ls1_ALUResult[1:0];
    assign perip_addr  = {ls1_ALUResult[31:2], 2'b0};  // Word-aligned address
    assign perip_wmask = ls1_wmask;
    assign perip_wen   = ls1_out_valid && ls1_out_ready && ls1_MemWrite;
    assign perip_ren   = ls1_out_valid && ls1_out_ready && ls1_MemRead;
    assign perip_wdata = ls1_wdata_aligned;

    // Generate write mask and aligned data based on mask type and offset
    always @(*) begin
        ls1_wmask = 4'b0000;
        ls1_wdata_aligned = ls1_rR2_data;
        case (ls1_mask)
            3'b000: begin // sb
                case (ls1_offset)
                    2'b00: begin
                        ls1_wmask = 4'b0001;
                        ls1_wdata_aligned = {24'b0, ls1_rR2_data[7:0]};
                    end
                    2'b01: begin
                        ls1_wmask = 4'b0010;
                        ls1_wdata_aligned = {16'b0, ls1_rR2_data[7:0], 8'b0};
                    end
                    2'b10: begin
                        ls1_wmask = 4'b0100;
                        ls1_wdata_aligned = {8'b0, ls1_rR2_data[7:0], 16'b0};
                    end
                    2'b11: begin
                        ls1_wmask = 4'b1000;
                        ls1_wdata_aligned = {ls1_rR2_data[7:0], 24'b0};
                    end
                endcase
            end
            3'b001: begin // sh
                case (ls1_offset[1])
                    1'b0: begin
                        ls1_wmask = 4'b0011;
                        ls1_wdata_aligned = {16'b0, ls1_rR2_data[15:0]};
                    end
                    1'b1: begin
                        ls1_wmask = 4'b1100;
                        ls1_wdata_aligned = {ls1_rR2_data[15:0], 16'b0};
                    end
                endcase
            end
            default: begin // sw
                ls1_wmask = 4'b1111;
                ls1_wdata_aligned = ls1_rR2_data;
            end
        endcase
    end

    // ================================================================
    // LS1_LS2 Pipeline Register
    // ================================================================
    // LS1 -> LS2 handshake coupling
    assign ls2_in_valid  = ls1_out_valid;
    assign ls2_in_ready  = ~ls2_out_valid || ls2_out_ready;
    assign ls1_out_ready = ls2_in_ready;

    always @(posedge clk) begin
        if (rst) begin
            ls2_out_valid   <= 0;
            ls2_RegWrite    <= 0;
            ls2_RFwaddr     <= 0;
            ls2_MemRead     <= 0;
            ls2_RFwdata_tmp <= 0;
            ls2_mask        <= 3'b0;
            ls2_offset      <= 2'b0;
        end else if (ls2_in_ready) begin
            ls2_out_valid <= ls2_in_valid;
            if (ls2_in_valid) begin
                ls2_RegWrite    <= ls1_RegWrite;
                ls2_RFwaddr     <= ls1_RFwaddr;
                ls2_MemRead     <= ls1_MemRead;
                ls2_RFwdata_tmp <= ls1_RFwdata;
                ls2_mask        <= ls1_mask;
                ls2_offset      <= ls1_offset;
            end else begin
                ls2_RegWrite    <= 0;
                ls2_RFwaddr     <= 0;
                ls2_MemRead     <= 0;
                ls2_RFwdata_tmp <= 0;
                ls2_mask        <= 3'b0;
                ls2_offset      <= 2'b0;
            end
        end
    end

    // trace
    `ifdef RUN_TRACE
        always @(posedge clk) begin
            if (rst) begin
                pc_LS2 <= 32'b0;
                have_inst_LS2 <= 1'b0;
                ls2_ebreak <= 1'b0;
            end else if (ls2_in_ready) begin
                if (ls2_in_valid) begin
                    pc_LS2 <= pc_LS1;
                    have_inst_LS2 <= have_inst_LS1;
                    ls2_ebreak <= ls1_ebreak;
                end else begin
                    pc_LS2 <= 32'b0;
                    have_inst_LS2 <= 1'b0;
                    ls2_ebreak <= 1'b0;
                end
            end
        end
    `endif

    // ================================================================
    // LS2: Read masking and sign extension
    // ================================================================
    reg [31:0] ls2_rdata_decoded;

    always @(*) begin
        ls2_rdata_decoded = perip_rdata;  // Default: lw
        case (ls2_mask)
            3'b000: begin   // lb
                case (ls2_offset)
                    2'b00: ls2_rdata_decoded = {{24{perip_rdata[7]}}, perip_rdata[7:0]};
                    2'b01: ls2_rdata_decoded = {{24{perip_rdata[15]}}, perip_rdata[15:8]};
                    2'b10: ls2_rdata_decoded = {{24{perip_rdata[23]}}, perip_rdata[23:16]};
                    2'b11: ls2_rdata_decoded = {{24{perip_rdata[31]}}, perip_rdata[31:24]};
                    default: ls2_rdata_decoded = 32'b0;
                endcase
            end
            3'b001: begin   // lh
                case (ls2_offset[1])
                    1'b0: ls2_rdata_decoded = {{16{perip_rdata[15]}}, perip_rdata[15:0]};
                    1'b1: ls2_rdata_decoded = {{16{perip_rdata[31]}}, perip_rdata[31:16]};
                    default: ls2_rdata_decoded = 32'b0;
                endcase
            end
            3'b100: begin   // lbu
                case (ls2_offset)
                    2'b00: ls2_rdata_decoded = {24'b0, perip_rdata[7:0]};
                    2'b01: ls2_rdata_decoded = {24'b0, perip_rdata[15:8]};
                    2'b10: ls2_rdata_decoded = {24'b0, perip_rdata[23:16]};
                    2'b11: ls2_rdata_decoded = {24'b0, perip_rdata[31:24]};
                    default: ls2_rdata_decoded = 32'b0;
                endcase
            end
            3'b101: begin   // lhu
                case (ls2_offset[1])
                    1'b0: ls2_rdata_decoded = {16'b0, perip_rdata[15:0]};
                    1'b1: ls2_rdata_decoded = {16'b0, perip_rdata[31:16]};
                    default: ls2_rdata_decoded = 32'b0;
                endcase
            end
            default: ls2_rdata_decoded = perip_rdata; // lw
        endcase
    end

    assign ls2_RFwdata = ls2_MemRead ? ls2_rdata_decoded : ls2_RFwdata_tmp;

endmodule
