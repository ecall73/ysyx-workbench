#ifndef YSYXSOC_H__
#define YSYXSOC_H__

#include <klib-macros.h>
#include <riscv/riscv.h>

#if __riscv_xlen != 32
#error "riscv32e-ysyxsoc must be built with a 32-bit RISC-V target"
#endif

#ifndef __riscv_e
#error "riscv32e-ysyxsoc must be built with RV32E"
#endif

// ysyxSoC canonical address map
#define CLINT_BASE          0x02000000u
#define CLINT_END           0x0200ffffu
#define SRAM_BASE           0x0f000000u
#define SRAM_END            0x0fffffffu
#define UART_BASE           0x10000000u
#define UART_END            0x10000fffu
#define SPI_BASE            0x10001000u
#define SPI_END             0x10001fffu
#define GPIO_BASE           0x10002000u
#define GPIO_END            0x1000200fu
#define PS2_BASE            0x10011000u
#define PS2_END             0x10011007u
#define MROM_BASE           0x20000000u
#define MROM_END            0x20000fffu
#define VGA_BASE            0x21000000u
#define VGA_END             0x211fffffu
#define FLASH_BASE          0x30000000u
#define FLASH_END           0x3fffffffu
#define CHIPLINK_MMIO_BASE  0x40000000u
#define CHIPLINK_MMIO_END   0x7fffffffu
#define PSRAM_BASE          0x80000000u
#define PSRAM_END           0x9fffffffu
#define SDRAM_BASE          0xa0000000u
#define SDRAM_END           0xbfffffffu
#define CHIPLINK_MEM_BASE   0xc0000000u
#define CHIPLINK_MEM_END    0xffffffffu

// Compatibility aliases used by AM runtime
#define DEVICE_BASE     UART_BASE
#define MMIO_BASE       DEVICE_BASE
#define SERIAL_PORT     (UART_BASE + 0x0u)
#define UART_REG_RBR    0x00u
#define UART_REG_THR    0x00u
#define UART_REG_DLL    0x00u
#define UART_REG_IER    0x01u
#define UART_REG_DLM    0x01u
#define UART_REG_FCR    0x02u
#define UART_REG_LCR    0x03u
#define UART_REG_LSR    0x05u
#define UART_LSR_DR     0x01u
#define UART_LCR_DLAB   0x80u
#define UART_LCR_8N1    0x03u
#define UART_LSR_THRE   0x20u
#define KBD_ADDR        PS2_BASE
#define CLINT_MTIME     0x0200bff8u
#define CLINT_MTIMEH    0x0200bffcu
// ysyxSoC has no standalone RTC block in this map; use CLINT mtime window.
#define RTC_ADDR        CLINT_MTIME

#define NPC_CPU_FREQ_HZ 1000000ull
#define NPC_CLINT_CYCLES_PER_US (NPC_CPU_FREQ_HZ / 1000000ull)
#define VGACTL_ADDR     VGA_BASE
#define AUDIO_ADDR      SPI_BASE
#define DISK_ADDR       FLASH_BASE
#define FB_ADDR         VGA_BASE
#define AUDIO_SBUF_ADDR SPI_BASE

extern char _heap_start;
extern char _heap_end;

typedef uintptr_t PTE;

#define PGSIZE    4096

_Static_assert(CLINT_MTIME >= CLINT_BASE && CLINT_MTIMEH <= CLINT_END,
    "ysyxSoC AM CLINT mtime aliases must stay inside CLINT range");
_Static_assert(CLINT_BASE == 0x02000000u && CLINT_MTIME == 0x0200bff8u,
    "ysyxSoC AM CLINT addresses must match the SoC map");
_Static_assert(CLINT_MTIMEH == CLINT_MTIME + 4,
    "ysyxSoC AM CLINT mtime high word must follow low word");
_Static_assert(RTC_ADDR == CLINT_MTIME,
    "ysyxSoC AM RTC alias must use CLINT mtime");
_Static_assert(UART_BASE == 0x10000000u,
    "ysyxSoC AM UART base must match the SoC map");
_Static_assert(SERIAL_PORT >= UART_BASE && SERIAL_PORT <= UART_END,
    "ysyxSoC AM serial alias must stay inside UART range");
_Static_assert((UART_BASE + UART_REG_LSR) <= UART_END,
    "ysyxSoC AM UART register offsets must stay inside UART range");
_Static_assert(PS2_BASE == 0x10011000u,
    "ysyxSoC AM PS/2 base must match the SoC map");
_Static_assert(KBD_ADDR == PS2_BASE,
    "ysyxSoC AM keyboard alias must use PS/2 base");
_Static_assert(VGA_BASE == 0x21000000u,
    "ysyxSoC AM VGA base must match the SoC map");
_Static_assert(FB_ADDR == VGA_BASE && VGACTL_ADDR == VGA_BASE,
    "ysyxSoC AM GPU aliases must use VGA base");
_Static_assert(GPIO_BASE == 0x10002000u,
    "ysyxSoC AM GPIO base must match the SoC map");
_Static_assert((GPIO_BASE + 0x8u) <= GPIO_END,
    "ysyxSoC AM GPIO LED/SW/SEG offsets must stay inside GPIO range");
_Static_assert(SRAM_BASE == 0x0f000000u && FLASH_BASE == 0x30000000u
    && SDRAM_BASE == 0xa0000000u,
    "ysyxSoC AM memory bases must match the SoC map");
_Static_assert(NPC_CPU_FREQ_HZ % 1000000ull == 0,
    "ysyxSoC AM timer conversion requires an integral cycles/us ratio");
_Static_assert(NPC_CLINT_CYCLES_PER_US > 0,
    "ysyxSoC AM timer conversion requires nonzero cycles/us");

#endif
