#ifndef __NPC_UTILS_H__
#define __NPC_UTILS_H__

#include <stdio.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

extern FILE *log_fp;

const char *npc_log_file(const char *file);
void _Log(const char *fmt, ...);
void init_log(const char *log_file);
void close_log();

#define Log(format, ...) \
  _Log(ANSI_FMT("[%s:%d %s] " format, ANSI_FG_BLUE) "\n", \
       npc_log_file(__FILE__), __LINE__, __func__, ##__VA_ARGS__)

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
void ftrace_call(vaddr_t pc, vaddr_t target);
void ftrace_ret(vaddr_t pc);

void npc_trace_read(int addr, int len, int data);
void npc_trace_write(int addr, int len, int data, int wstrb);

#ifdef __cplusplus
}
#endif

#endif
