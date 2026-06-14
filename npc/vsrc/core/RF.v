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
        if ((rR1 == 5'd0) || rR1[4]) begin
            rR1_data = 32'b0;
        end else begin
            case (rR1[3:0])
                4'd1: rR1_data = reg_bank[4'd1];
                4'd2: rR1_data = reg_bank[4'd2];
                4'd3: rR1_data = reg_bank[4'd3];
                4'd4: rR1_data = reg_bank[4'd4];
                4'd5: rR1_data = reg_bank[4'd5];
                4'd6: rR1_data = reg_bank[4'd6];
                4'd7: rR1_data = reg_bank[4'd7];
                4'd8: rR1_data = reg_bank[4'd8];
                4'd9: rR1_data = reg_bank[4'd9];
                4'd10: rR1_data = reg_bank[4'd10];
                4'd11: rR1_data = reg_bank[4'd11];
                4'd12: rR1_data = reg_bank[4'd12];
                4'd13: rR1_data = reg_bank[4'd13];
                4'd14: rR1_data = reg_bank[4'd14];
                4'd15: rR1_data = reg_bank[4'd15];
                default: rR1_data = 32'b0;
            endcase
        end

        if ((rR2 == 5'd0) || rR2[4]) begin
            rR2_data = 32'b0;
        end else begin
            case (rR2[3:0])
                4'd1: rR2_data = reg_bank[4'd1];
                4'd2: rR2_data = reg_bank[4'd2];
                4'd3: rR2_data = reg_bank[4'd3];
                4'd4: rR2_data = reg_bank[4'd4];
                4'd5: rR2_data = reg_bank[4'd5];
                4'd6: rR2_data = reg_bank[4'd6];
                4'd7: rR2_data = reg_bank[4'd7];
                4'd8: rR2_data = reg_bank[4'd8];
                4'd9: rR2_data = reg_bank[4'd9];
                4'd10: rR2_data = reg_bank[4'd10];
                4'd11: rR2_data = reg_bank[4'd11];
                4'd12: rR2_data = reg_bank[4'd12];
                4'd13: rR2_data = reg_bank[4'd13];
                4'd14: rR2_data = reg_bank[4'd14];
                4'd15: rR2_data = reg_bank[4'd15];
                default: rR2_data = 32'b0;
            endcase
        end
    end

endmodule
