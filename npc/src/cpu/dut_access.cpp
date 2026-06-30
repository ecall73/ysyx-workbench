#include <stdio.h>
#include <stdlib.h>

#include "common.h"

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

uint32_t npc_read_dut_gpr(int idx) {
    svScope prev = svSetScope(get_cpu_dpi_scope());
    uint32_t val = (uint32_t)npc_get_gpr(idx);
    svSetScope(prev);
    return val;
}

uint32_t npc_read_dut_csr(int addr) {
    svScope prev = svSetScope(get_cpu_dpi_scope());
    uint32_t val = (uint32_t)npc_get_csr(addr);
    svSetScope(prev);
    return val;
}
