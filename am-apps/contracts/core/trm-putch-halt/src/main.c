#include <contract.h>

int main(const char *args) {
  (void)args;
  contract_begin();
  contract_puts("TRM_PUTCH_TOKEN\n");
  contract_pass();
}
