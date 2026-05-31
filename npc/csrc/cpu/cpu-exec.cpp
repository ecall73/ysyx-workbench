#include <inttypes.h>
#include <stdio.h>
#include <time.h>

#include "verilated.h"
#include "verilated_vcd_c.h"
#include "npc.h"
#include "sim_mode.h"
#ifdef NPC_SIM_MODE_YSYXSOC
#include <nvboard.h>
#endif

static bool g_commit_valid = false;
static uint32_t g_commit_pc = 0;
static uint32_t g_commit_inst = 0;
static constexpr uint32_t kEbreakInst = 0x00100073u;

extern "C" void npc_commit(int pc, int inst) {
    if (is_finished) {
        return;
    }

    g_commit_valid = true;
    g_commit_pc = (uint32_t)pc;
    g_commit_inst = (uint32_t)inst;
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

        if (g_commit_valid) {
            uint32_t commit_pc = g_commit_pc;
            uint32_t commit_inst = g_commit_inst;
            g_commit_valid = false;

            g_nr_guest_inst++;
            if (!difftest_step(commit_pc, commit_inst)) {
                is_finished = true;
                trap_pc = (int)commit_pc;
                trap_a0 = -1;
            } else if (commit_inst == kEbreakInst) {
                is_finished = true;
                trap_pc = (int)commit_pc;
                trap_a0 = (int)npc_read_dut_gpr(10);
            }
        }
        if (is_finished || g_contextp->gotFinish()) {
            need_report = is_finished;
            break;
        }

#ifdef NPC_SIM_MODE_YSYXSOC
        nvboard_update();
#endif
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
