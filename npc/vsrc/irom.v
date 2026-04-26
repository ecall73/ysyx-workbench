module irom (
    input  wire [31:0] irom_addr,
    output wire [31:0] irom_data
);

    import "DPI-C" function int pmem_read(input int raddr);

    assign irom_data = pmem_read(irom_addr);

endmodule
