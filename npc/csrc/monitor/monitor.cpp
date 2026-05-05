#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "VysyxSoCFull.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include "npc.h"

VysyxSoCFull *g_top = NULL;
VerilatedContext *g_contextp = NULL;
VerilatedVcdC *g_tfp = NULL;

bool is_finished = false;
int trap_a0 = 0;
int trap_pc = 0;
uint64_t g_nr_guest_inst = 0;

bool sdb_batch_mode = false;
FILE *log_fp = NULL;

static void load_default_image() {
    // Keep default program aligned with NEMU's built-in behavior.
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

static long parse_args_and_load_image(int argc, char **argv, char **diff_so_file, int *diff_port) {
    bool img_loaded = false;
    char *log_file = NULL;
    long img_size = 0;
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
        } else if (argv[i][0] != '-') {
            img_size = load_image(argv[i]);
            img_loaded = true;
        }
    }

    init_log(log_file);

    if (!img_loaded) {
        load_default_image();
        img_size = 40;
    }

    return img_size;
}

void init_monitor(int argc, char **argv) {
    VerilatedContext *contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);

    VysyxSoCFull *top = new VysyxSoCFull{contextp};
    VerilatedVcdC *tfp = NULL;

    char *diff_so_file = NULL;
    int diff_port = 1234;
    long img_size = parse_args_and_load_image(argc, argv, &diff_so_file, &diff_port);

    init_disasm();

    if (!sdb_batch_mode) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open("waveform.vcd");
    }

    g_top = top;
    g_contextp = contextp;
    g_tfp = tfp;

    top->clock = 0;
    top->reset = 1;
    top->externalPins_gpio_in = 0;
    top->externalPins_ps2_clk = 0;
    top->externalPins_ps2_data = 0;
    top->externalPins_uart_rx = 0;
    top->eval();
    contextp->timeInc(1);
    if (tfp) tfp->dump(contextp->time());

    // Reset for a few cycles.
    for (int i = 0; i < 9; i++) {
        top->clock = !top->clock;
        top->eval();
        contextp->timeInc(1);
        if (tfp) tfp->dump(contextp->time());
    }
    top->reset = 0;

    init_difftest(diff_so_file, img_size, diff_port);
    Log("Simulation started...");
}

void npc_cleanup() {
    if (log_fp) {
        fclose(log_fp);
        log_fp = NULL;
    }

    if (g_tfp) {
        g_tfp->close();
        delete g_tfp;
        g_tfp = NULL;
    }

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
    return !(is_finished && trap_a0 == 0);
}
