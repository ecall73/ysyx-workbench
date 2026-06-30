#ifndef __NPC_COMMON_H__
#define __NPC_COMMON_H__

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "sim_top.h"

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

#define MEM_SIZE 0x8000000
#define SERIAL_PORT 0x10000000
#define RTC_ADDR    0x00100048

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

#define NPC_PMU_EVT_IFETCH_FIRE        (1u << 0)
#define NPC_PMU_EVT_ICACHE_MISS        (1u << 1)
#define NPC_PMU_EVT_ICACHE_MISS_CYCLE  (1u << 2)
#define NPC_PMU_EVT_DCACHE_ACCESS      (1u << 3)
#define NPC_PMU_EVT_DCACHE_STORE       (1u << 4)
#define NPC_PMU_EVT_DCACHE_MISS        (1u << 5)
#define NPC_PMU_EVT_DCACHE_MISS_CYCLE  (1u << 6)
#define NPC_PMU_EVT_REDIRECT           (1u << 7)

#ifndef CONFIG_MAX_SIM_TIME
#define CONFIG_MAX_SIM_TIME 1000000000
#endif

extern bool is_finished;
extern int trap_a0;
extern int trap_pc;
extern uint64_t g_nr_guest_inst;
extern bool sdb_batch_mode;
extern bool sdb_quit;
extern FILE *log_fp;
extern SimTop *g_top;
extern VerilatedContext *g_contextp;
extern VerilatedVcdC *g_tfp;

typedef struct {
  uint32_t gpr[32];
  uint32_t pc;
  uint32_t mstatus;
  uint32_t mtvec;
  uint32_t mepc;
  uint32_t mcause;
} DutState;

const char *npc_log_file(const char *file);
void _Log(const char *fmt, ...);
void init_log(const char *log_file);
void close_log();

#define Log(format, ...) \
  _Log(ANSI_FMT("[%s:%d %s] " format, ANSI_FG_BLUE) "\n", \
       npc_log_file(__FILE__), __LINE__, __func__, ##__VA_ARGS__)

bool npc_trace_enabled();
void init_ftrace_log(const char *log_file);
void init_etrace_log(const char *log_file);
void init_mtrace_log(const char *log_file);
void init_dtrace_log(const char *log_file);
void close_trace_logs();
void itrace_write(const char *fmt, ...);
void ftrace_write(const char *fmt, ...);
void etrace_write(const char *fmt, ...);
void mtrace_write(const char *fmt, ...);
void dtrace_write(const char *fmt, ...);

void init_disasm();
void disassemble(char *str, int size, uint32_t pc, uint32_t inst);

void init_ftrace(const char *elf_file);
void ftrace_check(uint32_t pc, uint32_t inst, uint32_t dnpc);

void init_monitor(int argc, char **argv);
void engine_start();
void npc_cleanup();
int is_exit_status_bad();

void sdb_set_batch_mode();
void sdb_mainloop();

void cpu_exec(uint64_t n);
void npc_read_dut_state(DutState *state);

void init_difftest(const char *ref_so_file, long img_size, int port);
bool difftest_step(uint32_t dut_pc, uint32_t dut_inst, const DutState *dut_post);
bool difftest_is_enabled();

void platform_init();
void platform_cleanup();
void platform_update();
void platform_set_external_idle(SimTop *top);
long platform_load_image(const char *img_file);
bool platform_read_word(uint32_t addr, uint32_t *data);
bool platform_in_comparable_mem(uint32_t addr);
const char *platform_device_name(uint32_t addr);
uint32_t platform_reset_pc();
void platform_difftest_memcpy(void (*ref_memcpy)(uint32_t, void *, size_t, bool), bool direction);
void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void));

extern "C" void npc_commit(int pc, int inst, int dnpc);
extern "C" void npc_pmu_event(int event_mask);
extern "C" void npc_trace_read(int addr, int len, int data);
extern "C" void npc_trace_write(int addr, int len, int data, int wstrb);

#endif
