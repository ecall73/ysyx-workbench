#include <am.h>
#include <stdint.h>

#define SPI_BASE       0x10001000u

#define SPI_TX0_ADDR   (SPI_BASE + 0x00u)
#define SPI_RX0_ADDR   (SPI_BASE + 0x00u)
#define SPI_TX1_ADDR   (SPI_BASE + 0x04u)
#define SPI_RX1_ADDR   (SPI_BASE + 0x04u)
#define SPI_CTRL_ADDR  (SPI_BASE + 0x10u)
#define SPI_DIV_ADDR   (SPI_BASE + 0x14u)
#define SPI_SS_ADDR    (SPI_BASE + 0x18u)

#define SPI_CTRL_ASS       (1u << 13)
#define SPI_CTRL_IE        (1u << 12)
#define SPI_CTRL_LSB       (1u << 11)
#define SPI_CTRL_TX_NEG    (1u << 10)
#define SPI_CTRL_RX_NEG    (1u << 9)
#define SPI_CTRL_GO        (1u << 8)
#define SPI_CTRL_CHAR_MASK 0x7fu

#define FLASH_CMD_READ             0x03u
#define FLASH_SS                   (1u << 0)
#define FLASH_PAYLOAD_OFF          0x1000u
#define FLASH_PAYLOAD_MAGIC        0x43485254u
#define FLASH_PAYLOAD_HEADER_SIZE  12u

static inline uint32_t mmio_read32(uintptr_t addr) {
  return *(volatile uint32_t *)addr;
}

static inline void mmio_write32(uintptr_t addr, uint32_t data) {
  *(volatile uint32_t *)addr = data;
}

static inline uint32_t bswap32(uint32_t x) {
  return ((x & 0x000000ffu) << 24) |
         ((x & 0x0000ff00u) << 8) |
         ((x & 0x00ff0000u) >> 8) |
         ((x & 0xff000000u) >> 24);
}

static inline uintptr_t align_up(uintptr_t x, uintptr_t a) {
  return (x + (a - 1u)) & ~(a - 1u);
}

static uint32_t flash_read(uint32_t addr) {
  uint32_t off = addr & 0x00fffffcu;
  uint32_t tx1 = (FLASH_CMD_READ << 24) | (off & 0x00ffffffu);

  mmio_write32(SPI_DIV_ADDR, 0u);
  mmio_write32(SPI_SS_ADDR, FLASH_SS);
  mmio_write32(SPI_TX1_ADDR, tx1);
  mmio_write32(SPI_TX0_ADDR, 0u);

  uint32_t ctrl = SPI_CTRL_ASS | SPI_CTRL_TX_NEG | (64u & SPI_CTRL_CHAR_MASK);
  ctrl &= ~(SPI_CTRL_IE | SPI_CTRL_LSB | SPI_CTRL_RX_NEG);
  mmio_write32(SPI_CTRL_ADDR, ctrl | SPI_CTRL_GO);

  while ((mmio_read32(SPI_CTRL_ADDR) & SPI_CTRL_GO) != 0u) {
  }

  (void)mmio_read32(SPI_RX1_ADDR);
  return bswap32(mmio_read32(SPI_RX0_ADDR));
}

static uint8_t flash_read_u8(uint32_t addr) {
  uint32_t word = flash_read(addr & ~0x3u);
  uint32_t shift = (addr & 0x3u) * 8u;
  return (uint8_t)((word >> shift) & 0xffu);
}

int main(void) {
  uint32_t magic = flash_read(FLASH_PAYLOAD_OFF + 0u);
  uint32_t size_bytes = flash_read(FLASH_PAYLOAD_OFF + 4u);
  uint32_t entry_off = flash_read(FLASH_PAYLOAD_OFF + 8u);

  if (magic != FLASH_PAYLOAD_MAGIC) {
    halt(1);
  }
  if ((size_bytes == 0u) || (size_bytes > 0x1000u)) {
    halt(1);
  }
  if (entry_off >= size_bytes) {
    halt(1);
  }

  uintptr_t dst = align_up((uintptr_t)heap.start, 4u);
  uintptr_t limit = (uintptr_t)heap.end;
  if ((dst + size_bytes) > limit) {
    halt(1);
  }

  uint8_t *p = (uint8_t *)dst;
  for (uint32_t i = 0; i < size_bytes; i++) {
    p[i] = flash_read_u8(FLASH_PAYLOAD_OFF + FLASH_PAYLOAD_HEADER_SIZE + i);
  }

  void (*entry)(void) = (void (*)(void))(dst + entry_off);
  asm volatile("mv a0, zero" ::: "a0");
  entry();

  halt(1);
  return 0;
}
