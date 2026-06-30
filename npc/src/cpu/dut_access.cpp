#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"

extern "C" void npc_get_state(
    int *pc,
    int *mstatus,
    int *mtvec,
    int *mepc,
    int *mcause,
    int *gpr
);

static svScope get_cpu_dpi_scope() {
    static svScope g_cpu_dpi_scope = nullptr;
    if (g_cpu_dpi_scope != nullptr) {
        return g_cpu_dpi_scope;
    }

#ifdef CONFIG_PLATFORM_NPC
    const char *candidates[] = {
        "top.Core_cpu",
        "TOP.top.Core_cpu",
    };
#else
    const char *candidates[] = {
        "ysyxSoCFull.asic.cpu.cpu",
        "TOP.ysyxSoCFull.asic.cpu.cpu",
    };
#endif

    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        svScope scope = svGetScopeFromName(candidates[i]);
        if (scope != nullptr) {
            g_cpu_dpi_scope = scope;
            return g_cpu_dpi_scope;
        }
    }

    fprintf(stderr, "failed to locate DUT DPI scope for register access\n");
    abort();
}

void npc_read_dut_state(DutState *state) {
    svScope prev = svSetScope(get_cpu_dpi_scope());
    int pc = 0;
    int mstatus = 0;
    int mtvec = 0;
    int mepc = 0;
    int mcause = 0;
    int gpr[16] = {};

    npc_get_state(&pc, &mstatus, &mtvec, &mepc, &mcause, gpr);

    memset(state, 0, sizeof(*state));
    for (int i = 0; i < 16; i++) {
        state->gpr[i] = (uint32_t)gpr[i];
    }
    state->pc = (uint32_t)pc;
    state->mstatus = (uint32_t)mstatus;
    state->mtvec = (uint32_t)mtvec;
    state->mepc = (uint32_t)mepc;
    state->mcause = (uint32_t)mcause;

    svSetScope(prev);
}
