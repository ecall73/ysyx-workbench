`timescale 1ns / 1ps

`include "defines.v"

module top
(
    input             clk,
    input             rst
`ifdef RUN_TRACE
,   output            debug_wb_have_inst,
    output [31:0]     debug_wb_pc,
    output            debug_wb_ena,
    output [ 4:0]     debug_wb_reg,
    output [31:0]     debug_wb_value,
    output            debug_wb_ebreak,
    output [31:0]     debug_reg_file [0:31]
`endif
);

    // IROM
    wire irom_ren;
    wire [31:0] irom_addr;
    wire [31:0] irom_data;

    // perip
    wire [31:0] perip_addr, perip_wdata, perip_rdata;
    wire perip_wen, perip_ren;
    wire [2:0] perip_mask;

    wire external_stall;
    wire [3:0] exception, interrupt;

    // No external_stall, exception or interrupt
    assign external_stall = 0;
    assign exception = 10;
    assign interrupt = 0;

    myCPU Core_cpu (
        .clk                (clk),
        .rst                (rst),
        .external_stall     (external_stall),

        .exception          (exception),
        .interrupt          (interrupt),

        // Interface to IROM
        .irom_ren           (irom_ren),
        .irom_addr          (irom_addr),
        .irom_data          (irom_data),

        // Interface to DRAM & periphera
        .perip_addr         (perip_addr),
        .perip_ren          (perip_ren),
        .perip_wen          (perip_wen),
        .perip_mask         (perip_mask),
        .perip_wdata        (perip_wdata),
        .perip_rdata        (perip_rdata)

    `ifdef RUN_TRACE
        ,
        .debug_wb_have_inst (debug_wb_have_inst),
        .debug_wb_pc        (debug_wb_pc),
        .debug_wb_ena       (debug_wb_ena),
        .debug_wb_reg       (debug_wb_reg),
        .debug_wb_value     (debug_wb_value),
        .debug_wb_ebreak    (debug_wb_ebreak),
        .debug_reg_file     (debug_reg_file)
    `endif
    );

    `ifdef RUN_TRACE
        import "DPI-C" function void npc_trap(input int pc, input int a0);
        always @(posedge clk) begin
            if (debug_wb_ebreak) npc_trap(debug_wb_pc, debug_reg_file[10]);
        end
    `endif

    irom irom_inst (
        .clk                (clk),
        .irom_ren           (irom_ren),
        .irom_addr          (irom_addr),
        .irom_data          (irom_data)
    );
    
    perip_bridge bridge_inst (
        .clk				(clk),
        .rst                (rst),
        .perip_addr			(perip_addr),
        .perip_wdata		(perip_wdata),
        .perip_ren          (perip_ren),
        .perip_wen			(perip_wen),
        .perip_mask			(perip_mask),
        .perip_rdata		(perip_rdata)
    );

endmodule
