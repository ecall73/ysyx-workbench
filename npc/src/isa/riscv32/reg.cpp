#include <stdio.h>
#include <string.h>

#include "common.h"
#include "cpu/cpu.h"

static const char *regs[] = {
    "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

#define NR_GPR (sizeof(regs) / sizeof(regs[0]))

void npc_reg_display() {
    DutState state;
    npc_read_dut_state(&state);
    for (int i = 0; i < (int)NR_GPR; i++) {
        printf(ANSI_FG_RED "(x%02d) " ANSI_FG_GREEN "%-4s " ANSI_FG_BLUE "0x%08x\t" ANSI_NONE,
            i, regs[i], state.gpr[i]);
        if (i % 4 == 3) {
            printf("\n");
        }
    }
    printf("      " ANSI_FG_GREEN "PC   " ANSI_FG_BLUE "0x%08x\n" ANSI_NONE, state.pc);
}

uint32_t npc_reg_str2val(const char *s, bool *success) {
    DutState state;
    npc_read_dut_state(&state);

    *success = true;
    if (strcmp(s, "$pc") == 0 || strcmp(s, "$PC") == 0) {
        return state.pc;
    }

    if (s[0] == '$' && s[1] == 'x') {
        int reg_idx = -1;
        if (sscanf(s + 2, "%d", &reg_idx) == 1 && reg_idx >= 0 && reg_idx < (int)NR_GPR) {
            return state.gpr[reg_idx];
        }
    }

    for (int i = 0; i < (int)NR_GPR; i++) {
        if (s[0] == '$' && strcmp(s + 1, regs[i]) == 0) {
            return state.gpr[i];
        }
    }

    *success = false;
    return 0;
}
