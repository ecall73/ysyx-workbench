#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <capstone/capstone.h>

#define CS_LIB_SUFFIX "so.5"

static csh handle;

void init_disasm() {
    if (cs_open(CS_ARCH_RISCV, CS_MODE_RISCV32, &handle) != CS_ERR_OK) {
        printf("Fail to initialize capstone\n");
        return;
    }
}

void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte) {
    cs_insn *insn;
    size_t count;

    count = cs_disasm(handle, code, nbyte, pc, 0, &insn);
    if (count > 0) {
        snprintf(str, size, "%s\t%s", insn[0].mnemonic, insn[0].op_str);
        cs_free(insn, count);
    } else {
        snprintf(str, size, "ERROR: Failed to disassemble given code!");
    }
}
