`timescale 1ns / 1ps

module lsu (
    // Handshake
    input  wire        ls_in_valid,
    output wire        ls_in_ready,
    output wire        ls_out_valid,
    input  wire        ls_out_ready,

    // LS payload inputs
    input  wire [31:0] ls_ALUResult,
    input  wire [ 2:0] ls_mask,
    input  wire        ls_MemWrite,
    input  wire        ls_MemRead,
    input  wire [31:0] ls_rR2_data,

    input  wire [31:0] ls_RFwdata,

    // Peripheral Interface
    input  wire [31:0] perip_rdata,
    output wire [31:0] perip_addr,
    output wire [ 3:0] perip_wmask,
    output wire        perip_wen,
    output wire        perip_ren,
    output wire [31:0] perip_wdata,

    // LS payload outputs
    output wire [31:0] ls_RFwdata_out
);

    wire [1:0] ls_offset;
    reg  [3:0] ls_wmask;
    reg  [31:0] ls_wdata_aligned;
    reg  [31:0] ls_rdata_decoded;

    assign ls_in_ready = ls_out_ready;
    assign ls_out_valid = ls_in_valid;

    assign ls_offset = ls_ALUResult[1:0];
    assign perip_addr = {ls_ALUResult[31:2], 2'b0};
    assign perip_wmask = ls_wmask;
    assign perip_wdata = ls_wdata_aligned;

    // Only issue memory operation when LS handshakes out.
    assign perip_wen = ls_in_valid && ls_out_ready && ls_MemWrite;
    assign perip_ren = ls_in_valid && ls_out_ready && ls_MemRead;

    assign ls_RFwdata_out = ls_MemRead ? ls_rdata_decoded : ls_RFwdata;

    // Store alignment
    always @(*) begin
        ls_wmask = 4'b0000;
        ls_wdata_aligned = ls_rR2_data;
        case (ls_mask)
            3'b000: begin // sb
                case (ls_offset)
                    2'b00: begin
                        ls_wmask = 4'b0001;
                        ls_wdata_aligned = {24'b0, ls_rR2_data[7:0]};
                    end
                    2'b01: begin
                        ls_wmask = 4'b0010;
                        ls_wdata_aligned = {16'b0, ls_rR2_data[7:0], 8'b0};
                    end
                    2'b10: begin
                        ls_wmask = 4'b0100;
                        ls_wdata_aligned = {8'b0, ls_rR2_data[7:0], 16'b0};
                    end
                    2'b11: begin
                        ls_wmask = 4'b1000;
                        ls_wdata_aligned = {ls_rR2_data[7:0], 24'b0};
                    end
                endcase
            end
            3'b001: begin // sh
                case (ls_offset[1])
                    1'b0: begin
                        ls_wmask = 4'b0011;
                        ls_wdata_aligned = {16'b0, ls_rR2_data[15:0]};
                    end
                    1'b1: begin
                        ls_wmask = 4'b1100;
                        ls_wdata_aligned = {ls_rR2_data[15:0], 16'b0};
                    end
                endcase
            end
            default: begin // sw
                ls_wmask = 4'b1111;
                ls_wdata_aligned = ls_rR2_data;
            end
        endcase
    end

    // Load sign/zero extension
    always @(*) begin
        ls_rdata_decoded = perip_rdata; // lw
        case (ls_mask)
            3'b000: begin // lb
                case (ls_offset)
                    2'b00: ls_rdata_decoded = {{24{perip_rdata[7]}}, perip_rdata[7:0]};
                    2'b01: ls_rdata_decoded = {{24{perip_rdata[15]}}, perip_rdata[15:8]};
                    2'b10: ls_rdata_decoded = {{24{perip_rdata[23]}}, perip_rdata[23:16]};
                    2'b11: ls_rdata_decoded = {{24{perip_rdata[31]}}, perip_rdata[31:24]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b001: begin // lh
                case (ls_offset[1])
                    1'b0: ls_rdata_decoded = {{16{perip_rdata[15]}}, perip_rdata[15:0]};
                    1'b1: ls_rdata_decoded = {{16{perip_rdata[31]}}, perip_rdata[31:16]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b100: begin // lbu
                case (ls_offset)
                    2'b00: ls_rdata_decoded = {24'b0, perip_rdata[7:0]};
                    2'b01: ls_rdata_decoded = {24'b0, perip_rdata[15:8]};
                    2'b10: ls_rdata_decoded = {24'b0, perip_rdata[23:16]};
                    2'b11: ls_rdata_decoded = {24'b0, perip_rdata[31:24]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b101: begin // lhu
                case (ls_offset[1])
                    1'b0: ls_rdata_decoded = {16'b0, perip_rdata[15:0]};
                    1'b1: ls_rdata_decoded = {16'b0, perip_rdata[31:16]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            default: ls_rdata_decoded = perip_rdata;
        endcase
    end

endmodule
