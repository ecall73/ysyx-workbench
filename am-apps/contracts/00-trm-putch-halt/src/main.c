#define CONTRACT_ID "00-trm-putch-halt"
#include <contract.h>

int main(const char *args) {
  (void)args;
  contract_begin();
  contract_puts("TRM_PUTCH_TOKEN\n");
  contract_pass();
}
