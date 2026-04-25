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
    uint32_t mstatus;
    uint32_t mtvec;
    uint32_t mepc;
    uint32_t mcause;
} RefCPUState;

static void *ref_handle = NULL;
static bool difftest_enabled = false;
static uint32_t dut_gpr_shadow[32] = {};

static void (*ref_difftest_memcpy)(uint32_t addr, void *buf, size_t n, bool direction) = NULL;
static void (*ref_difftest_regcpy)(void *dut, bool direction) = NULL;
static void (*ref_difftest_exec)(uint64_t n) = NULL;
static void (*ref_difftest_raise_intr)(uint64_t NO) = NULL;
static void (*ref_difftest_init)(int port) = NULL;

enum SkipReason {
    SKIP_NONE = 0,
    SKIP_COUNTER_CSR,
    SKIP_MMIO,
};

#define CSR_MCYCLE      0xB00u
#define CSR_MCYCLEH     0xB80u
#define CSR_MINSTRET    0xB02u
#define CSR_MINSTRETH   0xB82u
#define CSR_CYCLE       0xC00u
#define CSR_CYCLEH      0xC80u
#define CSR_TIME        0xC01u
#define CSR_TIMEH       0xC81u
#define CSR_INSTRET     0xC02u
#define CSR_INSTRETH    0xC82u

#define OPCODE_LOAD   0x03u
#define OPCODE_STORE  0x23u
#define OPCODE_SYSTEM 0x73u

static inline int32_t sext(uint32_t val, int bits) {
    uint32_t m = 1u << (bits - 1);
    return (int32_t)((val ^ m) - m);
}

static SkipReason get_skip_reason(uint32_t pc) {
    uint32_t inst = *(uint32_t *)&pmem[pc - 0x80000000u];
    uint32_t opcode = inst & 0x7fu;

    // Skip unstable time/cycle counters in CSR space.
    if (opcode == OPCODE_SYSTEM) {
        uint32_t funct3 = (inst >> 12) & 0x7u;
        if (funct3 != 0) {
            uint32_t csr = (inst >> 20) & 0xfffu;
            if (csr == CSR_MCYCLE || csr == CSR_MCYCLEH || csr == CSR_MINSTRET || csr == CSR_MINSTRETH ||
                csr == CSR_CYCLE || csr == CSR_CYCLEH || csr == CSR_TIME || csr == CSR_TIMEH ||
                csr == CSR_INSTRET || csr == CSR_INSTRETH) {
                return SKIP_COUNTER_CSR;
            }
        }
        return SKIP_NONE;
    }

    // Skip MMIO accesses (out of pmem) and resync architectural state.
    if (opcode == OPCODE_LOAD || opcode == OPCODE_STORE) {
        uint32_t rs1 = (inst >> 15) & 0x1fu;
        int32_t imm = 0;
        if (opcode == OPCODE_LOAD) {
            imm = sext((inst >> 20) & 0xfffu, 12);
        } else {
            uint32_t imm12 = ((inst >> 25) << 5) | ((inst >> 7) & 0x1fu);
            imm = sext(imm12, 12);
        }

        uint32_t addr = dut_gpr_shadow[rs1] + (uint32_t)imm;
        if (!check_bound((int)addr, "DIFFTEST")) {
            return SKIP_MMIO;
        }
    }

    return SKIP_NONE;
}

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

    SkipReason skip_reason = get_skip_reason(dut_pc);

    // For MMIO and unmodeled counter CSRs, skip REF execution and directly resync.
    if (skip_reason == SKIP_MMIO || skip_reason == SKIP_COUNTER_CSR) {
        if (dut_wen && dut_waddr != 0) {
            dut_gpr_shadow[dut_waddr] = dut_wdata;
        }
        dut_gpr_shadow[0] = 0;

        for (int i = 0; i < 32; i++) {
            ref_pre.gpr[i] = dut_gpr_shadow[i];
        }
        ref_pre.pc = dut_pc + 4;
        ref_difftest_regcpy(&ref_pre, DIFFTEST_TO_REF);
        return true;
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
