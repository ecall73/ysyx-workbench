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

    reg [31:0] perip_wdata_aligned;
    reg [31:0] perip_rdata_raw;
    reg [31:0] perip_addr_d1;
    reg [2:0] perip_mask_d1;

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

    always @(*) begin
        case (perip_mask[1:0])
            2'b00: begin    // sb
                case (perip_addr[1:0])
                    2'b00: perip_wdata_aligned = {24'b0, perip_wdata[7:0]};
                    2'b01: perip_wdata_aligned = {16'b0, perip_wdata[7:0], 8'b0};
                    2'b10: perip_wdata_aligned = {8'b0, perip_wdata[7:0], 16'b0};
                    2'b11: perip_wdata_aligned = {perip_wdata[7:0], 24'b0};
                    default: perip_wdata_aligned = 32'b0;
                endcase
            end
            2'b01: begin    // sh
                case (perip_addr[1])
                    1'b0: perip_wdata_aligned = {16'b0, perip_wdata[15:0]};
                    1'b1: perip_wdata_aligned = {perip_wdata[15:0], 16'b0};
                    default: perip_wdata_aligned = 32'b0;
                endcase
            end             // sw
            default: perip_wdata_aligned = perip_wdata;
        endcase
    end
    always @(posedge clk) begin
        if (!rst) begin
            perip_rdata_raw <= pmem_read(perip_addr);
            perip_addr_d1 <= perip_addr;
            perip_mask_d1 <= perip_mask;
            if (perip_wen) begin
                pmem_write(perip_addr, perip_wdata_aligned, wmask_byte);
            end
        end
    end

    always @(*) begin
        case (perip_mask_d1)
            3'b000: begin   // lb
                case (perip_addr_d1[1:0])
                    2'b00: perip_rdata = {{24{perip_rdata_raw[7]}}, perip_rdata_raw[7:0]};
                    2'b01: perip_rdata = {{24{perip_rdata_raw[15]}}, perip_rdata_raw[15:8]};
                    2'b10: perip_rdata = {{24{perip_rdata_raw[23]}}, perip_rdata_raw[23:16]};
                    2'b11: perip_rdata = {{24{perip_rdata_raw[31]}}, perip_rdata_raw[31:24]};
                    default: perip_rdata = 32'b0;
                endcase
            end
            3'b001: begin   // lh
                case (perip_addr_d1[1])
                    1'b0: perip_rdata = {{16{perip_rdata_raw[15]}}, perip_rdata_raw[15:0]};
                    1'b1: perip_rdata = {{16{perip_rdata_raw[31]}}, perip_rdata_raw[31:16]};
                    default: perip_rdata = 32'b0;
                endcase
            end
            3'b100: begin   // lbu
                case (perip_addr_d1[1:0])
                    2'b00: perip_rdata = {24'b0, perip_rdata_raw[7:0]};
                    2'b01: perip_rdata = {24'b0, perip_rdata_raw[15:8]};
                    2'b10: perip_rdata = {24'b0, perip_rdata_raw[23:16]};
                    2'b11: perip_rdata = {24'b0, perip_rdata_raw[31:24]};
                    default: perip_rdata = 32'b0;
                endcase
            end
            3'b101: begin   // lhu
                case (perip_addr_d1[1])
                    1'b0: perip_rdata = {16'b0, perip_rdata_raw[15:0]};
                    1'b1: perip_rdata = {16'b0, perip_rdata_raw[31:16]};
                    default: perip_rdata = 32'b0;
                endcase
            end             // lw
            default: perip_rdata = perip_rdata_raw;
        endcase
    end

endmodule
