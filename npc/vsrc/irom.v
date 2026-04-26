`timescale 1ns / 1ps
`include "defines.v"

module irom (
    input  wire        clk,
    input  wire        rst,
    input  wire        ifu_reqValid,
    output wire        ifu_reqReady,
    input  wire [31:0] ifu_addr,
    output wire        ifu_respValid,
    input  wire        ifu_respReady,
    output wire [31:0] ifu_rdata
);

    import "DPI-C" function int pmem_read(input int raddr);

    localparam I_WAIT_REQVALID = 3'd0;
    localparam I_WAIT_REQREADY = 3'd1;
    localparam I_REQ_READY     = 3'd2;
    localparam I_WAIT_RESP     = 3'd3;
    localparam I_RESP_VALID    = 3'd4;

    reg [2:0]  state;
    reg [31:0] req_addr_reg;
    reg [31:0] resp_data_reg;
    reg [3:0]  reqready_wait_cnt;
    reg [3:0]  resp_wait_cnt;

    wire [3:0] lfsr_resp_random;
    wire [3:0] lfsr_reqready_random;
    wire [3:0] reqready_delay_sampled;
    wire [3:0] resp_delay_sampled;
    wire       req_fire;
    wire       resp_fire;

    assign ifu_reqReady  = (state == I_REQ_READY);
    assign ifu_respValid = (state == I_RESP_VALID);
    assign ifu_rdata     = resp_data_reg;

    assign req_fire  = ifu_reqValid && ifu_reqReady;
    assign resp_fire = ifu_respValid && ifu_respReady;

    assign reqready_delay_sampled = (lfsr_reqready_random % `IFU_REQREADY_MAX_DELAY) + 4'd1;
    assign resp_delay_sampled     = (lfsr_resp_random % `IFU_MAX_DELAY) + 4'd1;

    lfsr4 u_lfsr4_resp (
        .clk                    (clk),
        .rst                    (rst),
        .en                     (req_fire),
        .random                 (lfsr_resp_random)
    );

    lfsr4 u_lfsr4_reqready (
        .clk                    (clk),
        .rst                    (rst),
        .en                     (ifu_reqValid && (state == I_WAIT_REQVALID)),
        .random                 (lfsr_reqready_random)
    );

    always @(posedge clk) begin
        if (rst) begin
            state              <= I_WAIT_REQVALID;
            req_addr_reg       <= 32'b0;
            resp_data_reg      <= 32'b0;
            reqready_wait_cnt  <= 4'b0;
            resp_wait_cnt      <= 4'b0;
        end else begin
            case (state)
                I_WAIT_REQVALID: begin
                    if (ifu_reqValid) begin
                        if (reqready_delay_sampled == 4'd1) begin
                            state <= I_REQ_READY;
                        end else begin
                            reqready_wait_cnt <= reqready_delay_sampled - 4'd1;
                            state             <= I_WAIT_REQREADY;
                        end
                    end
                end

                I_WAIT_REQREADY: begin
                    if (reqready_wait_cnt > 4'd1) begin
                        reqready_wait_cnt <= reqready_wait_cnt - 4'd1;
                    end else begin
                        state <= I_REQ_READY;
                    end
                end

                I_REQ_READY: begin
                    if (req_fire) begin
                        req_addr_reg <= ifu_addr;
                        if (resp_delay_sampled == 4'd1) begin
                            resp_data_reg <= pmem_read(ifu_addr);
                            state         <= I_RESP_VALID;
                        end else begin
                            resp_wait_cnt <= resp_delay_sampled - 4'd1;
                            state         <= I_WAIT_RESP;
                        end
                    end
                end

                I_WAIT_RESP: begin
                    if (resp_wait_cnt > 4'd1) begin
                        resp_wait_cnt <= resp_wait_cnt - 4'd1;
                    end else begin
                        resp_data_reg <= pmem_read(req_addr_reg);
                        state         <= I_RESP_VALID;
                    end
                end

                I_RESP_VALID: begin
                    if (resp_fire) begin
                        state <= I_WAIT_REQVALID;
                    end
                end

                default: begin
                    state <= I_WAIT_REQVALID;
                end
            endcase
        end
    end

endmodule
