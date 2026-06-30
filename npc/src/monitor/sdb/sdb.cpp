#include <readline/history.h>
#include <readline/readline.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "cpu/cpu.h"
#include "monitor/sdb.h"
#include "platform/platform.h"

#define NR_CMD (sizeof(cmd_table) / sizeof(cmd_table[0]))

static int cmd_help(char *args);

void init_regex();
void init_wp_pool();

static char *rl_gets() {
    static char *line_read = NULL;

    if (line_read) {
        free(line_read);
        line_read = NULL;
    }

    line_read = readline("(npc) ");

    if (line_read && *line_read) {
        add_history(line_read);
    }

    return line_read;
}

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
        n = strtol(args, NULL, 0);
    }
    cpu_exec(n);
    return 0;
}

static int cmd_info(char *args) {
    if (args == NULL) {
        printf("Usage: info r (registers) or info w (watchpoints)\n");
    } else if (strcmp(args, "r") == 0) {
        npc_reg_display();
    } else if (strcmp(args, "w") == 0) {
        wp_display();
    } else {
        printf("Unknown info type '%s'\n", args);
    }
    return 0;
}

static int cmd_x(char *args) {
    char *n_str = args == NULL ? NULL : strtok(args, " ");
    char *expr_str = n_str == NULL ? NULL : strtok(NULL, "");
    if (expr_str == NULL) {
        printf("Usage: x <N> <EXPR>\n");
        return 0;
    }
    int n = strtol(n_str, NULL, 0);

    bool success = false;
    uint32_t base_addr = expr(expr_str, &success);
    if (!success) {
        printf("Bad expression: %s\n", expr_str);
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

static int cmd_p(char *args) {
    if (args == NULL) {
        printf("Usage: p <EXPR>\n");
        return 0;
    }

    bool success = false;
    uint32_t ans = expr(args, &success);
    if (success) {
        printf(ANSI_FG_GREEN "[DEC] %u\n[HEX] 0x%x\n" ANSI_NONE, ans, ans);
    } else {
        printf(ANSI_FG_RED "EXPR is illegal!\n" ANSI_NONE);
    }
    return 0;
}

static int cmd_w(char *args) {
    if (args == NULL) {
        printf("Usage: w <EXPR>\n");
        return 0;
    }

    int NO = new_wp(args);
    if (NO == -1) {
        printf("Failed to create watchpoint\n");
    } else {
        printf("Watchpoint %d: %s\n", NO, args);
    }
    return 0;
}

static int cmd_d(char *args) {
    if (args == NULL) {
        printf("Usage: d <NO>\n");
        return 0;
    }

    int NO = strtol(args, NULL, 0);
    if (free_wp(NO)) {
        printf("Watchpoint %d deleted\n", NO);
    } else {
        printf("Watchpoint %d not found\n", NO);
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
    {"info", "r: Print register status, w: Print watchpoint information", cmd_info},
    {"x", "Scan <N> words starting from <EXPR>", cmd_x},
    {"p", "Find the value of <EXPR>", cmd_p},
    {"w", "Set watchpoint <EXPR>", cmd_w},
    {"d", "Delete watchpoint <NO>", cmd_d},
};

static int cmd_help(char *args) {
    char *arg = strtok(NULL, " ");
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

void init_sdb() {
    init_regex();
    init_wp_pool();
}

void sdb_mainloop() {
    if (sdb_batch_mode) {
        cmd_c(NULL);
        return;
    }

    for (char *str; (str = rl_gets()) != NULL;) {
        char *str_end = str + strlen(str);
        char *cmd = strtok(str, " ");
        if (cmd == NULL) {
            continue;
        }

        char *args = cmd + strlen(cmd) + 1;
        if (args >= str_end) {
            args = NULL;
        }

        int i;
        for (i = 0; i < (int)NR_CMD; i++) {
            if (strcmp(cmd, cmd_table[i].name) == 0) {
                if (cmd_table[i].handler(args) < 0) {
                    return;
                }
                break;
            }
        }

        if (i == (int)NR_CMD) {
            printf("Unknown command '%s'\n", cmd);
        }
    }
}
