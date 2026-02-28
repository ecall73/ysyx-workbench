module top (
    input clk,
    input rst,
    output reg [7:0] out_rs
);

    reg [7:0] R [3:0];
    reg [7:0] M [15:0];
    reg [7:0] PC;

    // Decode
    wire [7:0] inst = M[PC[3:0]];
    wire [1:0] opcode = inst[7:6];
    wire [1:0] rd     = inst[5:4];
    wire [1:0] rs1    = inst[3:2];
    wire [1:0] rs2    = inst[1:0];
    wire [3:0] imm    = inst[3:0];
    wire [3:0] addr   = inst[5:2];

    integer i;

    initial begin
        M[0] = 8'h95; 
        M[1] = 8'hA3;
        M[2] = 8'h36;
        M[3] = 8'h43;
        M[4] = 8'hC0;
        M[5] = 8'hC1;
        for (i = 6; i < 16; i = i + 1) M[i] = 8'h00;
    end

    always @(posedge clk) begin
        if (rst) begin
            PC <= 8'h00;
            out_rs <= 8'h00;
            for (i = 0; i < 4; i = i + 1) begin
                R[i] <= 8'h00;
            end
        end else begin
            case (opcode)
                2'b00: begin // add: R[rd] = R[rs1] + R[rs2]
                    R[rd] <= R[rs1] + R[rs2];
                    PC <= PC + 1;
                end
                2'b01: begin // out: out_rs = R[rs2]
                    out_rs <= R[rs2];
                    PC <= PC + 1;
                end
                2'b10: begin // li: R[rd] = imm
                    R[rd] <= {4'b0, imm};
                    PC <= PC + 1;
                end
                2'b11: begin // bner0: if (R[rs2] != R[0]) PC = addr
                    if (R[rs2] != R[0]) begin
                        PC <= {4'b0, addr};
                    end else begin
                        PC <= PC + 1;
                    end
                end
                default: begin
                    PC <= PC + 1;
                end
            endcase
        end
    end

endmodule
