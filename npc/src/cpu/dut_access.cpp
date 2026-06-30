#include <stdio.h>
#include <stdlib.h>

#include "common.h"

extern "C" int npc_get_gpr(int idx);
extern "C" int npc_get_csr(int addr);
extern "C" int npc_get_pc();

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

    for (int i = 0; i < 32; i++) {
        state->gpr[i] = (uint32_t)npc_get_gpr(i);
    }
    state->pc = (uint32_t)npc_get_pc();
    state->mstatus = (uint32_t)npc_get_csr(0x300);
    state->mtvec = (uint32_t)npc_get_csr(0x305);
    state->mepc = (uint32_t)npc_get_csr(0x341);
    state->mcause = (uint32_t)npc_get_csr(0x342);

    svSetScope(prev);
}
