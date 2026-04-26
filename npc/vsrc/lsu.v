`timescale 1ns / 1ps

module lsu (
    input  wire        clk,
    input  wire        rst,
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

    // LSU SimpleBus interface
    output wire        lsu_reqValid,
    input  wire        lsu_reqReady,
    output wire [31:0] lsu_addr,
    output wire        lsu_wen,
    output wire [31:0] lsu_wdata,
    output wire [ 3:0] lsu_wmask,
    input  wire        lsu_respValid,
    output wire        lsu_respReady,
    input  wire [31:0] lsu_rdata,

    // LS payload outputs
    output wire [31:0] ls_RFwdata_out
);

    localparam L_IDLE            = 2'd0;
    localparam L_REQ_VALID       = 2'd1;
    localparam L_WAIT_RESP_VALID = 2'd2;
    localparam L_RESP_READY      = 2'd3;

    reg  [1:0]  state;

    wire        ls_is_mem;
    wire        req_fire;
    wire        resp_fire;
    wire [1:0]  ls_offset;
    reg  [3:0]  ls_wmask_calc;
    reg  [31:0] ls_wdata_aligned;
    reg  [31:0] ls_rdata_decoded;

    assign ls_is_mem = ls_MemRead || ls_MemWrite;
    assign req_fire = lsu_reqValid && lsu_reqReady;
    assign resp_fire = lsu_respValid && lsu_respReady;
    assign ls_offset = ls_ALUResult[1:0];

    // Non-memory ops pass through in IDLE with zero extra delay.
    // For memory ops, ls_in_ready is only released when the response handshakes,
    // so LS payload can advance exactly once and avoid replaying the same request.
    assign ls_in_ready = (state == L_IDLE) ? ((ls_in_valid && ls_is_mem) ? 1'b0 : ls_out_ready) :
                         (state == L_RESP_READY) ? (lsu_respValid && ls_out_ready) : 1'b0;
    assign ls_out_valid = (state == L_IDLE) ? (ls_in_valid && ~ls_is_mem) :
                          (state == L_RESP_READY) ? lsu_respValid : 1'b0;

    assign lsu_reqValid = (state == L_REQ_VALID);
    assign lsu_addr = (state == L_REQ_VALID) ? {ls_ALUResult[31:2], 2'b0} : 32'b0;
    assign lsu_wen = (state == L_REQ_VALID) ? ls_MemWrite : 1'b0;
    assign lsu_wdata = (state == L_REQ_VALID) ? ls_wdata_aligned : 32'b0;
    assign lsu_wmask = (state == L_REQ_VALID) ? ls_wmask_calc : 4'b0;

    // No LSU response buffer is needed because WB is always ready.
    assign lsu_respReady = (state == L_RESP_READY) && ls_out_ready;

    assign ls_RFwdata_out = ((state == L_RESP_READY) && lsu_respValid && ls_MemRead) ? ls_rdata_decoded : ls_RFwdata;

    // Store alignment
    always @(*) begin
        ls_wmask_calc = 4'b0000;
        ls_wdata_aligned = ls_rR2_data;
        case (ls_mask)
            3'b000: begin // sb
                case (ls_offset)
                    2'b00: begin
                        ls_wmask_calc = 4'b0001;
                        ls_wdata_aligned = {24'b0, ls_rR2_data[7:0]};
                    end
                    2'b01: begin
                        ls_wmask_calc = 4'b0010;
                        ls_wdata_aligned = {16'b0, ls_rR2_data[7:0], 8'b0};
                    end
                    2'b10: begin
                        ls_wmask_calc = 4'b0100;
                        ls_wdata_aligned = {8'b0, ls_rR2_data[7:0], 16'b0};
                    end
                    2'b11: begin
                        ls_wmask_calc = 4'b1000;
                        ls_wdata_aligned = {ls_rR2_data[7:0], 24'b0};
                    end
                endcase
            end
            3'b001: begin // sh
                case (ls_offset[1])
                    1'b0: begin
                        ls_wmask_calc = 4'b0011;
                        ls_wdata_aligned = {16'b0, ls_rR2_data[15:0]};
                    end
                    1'b1: begin
                        ls_wmask_calc = 4'b1100;
                        ls_wdata_aligned = {ls_rR2_data[15:0], 16'b0};
                    end
                endcase
            end
            default: begin // sw
                ls_wmask_calc = 4'b1111;
                ls_wdata_aligned = ls_rR2_data;
            end
        endcase
    end

    // Load sign/zero extension
    always @(*) begin
        ls_rdata_decoded = lsu_rdata; // lw
        case (ls_mask)
            3'b000: begin // lb
                case (ls_offset)
                    2'b00: ls_rdata_decoded = {{24{lsu_rdata[7]}}, lsu_rdata[7:0]};
                    2'b01: ls_rdata_decoded = {{24{lsu_rdata[15]}}, lsu_rdata[15:8]};
                    2'b10: ls_rdata_decoded = {{24{lsu_rdata[23]}}, lsu_rdata[23:16]};
                    2'b11: ls_rdata_decoded = {{24{lsu_rdata[31]}}, lsu_rdata[31:24]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b001: begin // lh
                case (ls_offset[1])
                    1'b0: ls_rdata_decoded = {{16{lsu_rdata[15]}}, lsu_rdata[15:0]};
                    1'b1: ls_rdata_decoded = {{16{lsu_rdata[31]}}, lsu_rdata[31:16]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b100: begin // lbu
                case (ls_offset)
                    2'b00: ls_rdata_decoded = {24'b0, lsu_rdata[7:0]};
                    2'b01: ls_rdata_decoded = {24'b0, lsu_rdata[15:8]};
                    2'b10: ls_rdata_decoded = {24'b0, lsu_rdata[23:16]};
                    2'b11: ls_rdata_decoded = {24'b0, lsu_rdata[31:24]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b101: begin // lhu
                case (ls_offset[1])
                    1'b0: ls_rdata_decoded = {16'b0, lsu_rdata[15:0]};
                    1'b1: ls_rdata_decoded = {16'b0, lsu_rdata[31:16]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            default: ls_rdata_decoded = lsu_rdata;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= L_IDLE;
        end else begin
            case (state)
                L_IDLE: begin
                    if (ls_in_valid && ls_is_mem) begin
                        state <= L_REQ_VALID;
                    end
                end
                L_REQ_VALID: begin
                    if (req_fire) begin
                        state <= L_WAIT_RESP_VALID;
                    end
                end
                L_WAIT_RESP_VALID: begin
                    if (lsu_respValid) begin
                        state <= L_RESP_READY;
                    end
                end
                L_RESP_READY: begin
                    if (resp_fire) begin
                        state <= L_IDLE;
                    end
                end
                default: begin
                    state <= L_IDLE;
                end
            endcase
        end
    end

endmodule
