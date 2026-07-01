#include <cpu/cpu.h>
#include <isa.h>

static bool commit_valid = false;
static vaddr_t commit_pc = 0;
static uint32_t commit_inst = 0;

static bool program_has_ended() {
  return npc_state.state == NPC_END || npc_state.state == NPC_ABORT || npc_state.state == NPC_QUIT;
}

extern "C" void npc_commit(
    uint32_t retired_pc,
    uint32_t retired_inst,
    uint32_t pc,
    uint32_t mstatus,
    uint32_t mtvec,
    uint32_t mepc,
    uint32_t mcause,
    const uint32_t *gpr
) {
  if (program_has_ended()) return;

  commit_valid = true;
  commit_pc = retired_pc;
  commit_inst = retired_inst;

  for (int i = 0; i < 32; i++) cpu.gpr[i] = gpr[i];
  cpu.pc = pc;
  cpu.mstatus = mstatus;
  cpu.mtvec = mtvec;
  cpu.mepc = mepc;
  cpu.mcause = mcause;

  if (retired_inst == 0x00100073) {
    npc_state.state = NPC_END;
    npc_state.halt_pc = retired_pc;
    npc_state.halt_ret = cpu.gpr[10];
  }
}

bool npc_fetch_commit(vaddr_t *pc, uint32_t *inst) {
  if (!commit_valid) return false;
  *pc = commit_pc;
  *inst = commit_inst;
  commit_valid = false;
  return true;
}

void npc_reset_commit_state(vaddr_t pc) {
  commit_valid = false;
  commit_pc = pc;
  commit_inst = 0;
  memset(&cpu, 0, sizeof(cpu));
  cpu.pc = pc;
  cpu.mstatus = 0x1800;
  cpu.mtvec = 1;
}
