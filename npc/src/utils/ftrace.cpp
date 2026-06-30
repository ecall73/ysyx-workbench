#include <assert.h>
#include <elf.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "utils.h"

#ifdef CONFIG_FTRACE
struct FuncSymbol {
    uint32_t addr;
    uint32_t size;
    char *name;
};

static FuncSymbol *funcs = NULL;
static size_t func_count = 0;
static int call_depth = 0;
static bool ftrace_ready = false;

static int32_t sign_extend(uint32_t val, int bits) {
    uint32_t mask = 1u << (bits - 1);
    return (int32_t)((val ^ mask) - mask);
}

static const char *find_func(uint32_t addr) {
    for (size_t i = 0; i < func_count; i++) {
        uint32_t start = funcs[i].addr;
        uint32_t end = funcs[i].size == 0 ? start + 4 : start + funcs[i].size;
        if (addr >= start && addr < end) {
            return funcs[i].name;
        }
    }
    return "???";
}

static uint32_t jal_imm(uint32_t inst) {
    uint32_t imm =
        ((inst >> 31) & 0x1) << 20 |
        ((inst >> 21) & 0x3ff) << 1 |
        ((inst >> 20) & 0x1) << 11 |
        ((inst >> 12) & 0xff) << 12;
    return (uint32_t)sign_extend(imm, 21);
}

static bool is_jal(uint32_t inst) {
    return (inst & 0x7f) == 0x6f;
}

static bool is_jalr(uint32_t inst) {
    return (inst & 0x707f) == 0x67;
}

static void free_symbols() {
    for (size_t i = 0; i < func_count; i++) {
        free(funcs[i].name);
    }
    free(funcs);
    funcs = NULL;
    func_count = 0;
    ftrace_ready = false;
    call_depth = 0;
}

void init_ftrace(const char *elf_file) {
    free_symbols();
    if (elf_file == NULL) {
        Log("FTrace is enabled, but no ELF file is provided");
        return;
    }

    FILE *fp = fopen(elf_file, "rb");
    if (fp == NULL) {
        Log("Failed to open ftrace ELF file: %s", elf_file);
        return;
    }

    Elf32_Ehdr ehdr;
    if (fread(&ehdr, sizeof(ehdr), 1, fp) != 1 ||
        memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0 ||
        ehdr.e_ident[EI_CLASS] != ELFCLASS32) {
        fclose(fp);
        Log("Bad ftrace ELF file: %s", elf_file);
        return;
    }

    Elf32_Shdr *shdrs = (Elf32_Shdr *)malloc(ehdr.e_shentsize * ehdr.e_shnum);
    assert(shdrs);
    fseek(fp, ehdr.e_shoff, SEEK_SET);
    assert(fread(shdrs, ehdr.e_shentsize, ehdr.e_shnum, fp) == ehdr.e_shnum);

    Elf32_Shdr *symtab = NULL;
    Elf32_Shdr *strtab = NULL;
    for (int i = 0; i < ehdr.e_shnum; i++) {
        if (shdrs[i].sh_type == SHT_SYMTAB) {
            symtab = &shdrs[i];
            strtab = &shdrs[shdrs[i].sh_link];
            break;
        }
    }
    if (symtab == NULL || strtab == NULL) {
        free(shdrs);
        fclose(fp);
        Log("No symbol table in ftrace ELF file: %s", elf_file);
        return;
    }

    char *strs = (char *)malloc(strtab->sh_size);
    assert(strs);
    fseek(fp, strtab->sh_offset, SEEK_SET);
    assert(fread(strs, 1, strtab->sh_size, fp) == strtab->sh_size);

    size_t nsyms = symtab->sh_size / sizeof(Elf32_Sym);
    Elf32_Sym *syms = (Elf32_Sym *)malloc(symtab->sh_size);
    assert(syms);
    fseek(fp, symtab->sh_offset, SEEK_SET);
    assert(fread(syms, sizeof(Elf32_Sym), nsyms, fp) == nsyms);

    funcs = (FuncSymbol *)calloc(nsyms, sizeof(FuncSymbol));
    assert(funcs);
    for (size_t i = 0; i < nsyms; i++) {
        if (ELF32_ST_TYPE(syms[i].st_info) == STT_FUNC && syms[i].st_name < strtab->sh_size) {
            funcs[func_count].addr = syms[i].st_value;
            funcs[func_count].size = syms[i].st_size;
            funcs[func_count].name = strdup(strs + syms[i].st_name);
            assert(funcs[func_count].name);
            func_count++;
        }
    }

    free(syms);
    free(strs);
    free(shdrs);
    fclose(fp);
    if (func_count > 0) {
        ftrace_ready = true;
        Log("FTrace loaded %zu function symbols from %s", func_count, elf_file);
    } else {
        Log("No function symbols found in ftrace ELF file: %s", elf_file);
    }
}

void ftrace_check(uint32_t pc, uint32_t inst, uint32_t dnpc) {
    if (!ftrace_ready) {
        return;
    }

    uint32_t rd = (inst >> 7) & 0x1f;
    uint32_t rs1 = (inst >> 15) & 0x1f;
    int32_t imm = (int32_t)jal_imm(inst);
    if (is_jal(inst) && (rd == 1 || rd == 5)) {
        const char *name = find_func(pc + (uint32_t)imm);
        ftrace_write("0x%08x: %*scall [%s@0x%08x]\n", pc, call_depth * 2, "", name, dnpc);
        call_depth++;
    } else if (is_jalr(inst) && rd == 0 && rs1 == 1) {
        if (call_depth > 0) call_depth--;
        ftrace_write("0x%08x: %*sret  [%s@0x%08x]\n", pc, call_depth * 2, "", find_func(dnpc), dnpc);
    } else if (is_jalr(inst) && (rd == 1 || rd == 5)) {
        ftrace_write("0x%08x: %*scall [%s@0x%08x]\n", pc, call_depth * 2, "", find_func(dnpc), dnpc);
        call_depth++;
    }
}
#else
void init_ftrace(const char *elf_file) {
    (void)elf_file;
}

void ftrace_check(uint32_t pc, uint32_t inst, uint32_t dnpc) {
    (void)pc;
    (void)inst;
    (void)dnpc;
}
#endif
