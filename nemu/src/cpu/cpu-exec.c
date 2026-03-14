/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <cpu/cpu.h>
#include <cpu/decode.h>
#include <cpu/difftest.h>
#include <locale.h>

/* The assembly code of instructions executed is only output to the screen
 * when the number of instructions executed is less than this value.
 * This is useful when you use the `si' command.
 * You can modify this value as you want.
 */
#define MAX_INST_TO_PRINT 10

CPU_state cpu = {};
uint64_t g_nr_guest_inst = 0;
static uint64_t g_timer = 0; // unit: us
static bool g_print_step = false;

#define IRINGBUF_SIZE 16

typedef struct {
  bool valid;
  char text[128];
} IRingBufSlot;

static IRingBufSlot iringbuf[IRINGBUF_SIZE] = {};
static int iringbuf_wptr = 0;
static int iringbuf_count = 0;
static Decode *cur_exec = NULL;

static void format_inst_trace(const Decode *s, char *buf, size_t size) {
  char *p = buf;
  p += snprintf(p, size, FMT_WORD ":", s->pc);

  int ilen = s->snpc - s->pc;
  int ilen_max = MUXDEF(CONFIG_ISA_x86, 8, 4);
  if (ilen <= 0 || ilen > ilen_max) ilen = ilen_max;

  int i;
  uint8_t *inst = (uint8_t *)&s->isa.inst;
#ifdef CONFIG_ISA_x86
  for (i = 0; i < ilen; i ++) {
#else
  for (i = ilen - 1; i >= 0; i --) {
#endif
    p += snprintf(p, 4, " %02x", inst[i]);
  }

  int space_len = ilen_max - ilen;
  if (space_len < 0) space_len = 0;
  space_len = space_len * 3 + 1;
  memset(p, ' ', space_len);
  p += space_len;

#if defined(CONFIG_ITRACE) || defined(CONFIG_IQUEUE)
  void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);
  disassemble(p, buf + size - p,
      MUXDEF(CONFIG_ISA_x86, s->snpc, s->pc), (uint8_t *)&s->isa.inst, ilen);
#endif
}

static void iringbuf_push(const Decode *s) {
  format_inst_trace(s, iringbuf[iringbuf_wptr].text, sizeof(iringbuf[iringbuf_wptr].text));
  iringbuf[iringbuf_wptr].valid = true;
  iringbuf_wptr = (iringbuf_wptr + 1) % IRINGBUF_SIZE;
  if (iringbuf_count < IRINGBUF_SIZE) iringbuf_count ++;
}

static void iringbuf_dump(int focus) {
  if (iringbuf_count == 0) return;

  puts("Instruction ring buffer (oldest -> newest):");
  for (int i = 0; i < iringbuf_count; i ++) {
    int idx = (iringbuf_wptr - iringbuf_count + i + IRINGBUF_SIZE) % IRINGBUF_SIZE;
    if (!iringbuf[idx].valid) continue;
    printf("%s %s\n", (idx == focus ? "-->" : "   "), iringbuf[idx].text);
  }
}

void device_update();

static void trace_and_difftest(Decode *_this, vaddr_t dnpc) {
#ifdef CONFIG_ITRACE_COND
  if (ITRACE_COND) { log_write("%s\n", _this->logbuf); }
#endif
  if (g_print_step) { IFDEF(CONFIG_ITRACE, puts(_this->logbuf)); }
  IFDEF(CONFIG_DIFFTEST, difftest_step(_this->pc, dnpc));

#ifdef CONFIG_WATCHPOINT
  bool wp_check();
  if (wp_check()) {
    nemu_state.state = NEMU_STOP;
  }
#endif
}

static void exec_once(Decode *s, vaddr_t pc) {
  s->pc = pc;
  s->snpc = pc;
  cur_exec = s;
  isa_exec_once(s);
  cur_exec = NULL;
  cpu.pc = s->dnpc;
#ifdef CONFIG_ITRACE
  format_inst_trace(s, s->logbuf, sizeof(s->logbuf));
#endif
  iringbuf_push(s);
}

static void execute(uint64_t n) {
  Decode s;
  for (;n > 0; n --) {
    exec_once(&s, cpu.pc);
    g_nr_guest_inst ++;
    trace_and_difftest(&s, cpu.pc);
    if (nemu_state.state != NEMU_RUNNING) break;
    IFDEF(CONFIG_DEVICE, device_update());
  }
}

static void statistic() {
  IFNDEF(CONFIG_TARGET_AM, setlocale(LC_NUMERIC, ""));
#define NUMBERIC_FMT MUXDEF(CONFIG_TARGET_AM, "%", "%'") PRIu64
  Log("host time spent = " NUMBERIC_FMT " us", g_timer);
  Log("total guest instructions = " NUMBERIC_FMT, g_nr_guest_inst);
  if (g_timer > 0) Log("simulation frequency = " NUMBERIC_FMT " inst/s", g_nr_guest_inst * 1000000 / g_timer);
  else Log("Finish running in less than 1 us and can not calculate the simulation frequency");
}

void assert_fail_msg() {
  int focus = -1;
  if (cur_exec != NULL) {
    iringbuf_push(cur_exec);
    focus = (iringbuf_wptr + IRINGBUF_SIZE - 1) % IRINGBUF_SIZE;
  }
  iringbuf_dump(focus);
  isa_reg_display();
  statistic();
}

/* Simulate how the CPU works. */
void cpu_exec(uint64_t n) {
  g_print_step = (n < MAX_INST_TO_PRINT);
  switch (nemu_state.state) {
    case NEMU_END: case NEMU_ABORT: case NEMU_QUIT:
      printf("Program execution has ended. To restart the program, exit NEMU and run again.\n");
      return;
    default: nemu_state.state = NEMU_RUNNING;
  }

  uint64_t timer_start = get_time();

  execute(n);

  uint64_t timer_end = get_time();
  g_timer += timer_end - timer_start;

  switch (nemu_state.state) {
    case NEMU_RUNNING: nemu_state.state = NEMU_STOP; break;

    case NEMU_END: case NEMU_ABORT:
      Log("nemu: %s at pc = " FMT_WORD,
          (nemu_state.state == NEMU_ABORT ? ANSI_FMT("ABORT", ANSI_FG_RED) :
           (nemu_state.halt_ret == 0 ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN) :
            ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED))),
          nemu_state.halt_pc);
      // fall through
    case NEMU_QUIT: statistic();
  }
}
