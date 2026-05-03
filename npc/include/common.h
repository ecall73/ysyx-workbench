#ifndef __COMMON_H__
#define __COMMON_H__

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// Memory size 128MB
#define MEM_SIZE 0x8000000
#define MAX_SIM_TIME 100000000
#define SERIAL_PORT 0x10000000
#define RTC_ADDR    0x00100048

extern uint8_t pmem[MEM_SIZE];
extern Vtop* g_top;
extern VerilatedContext* g_contextp;
extern VerilatedVcdC* g_tfp;

extern bool is_finished;
extern int trap_a0;
extern int trap_pc;
extern bool sdb_batch_mode;

// memory
bool check_bound(int addr, const char* type);
long load_image(char *img_file);

// cpu
void cpu_exec(uint64_t n);

// sdb
void sdb_mainloop();

#endif
