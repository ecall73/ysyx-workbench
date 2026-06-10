`timescale 1ns / 1ns

module tb_iverilog;

    localparam [31:0] EBREAK_INST = 32'h0010_0073;
    localparam integer DEFAULT_MAX_CYCLES = 5000000;

    reg clock;
    reg reset;

    integer cycle_count;
    integer max_cycles;
    reg dump_started;

    top dut (
        .clock                  (clock),
        .reset                  (reset)
    );

    initial begin
        clock = 1'b0;
        forever #5 clock = ~clock;
    end

    initial begin
        reset = 1'b1;
        cycle_count = 0;
        max_cycles = DEFAULT_MAX_CYCLES;
        dump_started = 1'b0;

        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            max_cycles = DEFAULT_MAX_CYCLES;
        end

        repeat (10) @(posedge clock);
        reset = 1'b0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            cycle_count = cycle_count + 1;

            if ($test$plusargs("WAVE") && !dump_started) begin
                dump_started = 1'b1;
                $dumpfile("build/iverilog/wave.vcd");
                $dumpvars(0, tb_iverilog);
                $dumpvars(0, dut);
            end

            if (dut.Core_cpu.ls_out_valid && dut.Core_cpu.have_inst_LS) begin
                if (dut.Core_cpu.inst_LS === EBREAK_INST) begin
                    if (dut.Core_cpu.RF.reg_bank[10] === 32'h0000_0000) begin
                        $display("HIT GOOD TRAP at pc = 0x%08x cycle = %0d",
                            dut.Core_cpu.pc_LS, cycle_count);
                    end else begin
                        $display("HIT BAD TRAP at pc = 0x%08x a0 = 0x%08x cycle = %0d",
                            dut.Core_cpu.pc_LS, dut.Core_cpu.RF.reg_bank[10], cycle_count);
                    end
                    $finish;
                end
            end

            if (cycle_count >= max_cycles) begin
                $display("TIMEOUT at cycle %0d", cycle_count);
                $finish;
            end
        end
    end

endmodule
