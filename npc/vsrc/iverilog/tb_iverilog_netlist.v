`timescale 1ns / 1ns

module tb_iverilog_netlist;

    localparam [31:0] DEFAULT_BOOT_FETCH_PC = 32'h8000_0000;
    localparam integer DEFAULT_MAX_CYCLES = 5000000;

    reg clock;
    reg reset;
    reg [31:0] boot_fetch_pc;

    integer cycle_count;
    integer max_cycles;
    reg dump_started;
    reg first_ifu_seen;

    wire ifu_ar_fire;

    assign ifu_ar_fire = dut.mem_axi_arvalid && dut.mem_axi_arready;

    top_netlist dut (
        .clock                  (clock),
        .reset                  (reset)
    );

    initial begin
        clock = 1'b0;
        forever #5 clock = ~clock;
    end

    initial begin
        reset = 1'b1;
        boot_fetch_pc = DEFAULT_BOOT_FETCH_PC;
        cycle_count = 0;
        max_cycles = DEFAULT_MAX_CYCLES;
        dump_started = 1'b0;
        first_ifu_seen = 1'b0;

        if (!$value$plusargs("BOOT_FETCH_PC=%h", boot_fetch_pc)) begin
            boot_fetch_pc = DEFAULT_BOOT_FETCH_PC;
        end

        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            max_cycles = DEFAULT_MAX_CYCLES;
        end

        repeat (10) @(posedge clock);
        reset = 1'b0;
    end

    always @(posedge clock) begin
        if (reset) begin
            first_ifu_seen = 1'b0;
        end else begin
            cycle_count = cycle_count + 1;

            if ($test$plusargs("WAVE") && !dump_started) begin
                dump_started = 1'b1;
                $dumpfile("build/iverilog-netlist/wave.vcd");
                $dumpvars(0, tb_iverilog_netlist);
                $dumpvars(0, dut);
            end

            if (ifu_ar_fire && !first_ifu_seen) begin
                first_ifu_seen = 1'b1;
                if (dut.mem_axi_araddr !== boot_fetch_pc) begin
                    $display("BAD RESET FETCH at pc = 0x%08x expected = 0x%08x",
                        dut.mem_axi_araddr, boot_fetch_pc);
                    $finish;
                end
            end

            if (cycle_count >= max_cycles) begin
                if (!first_ifu_seen) begin
                    $display("TIMEOUT before first fetch at cycle %0d", cycle_count);
                end else begin
                    $display("HIT GOOD TRAP via MAX_CYCLES at cycle %0d", cycle_count);
                end
                $finish;
            end
        end
    end

endmodule
