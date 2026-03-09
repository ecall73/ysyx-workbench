module perip_bridge (
    input clk,
    input rst,
    input perip_ren,
    input perip_wen,
    input [2:0] perip_mask,
    input [31:0] perip_addr,
    input [31:0] perip_wdata,
    output reg [31:0] perip_rdata
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    // Decode mask (assuming funct3 format)
    reg [7:0] wmask_byte;
    always @(*) begin
        case (perip_mask)
            3'b000: wmask_byte = 8'h01 << perip_addr[1:0]; // SB
            3'b001: wmask_byte = 8'h03 << perip_addr[1:0]; // SH
            3'b010: wmask_byte = 8'h0F;                    // SW
            default: wmask_byte = 8'h00;
        endcase
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (perip_ren) begin
                perip_rdata <= pmem_read(perip_addr);
            end
            if (perip_wen) begin
                pmem_write(perip_addr, perip_wdata, wmask_byte);
            end
        end
    end

endmodule
