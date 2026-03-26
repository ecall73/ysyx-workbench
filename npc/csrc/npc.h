#ifndef __NPC_H__
#define __NPC_H__

#include <stdint.h>
#include <stdbool.h>

// Memory size 128MB
#define MEM_SIZE 0x8000000
#define MAX_SIM_TIME 100000000
#define SERIAL_PORT 0x10000000
#define RTC_ADDR    0x10000048

extern bool is_finished;
extern int trap_a0;
extern int trap_pc;
extern bool sdb_batch_mode;

extern uint8_t pmem[];

bool check_bound(int addr, const char* type);
long load_image(char *img_file);
void sdb_mainloop();
void cpu_exec(uint64_t n);
void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);

#endif
