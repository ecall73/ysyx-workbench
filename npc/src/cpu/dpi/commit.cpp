#include <cpu/cpu.h>
#include <isa.h>

bool npc_commit_valid = false;
vaddr_t npc_commit_pc = 0;
uint32_t npc_commit_inst = 0;
static uint32_t shadow_mstatus = 0x1800;
static uint32_t shadow_mtvec = 1;
static uint32_t shadow_mepc = 0;
static uint32_t shadow_mcause = 0;

enum {
  MSTATUS_MIE  = (1u << 3),
  MSTATUS_MPIE = (1u << 7),
  MSTATUS_MPP  = (3u << 11),
};

static bool program_has_ended() {
  return npc_state.state == NPC_END || npc_state.state == NPC_ABORT || npc_state.state == NPC_QUIT;
}

static void commit_csr(uint32_t pc, uint32_t inst,
    uint32_t mstatus, uint32_t mtvec, uint32_t mepc, uint32_t mcause) {
  uint32_t opcode = inst & 0x7fu;
  if (opcode != 0x73) {
    return;
  }

  uint32_t funct3 = BITS(inst, 14, 12);
  uint32_t csr = BITS(inst, 31, 20);

  if (funct3 == 0) {
    if (csr == 0) {
      uint32_t mie = (shadow_mstatus & MSTATUS_MIE) ? 1 : 0;
      shadow_mstatus = (shadow_mstatus & ~MSTATUS_MPIE) | (mie ? MSTATUS_MPIE : 0);
      shadow_mstatus &= ~MSTATUS_MIE;
      shadow_mstatus = (shadow_mstatus & ~MSTATUS_MPP) | MSTATUS_MPP;
      shadow_mepc = pc;
      shadow_mcause = 11;
    } else if (csr == 0x302) {
      uint32_t mpie = (shadow_mstatus & MSTATUS_MPIE) ? 1 : 0;
      shadow_mstatus = (shadow_mstatus & ~MSTATUS_MIE) | (mpie ? MSTATUS_MIE : 0);
      shadow_mstatus |= MSTATUS_MPIE;
      shadow_mstatus &= ~MSTATUS_MPP;
    }
  } else {
    shadow_mstatus = mstatus;
    shadow_mtvec = mtvec;
    shadow_mepc = mepc;
    shadow_mcause = mcause;
  }
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
  commit_csr(commit_pc, commit_inst, mstatus, mtvec, mepc, mcause);

  for (int i = 0; i < 32; i++) cpu.gpr[i] = gpr[i];
  cpu.pc = pc;
  cpu.mstatus = shadow_mstatus;
  cpu.mtvec = shadow_mtvec;
  cpu.mepc = shadow_mepc;
  cpu.mcause = shadow_mcause;

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
  shadow_mstatus = 0x1800;
  shadow_mtvec = 1;
  shadow_mepc = 0;
  shadow_mcause = 0;
  cpu.mstatus = shadow_mstatus;
  cpu.mtvec = shadow_mtvec;
  cpu.mepc = shadow_mepc;
  cpu.mcause = shadow_mcause;
}
