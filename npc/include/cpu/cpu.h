#ifndef __NPC_CPU_CPU_H__
#define __NPC_CPU_CPU_H__

#include <stdint.h>

typedef struct {
  uint32_t gpr[32];
  // Architectural PC after the committed instruction, like NEMU's cpu.pc.
  uint32_t pc;
  uint32_t mstatus;
  uint32_t mtvec;
  uint32_t mepc;
  uint32_t mcause;
} DutState;

extern bool is_finished;
extern int trap_a0;
extern int trap_pc;
extern uint64_t g_nr_guest_inst;

void cpu_exec(uint64_t n);
void npc_read_dut_state(DutState *state);

// commit_pc/commit_inst identify the retired instruction.
// pc and CSR/GPR values are the architectural state after that retirement.
extern "C" void npc_commit(
    uint32_t commit_pc,
    uint32_t commit_inst,
    uint32_t pc,
    uint32_t mstatus,
    uint32_t mtvec,
    uint32_t mepc,
    uint32_t mcause,
    const uint32_t *gpr
);

extern "C" void npc_pmu_event(int event_mask);

#endif
