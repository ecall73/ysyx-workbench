#include <am.h>
#include "include/npc.h"
#include <klib.h>
#include <klib-macros.h>

extern char _heap_start;
extern char _heap_end;
int main(const char *args);
void halt(int code);

Area heap = RANGE(&_heap_start, &_heap_end);
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER); // defined in CFLAGS

static inline void uart_write8(uint32_t off, uint8_t val) {
  outb(UART_BASE + off, val);
}

static inline uint8_t uart_read8(uint32_t off) {
  return inb(UART_BASE + off);
}

static void uart_init(void) {
  // Enable divisor latch access.
  uart_write8(UART_REG_LCR, UART_LCR_DLAB);
  // Small divisor for fast transmit in simulation.
  uart_write8(UART_REG_DLL, 0x01u);
  uart_write8(UART_REG_DLM, 0x00u);
  // Restore normal register map and set 8N1 format.
  uart_write8(UART_REG_LCR, UART_LCR_8N1);
  // Enable FIFO and clear TX/RX FIFOs.
  uart_write8(UART_REG_FCR, 0x07u);
}

void putch(char ch) {
  uart_write8(UART_REG_THR, (uint8_t)ch);
}

void halt(int code) {
  (void)code;
  asm volatile("ebreak");
  while (1);
}

void _trm_init() {
  uart_init();
  int ret = main(mainargs);
  halt(ret);
}
