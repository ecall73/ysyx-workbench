#include <cpu/arch-event.h>
#include <cpu/cpu.h>
#include <isa.h>

static bool event_pending = false;
static npc_arch_event_t pending_event = {};

typedef struct {
  uint64_t samples;
  uint64_t aw_count;
  uint64_t w_count;
  uint64_t b_count;
  uint32_t aw_valid;
  uint32_t aw_ready;
  uint32_t aw_addr;
  uint32_t aw_len;
  uint32_t w_valid;
  uint32_t w_ready;
  uint32_t w_data;
  uint32_t w_last;
  uint32_t b_valid;
  uint32_t b_ready;
  uint32_t b_id;
  uint32_t b_resp;
  uint32_t last_aw_addr;
  uint32_t last_aw_len;
  uint32_t last_w_data;
  uint32_t last_w_last;
  uint32_t last_b_id;
  uint32_t last_b_resp;
} npc_axi_state_t;

static npc_axi_state_t axi_state = {};

static bool program_has_ended() {
  return npc_state.state == NPC_END || npc_state.state == NPC_ABORT || npc_state.state == NPC_QUIT;
}

extern "C" void npc_axi_sample(
    uint32_t aw_valid, uint32_t aw_ready, uint32_t aw_addr,
    uint32_t aw_len, uint32_t w_valid, uint32_t w_ready,
    uint32_t w_data, uint32_t w_last, uint32_t b_valid,
    uint32_t b_ready, uint32_t b_id, uint32_t b_resp) {
  axi_state.samples++;
  axi_state.aw_valid = aw_valid;
  axi_state.aw_ready = aw_ready;
  axi_state.aw_addr = aw_addr;
  axi_state.aw_len = aw_len;
  axi_state.w_valid = w_valid;
  axi_state.w_ready = w_ready;
  axi_state.w_data = w_data;
  axi_state.w_last = w_last;
  axi_state.b_valid = b_valid;
  axi_state.b_ready = b_ready;
  axi_state.b_id = b_id;
  axi_state.b_resp = b_resp;
  if (aw_valid && aw_ready) {
    axi_state.aw_count++;
    axi_state.last_aw_addr = aw_addr;
    axi_state.last_aw_len = aw_len;
  }
  if (w_valid && w_ready) {
    axi_state.w_count++;
    axi_state.last_w_data = w_data;
    axi_state.last_w_last = w_last;
  }
  if (b_valid && b_ready) {
    axi_state.b_count++;
    axi_state.last_b_id = b_id;
    axi_state.last_b_resp = b_resp;
  }
}

void npc_dump_axi_state(void) {
  Log("AXI write state: samples=%" PRIu64 " aw=%" PRIu64
      " w=%" PRIu64 " b=%" PRIu64,
      axi_state.samples, axi_state.aw_count, axi_state.w_count,
      axi_state.b_count);
  Log("AXI current: AW v/r=%u/%u addr=" FMT_WORD " len=%u; "
      "W v/r=%u/%u data=" FMT_WORD " last=%u; "
      "B v/r=%u/%u id=%u resp=%u",
      axi_state.aw_valid, axi_state.aw_ready, axi_state.aw_addr,
      axi_state.aw_len, axi_state.w_valid, axi_state.w_ready,
      axi_state.w_data, axi_state.w_last, axi_state.b_valid,
      axi_state.b_ready, axi_state.b_id, axi_state.b_resp);
  Log("AXI last handshakes: AW addr=" FMT_WORD " len=%u; "
      "W data=" FMT_WORD " last=%u; B id=%u resp=%u",
      axi_state.last_aw_addr, axi_state.last_aw_len,
      axi_state.last_w_data, axi_state.last_w_last,
      axi_state.last_b_id, axi_state.last_b_resp);
}

extern "C" void npc_arch_event(
    uint32_t event_type,
    uint32_t instruction_pc,
    uint32_t instruction_bits,
    uint32_t instruction_length,
    uint32_t instruction_valid,
    uint32_t cause,
    uint32_t pretrap_pc,
    uint32_t post_pc,
    uint32_t priv,
    uint32_t mstatus,
    uint32_t mtvec,
    uint32_t mepc,
    uint32_t mcause,
    uint32_t mtval,
    uint32_t medeleg,
    uint32_t mideleg,
    uint32_t mie,
    uint32_t stvec,
    uint32_t sepc,
    uint32_t scause,
    uint32_t stval,
    uint32_t sscratch,
    uint32_t satp,
    uint32_t mscratch,
    uint32_t menvcfgh,
    uint32_t mcounteren,
    uint32_t scounteren,
    uint32_t mcountinhibit,
    const uint32_t *gpr
) {
  if (program_has_ended()) return;
  Assert(!event_pending,
      "DPI architecture event overwrites an unconsumed event: old_type=%u new_type=%u",
      pending_event.type, event_type);
  Assert(event_type == NPC_ARCH_EVENT_COMMIT ||
      event_type == NPC_ARCH_EVENT_INTERRUPT,
      "DPI architecture event has invalid type=%u", event_type);
  Assert(gpr != NULL, "DPI architecture event has a null GPR pointer");
  Assert((post_pc & 0x1u) == 0 && priv <= 3 && priv != 2 && gpr[0] == 0,
      "DPI architecture state is invalid: post_pc=" FMT_WORD
      " priv=%u x0=" FMT_WORD, post_pc, priv, gpr[0]);

  for (int i = 0; i < 32; i++) cpu.gpr[i] = gpr[i];
  cpu.pc = post_pc;
  cpu.priv = priv;
  cpu.mstatus = mstatus;
  cpu.mtvec = mtvec;
  cpu.mepc = mepc;
  cpu.mcause = mcause;
  cpu.mtval = mtval;
  cpu.medeleg = medeleg;
  cpu.mideleg = mideleg;
  cpu.mie = mie;
  cpu.stvec = stvec;
  cpu.sepc = sepc;
  cpu.scause = scause;
  cpu.stval = stval;
  cpu.sscratch = sscratch;
  cpu.satp = satp;
  cpu.mscratch = mscratch;
  cpu.menvcfgh = menvcfgh;
  cpu.mcounteren = mcounteren;
  cpu.scounteren = scounteren;
  cpu.mcountinhibit = mcountinhibit;

  pending_event.type = event_type;
  if (event_type == NPC_ARCH_EVENT_COMMIT) {
    Assert((instruction_pc & 0x1u) == 0 &&
        (instruction_length == 2 || instruction_length == 4) &&
        instruction_valid <= 1,
        "DPI commit metadata is invalid: pc=" FMT_WORD
        " inst=0x%08x length=%u valid=%u",
        instruction_pc, instruction_bits, instruction_length,
        instruction_valid);
    if (instruction_valid) {
      Assert(instruction_length == 2
          ? ((instruction_bits & 0xffff0000u) == 0 &&
             (instruction_bits & 0x3u) != 0x3u)
          : ((instruction_bits & 0x3u) == 0x3u),
          "DPI commit instruction encoding disagrees with its length: "
          "pc=" FMT_WORD " inst=0x%08x length=%u",
          instruction_pc, instruction_bits, instruction_length);
    }

    bool is_ebreak = instruction_valid &&
        ((instruction_length == 4 && instruction_bits == 0x00100073u) ||
         (instruction_length == 2 && instruction_bits == 0x00009002u));
    if (is_ebreak) {
      event_pending = false;
      pending_event = {};
      npc_state.state = NPC_END;
      npc_state.halt_pc = instruction_pc;
      npc_state.halt_ret = cpu.gpr[10];
      return;
    }

    pending_event.payload.commit.pc = instruction_pc;
    pending_event.payload.commit.instruction = instruction_bits;
    pending_event.payload.commit.instruction_length = instruction_length;
    pending_event.payload.commit.instruction_valid = instruction_valid;
  } else {
    Assert((cause & 0x80000000u) != 0 && (pretrap_pc & 0x1u) == 0,
        "DPI interrupt metadata is invalid: cause=" FMT_WORD
        " pretrap_pc=" FMT_WORD, cause, pretrap_pc);
    Assert(instruction_pc == 0 && instruction_bits == 0 &&
        instruction_length == 0 && instruction_valid == 0,
        "DPI interrupt carries instruction metadata");
    pending_event.payload.interrupt.cause = cause;
    pending_event.payload.interrupt.pretrap_pc = pretrap_pc;
  }
  event_pending = true;
}

bool npc_fetch_arch_event(npc_arch_event_t *event) {
  Assert(event != NULL, "npc_fetch_arch_event with null output");
  if (!event_pending) return false;
  *event = pending_event;
  pending_event = {};
  event_pending = false;
  return true;
}

void npc_reset_commit_state(vaddr_t pc) {
  Assert((pc & 0x1) == 0, "reset commit pc is unaligned: pc=" FMT_WORD, pc);
  event_pending = false;
  pending_event = {};
  axi_state = {};
  memset(&cpu, 0, sizeof(cpu));
  cpu.pc = pc;
  cpu.priv = 3;
  cpu.mstatus = 0x1800;
}
