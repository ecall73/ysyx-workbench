#include <stdio.h>
#include <stdlib.h>

#include "npc.h"

uint32_t npc_read_dut_gpr(int idx) {
    static svScope g_cpu_dpi_scope = nullptr;
    if (g_cpu_dpi_scope == nullptr) {
#ifdef NPC_SIM_MODE_NPC
        const char *candidates[] = {
            "top.Core_cpu",
            "TOP.top.Core_cpu",
        };
#else
        const char *candidates[] = {
            "ysyxSoCFull.asic.cpu.cpu.u_cpu",
            "TOP.ysyxSoCFull.asic.cpu.cpu.u_cpu",
        };
#endif

        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
            svScope scope = svGetScopeFromName(candidates[i]);
            if (scope != nullptr) {
                g_cpu_dpi_scope = scope;
                break;
            }
        }

        if (g_cpu_dpi_scope == nullptr) {
            fprintf(stderr, "failed to locate DUT DPI scope for gpr access\n");
            abort();
        }
    }

    svScope prev = svSetScope(g_cpu_dpi_scope);
    uint32_t val = (uint32_t)npc_get_gpr(idx);
    svSetScope(prev);
    return val;
}
