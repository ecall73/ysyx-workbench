#include <stdint.h>

#include "npc.h"

static bool difftest_enabled = false;

bool difftest_is_enabled() {
    return difftest_enabled;
}

void init_difftest(const char *ref_so_file, long img_size, int port) {
    (void)img_size;
    (void)port;
    difftest_enabled = false;
    if (ref_so_file != NULL) {
        Log("Differential testing is disabled in ysyxSoC mode");
    }
}

bool difftest_step(uint32_t dut_pc, bool dut_wen, uint8_t dut_waddr, uint32_t dut_wdata) {
    (void)dut_pc;
    (void)dut_wen;
    (void)dut_waddr;
    (void)dut_wdata;
    return true;
}
