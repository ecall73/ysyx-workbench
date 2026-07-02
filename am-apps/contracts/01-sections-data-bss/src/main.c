#define CONTRACT_ID "01-sections-data-bss"
#include <contract.h>

static uint32_t data_word = 0x13579bdfu;
static uint8_t data_bytes[8] = {0x13, 0x57, 0x9b, 0xdf, 0x24, 0x68, 0xac, 0xe0};
static uint32_t bss_word;
static uint8_t bss_bytes[64];

static void check_stack(void) {
  volatile uint32_t stack_words[16];
  for (int i = 0; i < 16; i++) {
    stack_words[i] = 0xa5a50000u + (uint32_t)i;
  }
  for (int i = 0; i < 16; i++) {
    CONTRACT_CHECK(stack_words[i] == 0xa5a50000u + (uint32_t)i, "stack");
  }
}

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(data_word == 0x13579bdfu, "data-word");
  for (int i = 0; i < 8; i++) {
    static const uint8_t exp[8] = {0x13, 0x57, 0x9b, 0xdf, 0x24, 0x68, 0xac, 0xe0};
    CONTRACT_CHECK(data_bytes[i] == exp[i], "data-bytes");
  }

  CONTRACT_CHECK(bss_word == 0, "bss-word");
  for (int i = 0; i < 64; i++) {
    CONTRACT_CHECK(bss_bytes[i] == 0, "bss-bytes");
    bss_bytes[i] = (uint8_t)(0x40 + i);
  }
  for (int i = 0; i < 64; i++) {
    CONTRACT_CHECK(bss_bytes[i] == (uint8_t)(0x40 + i), "bss-write");
  }

  check_stack();
  contract_pass();
}
