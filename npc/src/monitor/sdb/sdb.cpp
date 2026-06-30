#include <readline/history.h>
#include <readline/readline.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"

static const char *regs[] = {
    "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

#define NR_CMD (sizeof(cmd_table) / sizeof(cmd_table[0]))
#define NR_GPR (sizeof(regs) / sizeof(regs[0]))

static int cmd_help(char *args);

static int cmd_q(char *args) {
    sdb_quit = true;
    return -1;
}

static int cmd_c(char *args) {
    cpu_exec(-1);
    return 0;
}

static int cmd_si(char *args) {
    uint64_t n = 1;
    if (args != NULL) {
        sscanf(args, "%lu", &n);
    }
    cpu_exec(n);
    return 0;
}

static int cmd_info(char *args) {
    if (args == NULL) {
        printf("Usage: info r (registers)\n");
    } else if (strcmp(args, "r") == 0) {
        for (int i = 0; i < (int)NR_GPR; i++) {
            printf(ANSI_FG_RED "(x%02d) " ANSI_FG_GREEN "%-4s " ANSI_FG_BLUE "0x%08x\t" ANSI_NONE,
                i, regs[i], npc_read_dut_gpr(i));
            if (i % 4 == 3) {
                printf("\n");
            }
        }
        printf("      " ANSI_FG_GREEN "PC   " ANSI_FG_BLUE "0x%08x\n" ANSI_NONE, npc_read_dut_pc());
    } else {
        printf("Unknown info type '%s'\n", args);
    }
    return 0;
}

static int cmd_x(char *args) {
    if (args == NULL) {
        printf("Usage: x <N> <ADDR>\n");
        return 0;
    }

    int n;
    uint32_t base_addr;
    if (sscanf(args, "%d %x", &n, &base_addr) != 2) {
        printf("Usage: x <N> <ADDR>\n");
        return 0;
    }

    for (int i = 0; i < n; i++) {
        uint32_t addr = base_addr + i * 4;
        uint32_t data = 0;
        if (platform_read_word(addr, &data)) {
            printf(ANSI_FG_GREEN "0x%08x: " ANSI_FG_BLUE "0x%08x\n" ANSI_NONE, addr, data);
        } else {
            printf(ANSI_FG_GREEN "0x%08x: " ANSI_FG_BLUE "unsupported\n" ANSI_NONE, addr);
        }
    }
    return 0;
}

static struct {
    const char *name;
    const char *description;
    int (*handler)(char *);
} cmd_table[] = {
    {"help", "Display information about all supported commands", cmd_help},
    {"c", "Continue the execution of the program", cmd_c},
    {"q", "Exit NPC", cmd_q},
    {"si", "Pause after executing [N] instructions", cmd_si},
    {"info", "r: Print register status", cmd_info},
    {"x", "Scan <N> words starting from <ADDR>", cmd_x},
};

static int cmd_help(char *args) {
    char *arg = args == NULL ? NULL : strtok(args, " ");
    if (arg == NULL) {
        for (int i = 0; i < (int)NR_CMD; i++) {
            printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
        }
    } else {
        for (int i = 0; i < (int)NR_CMD; i++) {
            if (strcmp(arg, cmd_table[i].name) == 0) {
                printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
                return 0;
            }
        }
        printf("Unknown command '%s'\n", arg);
    }
    return 0;
}

void sdb_set_batch_mode() {
    sdb_batch_mode = true;
}

void sdb_mainloop() {
    if (sdb_batch_mode) {
        cmd_c(NULL);
        return;
    }

    for (char *str; (str = readline("(npc) ")) != NULL;) {
        char *str_end = str + strlen(str);
        char *cmd = strtok(str, " ");
        if (cmd == NULL) {
            free(str);
            continue;
        }

        char *args = cmd + strlen(cmd) + 1;
        if (args >= str_end) {
            args = NULL;
        }

        add_history(str);

        bool found = false;
        for (int i = 0; i < (int)NR_CMD; i++) {
            if (strcmp(cmd, cmd_table[i].name) == 0) {
                if (cmd_table[i].handler(args) < 0) {
                    free(str);
                    return;
                }
                found = true;
                break;
            }
        }

        if (!found) {
            printf("Unknown command '%s'\n", cmd);
        }

        free(str);
    }
}
