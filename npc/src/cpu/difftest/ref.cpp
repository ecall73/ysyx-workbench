#include <assert.h>
#include <dlfcn.h>

#include "common.h"
#include "cpu/difftest.h"
#include "platform/platform.h"
#include "utils.h"
#include "internal.h"

bool difftest_enabled = false;

void (*ref_difftest_memcpy)(uint32_t addr, void *buf, size_t n, bool direction) = NULL;
void (*ref_difftest_regcpy)(void *dut, bool direction) = NULL;
void (*ref_difftest_exec)(uint64_t n) = NULL;
void (*ref_difftest_raise_intr)(uint64_t NO) = NULL;

bool difftest_is_enabled() {
  return difftest_enabled;
}

void init_difftest(const char *ref_so_file, long img_size, int port) {
  (void)img_size;
  if (ref_so_file == NULL) {
    return;
  }

  void *handle = dlopen(ref_so_file, RTLD_LAZY);
  assert(handle);

  ref_difftest_memcpy = (void (*)(uint32_t, void *, size_t, bool))dlsym(handle, "difftest_memcpy");
  assert(ref_difftest_memcpy);

  ref_difftest_regcpy = (void (*)(void *, bool))dlsym(handle, "difftest_regcpy");
  assert(ref_difftest_regcpy);

  ref_difftest_exec = (void (*)(uint64_t))dlsym(handle, "difftest_exec");
  assert(ref_difftest_exec);

  ref_difftest_raise_intr = (void (*)(uint64_t))dlsym(handle, "difftest_raise_intr");
  assert(ref_difftest_raise_intr);

  void (*ref_difftest_init)(int) = (void (*)(int))dlsym(handle, "difftest_init");
  assert(ref_difftest_init);

  void (*ref_enable_ysyxsoc_paddr)(void) =
      (void (*)(void))dlsym(handle, "difftest_enable_ysyxsoc_paddr");
  platform_enable_ref_paddr(ref_enable_ysyxsoc_paddr);

  ref_difftest_init(port);
  platform_difftest_memcpy(ref_difftest_memcpy, DIFFTEST_TO_REF);
  difftest_init_ref_regs();

  difftest_enabled = true;
  Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
  Log("The result of every retired instruction will be compared with %s", ref_so_file);
}
