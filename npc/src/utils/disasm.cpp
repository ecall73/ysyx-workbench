#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#include "common.h"
#include "utils.h"

#ifdef CONFIG_ITRACE
#include <capstone/capstone.h>

static csh handle;
static bool disasm_ready = false;

void init_disasm() {
    cs_err ret = cs_open(CS_ARCH_RISCV, (cs_mode)(CS_MODE_RISCV32 | CS_MODE_RISCVC), &handle);
    assert(ret == CS_ERR_OK);
    disasm_ready = true;
}

void disassemble(char *str, int size, uint32_t pc, uint32_t inst) {
    if (!disasm_ready) {
        snprintf(str, size, "<disasm not initialized>");
        return;
    }

    uint8_t code[4] = {
        (uint8_t)(inst & 0xff),
        (uint8_t)((inst >> 8) & 0xff),
        (uint8_t)((inst >> 16) & 0xff),
        (uint8_t)((inst >> 24) & 0xff),
    };

    cs_insn *insn = NULL;
    size_t count = cs_disasm(handle, code, sizeof(code), pc, 1, &insn);
    if (count != 1) {
        snprintf(str, size, "<invalid>");
        return;
    }

    int ret = snprintf(str, size, "%s", insn[0].mnemonic);
    if (insn[0].op_str[0] != '\0' && ret < size) {
        snprintf(str + ret, size - ret, "\t%s", insn[0].op_str);
    }
    cs_free(insn, count);
}
#else
void init_disasm() {}

void disassemble(char *str, int size, uint32_t pc, uint32_t inst) {
    (void)pc;
    snprintf(str, size, "0x%08x", inst);
}
#endif
