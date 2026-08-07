#ifndef __CPU_ARCH_EVENT_H__
#define __CPU_ARCH_EVENT_H__

#include <common.h>

enum {
  NPC_ARCH_EVENT_COMMIT = 0,
  NPC_ARCH_EVENT_INTERRUPT = 1,
};

typedef struct {
  uint32_t type;
  union {
    struct {
      vaddr_t pc;
      uint32_t instruction;
      uint32_t instruction_length;
      uint32_t instruction_valid;
    } commit;
    struct {
      uint32_t cause;
      vaddr_t pretrap_pc;
    } interrupt;
  } payload;
} npc_arch_event_t;

#ifdef __cplusplus
extern "C" {
#endif

bool npc_fetch_arch_event(npc_arch_event_t *event);
void npc_reset_commit_state(vaddr_t pc);
void npc_dump_axi_state(void);

#ifdef __cplusplus
}
#endif

#endif
