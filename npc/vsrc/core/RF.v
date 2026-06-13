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
    wire [15:1] write_en;
    wire [15:1] reg_clock;

    genvar i;
    generate
        for (i = 1; i < 16; i = i + 1) begin : gen_reg_write
            assign write_en[i] = wen && (waddr[3:0] == i[3:0]) && !waddr[4];
`ifdef SYNTHESIS
            CLKGATE_X1 u_reg_clock_gate (
                .CK  (clock),
                .E   (write_en[i]),
                .GCK (reg_clock[i])
            );
`else
            assign reg_clock[i] = clock;
`endif
            always @(posedge reg_clock[i]) begin
                if (write_en[i]) begin
                    reg_bank[i] <= wdata;
                end
            end
        end
    endgenerate


    always @(*) begin
        rR1_data = (rR1 == 5'd0 || rR1[4]) ? 32'b0 : reg_bank[rR1[3:0]];
        rR2_data = (rR2 == 5'd0 || rR2[4]) ? 32'b0 : reg_bank[rR2[3:0]];
    end

endmodule
