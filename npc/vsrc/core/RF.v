module ysyx_26030082_RF(
    input  wire        clock,
    input  wire        reset,
    // Write rd
    input  wire        wen,
    input  wire [ 4:0] waddr,
    input  wire [31:0] wdata,
    // Read rs1 rs2
    input  wire [ 4:0] raddr1,
    input  wire [ 4:0] raddr2,

    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);

    reg [31:0] reg_bank [1:15];

    always @(posedge clock) begin
        if (wen & (waddr != 5'd0) & ~waddr[4]) begin
            reg_bank[waddr[3:0]] <= wdata;
        end
    end

    assign rdata1 = (raddr1 == 5'd0 || raddr1[4]) ? 32'b0 : reg_bank[raddr1[3:0]];
    assign rdata2 = (raddr2 == 5'd0 || raddr2[4]) ? 32'b0 : reg_bank[raddr2[3:0]];

endmodule
