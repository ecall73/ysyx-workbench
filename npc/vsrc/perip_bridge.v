module perip_bridge (
    input clk,
    input rst,
    input perip_ren,
    input perip_wen,
    input [3:0] perip_wmask,
    input [31:0] perip_addr,
    input [31:0] perip_wdata,
    output wire [31:0] perip_rdata
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    reg [7:0] wmask_byte;

    always @(*) begin
        wmask_byte = {4'b0000, perip_wmask};
    end

    always @(posedge clk) begin
        if (!rst && perip_wen) begin
            pmem_write(perip_addr, perip_wdata, wmask_byte);
        end
    end

    assign perip_rdata = perip_ren ? pmem_read(perip_addr) : 32'b0;

endmodule
