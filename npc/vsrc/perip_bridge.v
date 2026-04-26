`timescale 1ns / 1ps
`include "defines.v"

module perip_bridge (
    input  wire        clk,
    input  wire        rst,
    input  wire        lsu_reqValid,
    output wire        lsu_reqReady,
    input  wire [31:0] lsu_addr,
    input  wire        lsu_wen,
    input  wire [31:0] lsu_wdata,
    input  wire [ 3:0] lsu_wmask,
    output wire        lsu_respValid,
    input  wire        lsu_respReady,
    output wire [31:0] lsu_rdata
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    localparam B_WAIT_REQVALID = 3'd0;
    localparam B_WAIT_REQREADY = 3'd1;
    localparam B_REQ_READY     = 3'd2;
    localparam B_WAIT_RESP     = 3'd3;
    localparam B_RESP_VALID    = 3'd4;

    reg  [2:0]  state;
    reg  [31:0] req_addr_reg;
    reg         req_wen_reg;
    reg  [31:0] req_wdata_reg;
    reg  [ 3:0] req_wmask_reg;
    reg  [31:0] resp_data_reg;
    reg  [3:0]  reqready_wait_cnt;
    reg  [3:0]  resp_wait_cnt;

    wire [3:0] lfsr_resp_random;
    wire [3:0] lfsr_reqready_random;
    wire [3:0] reqready_delay_sampled;
    wire [3:0] resp_delay_sampled;
    wire       req_fire;
    wire       resp_fire;

    assign lsu_reqReady = (state == B_REQ_READY);
    assign lsu_respValid = (state == B_RESP_VALID);
    assign lsu_rdata = resp_data_reg;

    assign req_fire = lsu_reqValid && lsu_reqReady;
    assign resp_fire = lsu_respValid && lsu_respReady;

    assign reqready_delay_sampled = (lfsr_reqready_random % `LSU_REQREADY_MAX_DELAY) + 4'd1;
    assign resp_delay_sampled = (lfsr_resp_random % `LSU_MAX_DELAY) + 4'd1;

    lfsr4 u_lfsr4_resp (
        .clk                    (clk),
        .rst                    (rst),
        .en                     (req_fire),
        .random                 (lfsr_resp_random)
    );

    lfsr4 u_lfsr4_reqready (
        .clk                    (clk),
        .rst                    (rst),
        .en                     (lsu_reqValid && (state == B_WAIT_REQVALID)),
        .random                 (lfsr_reqready_random)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= B_WAIT_REQVALID;
            req_addr_reg <= 32'b0;
            req_wen_reg <= 1'b0;
            req_wdata_reg <= 32'b0;
            req_wmask_reg <= 4'b0;
            resp_data_reg <= 32'b0;
            reqready_wait_cnt <= 4'b0;
            resp_wait_cnt <= 4'b0;
        end else begin
            case (state)
                B_WAIT_REQVALID: begin
                    if (lsu_reqValid) begin
                        if (reqready_delay_sampled == 4'd1) begin
                            state <= B_REQ_READY;
                        end else begin
                            reqready_wait_cnt <= reqready_delay_sampled - 4'd1;
                            state <= B_WAIT_REQREADY;
                        end
                    end
                end

                B_WAIT_REQREADY: begin
                    if (reqready_wait_cnt > 4'd1) begin
                        reqready_wait_cnt <= reqready_wait_cnt - 4'd1;
                    end else begin
                        state <= B_REQ_READY;
                    end
                end

                B_REQ_READY: begin
                    if (req_fire) begin
                        req_addr_reg <= lsu_addr;
                        req_wen_reg <= lsu_wen;
                        req_wdata_reg <= lsu_wdata;
                        req_wmask_reg <= lsu_wmask;
                        if (resp_delay_sampled == 4'd1) begin
                            if (lsu_wen) begin
                                pmem_write(lsu_addr, lsu_wdata, {4'b0000, lsu_wmask});
                                resp_data_reg <= 32'b0;
                            end else begin
                                resp_data_reg <= pmem_read(lsu_addr);
                            end
                            state <= B_RESP_VALID;
                        end else begin
                            resp_wait_cnt <= resp_delay_sampled - 4'd1;
                            state <= B_WAIT_RESP;
                        end
                    end
                end

                B_WAIT_RESP: begin
                    if (resp_wait_cnt > 4'd1) begin
                        resp_wait_cnt <= resp_wait_cnt - 4'd1;
                    end else begin
                        if (req_wen_reg) begin
                            pmem_write(req_addr_reg, req_wdata_reg, {4'b0000, req_wmask_reg});
                            resp_data_reg <= 32'b0;
                        end else begin
                            resp_data_reg <= pmem_read(req_addr_reg);
                        end
                        state <= B_RESP_VALID;
                    end
                end

                B_RESP_VALID: begin
                    if (resp_fire) begin
                        state <= B_WAIT_REQVALID;
                    end
                end

                default: begin
                    state <= B_WAIT_REQVALID;
                end
            endcase
        end
    end

endmodule
