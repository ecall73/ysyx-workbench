#include <stdio.h>
#include <inttypes.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include "npc.h"

extern "C" void npc_trap(int pc, int a0) {
    is_finished = true;
    trap_pc = pc;
    trap_a0 = a0;
}

void cpu_exec(uint64_t n) {
    if (is_finished) {
        printf("Program execution has ended. To restart the program, exit NPC and run again.\n");
        return;
    }

    for (uint64_t i = 0; i < n; i++) {
        while (!is_finished && !g_contextp->gotFinish()) {
            g_top->clk = 0;
            g_top->eval();
            g_contextp->timeInc(1);
            g_tfp->dump(g_contextp->time());

            g_top->clk = 1;
            g_top->eval();
            g_contextp->timeInc(1);
            g_tfp->dump(g_contextp->time());

            if (g_contextp->time() > MAX_SIM_TIME) {
                printf("Simulation timed out at time %ld\n", g_contextp->time());
                is_finished = true;
                break;
            }

            if (g_top->debug_wb_have_inst) {
                g_nr_guest_inst++;
                uint32_t pc = g_top->debug_wb_pc;
                uint32_t inst_val = 0;
                if (check_bound(pc, "FETCH")) {
                    inst_val = *(uint32_t *)&pmem[pc - 0x80000000];
                }
                char asm_buf[128];
                disassemble(asm_buf, sizeof(asm_buf), pc, (uint8_t *)&inst_val, 4);

                if (log_fp) {
                    fprintf(log_fp, "0x%08x: %08x\t%s\n", pc, inst_val, asm_buf);
                }

                if (n < 10) {
                    printf("0x%08x: %08x\t%s\n", pc, inst_val, asm_buf);
                }

                // Keep trap response at the same retire point as instruction trace.
                if (g_top->debug_wb_ebreak) {
                    npc_trap(pc, g_top->debug_reg_file[10]);
                }
                break;
            }
        }

        if (is_finished) {
            if (trap_a0 == 0) {
                printf("npc: " ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN) " at pc = 0x%08x\n", trap_pc);
            } else {
                printf("npc: " ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED) " at pc = 0x%08x\n", trap_pc);
            }
            printf(ANSI_FG_BLUE "total guest instructions = %" PRIu64 ANSI_NONE "\n", g_nr_guest_inst);
            break;
        }

        if (g_contextp->gotFinish()) {
            break;
        }
    }
}
