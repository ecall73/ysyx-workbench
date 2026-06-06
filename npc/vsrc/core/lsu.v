`timescale 1ns / 1ps

module lsu (
    input  wire        clock,
    input  wire        reset,
    // Handshake
    input  wire        ls_in_valid,
    output wire        ls_in_ready,
    output wire        ls_out_valid,
    input  wire        ls_out_ready,

    // LS payload inputs
    input  wire [31:0] ls_ALUResult,
    input  wire [ 2:0] ls_funct3,
    input  wire        ls_MemWrite,
    input  wire        ls_MemRead,
    input  wire [31:0] ls_rR2_data,
    input  wire [31:0] ls_RFwdata,

    // LSU AXI4-Lite interface
    // Read address channel
    output wire [31:0] lsu_axi_araddr,
    output wire [ 2:0] lsu_axi_arsize,
    output wire        lsu_axi_arvalid,
    input  wire        lsu_axi_arready,
    // Read data channel
    input  wire [31:0] lsu_axi_rdata,
    input  wire [ 1:0] lsu_axi_rresp,
    input  wire        lsu_axi_rvalid,
    output wire        lsu_axi_rready,
    // Write address channel
    output wire [31:0] lsu_axi_awaddr,
    output wire [ 2:0] lsu_axi_awsize,
    output wire        lsu_axi_awvalid,
    input  wire        lsu_axi_awready,
    // Write data channel
    output wire [31:0] lsu_axi_wdata,
    output wire [ 3:0] lsu_axi_wstrb,
    output wire        lsu_axi_wvalid,
    input  wire        lsu_axi_wready,
    // Write response channel
    input  wire [ 1:0] lsu_axi_bresp,
    input  wire        lsu_axi_bvalid,
    output wire        lsu_axi_bready,

    // LS payload outputs
    output wire [31:0] ls_RFwdata_out
);

    localparam L_IDLE      = 3'd0;
    localparam L_RD_AR     = 3'd1;
    localparam L_RD_WAIT_R = 3'd2;
    localparam L_WR_AW_W   = 3'd3;
    localparam L_WR_WAIT_B = 3'd4;

    reg  [2:0]  state;
    reg         wr_aw_done;
    reg         wr_w_done;

    wire        ls_is_mem;
    wire        ls_is_load;
    wire        ar_fire;
    wire        r_fire;
    wire        aw_fire;
    wire        w_fire;
    wire        b_fire;
    wire [1:0]  ls_offset;
    reg  [3:0]  ls_wmask_calc;
    reg  [31:0] ls_wdata_aligned;
    reg  [31:0] ls_rdata_decoded;
    reg  [2:0]  ls_axi_size;

    assign ls_is_mem = ls_MemRead || ls_MemWrite;
    assign ls_is_load = ls_MemRead && ~ls_MemWrite;

    assign ar_fire = lsu_axi_arvalid && lsu_axi_arready;
    assign r_fire = lsu_axi_rvalid && lsu_axi_rready;
    assign aw_fire = lsu_axi_awvalid && lsu_axi_awready;
    assign w_fire = lsu_axi_wvalid && lsu_axi_wready;
    assign b_fire = lsu_axi_bvalid && lsu_axi_bready;
    assign ls_offset = ls_ALUResult[1:0];

    // Non-memory ops pass through in IDLE with zero extra delay.
    // For memory ops, ls_in_ready is only released when R/B handshakes.
    assign ls_in_ready = (state == L_IDLE) ? ((ls_in_valid && ls_is_mem) ? 1'b0 : ls_out_ready) :
                         (state == L_RD_WAIT_R) ? (lsu_axi_rvalid && ls_out_ready) :
                         (state == L_WR_WAIT_B) ? (lsu_axi_bvalid && ls_out_ready) : 1'b0;
    assign ls_out_valid = (state == L_IDLE) ? (ls_in_valid && ~ls_is_mem) :
                          (state == L_RD_WAIT_R) ? lsu_axi_rvalid :
                          (state == L_WR_WAIT_B) ? lsu_axi_bvalid : 1'b0;

    assign lsu_axi_araddr = ls_ALUResult;
    assign lsu_axi_arsize = ls_axi_size;
    assign lsu_axi_arvalid = (state == L_RD_AR);
    assign lsu_axi_rready = (state == L_RD_WAIT_R) && ls_out_ready;

    assign lsu_axi_awaddr = ls_ALUResult;
    assign lsu_axi_awsize = ls_axi_size;
    assign lsu_axi_awvalid = (state == L_WR_AW_W) && ~wr_aw_done;
    assign lsu_axi_wdata = ls_wdata_aligned;
    assign lsu_axi_wstrb = ls_wmask_calc;
    assign lsu_axi_wvalid = (state == L_WR_AW_W) && ~wr_w_done;
    assign lsu_axi_bready = (state == L_WR_WAIT_B) && ls_out_ready;

    assign ls_RFwdata_out = ((state == L_RD_WAIT_R) && lsu_axi_rvalid && ls_MemRead) ? ls_rdata_decoded : ls_RFwdata;

    // Store alignment
    always @(*) begin
        ls_wmask_calc = 4'b0000;
        ls_wdata_aligned = ls_rR2_data;
        ls_axi_size = 3'b010;
        case (ls_funct3)
            3'b000: begin // sb
                ls_axi_size = 3'b000;
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
                ls_axi_size = 3'b001;
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
            3'b100: begin // lbu
                ls_axi_size = 3'b000;
            end
            3'b101: begin // lhu
                ls_axi_size = 3'b001;
            end
            default: begin // sw
                ls_wmask_calc = 4'b1111;
                ls_wdata_aligned = ls_rR2_data;
            end
        endcase
    end

    // Load sign/zero extension
    always @(*) begin
        ls_rdata_decoded = lsu_axi_rdata; // lw
        case (ls_funct3)
            3'b000: begin // lb
                case (ls_offset)
                    2'b00: ls_rdata_decoded = {{24{lsu_axi_rdata[7]}}, lsu_axi_rdata[7:0]};
                    2'b01: ls_rdata_decoded = {{24{lsu_axi_rdata[15]}}, lsu_axi_rdata[15:8]};
                    2'b10: ls_rdata_decoded = {{24{lsu_axi_rdata[23]}}, lsu_axi_rdata[23:16]};
                    2'b11: ls_rdata_decoded = {{24{lsu_axi_rdata[31]}}, lsu_axi_rdata[31:24]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b001: begin // lh
                case (ls_offset[1])
                    1'b0: ls_rdata_decoded = {{16{lsu_axi_rdata[15]}}, lsu_axi_rdata[15:0]};
                    1'b1: ls_rdata_decoded = {{16{lsu_axi_rdata[31]}}, lsu_axi_rdata[31:16]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b100: begin // lbu
                case (ls_offset)
                    2'b00: ls_rdata_decoded = {24'b0, lsu_axi_rdata[7:0]};
                    2'b01: ls_rdata_decoded = {24'b0, lsu_axi_rdata[15:8]};
                    2'b10: ls_rdata_decoded = {24'b0, lsu_axi_rdata[23:16]};
                    2'b11: ls_rdata_decoded = {24'b0, lsu_axi_rdata[31:24]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            3'b101: begin // lhu
                case (ls_offset[1])
                    1'b0: ls_rdata_decoded = {16'b0, lsu_axi_rdata[15:0]};
                    1'b1: ls_rdata_decoded = {16'b0, lsu_axi_rdata[31:16]};
                    default: ls_rdata_decoded = 32'b0;
                endcase
            end
            default: ls_rdata_decoded = lsu_axi_rdata;
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            state <= L_IDLE;
            wr_aw_done <= 1'b0;
            wr_w_done <= 1'b0;
        end else begin
            case (state)
                L_IDLE: begin
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                    if (ls_in_valid && ls_is_mem) begin
                        if (ls_is_load) begin
                            state <= L_RD_AR;
                        end else begin
                            state <= L_WR_AW_W;
                        end
                    end
                end

                L_RD_AR: begin
                    if (ar_fire) begin
                        state <= L_RD_WAIT_R;
                    end
                end

                L_RD_WAIT_R: begin
                    if (r_fire) begin
                        state <= L_IDLE;
                    end
                end

                L_WR_AW_W: begin
                    if (aw_fire) begin
                        wr_aw_done <= 1'b1;
                    end
                    if (w_fire) begin
                        wr_w_done <= 1'b1;
                    end
                    if ((wr_aw_done || aw_fire) && (wr_w_done || w_fire)) begin
                        wr_aw_done <= 1'b0;
                        wr_w_done <= 1'b0;
                        state <= L_WR_WAIT_B;
                    end
                end

                L_WR_WAIT_B: begin
                    if (b_fire) begin
                        state <= L_IDLE;
                    end
                end

                default: begin
                    state <= L_IDLE;
                    wr_aw_done <= 1'b0;
                    wr_w_done <= 1'b0;
                end
            endcase
        end
    end

endmodule
