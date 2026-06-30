#include "cpu/cpu.h"

static bool commit_valid = false;
static uint32_t commit_pc = 0;
static uint32_t commit_inst = 0;
static DutState dut_state = {};

static bool program_has_ended() {
  return npc_state == NPC_END || npc_state == NPC_ABORT || npc_state == NPC_QUIT;
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
  if (program_has_ended()) {
    return;
  }

  commit_valid = true;
  commit_pc = retired_pc;
  commit_inst = retired_inst;
  for (int i = 0; i < 16; i++) {
    dut_state.gpr[i] = gpr[i];
  }
  for (int i = 16; i < 32; i++) {
    dut_state.gpr[i] = 0;
  }
  dut_state.pc = pc;
  dut_state.mstatus = mstatus;
  dut_state.mtvec = mtvec;
  dut_state.mepc = mepc;
  dut_state.mcause = mcause;
}

void npc_read_dut_state(DutState *state) {
  *state = dut_state;
}

bool npc_fetch_retired_inst(RetiredInst *retired) {
  if (!commit_valid) {
    return false;
  }

  retired->commit_pc = commit_pc;
  retired->commit_inst = commit_inst;
  retired->state = dut_state;
  commit_valid = false;
  return true;
}

void npc_reset_dut_state(uint32_t pc) {
  commit_valid = false;
  commit_pc = pc;
  commit_inst = 0;
  for (int i = 0; i < 32; i++) {
    dut_state.gpr[i] = 0;
  }
  dut_state.pc = pc;
  dut_state.mstatus = 0x00001800u;
  dut_state.mtvec = 0x00000001u;
  dut_state.mepc = 0;
  dut_state.mcause = 0;
}
