#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <time.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include "npc.h"

static Vtop* g_top = NULL;

bool is_finished = false;
int trap_a0 = 0;
int trap_pc = 0;

extern "C" void npc_trap(int pc, int a0) {
    is_finished = true;
    trap_pc = pc;
    trap_a0 = a0;
}

const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

bool sdb_batch_mode = false;
FILE *log_fp = NULL;
VerilatedContext* g_contextp = NULL;
VerilatedVcdC* g_tfp = NULL;

void cpu_exec(uint64_t n) {
    if (is_finished) {
        printf("Program execution has ended. To restart the program, exit NPC and run again.\n");
        return;
    }
    for (uint64_t i = 0; i < n; i++) {
        while (!is_finished && !g_contextp->gotFinish()) {
            g_top->clk = 0;
            g_top->eval();
            g_contextp->timeInc(1);
            g_tfp->dump(g_contextp->time());
            
            g_top->clk = 1;
            g_top->eval();
            g_contextp->timeInc(1);
            g_tfp->dump(g_contextp->time());

            if (g_contextp->time() > MAX_SIM_TIME) {
                printf("Simulation timed out at time %ld\n", g_contextp->time());
                is_finished = true;
                break;
            }

            if (g_top->debug_wb_have_inst) {
                uint32_t pc = g_top->debug_wb_pc;
                uint32_t inst_val = 0;
                if (check_bound(pc, "FETCH")) {
                    inst_val = *(uint32_t*)&pmem[pc - 0x80000000];
                }
                char asm_buf[128];
                disassemble(asm_buf, sizeof(asm_buf), pc, (uint8_t*)&inst_val, 4);
                
                if (log_fp) {
                    fprintf(log_fp, "0x%08x: %08x\t%s\n", pc, inst_val, asm_buf);
                }

                if (n < 10) {
                    printf("0x%08x: %08x\t%s\n", pc, inst_val, asm_buf);
                }
                break; // One instruction retired
            }
        }
        if (is_finished) {
            if (trap_a0 == 0) {
                printf("npc: " ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN) " at pc = 0x%08x\n", trap_pc);
            } else {
                printf("npc: " ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED) " at pc = 0x%08x\n", trap_pc);
            }
            break;
        }
        if (g_contextp->gotFinish()) break;
    }
}

#include <readline/readline.h>
#include <readline/history.h>

static int cmd_q(char *args) {
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
    if (args != NULL && strcmp(args, "r") == 0) {
        for (int i = 0; i < 32; i++) {
            printf(ANSI_FMT("(x%02d) ", ANSI_FG_RED) ANSI_FMT("%-4s ", ANSI_FG_GREEN) ANSI_FMT("0x%08x\t", ANSI_FG_BLUE), i, regs[i], g_top->debug_reg_file[i]);
            if (i % 4 == 3) printf("\n");
        }
        printf("      " ANSI_FMT("PC   ", ANSI_FG_GREEN) ANSI_FMT("0x%08x\n", ANSI_FG_BLUE), g_top->debug_wb_pc);
    }
    return 0;
}

static int cmd_x(char *args) {
    if (args == NULL) return 0;
    int n;
    uint32_t base_addr;
    if (sscanf(args, "%d %x", &n, &base_addr) == 2) {
        for (int i = 0; i < n; i++) {
            uint32_t addr = base_addr + i * 4;
            if (check_bound(addr, "SDB")) {
                int index = addr - 0x80000000;
                printf("0x%08x: 0x%08x\n", addr, *(uint32_t *)&pmem[index]);
            } else {
                printf("0x%08x: OUT OF BOUNDS\n", addr);
            }
        }
    }
    return 0;
}

static int cmd_help(char *args);

static struct {
  const char *name;
  const char *description;
  int (*handler) (char *);
} cmd_table [] = {
  { "help", "Display information about all supported commands", cmd_help },
  { "q", "Exit NPC", cmd_q },
  { "c", "Continue the execution of the program", cmd_c },
  { "si", "Step one instruction exactly", cmd_si },
  { "info", "Generic command for showing things about the program being debugged", cmd_info },
  { "x", "Examine memory: x N ADDR", cmd_x },
};

static int cmd_help(char *args) {
  for (int i = 0; i < sizeof(cmd_table) / sizeof(cmd_table[0]); i ++) {
    printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
  }
  return 0;
}

void sdb_mainloop() {
    if (sdb_batch_mode) {
        cmd_c(NULL);
        return;
    }

    for (char *str; (str = readline("(npc) ")) != NULL; ) {
        char *str_end = str + strlen(str);
        char *cmd = strtok(str, " ");
        if (cmd == NULL) { continue; }
        
        char *args = cmd + strlen(cmd) + 1;
        if (args >= str_end) { args = NULL; }
        
        add_history(str);
        
        bool found = false;
        for (int i = 0; i < sizeof(cmd_table) / sizeof(cmd_table[0]); i++) {
            if (strcmp(cmd, cmd_table[i].name) == 0) {
                if (cmd_table[i].handler(args) < 0) { return; }
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

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    Vtop* top = new Vtop{contextp};
    g_top = top;

    extern void init_disasm();
    init_disasm();

    // Enable Trace
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99); // Trace 99 levels of hierarchy
    tfp->open("waveform.vcd");

    bool img_loaded = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-b") == 0) {
            sdb_batch_mode = true;
        } else if (strncmp(argv[i], "-l", 2) == 0) {
            char *log_file = NULL;
            if (strlen(argv[i]) > 2) {
                log_file = argv[i] + 2;
            } else if (i + 1 < argc) {
                log_file = argv[++i];
            }
            if (log_file) {
                log_fp = fopen(log_file, "w");
                if (log_fp) {
                    printf("Log is written to %s\n", log_file);
                } else {
                    printf("Failed to open log file %s\n", log_file);
                }
            }
        } else if (argv[i][0] != '-') {
            load_image(argv[i]);
            img_loaded = true;
        }
    }

    if (!img_loaded) {
        // Load default program: 
        uint32_t *inst = (uint32_t *)&pmem[0];
        inst[0] = 0x00000297;   // auipc t0, 0
        inst[1] = 0x00028823;   // sb zero, 0x10(t0)
        inst[2] = 0x0102c503;   // lbu a0, 0x10(t0)
        inst[3] = 0x00100073;   // ebreak
        inst[4] = 0xdeadbeef;
        inst[5] = 0xdeadbeef;
        inst[6] = 0xdeadbeef;
        inst[7] = 0xdeadbeef;
        inst[8] = 0xdeadbeef;
        inst[9] = 0xdeadbeef;
    }

    top->clk = 0;
    top->rst = 1;
    top->eval();
    contextp->timeInc(1);
    tfp->dump(contextp->time());
    
    // Reset for a few cycles
    for (int i = 0; i < 9; i++) {
        top->clk = !top->clk;
        top->eval();
        contextp->timeInc(1);
        tfp->dump(contextp->time());
    }
    top->rst = 0;

    printf("Simulation started...\n");

    g_contextp = contextp;
    g_tfp = tfp;

    sdb_mainloop();

    int exit_code = 0;

    if (is_finished) {
        if (trap_a0 == 0) {
            exit_code = 0;
        } else {
            exit_code = -1;
        }
    } else {
        exit_code = -1;
    }

    if (log_fp) {
        fclose(log_fp);
    }

    tfp->close();
    delete tfp;
    delete top;
    delete contextp;
    return exit_code;
}
