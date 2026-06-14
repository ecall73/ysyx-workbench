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

    output reg  [31:0] rR1_data,
    output reg  [31:0] rR2_data
);

    reg [31:0] reg_bank [1:15];

    always @(posedge clock) begin
        if (wen & (waddr != 5'd0) & ~waddr[4]) begin
            reg_bank[waddr[3:0]] <= wdata;
        end
    end

    always @(*) begin
        case (rR1)
            5'd1:  rR1_data = reg_bank[1];
            5'd2:  rR1_data = reg_bank[2];
            5'd3:  rR1_data = reg_bank[3];
            5'd4:  rR1_data = reg_bank[4];
            5'd5:  rR1_data = reg_bank[5];
            5'd6:  rR1_data = reg_bank[6];
            5'd7:  rR1_data = reg_bank[7];
            5'd8:  rR1_data = reg_bank[8];
            5'd9:  rR1_data = reg_bank[9];
            5'd10: rR1_data = reg_bank[10];
            5'd11: rR1_data = reg_bank[11];
            5'd12: rR1_data = reg_bank[12];
            5'd13: rR1_data = reg_bank[13];
            5'd14: rR1_data = reg_bank[14];
            5'd15: rR1_data = reg_bank[15];
            default: rR1_data = 32'b0;
        endcase

        case (rR2)
            5'd1:  rR2_data = reg_bank[1];
            5'd2:  rR2_data = reg_bank[2];
            5'd3:  rR2_data = reg_bank[3];
            5'd4:  rR2_data = reg_bank[4];
            5'd5:  rR2_data = reg_bank[5];
            5'd6:  rR2_data = reg_bank[6];
            5'd7:  rR2_data = reg_bank[7];
            5'd8:  rR2_data = reg_bank[8];
            5'd9:  rR2_data = reg_bank[9];
            5'd10: rR2_data = reg_bank[10];
            5'd11: rR2_data = reg_bank[11];
            5'd12: rR2_data = reg_bank[12];
            5'd13: rR2_data = reg_bank[13];
            5'd14: rR2_data = reg_bank[14];
            5'd15: rR2_data = reg_bank[15];
            default: rR2_data = 32'b0;
        endcase
    end

endmodule
