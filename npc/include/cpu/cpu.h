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

enum NpcState {
  NPC_STOP,
  NPC_RUNNING,
  NPC_END,
  NPC_ABORT,
  NPC_QUIT,
};

extern NpcState npc_state;
extern int trap_a0;
extern int trap_pc;
extern uint64_t g_nr_guest_inst;

void cpu_exec(uint64_t n);
void npc_reset_dut_state(uint32_t pc);
void npc_read_dut_state(DutState *state);
void npc_reg_display();
uint32_t npc_reg_str2val(const char *s, bool *success);

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
