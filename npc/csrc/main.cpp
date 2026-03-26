#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <time.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// Memory size 128MB
#define MEM_SIZE 0x8000000
#define MAX_SIM_TIME 100000000
#define SERIAL_PORT 0x10000000
#define RTC_ADDR    0x10000048
static uint8_t pmem[MEM_SIZE];
static Vtop* g_top = NULL;

static uint64_t get_time_us() {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

// Check boundary
bool check_bound(int addr, const char* type) {
    if (addr < 0x80000000 || addr >= 0x80000000 + MEM_SIZE) {
        return false;
    }
    return true;
}

extern "C" int pmem_read(int raddr) {
    // 总是读取地址为`raddr & ~0x3u`的4字节返回
    uint32_t aligned = (uint32_t)raddr & ~0x3u;
    if (aligned == RTC_ADDR || aligned == RTC_ADDR + 4) {
        uint64_t now = get_time_us();
        return (aligned == RTC_ADDR) ? (uint32_t)now : (uint32_t)(now >> 32);
    }

    if (!check_bound(aligned, "READ")) return 0;
    int index = (aligned - 0x80000000);
    return *(int *)&pmem[index];
}

extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    // 总是往地址为`waddr & ~0x3u`的4字节按写掩码`wmask`写入`wdata`
    if (waddr == SERIAL_PORT) {
        putchar((char)(wdata & 0xff));
        fflush(stdout);
        return;
    }
    if (!check_bound(waddr, "WRITE")) return;
    int index = (waddr - 0x80000000) & ~0x3u;
    uint32_t *p = (uint32_t *)&pmem[index];
    uint32_t orig = *p;
    uint32_t mask = 0;
    if (wmask & 0x1) mask |= 0x000000FF;
    if (wmask & 0x2) mask |= 0x0000FF00;
    if (wmask & 0x4) mask |= 0x00FF0000;
    if (wmask & 0x8) mask |= 0xFF000000;
    *p = (orig & ~mask) | (wdata & mask);
}

bool is_finished = false;
int trap_a0 = 0;
int trap_pc = 0;

extern "C" void npc_trap(int pc, int a0) {
    is_finished = true;
    trap_pc = pc;
    trap_a0 = a0;
}

long load_image(char *img_file) {
    if (img_file == NULL) {
        printf("No image file specified.\n");
        return 0;
    }

    FILE *fp = fopen(img_file, "rb");
    if (fp == NULL) {
        printf("Can not open '%s'\n", img_file);
        return 0;
    }

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);

    printf("The image is %s, size = %ld\n", img_file, size);

    fseek(fp, 0, SEEK_SET);
    int ret = fread(pmem, size, 1, fp);
    assert(ret == 1);

    fclose(fp);
    return size;
}

#include <readline/readline.h>
#include <readline/history.h>

const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

bool sdb_batch_mode = false;
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
                break; // One instruction retired
            }
        }
        if (is_finished) {
            if (trap_a0 == 0) {
                printf("npc: HIT GOOD TRAP at pc = 0x%08x\n", trap_pc);
            } else {
                printf("npc: HIT BAD TRAP at pc = 0x%08x\n", trap_pc);
            }
            break;
        }
        if (g_contextp->gotFinish()) break;
    }
}

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
            printf("\033[1;31m(x%02d) \033[1;32m%-4s \033[1;34m0x%08x\033[0m\t", i, regs[i], g_top->debug_reg_file[i]);
            if (i % 4 == 3) printf("\n");
        }
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

    // Enable Trace
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99); // Trace 99 levels of hierarchy
    tfp->open("waveform.vcd");

    bool img_loaded = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-b") == 0) {
            sdb_batch_mode = true;
        } else if (argv[i][0] != '-') {
            load_image(argv[i]);
            img_loaded = true;
        }
    }

    if (!img_loaded) {
        // Load default program: 
        // 0x80000000: auipc t0, 0          (0x00000297)
        // 0x80000004: sb zero, 16(t0)      (0x00028823) -> [0x80000000 + 16] = 0
        // 0x80000008: lbu a0, 16(t0)       (0x0102c503) -> a0 = 0
        // 0x8000000C: ebreak               (0x00100073)
        // 0x80000010: deadbeef             (0xdeadbeef)
        uint32_t *inst = (uint32_t *)&pmem[0];
        inst[0] = 0x00900293; 
        inst[1] = 0xfff00313;
        inst[2] = 0x00000393;
        inst[3] = 0x00200e13;
        inst[4] = 0x01c30333;
        inst[5] = 0x006383b3;
        inst[6] = 0xfe629ce3;
        inst[7] = 0x00100073;
    }

    top->clk = 0;
    top->rst = 1;
    top->eval();
    contextp->timeInc(1);
    tfp->dump(contextp->time());
    
    // Reset for a few cycles
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        contextp->timeInc(1);
        tfp->dump(contextp->time());
    }
    top->rst = 0;

    printf("Simulation started. Waiting for ebreak...\n");

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

    tfp->close();
    delete tfp;
    delete top;
    delete contextp;
    return exit_code;
}
