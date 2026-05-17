#include <assert.h>
#include <stdlib.h>
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

static void build_default_char_test_path(const char *argv0, char *buf, size_t buflen) {
    const char *fallback = "build/char-test.bin";
    if (buflen == 0) {
        return;
    }

    if (argv0 == NULL || argv0[0] == '\0') {
        snprintf(buf, buflen, "%s", fallback);
        return;
    }

    const char *slash = strrchr(argv0, '/');
    if (slash == NULL) {
        snprintf(buf, buflen, "%s", fallback);
        return;
    }

    size_t dir_len = (size_t)(slash - argv0 + 1);
    if (dir_len + strlen("char-test.bin") + 1 > buflen) {
        snprintf(buf, buflen, "%s", fallback);
        return;
    }
    memcpy(buf, argv0, dir_len);
    memcpy(buf + dir_len, "char-test.bin", strlen("char-test.bin") + 1);
}

static long parse_args_and_load_image(int argc, char **argv, char **diff_so_file, int *diff_port) {
    char *log_file = NULL;
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
        } else if (argv[i][0] != '-') {
            img_file = argv[i];
        }
    }

    init_log(log_file);

    char default_flash_path[1024];
    if (img_file == NULL) {
        build_default_char_test_path((argc > 0) ? argv[0] : NULL, default_flash_path, sizeof(default_flash_path));
        img_file = default_flash_path;
    }

    flash_init_default_image();
    if (!flash_load_boot_image(img_file)) {
        fprintf(stderr, "Failed to load flash boot image: %s\n", img_file);
        exit(1);
    }

    uint32_t boot_base = 0;
    const uint8_t *boot_img = NULL;
    size_t boot_size = 0;
    if (!flash_get_boot_image_info(&boot_base, &boot_img, &boot_size) || boot_img == NULL || boot_size == 0) {
        fprintf(stderr, "Failed to query loaded flash boot image information\n");
        exit(1);
    }

    return (long)boot_size;
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
    for (int i = 0; i < 20; i++) {
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
