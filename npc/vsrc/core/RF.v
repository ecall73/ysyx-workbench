module ysyx_26030082_RF(
    input  wire        clock,
    input  wire        reset,
    // Write rd
    input  wire        rf_wen,
    input  wire [ 4:0] rf_waddr,
    input  wire [31:0] rf_wdata,
    // Read rs1 rs2
    input  wire [ 4:0] rf_raddr1,
    input  wire [ 4:0] rf_raddr2,

    output wire [31:0] rf_rdata1,
    output wire [31:0] rf_rdata2
);

    reg [31:0] reg_bank [1:15];

    always @(posedge clock) begin
        if (rf_wen & (rf_waddr != 5'd0) & ~rf_waddr[4]) begin
            reg_bank[rf_waddr[3:0]] <= rf_wdata;
        end
    end

    assign rf_rdata1 = (rf_raddr1 == 5'd0 || rf_raddr1[4]) ? 32'b0 : reg_bank[rf_raddr1[3:0]];
    assign rf_rdata2 = (rf_raddr2 == 5'd0 || rf_raddr2[4]) ? 32'b0 : reg_bank[rf_raddr2[3:0]];

endmodule
