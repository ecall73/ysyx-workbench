#ifndef __NPC_CPU_DIFFTEST_H__
#define __NPC_CPU_DIFFTEST_H__

#include <stdbool.h>
#include <stdint.h>

#include "cpu/cpu.h"

void init_difftest(const char *ref_so_file, long img_size, int port);
bool difftest_step(uint32_t commit_pc, uint32_t commit_inst, const DutState *dut_state);
bool difftest_is_enabled();

#endif
