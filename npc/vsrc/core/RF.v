module ysyx_26030082_RF(
    input  wire        clock,
    input  wire        reset,
    // Write rd
    input  wire        wen,
    input  wire [ 4:0] waddr,
    input  wire [31:0] wdata,
    // Read rs1 rs2
    input  wire [ 4:0] rR1,
    input  wire [ 4:0] rR2,

    output wire [31:0] rR1_data,
    output wire [31:0] rR2_data
);

    reg [31:0] reg_bank [1:15];

    always @(posedge clock) begin
        if (wen & (waddr != 5'd0) & ~waddr[4]) begin
            reg_bank[waddr[3:0]] <= wdata;
        end
    end

    assign rR1_data = (rR1 == 5'd0 || rR1[4]) ? 32'b0 : reg_bank[rR1[3:0]];
    assign rR2_data = (rR2 == 5'd0 || rR2[4]) ? 32'b0 : reg_bank[rR2[3:0]];

endmodule
