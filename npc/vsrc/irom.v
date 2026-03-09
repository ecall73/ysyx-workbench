module irom (
    input clk,
    input irom_ren,
    input [31:0] irom_addr,
    output reg [31:0] irom_data
);

    import "DPI-C" function int pmem_read(input int raddr);

    always @(posedge clk) begin
        if (irom_ren)
            irom_data <= pmem_read(irom_addr);
        else
            irom_data <= irom_data;
    end

endmodule
