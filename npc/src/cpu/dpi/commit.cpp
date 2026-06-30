#include <cpu/cpu.h>
#include <isa.h>

bool npc_commit_valid = false;
vaddr_t npc_commit_pc = 0;
uint32_t npc_commit_inst = 0;

static bool program_has_ended() {
  return npc_state.state == NPC_END || npc_state.state == NPC_ABORT || npc_state.state == NPC_QUIT;
}

extern "C" void npc_commit(
    uint32_t commit_pc,
    uint32_t commit_inst,
    uint32_t pc,
    uint32_t mstatus,
    uint32_t mtvec,
    uint32_t mepc,
    uint32_t mcause,
    const uint32_t *gpr
) {
  if (program_has_ended()) return;

  npc_commit_valid = true;
  npc_commit_pc = commit_pc;
  npc_commit_inst = commit_inst;

  for (int i = 0; i < 32; i++) cpu.gpr[i] = gpr[i];
  cpu.pc = pc;
  cpu.mstatus = mstatus;
  cpu.mtvec = mtvec;
  cpu.mepc = mepc;
  cpu.mcause = mcause;

  if (commit_inst == 0x00100073) {
    npc_state.state = NPC_END;
    npc_state.halt_pc = commit_pc;
    npc_state.halt_ret = cpu.gpr[10];
  }
}

bool npc_fetch_commit(vaddr_t *pc, uint32_t *inst) {
  if (!npc_commit_valid) return false;
  *pc = npc_commit_pc;
  *inst = npc_commit_inst;
  npc_commit_valid = false;
  return true;
}

void npc_reset_commit_state(vaddr_t pc) {
  npc_commit_valid = false;
  npc_commit_pc = pc;
  npc_commit_inst = 0;
  memset(&cpu, 0, sizeof(cpu));
  cpu.pc = pc;
  cpu.mstatus = 0x1800;
  cpu.mtvec = 0;
  cpu.mepc = 0;
  cpu.mcause = 0;
}
