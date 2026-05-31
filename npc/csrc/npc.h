#ifndef __NPC_H__
#define __NPC_H__

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "sim_mode.h"
class VerilatedContext;
class VerilatedVcdC;

// ----------- log -----------

#define ANSI_FG_BLACK   "\33[1;30m"
#define ANSI_FG_RED     "\33[1;31m"
#define ANSI_FG_GREEN   "\33[1;32m"
#define ANSI_FG_YELLOW  "\33[1;33m"
#define ANSI_FG_BLUE    "\33[1;34m"
#define ANSI_FG_MAGENTA "\33[1;35m"
#define ANSI_FG_CYAN    "\33[1;36m"
#define ANSI_FG_WHITE   "\33[1;37m"
#define ANSI_BG_BLACK   "\33[1;40m"
#define ANSI_BG_RED     "\33[1;41m"
#define ANSI_BG_GREEN   "\33[1;42m"
#define ANSI_BG_YELLOW  "\33[1;43m"
#define ANSI_BG_BLUE    "\33[1;44m"
#define ANSI_BG_MAGENTA "\33[1;45m"
#define ANSI_BG_CYAN    "\33[1;46m"
#define ANSI_BG_WHITE   "\33[1;47m"
#define ANSI_NONE       "\33[0m"

#define ANSI_FMT(str, fmt) fmt str ANSI_NONE

const char *npc_log_file(const char *file);
void _Log(const char *fmt, ...);
void init_log(const char *log_file);

#define Log(format, ...) \
    _Log(ANSI_FMT("[%s:%d %s] " format, ANSI_FG_BLUE) "\n", \
         npc_log_file(__FILE__), __LINE__, __func__, ##__VA_ARGS__)

// Memory size 128MB
#define MEM_SIZE 0x8000000
#define MAX_SIM_TIME 1000000000
#define SERIAL_PORT 0x10000000
#define RTC_ADDR    0x00100048

// Unified memory map constants.
#define NPC_PMEM_BASE        0x80000000u
#define NPC_PMEM_SIZE        MEM_SIZE
#define NPC_FLASH_BASE       0x30000000u
#define NPC_FLASH_SIZE       0x01000000u
#define NPC_SRAM_BASE        0x0f000000u
#define NPC_SRAM_SIZE        0x00002000u
#define NPC_SDRAM_BASE       0xa0000000u
#define NPC_SDRAM_SIZE       0x02000000u
#define NPC_RESET_PC_NPC     NPC_PMEM_BASE
#define NPC_RESET_PC_YSYXSOC NPC_FLASH_BASE

extern bool is_finished;
extern int trap_a0;
extern int trap_pc;
extern uint64_t g_nr_guest_inst;

extern bool sdb_batch_mode;
extern FILE *log_fp;

extern uint8_t pmem[MEM_SIZE];

extern SimTop *g_top;
extern VerilatedContext *g_contextp;
extern VerilatedVcdC *g_tfp;

// main flow (similar to NEMU)
void init_monitor(int argc, char **argv);
void engine_start();
void npc_cleanup();
int is_exit_status_bad();

// sdb
void sdb_set_batch_mode();
void sdb_mainloop();

// cpu
void cpu_exec(uint64_t n);
extern "C" int npc_get_gpr(int idx);
uint32_t npc_read_dut_gpr(int idx);

// difftest
void init_difftest(const char *ref_so_file, long img_size, int port);
bool difftest_step(uint32_t dut_pc, uint32_t dut_inst);
bool difftest_is_enabled();

// memory and image
bool check_bound(int addr, const char *type);
long load_image(char *img_file);
void flash_init_default_image();
bool flash_load_boot_image(const char *img_file);
bool flash_get_boot_image_info(uint32_t *base, const uint8_t **img, size_t *size);

// disasm
void init_disasm();
void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);

// commit callback from RTL
extern "C" void npc_commit(int pc, int inst);

#endif
