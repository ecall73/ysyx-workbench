#ifndef __RISCV32_DIFFTEST_STATE_H__
#define __RISCV32_DIFFTEST_STATE_H__

#include <isa.h>
#include <riscv-difftest.h>

void riscv_difftest_build_arch_state(riscv_difftest_arch_state_t *dest,
    uint32_t profile_id, const CPU_state *src);
void riscv_difftest_build_observation(riscv_difftest_observation_t *dest,
    uint32_t profile_id, uint64_t sequence, const CPU_state *src);
void riscv_difftest_build_sync_state(riscv_difftest_sync_state_t *dest,
    uint32_t profile_id, const CPU_state *src);
int riscv_difftest_build_skip_sync_state(riscv_difftest_sync_state_t *dest,
    uint32_t reason, uint32_t instruction_bits, uint32_t instruction_length,
    const CPU_state *src);
int riscv_difftest_apply_sync_state(CPU_state *dest,
    uint32_t profile_id, const riscv_difftest_sync_state_t *src);
bool riscv_difftest_check_observation(
    const riscv_difftest_observation_t *ref,
    const riscv_difftest_observation_t *dut,
    const char *event_name, vaddr_t event_pc);

#endif
