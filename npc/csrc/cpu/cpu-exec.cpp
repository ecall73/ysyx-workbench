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

// PMU report uses magenta so it can be visually separated from normal logs.
#define PmuLog(format, ...) \
    _Log(ANSI_FMT("[PMU] " format, ANSI_FG_MAGENTA) "\n", ##__VA_ARGS__)

static bool g_commit_valid = false;
static uint32_t g_commit_pc = 0;
static uint32_t g_commit_inst = 0;
static constexpr uint32_t kEbreakInst = 0x00100073u;

static uint64_t g_timer_us = 0;
static uint64_t g_nr_sim_cycle = 0;

struct PmuCounters {
    uint64_t ifu_supply;
    uint64_t ifu_nosupply_total;
    uint64_t ifu_wait_arready;
    uint64_t ifu_wait_rvalid;
    uint64_t ifu_ex_backpressure;
    uint64_t ifu_redirect_drop;
    uint64_t lsu_load_resp;
    uint64_t lsu_load_req;
    uint64_t lsu_store_req;
    uint64_t lsu_load_pending_cycle;
    uint64_t lsu_store_pending_cycle;
    uint64_t exu_done_fire;
    uint64_t non_redirect_commit;
    uint64_t icache_hit_cycle;
    uint64_t icache_miss;
    uint64_t icache_miss_refill_cycle;
};

static PmuCounters g_pmu = {};

extern "C" void npc_commit(int pc, int inst) {
    if (is_finished) {
        return;
    }

    g_commit_valid = true;
    g_commit_pc = (uint32_t)pc;
    g_commit_inst = (uint32_t)inst;
}

extern "C" void npc_pmu_event(int event_mask) {
    if (is_finished) {
        return;
    }

    uint32_t mask = (uint32_t)event_mask;
    if (mask & NPC_PMU_EVT_IFU_R_FIRE) g_pmu.ifu_supply++;
    if (mask & NPC_PMU_EVT_IFU_NOSUPPLY_TOTAL) g_pmu.ifu_nosupply_total++;
    if (mask & NPC_PMU_EVT_IFU_WAIT_ARREADY) g_pmu.ifu_wait_arready++;
    if (mask & NPC_PMU_EVT_IFU_WAIT_RVALID) g_pmu.ifu_wait_rvalid++;
    if (mask & NPC_PMU_EVT_IFU_ID_BACKPRESSURE) g_pmu.ifu_ex_backpressure++;
    if (mask & NPC_PMU_EVT_IFU_REDIRECT_DROP) g_pmu.ifu_redirect_drop++;
    if (mask & NPC_PMU_EVT_LSU_R_FIRE) g_pmu.lsu_load_resp++;
    if (mask & NPC_PMU_EVT_LSU_LOAD_REQ) g_pmu.lsu_load_req++;
    if (mask & NPC_PMU_EVT_LSU_STORE_REQ) g_pmu.lsu_store_req++;
    if (mask & NPC_PMU_EVT_LSU_LOAD_PENDING_CYCLE) g_pmu.lsu_load_pending_cycle++;
    if (mask & NPC_PMU_EVT_LSU_STORE_PENDING_CYCLE) g_pmu.lsu_store_pending_cycle++;
    if (mask & NPC_PMU_EVT_EXU_DONE_FIRE) g_pmu.exu_done_fire++;
    if (mask & NPC_PMU_EVT_DEC_TOTAL) g_pmu.non_redirect_commit++;
    if (mask & NPC_PMU_EVT_ICACHE_HIT) g_pmu.icache_hit_cycle++;
    if (mask & NPC_PMU_EVT_ICACHE_MISS) g_pmu.icache_miss++;
    if (mask & NPC_PMU_EVT_ICACHE_MISS_REFILL_CYCLE) g_pmu.icache_miss_refill_cycle++;
}

static uint64_t get_time_us() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

static double ratio(uint64_t numerator, uint64_t denominator) {
    return denominator ? (double)numerator / (double)denominator : 0.0;
}

static void pmu_table_header(const char *title) {
    PmuLog("=== %s ===", title);
    PmuLog("+----------------------+--------------+------------+------------------+");
    PmuLog("| %-20s | %12s | %10s | %-16s |", "item", "count/value", "cycle%", "detail");
    PmuLog("+----------------------+--------------+------------+------------------+");
}

static void pmu_table_row_count(const char *item, uint64_t count, const char *detail) {
    PmuLog("| %-20s | %12" PRIu64 " | %9.2f%% | %-16s |",
        item, count, 100.0 * ratio(count, g_nr_sim_cycle), detail);
}

static void pmu_table_row_value(const char *item, double value, const char *unit) {
    PmuLog("| %-20s | %12.3f | %10s | %-16s |", item, value, "-", unit);
}

static void pmu_table_footer() {
    PmuLog("+----------------------+--------------+------------+------------------+");
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

    uint64_t ifu_reason_known = g_pmu.ifu_wait_arready + g_pmu.ifu_wait_rvalid +
                                g_pmu.ifu_ex_backpressure + g_pmu.ifu_redirect_drop;
    uint64_t ifu_reason_unknown = (g_pmu.ifu_nosupply_total >= ifu_reason_known)
                                      ? (g_pmu.ifu_nosupply_total - ifu_reason_known)
                                      : 0;
    uint64_t icache_lookup = g_pmu.icache_hit_cycle + g_pmu.icache_miss;
    double icache_miss_rate = ratio(g_pmu.icache_miss, icache_lookup);
    double icache_miss_penalty = ratio(g_pmu.icache_miss_refill_cycle, g_pmu.icache_miss);
    double icache_amat = 1.0 + icache_miss_rate * icache_miss_penalty;
    uint64_t redirect_commit = (g_pmu.exu_done_fire >= g_pmu.non_redirect_commit)
                                   ? (g_pmu.exu_done_fire - g_pmu.non_redirect_commit)
                                   : 0;

    pmu_table_header("PMU IFU-ICache");
    pmu_table_row_count("if_supply", g_pmu.ifu_supply, "frontend valid");
    pmu_table_row_count("if_no_supply", g_pmu.ifu_nosupply_total, "frontend bubble");
    pmu_table_row_count("wait_arready", g_pmu.ifu_wait_arready, "miss request");
    pmu_table_row_count("wait_rvalid", g_pmu.ifu_wait_rvalid, "miss refill");
    pmu_table_row_count("ex_backpressure", g_pmu.ifu_ex_backpressure, "EX not ready");
    pmu_table_row_count("icache_hit_cycle", g_pmu.icache_hit_cycle, "hit valid cycle");
    pmu_table_row_count("icache_miss", g_pmu.icache_miss, "lookup miss");
    pmu_table_row_count("refill_cycles", g_pmu.icache_miss_refill_cycle, "miss service");
    if (ifu_reason_unknown != 0) {
        pmu_table_row_count("unclassified", ifu_reason_unknown, "PMU coverage");
    }
    pmu_table_row_value("hit_rate", 100.0 * ratio(g_pmu.icache_hit_cycle, icache_lookup), "% of lookup");
    pmu_table_row_value("avg_miss_penalty", icache_miss_penalty, "cycles/miss");
    pmu_table_row_value("AMAT", icache_amat, "cycles/access");
    pmu_table_footer();

    pmu_table_header("PMU LSU");
    pmu_table_row_count("load_req", g_pmu.lsu_load_req, "load access");
    pmu_table_row_count("load_resp", g_pmu.lsu_load_resp, "external R beat");
    pmu_table_row_count("store_req", g_pmu.lsu_store_req, "store access");
    pmu_table_row_count("load_pending", g_pmu.lsu_load_pending_cycle, "load wait");
    pmu_table_row_count("store_pending", g_pmu.lsu_store_pending_cycle, "store wait");
    pmu_table_row_value("avg_load_latency",
        ratio(g_pmu.lsu_load_pending_cycle, g_pmu.lsu_load_req), "cycles/load");
    pmu_table_row_value("avg_store_latency",
        ratio(g_pmu.lsu_store_pending_cycle, g_pmu.lsu_store_req), "cycles/store");
    pmu_table_footer();

    pmu_table_header("PMU Redirect");
    pmu_table_row_count("commit", g_pmu.exu_done_fire, "retire fire");
    pmu_table_row_count("non_redirect", g_pmu.non_redirect_commit, "normal retire");
    pmu_table_row_count("redirect", redirect_commit, "flush retire");
    pmu_table_row_count("if_drop", g_pmu.ifu_redirect_drop, "frontend bubble");
    pmu_table_row_value("redirect_rate",
        100.0 * ratio(redirect_commit, g_pmu.exu_done_fire), "% of commit");
    pmu_table_row_value("predict_accuracy", 0.0, "N/A no predictor");
    pmu_table_footer();
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
