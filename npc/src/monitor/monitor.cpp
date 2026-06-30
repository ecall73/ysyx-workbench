#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "verilated.h"
#include "verilated_vcd_c.h"
#include "common.h"

SimTop *g_top = NULL;
VerilatedContext *g_contextp = NULL;
VerilatedVcdC *g_tfp = NULL;

bool is_finished = false;
int trap_a0 = 0;
int trap_pc = 0;
uint64_t g_nr_guest_inst = 0;

bool sdb_batch_mode = false;
bool sdb_quit = false;
FILE *log_fp = NULL;

static long parse_args_and_load_image(int argc, char **argv, char **diff_so_file, int *diff_port) {
    char *log_file = NULL;
    char *elf_file = NULL;
    char *ftrace_log = NULL;
    char *etrace_log = NULL;
    char *mtrace_log = NULL;
    char *dtrace_log = NULL;
    char *img_file = NULL;
    *diff_so_file = NULL;
    *diff_port = 1234;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-b") == 0) {
            sdb_set_batch_mode();
        } else if (strncmp(argv[i], "-d", 2) == 0) {
            if (strlen(argv[i]) > 2) {
                *diff_so_file = argv[i] + 2;
            } else if (i + 1 < argc) {
                *diff_so_file = argv[++i];
            }
        } else if (strncmp(argv[i], "-p", 2) == 0) {
            char *port_arg = NULL;
            if (strlen(argv[i]) > 2) {
                port_arg = argv[i] + 2;
            } else if (i + 1 < argc) {
                port_arg = argv[++i];
            }
            if (port_arg != NULL) {
                sscanf(port_arg, "%d", diff_port);
            }
        } else if (strncmp(argv[i], "-l", 2) == 0) {
            if (strlen(argv[i]) > 2) {
                log_file = argv[i] + 2;
            } else if (i + 1 < argc) {
                log_file = argv[++i];
            }
        } else if (strncmp(argv[i], "-f", 2) == 0) {
            if (strlen(argv[i]) > 2) {
                elf_file = argv[i] + 2;
            } else if (i + 1 < argc) {
                elf_file = argv[++i];
            }
        } else if (strncmp(argv[i], "-F", 2) == 0) {
            if (strlen(argv[i]) > 2) {
                ftrace_log = argv[i] + 2;
            } else if (i + 1 < argc) {
                ftrace_log = argv[++i];
            }
        } else if (strncmp(argv[i], "-E", 2) == 0) {
            if (strlen(argv[i]) > 2) {
                etrace_log = argv[i] + 2;
            } else if (i + 1 < argc) {
                etrace_log = argv[++i];
            }
        } else if (strncmp(argv[i], "-M", 2) == 0) {
            if (strlen(argv[i]) > 2) {
                mtrace_log = argv[i] + 2;
            } else if (i + 1 < argc) {
                mtrace_log = argv[++i];
            }
        } else if (strncmp(argv[i], "-D", 2) == 0) {
            if (strlen(argv[i]) > 2) {
                dtrace_log = argv[i] + 2;
            } else if (i + 1 < argc) {
                dtrace_log = argv[++i];
            }
        } else if (argv[i][0] != '-') {
            img_file = argv[i];
        }
    }

    init_log(log_file);
#ifdef CONFIG_ITRACE
    init_disasm();
#endif
#ifdef CONFIG_FTRACE
    init_ftrace_log(ftrace_log);
    init_ftrace(elf_file);
#else
    (void)elf_file;
    (void)ftrace_log;
#endif
#ifdef CONFIG_ETRACE
    init_etrace_log(etrace_log);
#else
    (void)etrace_log;
#endif
#ifdef CONFIG_MTRACE
    init_mtrace_log(mtrace_log);
#else
    (void)mtrace_log;
#endif
#ifdef CONFIG_DTRACE
    init_dtrace_log(dtrace_log);
#else
    (void)dtrace_log;
#endif
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

void init_monitor(int argc, char **argv) {
    VerilatedContext *contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);

    SimTop *top = new SimTop{contextp};
    VerilatedVcdC *tfp = NULL;

    char *diff_so_file = NULL;
    int diff_port = 1234;
    long img_size = parse_args_and_load_image(argc, argv, &diff_so_file, &diff_port);

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

    init_difftest(diff_so_file, img_size, diff_port);
    Log("Simulation started...");
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
    return !(sdb_quit || (is_finished && trap_a0 == 0));
}
