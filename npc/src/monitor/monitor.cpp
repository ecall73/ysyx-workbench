#include <assert.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "verilated.h"
#include "verilated_vcd_c.h"
#include "common.h"
#include "cpu/difftest.h"
#include "memory/paddr.h"
#include "monitor/monitor.h"
#include "monitor/sdb.h"
#include "platform/platform.h"
#include "utils.h"

SimTop *g_top = NULL;
VerilatedContext *g_contextp = NULL;
VerilatedVcdC *g_tfp = NULL;

NpcState npc_state = NPC_STOP;
int trap_a0 = 0;
int trap_pc = 0;
uint64_t g_nr_guest_inst = 0;

bool sdb_batch_mode = false;
bool sdb_quit = false;
FILE *log_fp = NULL;

static char *log_file = NULL;
static char *diff_so_file = NULL;
static char *img_file = NULL;
static char *elf_file = NULL;
static char *ftrace_log_file = NULL;
static char *etrace_log_file = NULL;
static char *mtrace_log_file = NULL;
static char *dtrace_log_file = NULL;
static int difftest_port = 1234;

#ifdef NPC_BUILD_PLATFORM_NPC
#define NPC_BUILD_PLATFORM_NAME "npc"
#else
#define NPC_BUILD_PLATFORM_NAME "ysyxsoc"
#endif

static void welcome() {
    Log("Trace: %s",
#ifdef CONFIG_TRACE
        ANSI_FMT("ON", ANSI_FG_GREEN)
#else
        ANSI_FMT("OFF", ANSI_FG_RED)
#endif
    );
    Log("Build time: %s, %s", __TIME__, __DATE__);
    printf("Welcome to %s-NPC!\n", ANSI_FMT(NPC_BUILD_PLATFORM_NAME, ANSI_FG_YELLOW ANSI_BG_RED));
    printf("For help, type \"help\"\n");
}

static long load_img() {
    if (img_file == NULL) {
        fprintf(stderr, "No image file specified\n");
        exit(1);
    }

    long img_size = platform_load_image(img_file);
    if (img_size <= 0) {
        fprintf(stderr, "Failed to load image file: %s\n", img_file);
        exit(1);
    }
    return img_size;
}

static int parse_args(int argc, char **argv) {
    const struct option table[] = {
        {"batch",      no_argument,       NULL, 'b'},
        {"log",        required_argument, NULL, 'l'},
        {"diff",       required_argument, NULL, 'd'},
        {"elf",        required_argument, NULL, 'f'},
        {"ftrace-log", required_argument, NULL, 'F'},
        {"etrace-log", required_argument, NULL, 'E'},
        {"mtrace-log", required_argument, NULL, 'M'},
        {"dtrace-log", required_argument, NULL, 'D'},
        {"port",       required_argument, NULL, 'p'},
        {"help",       no_argument,       NULL, 'h'},
        {0,            0,                 NULL,  0 },
    };

    int o;
    while ((o = getopt_long(argc, argv, "-bhf:F:E:M:D:l:d:p:", table, NULL)) != -1) {
        switch (o) {
            case 'b': sdb_set_batch_mode(); break;
            case 'l': log_file = optarg; break;
            case 'd': diff_so_file = optarg; break;
            case 'f': elf_file = optarg; break;
            case 'F': ftrace_log_file = optarg; break;
            case 'E': etrace_log_file = optarg; break;
            case 'M': mtrace_log_file = optarg; break;
            case 'D': dtrace_log_file = optarg; break;
            case 'p': sscanf(optarg, "%d", &difftest_port); break;
            case 1: img_file = optarg; return 0;
            default:
                printf("Usage: %s [OPTION...] IMAGE\n\n", argv[0]);
                printf("\t-b,--batch              run with batch mode\n");
                printf("\t-l,--log=FILE           output log to FILE\n");
                printf("\t-d,--diff=REF_SO        run DiffTest with reference REF_SO\n");
                printf("\t-p,--port=PORT          run DiffTest with port PORT\n");
                printf("\t-f,--elf=FILE           load ELF symbols for ftrace\n");
                printf("\t-F,--ftrace-log=FILE    output ftrace to FILE\n");
                printf("\t-E,--etrace-log=FILE    output etrace to FILE\n");
                printf("\t-M,--mtrace-log=FILE    output mtrace to FILE\n");
                printf("\t-D,--dtrace-log=FILE    output dtrace to FILE\n");
                printf("\n");
                exit(0);
        }
    }
    return 0;
}

void init_monitor(int argc, char **argv) {
    parse_args(argc, argv);

    VerilatedContext *contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);

    SimTop *top = new SimTop{contextp};
    VerilatedVcdC *tfp = NULL;

    init_log(log_file);
#ifdef CONFIG_FTRACE
    init_ftrace_log(ftrace_log_file);
    init_ftrace(elf_file);
#endif
#ifdef CONFIG_ETRACE
    init_etrace_log(etrace_log_file);
#endif
#ifdef CONFIG_MTRACE
    init_mtrace_log(mtrace_log_file);
#endif
#ifdef CONFIG_DTRACE
    init_dtrace_log(dtrace_log_file);
#endif
#ifdef CONFIG_ITRACE
    init_disasm();
#endif

    long img_size = load_img();

#ifdef CONFIG_WAVE
    {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open("waveform.vcd");
    }
#endif

    g_top = top;
    g_contextp = contextp;
    g_tfp = tfp;

    platform_init();

    top->clock = 0;
    top->reset = 1;
    platform_set_external_idle(top);
    top->eval();
    contextp->timeInc(1);
#ifdef CONFIG_WAVE
    if (tfp) tfp->dump(contextp->time());
#endif

    // ChipLink requires reset to be held for at least 10 full cycles.
    constexpr int kResetCycles = 10;
    for (int cyc = 0; cyc < kResetCycles; cyc++) {
        top->clock = 1;
        top->eval();
        contextp->timeInc(1);
#ifdef CONFIG_WAVE
        if (tfp) tfp->dump(contextp->time());
#endif

        top->clock = 0;
        top->eval();
        contextp->timeInc(1);
#ifdef CONFIG_WAVE
        if (tfp) tfp->dump(contextp->time());
#endif
    }
    top->reset = 0;
    npc_reset_dut_state(platform_reset_pc());

#ifdef CONFIG_DIFFTEST
    init_difftest(diff_so_file, img_size, difftest_port);
#else
    (void)diff_so_file;
    (void)difftest_port;
    (void)img_size;
#endif
    init_sdb();
    welcome();
}

void npc_cleanup() {
    platform_cleanup();

    close_trace_logs();
    close_log();

#ifdef CONFIG_WAVE
    if (g_tfp) {
        g_tfp->close();
        delete g_tfp;
        g_tfp = NULL;
    }
#endif

    if (g_top) {
        delete g_top;
        g_top = NULL;
    }

    if (g_contextp) {
        delete g_contextp;
        g_contextp = NULL;
    }
}

int is_exit_status_bad() {
    return !(npc_state == NPC_QUIT || (npc_state == NPC_END && trap_a0 == 0));
}
