#include <assert.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

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

static void (*ref_difftest_memcpy)(uint32_t addr, void *buf, size_t n, bool direction) = NULL;
static void (*ref_difftest_regcpy)(void *dut, bool direction) = NULL;
static void (*ref_difftest_exec)(uint64_t n) = NULL;
static void (*ref_difftest_raise_intr)(uint64_t NO) = NULL;
static void (*ref_difftest_init)(int port) = NULL;
static void (*ref_difftest_enable_ysyxsoc_paddr)(void) = NULL;

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

#define OPCODE_LOAD     0x03u
#define OPCODE_STORE    0x23u
#define OPCODE_SYSTEM   0x73u

static inline int32_t sext32(uint32_t val, int bits) {
    uint32_t m = 1u << (bits - 1);
    return (int32_t)((val ^ m) - m);
}

static inline bool in_comparable_mem(uint32_t addr) {
#ifdef NPC_SIM_MODE_NPC
    return ((addr >= NPC_PMEM_BASE) && (addr < (NPC_PMEM_BASE + NPC_PMEM_SIZE)));
#else
    return ((addr >= NPC_FLASH_BASE) && (addr < (NPC_FLASH_BASE + NPC_FLASH_SIZE))) ||
           ((addr >= NPC_SRAM_BASE) && (addr < (NPC_SRAM_BASE + NPC_SRAM_SIZE))) ||
           ((addr >= NPC_SDRAM_BASE) && (addr < (NPC_SDRAM_BASE + NPC_SDRAM_SIZE)));
#endif
}

static void collect_dut_gprs(RefCPUState *dut_r) {
    memset(dut_r, 0, sizeof(*dut_r));
    for (int i = 0; i < 32; i++) {
        dut_r->gpr[i] = npc_read_dut_gpr(i);
    }
}

static SkipReason get_skip_reason(uint32_t inst, const RefCPUState *ref_pre) {
    uint32_t opcode = inst & 0x7fu;

    if (opcode == OPCODE_SYSTEM) {
        uint32_t funct3 = (inst >> 12) & 0x7u;
        if (funct3 != 0u) {
            uint32_t csr = (inst >> 20) & 0xfffu;
            if (csr == CSR_MCYCLE || csr == CSR_MCYCLEH || csr == CSR_MINSTRET || csr == CSR_MINSTRETH ||
                csr == CSR_CYCLE || csr == CSR_CYCLEH || csr == CSR_TIME || csr == CSR_TIMEH ||
                csr == CSR_INSTRET || csr == CSR_INSTRETH) {
                return SKIP_COUNTER_CSR;
            }
        }
        return SKIP_NONE;
    }

    if (opcode == OPCODE_LOAD || opcode == OPCODE_STORE) {
        uint32_t rs1 = (inst >> 15) & 0x1fu;
        int32_t imm = 0;
        if (opcode == OPCODE_LOAD) {
            imm = sext32((inst >> 20) & 0xfffu, 12);
        } else {
            uint32_t imm12 = ((inst >> 25) << 5) | ((inst >> 7) & 0x1fu);
            imm = sext32(imm12, 12);
        }
        uint32_t addr = ref_pre->gpr[rs1] + (uint32_t)imm;
        if (!in_comparable_mem(addr)) {
            return SKIP_MMIO;
        }
    }

    return SKIP_NONE;
}

static void collect_dut_init_regs(RefCPUState *dut_r) {
    memset(dut_r, 0, sizeof(*dut_r));
#ifdef NPC_SIM_MODE_NPC
    dut_r->pc = NPC_RESET_PC_NPC;
#else
    dut_r->pc = NPC_RESET_PC_YSYXSOC;
#endif
    dut_r->mstatus = 0x00001800u;
    dut_r->mtvec = 0x00000001u;
    dut_r->mepc = 0;
    dut_r->mcause = 0;
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
    (void)img_size;
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

    ref_difftest_enable_ysyxsoc_paddr = (void (*)(void))dlsym(ref_handle, "difftest_enable_ysyxsoc_paddr");
#ifndef NPC_SIM_MODE_NPC
    assert(ref_difftest_enable_ysyxsoc_paddr);
    ref_difftest_enable_ysyxsoc_paddr();
#endif

    ref_difftest_init(port);

#ifdef NPC_SIM_MODE_NPC
    if (img_size > 0) {
        ref_difftest_memcpy(NPC_PMEM_BASE, pmem, (size_t)img_size, DIFFTEST_TO_REF);
    } else {
        Log("warning: no pmem image loaded before DiffTest init");
    }
#else
    uint32_t flash_base = 0;
    const uint8_t *flash_img = NULL;
    size_t flash_size = 0;
    bool has_flash_boot = flash_get_boot_image_info(&flash_base, &flash_img, &flash_size);
    if (has_flash_boot && flash_size > 0) {
        ref_difftest_memcpy(flash_base, (void *)flash_img, flash_size, DIFFTEST_TO_REF);
    } else {
        Log("warning: no flash boot image loaded before DiffTest init");
    }
#endif

    RefCPUState dut_r;
    collect_dut_init_regs(&dut_r);
    ref_difftest_regcpy(&dut_r, DIFFTEST_TO_REF);

    difftest_enabled = true;
    Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
    Log("The result of every retired instruction will be compared with %s", ref_so_file);
}

bool difftest_step(uint32_t dut_pc, uint32_t dut_inst) {
    if (!difftest_enabled) {
        return true;
    }

    if (!in_comparable_mem(dut_pc)) {
        Log("difftest detached: DUT enters unsupported ref execute region at pc = 0x%08x", dut_pc);
        difftest_enabled = false;
        return true;
    }

    RefCPUState ref_pre;
    ref_difftest_regcpy(&ref_pre, DIFFTEST_TO_DUT);
    if (ref_pre.pc != dut_pc) {
        Log("difftest error at pc = 0x%08x: pc mismatch before exec, ref = 0x%08x, dut = 0x%08x",
            dut_pc, ref_pre.pc, dut_pc);
        return false;
    }

    SkipReason skip_reason = get_skip_reason(dut_inst, &ref_pre);

    if (skip_reason == SKIP_MMIO || skip_reason == SKIP_COUNTER_CSR) {
        RefCPUState dut_post;
        collect_dut_gprs(&dut_post);

        for (int i = 0; i < 32; i++) {
            ref_pre.gpr[i] = dut_post.gpr[i];
        }
        ref_pre.pc = dut_pc + 4;
        ref_difftest_regcpy(&ref_pre, DIFFTEST_TO_REF);
        return true;
    }

    ref_difftest_exec(1);

    RefCPUState ref_post;
    RefCPUState dut_post;
    ref_difftest_regcpy(&ref_post, DIFFTEST_TO_DUT);
    collect_dut_gprs(&dut_post);

    return difftest_checkregs(&ref_post, &dut_post, dut_pc);
}
