#ifndef __RISCV32_STATE_H__
#define __RISCV32_STATE_H__

typedef struct riscv_retire_info {
  word_t pre_mcountinhibit;
  bool mcycle_written;
  bool minstret_written;
  bool mcountinhibit_written;
  uint64_t mcycle_write_value;
  uint64_t minstret_write_value;
  word_t mcountinhibit_write_value;
} riscv_retire_info_t;

const riscv_retire_info_t *riscv_begin_arch_step(void);
void riscv_record_counter_write(uint32_t addr);
void riscv_update_arch_state(const riscv_retire_info_t *retire_info);
word_t riscv_mip_value(void);
word_t riscv_sip_value(void);

#endif
