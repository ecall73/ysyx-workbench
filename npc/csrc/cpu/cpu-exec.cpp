#include <inttypes.h>
#include <stdio.h>
#include <time.h>

#include "VysyxSoCFull.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include "npc.h"
#include <nvboard.h>

extern "C" void npc_trap(int pc, int a0) {
    is_finished = true;
    trap_pc = pc;
    trap_a0 = a0;
}

extern "C" void npc_commit(int pc, char wen, char waddr, int wdata, int inst) {
    if (is_finished) {
        return;
    }

    uint32_t dut_pc = (uint32_t)pc;
    bool dut_wen = (wen & 0x1) != 0;
    uint8_t dut_waddr = (uint8_t)waddr & 0x1f;
    uint32_t dut_wdata = (uint32_t)wdata;
    uint32_t dut_inst = (uint32_t)inst;

    g_nr_guest_inst++;
    if (!difftest_step(dut_pc, dut_wen, dut_waddr, dut_wdata, dut_inst)) {
        is_finished = true;
        trap_pc = (int)dut_pc;
        trap_a0 = -1;
    }
}

static uint64_t g_timer_us = 0;
static uint64_t g_nr_sim_cycle = 0;

static uint64_t get_time_us() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

static void statistic() {
    Log("host time spent = %" PRIu64 " us", g_timer_us);
    Log("total guest instructions = %" PRIu64, g_nr_guest_inst);
    Log("total simulation cycles = %" PRIu64, g_nr_sim_cycle);

    if (g_nr_sim_cycle > 0) {
        Log("IPC = %.4f", (double)g_nr_guest_inst / (double)g_nr_sim_cycle);
    } else {
        Log("No simulation cycle counted, can not calculate IPC");
    }

    if (g_timer_us > 0) {
        Log("simulation frequency = %" PRIu64 " inst/s", g_nr_guest_inst * 1000000 / g_timer_us);
    } else {
        Log("Finish running in less than 1 us and can not calculate the simulation frequency");
    }
}

void cpu_exec(uint64_t n) {
    if (is_finished) {
        printf("Program execution has ended. To restart the program, exit NPC and run again.\n");
        return;
    }

    uint64_t timer_start = get_time_us();
    bool need_report = false;

    bool run_forever = (n == (uint64_t)-1);
    uint64_t start_inst = g_nr_guest_inst;
    while (1) {
        if (!run_forever && (g_nr_guest_inst - start_inst >= n)) {
            break;
        }

        if (is_finished || g_contextp->gotFinish()) {
            if (is_finished) {
                need_report = true;
            }
            break;
        }

        g_top->clock = 0;
        g_top->eval();
        g_contextp->timeInc(1);
        if (g_tfp) g_tfp->dump(g_contextp->time());

        g_top->clock = 1;
        g_top->eval();
        g_contextp->timeInc(1);
        if (g_tfp) g_tfp->dump(g_contextp->time());
        nvboard_update();
        g_nr_sim_cycle++;

        if (is_finished) {
            need_report = true;
            break;
        }

        if (g_nr_sim_cycle > MAX_SIM_TIME) {
            Log("Simulation timed out at cycle %" PRIu64, g_nr_sim_cycle);
            is_finished = true;
            trap_a0 = -1;
            trap_pc = 0;
            need_report = true;
            break;
        }
    }

    uint64_t timer_end = get_time_us();
    g_timer_us += timer_end - timer_start;

    if (need_report) {
        Log("npc: %s at pc = 0x%08x",
            (trap_a0 == 0 ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN)
                          : ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED)),
            trap_pc);
        statistic();
    }
}
