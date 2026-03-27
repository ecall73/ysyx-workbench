#include <assert.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "Vtop.h"
#include "npc.h"

enum { DIFFTEST_TO_DUT = 0, DIFFTEST_TO_REF = 1 };

typedef struct {
    uint32_t gpr[32];
    uint32_t pc;
} RefCPUState;

static void *ref_handle = NULL;
static bool difftest_enabled = false;
static uint32_t dut_gpr_shadow[32] = {};

static void (*ref_difftest_memcpy)(uint32_t addr, void *buf, size_t n, bool direction) = NULL;
static void (*ref_difftest_regcpy)(void *dut, bool direction) = NULL;
static void (*ref_difftest_exec)(uint64_t n) = NULL;
static void (*ref_difftest_raise_intr)(uint64_t NO) = NULL;
static void (*ref_difftest_init)(int port) = NULL;

static void collect_dut_regs(RefCPUState *dut_r) {
    memset(dut_r, 0, sizeof(*dut_r));
    for (int i = 0; i < 32; i++) {
        dut_r->gpr[i] = g_top->debug_reg_file[i];
    }
    // Architectural PC before first retire.
    dut_r->pc = 0x80000000u;
}

static bool difftest_checkregs(const RefCPUState *ref_r, const RefCPUState *dut_r, uint32_t dut_pc) {
    for (int i = 0; i < 32; i++) {
        if (ref_r->gpr[i] != dut_r->gpr[i]) {
            Log("difftest error at pc = 0x%08x: gpr[%d] mismatch, ref = 0x%08x, dut = 0x%08x",
                dut_pc, i, ref_r->gpr[i], dut_r->gpr[i]);
            return false;
        }
    }
    return true;
}

bool difftest_is_enabled() {
    return difftest_enabled;
}

void init_difftest(const char *ref_so_file, long img_size, int port) {
    if (ref_so_file == NULL) {
        return;
    }

    ref_handle = dlopen(ref_so_file, RTLD_LAZY);
    assert(ref_handle);

    ref_difftest_memcpy = (void (*)(uint32_t, void *, size_t, bool))dlsym(ref_handle, "difftest_memcpy");
    assert(ref_difftest_memcpy);

    ref_difftest_regcpy = (void (*)(void *, bool))dlsym(ref_handle, "difftest_regcpy");
    assert(ref_difftest_regcpy);

    ref_difftest_exec = (void (*)(uint64_t))dlsym(ref_handle, "difftest_exec");
    assert(ref_difftest_exec);

    ref_difftest_raise_intr = (void (*)(uint64_t))dlsym(ref_handle, "difftest_raise_intr");
    assert(ref_difftest_raise_intr);

    ref_difftest_init = (void (*)(int))dlsym(ref_handle, "difftest_init");
    assert(ref_difftest_init);

    ref_difftest_init(port);

    if (img_size > 0) {
        ref_difftest_memcpy(0x80000000u, pmem, (size_t)img_size, DIFFTEST_TO_REF);
    }

    RefCPUState dut_r;
    collect_dut_regs(&dut_r);
    for (int i = 0; i < 32; i++) {
        dut_gpr_shadow[i] = dut_r.gpr[i];
    }
    ref_difftest_regcpy(&dut_r, DIFFTEST_TO_REF);

    difftest_enabled = true;
    Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
    Log("The result of every instruction will be compared with %s", ref_so_file);
}

bool difftest_step(uint32_t dut_pc, bool dut_wen, uint8_t dut_waddr, uint32_t dut_wdata) {
    if (!difftest_enabled) {
        return true;
    }

    // Pre-check PC alignment at the instruction boundary.
    RefCPUState ref_pre;
    ref_difftest_regcpy(&ref_pre, DIFFTEST_TO_DUT);
    if (ref_pre.pc != dut_pc) {
        Log("difftest error at pc = 0x%08x: pc mismatch before exec, ref = 0x%08x, dut = 0x%08x",
            dut_pc, ref_pre.pc, dut_pc);
        return false;
    }

    ref_difftest_exec(1);

    RefCPUState ref_post;
    RefCPUState dut_post;
    ref_difftest_regcpy(&ref_post, DIFFTEST_TO_DUT);

    // DUT architectural state after this retirement, built from WB commit info.
    if (dut_wen && dut_waddr != 0) {
        dut_gpr_shadow[dut_waddr] = dut_wdata;
    }
    dut_gpr_shadow[0] = 0;
    for (int i = 0; i < 32; i++) {
        dut_post.gpr[i] = dut_gpr_shadow[i];
    }
    dut_post.pc = ref_post.pc;

    return difftest_checkregs(&ref_post, &dut_post, dut_pc);
}
