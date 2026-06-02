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

enum PmuInstClass : uint8_t {
    PMU_CLASS_LOAD = 0,
    PMU_CLASS_MISC_MEM,
    PMU_CLASS_OP_IMM,
    PMU_CLASS_AUIPC,
    PMU_CLASS_STORE,
    PMU_CLASS_OP,
    PMU_CLASS_LUI,
    PMU_CLASS_BRANCH,
    PMU_CLASS_JALR,
    PMU_CLASS_JAL,
    PMU_CLASS_SYSTEM,
    PMU_CLASS_INVALID,
    PMU_CLASS_COUNT
};

static const char *kPmuClassName[PMU_CLASS_COUNT] = {
    "LOAD", "MISC-MEM", "OP-IMM", "AUIPC", "STORE", "OP",
    "LUI", "BRANCH", "JALR", "JAL", "SYSTEM", "INVALID"
};

struct PmuCounters {
    uint64_t ifu_r_fire;
    uint64_t ifu_nosupply_total;
    uint64_t ifu_wait_arready;
    uint64_t ifu_wait_rvalid;
    uint64_t ifu_id_backpressure;
    uint64_t ifu_redirect_drop;
    uint64_t lsu_r_fire;
    uint64_t lsu_load_req;
    uint64_t lsu_load_pending_cycle;
    uint64_t exu_done_fire;
    uint64_t dec_total;
};

static PmuCounters g_pmu = {};
static uint64_t g_ret_class_cnt[PMU_CLASS_COUNT] = {};

static uint8_t pmu_classify_inst(uint32_t inst) {
    uint32_t opcode = inst & 0x7f;
    switch (opcode) {
        case 0x03: return PMU_CLASS_LOAD;      // LOAD
        case 0x0f: return PMU_CLASS_MISC_MEM;  // MISC-MEM (e.g. fence)
        case 0x13: return PMU_CLASS_OP_IMM;    // OP-IMM
        case 0x17: return PMU_CLASS_AUIPC;     // AUIPC
        case 0x23: return PMU_CLASS_STORE;     // STORE
        case 0x33: return PMU_CLASS_OP;        // OP
        case 0x37: return PMU_CLASS_LUI;       // LUI
        case 0x63: return PMU_CLASS_BRANCH;    // BRANCH
        case 0x67: return PMU_CLASS_JALR;      // JALR
        case 0x6f: return PMU_CLASS_JAL;       // JAL
        case 0x73: return PMU_CLASS_SYSTEM;    // SYSTEM
        default: return PMU_CLASS_INVALID;
    }
}

static void pmu_on_commit(uint32_t inst) {
    g_ret_class_cnt[pmu_classify_inst(inst)]++;
}

extern "C" void npc_commit(int pc, int inst) {
    if (is_finished) {
        return;
    }

    g_commit_valid = true;
    g_commit_pc = (uint32_t)pc;
    g_commit_inst = (uint32_t)inst;
    pmu_on_commit((uint32_t)inst);
}

extern "C" void npc_pmu_event(int event_mask) {
    if (is_finished) {
        return;
    }

    uint32_t mask = (uint32_t)event_mask;
    if (mask & NPC_PMU_EVT_IFU_R_FIRE) g_pmu.ifu_r_fire++;
    if (mask & NPC_PMU_EVT_IFU_NOSUPPLY_TOTAL) g_pmu.ifu_nosupply_total++;
    if (mask & NPC_PMU_EVT_IFU_WAIT_ARREADY) g_pmu.ifu_wait_arready++;
    if (mask & NPC_PMU_EVT_IFU_WAIT_RVALID) g_pmu.ifu_wait_rvalid++;
    if (mask & NPC_PMU_EVT_IFU_ID_BACKPRESSURE) g_pmu.ifu_id_backpressure++;
    if (mask & NPC_PMU_EVT_IFU_REDIRECT_DROP) g_pmu.ifu_redirect_drop++;
    if (mask & NPC_PMU_EVT_LSU_R_FIRE) g_pmu.lsu_r_fire++;
    if (mask & NPC_PMU_EVT_LSU_LOAD_REQ) g_pmu.lsu_load_req++;
    if (mask & NPC_PMU_EVT_LSU_LOAD_PENDING_CYCLE) g_pmu.lsu_load_pending_cycle++;
    if (mask & NPC_PMU_EVT_EXU_DONE_FIRE) g_pmu.exu_done_fire++;
    if (mask & NPC_PMU_EVT_DEC_TOTAL) g_pmu.dec_total++;
}

static uint64_t get_time_us() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

static double ratio(uint64_t numerator, uint64_t denominator) {
    return denominator ? (double)numerator / (double)denominator : 0.0;
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

    uint64_t dec_total = g_pmu.dec_total;
    uint64_t ifu_reason_known = g_pmu.ifu_wait_arready + g_pmu.ifu_wait_rvalid +
                                g_pmu.ifu_id_backpressure + g_pmu.ifu_redirect_drop;
    uint64_t ifu_reason_unknown = (g_pmu.ifu_nosupply_total >= ifu_reason_known)
                                      ? (g_pmu.ifu_nosupply_total - ifu_reason_known)
                                      : 0;

    PmuLog("=== PMU counters (simulation-only) ===");
    PmuLog("ifu_r_fire      = %" PRIu64, g_pmu.ifu_r_fire);
    PmuLog("ifu_nosupply_total   = %" PRIu64, g_pmu.ifu_nosupply_total);
    PmuLog("ifu_wait_arready     = %" PRIu64, g_pmu.ifu_wait_arready);
    PmuLog("ifu_wait_rvalid      = %" PRIu64, g_pmu.ifu_wait_rvalid);
    PmuLog("ifu_id_backpressure  = %" PRIu64, g_pmu.ifu_id_backpressure);
    PmuLog("ifu_redirect_drop    = %" PRIu64, g_pmu.ifu_redirect_drop);
    PmuLog("lsu_r_fire      = %" PRIu64, g_pmu.lsu_r_fire);
    PmuLog("lsu_load_req    = %" PRIu64, g_pmu.lsu_load_req);
    PmuLog("lsu_load_pending_cycle = %" PRIu64, g_pmu.lsu_load_pending_cycle);
    PmuLog("exu_done_fire   = %" PRIu64, g_pmu.exu_done_fire);
    PmuLog("dec_total       = %" PRIu64, dec_total);

    if (g_nr_sim_cycle > 0) {
        PmuLog("rate.ifu_r/cycle      = %.4f", ratio(g_pmu.ifu_r_fire, g_nr_sim_cycle));
        PmuLog("rate.ifu_nosupply/cycle = %.4f", ratio(g_pmu.ifu_nosupply_total, g_nr_sim_cycle));
        PmuLog("rate.exu_done/cycle   = %.4f", ratio(g_pmu.exu_done_fire, g_nr_sim_cycle));
        PmuLog("rate.instret/cycle    = %.4f", ratio(g_nr_guest_inst, g_nr_sim_cycle));
    }

    PmuLog("=== PMU IFU no-supply breakdown ===");
    PmuLog("ifu.reason.wait_arready: P(reason|nosupply)=%.2f%%, P(reason)=%.2f%%",
        100.0 * ratio(g_pmu.ifu_wait_arready, g_pmu.ifu_nosupply_total),
        100.0 * ratio(g_pmu.ifu_wait_arready, g_nr_sim_cycle));
    PmuLog("ifu.reason.wait_rvalid: P(reason|nosupply)=%.2f%%, P(reason)=%.2f%%",
        100.0 * ratio(g_pmu.ifu_wait_rvalid, g_pmu.ifu_nosupply_total),
        100.0 * ratio(g_pmu.ifu_wait_rvalid, g_nr_sim_cycle));
    PmuLog("ifu.reason.id_backpressure: P(reason|nosupply)=%.2f%%, P(reason)=%.2f%%",
        100.0 * ratio(g_pmu.ifu_id_backpressure, g_pmu.ifu_nosupply_total),
        100.0 * ratio(g_pmu.ifu_id_backpressure, g_nr_sim_cycle));
    PmuLog("ifu.reason.redirect_drop: P(reason|nosupply)=%.2f%%, P(reason)=%.2f%%",
        100.0 * ratio(g_pmu.ifu_redirect_drop, g_pmu.ifu_nosupply_total),
        100.0 * ratio(g_pmu.ifu_redirect_drop, g_nr_sim_cycle));
    PmuLog("ifu.reason.unclassified: P(reason|nosupply)=%.2f%%, P(reason)=%.2f%%",
        100.0 * ratio(ifu_reason_unknown, g_pmu.ifu_nosupply_total),
        100.0 * ratio(ifu_reason_unknown, g_nr_sim_cycle));

    PmuLog("=== PMU LSU load latency ===");
    PmuLog("lsu.avg_load_latency(cycle) = %.3f (pending=%" PRIu64 ", load_req=%" PRIu64 ")",
        ratio(g_pmu.lsu_load_pending_cycle, g_pmu.lsu_load_req),
        g_pmu.lsu_load_pending_cycle, g_pmu.lsu_load_req);

    PmuLog("=== PMU commit table (type/count/percentage) ===");
    PmuLog("+----------+--------------+------------+");
    PmuLog("| %-8s | %12s | %10s |", "type", "count", "percentage");
    PmuLog("+----------+--------------+------------+");
    for (int i = 0; i < PMU_CLASS_COUNT; i++) {
        double retire_mix = 100.0 * ratio(g_ret_class_cnt[i], g_nr_guest_inst);
        PmuLog("| %-8s | %12" PRIu64 " | %9.5f%% |",
            kPmuClassName[i], g_ret_class_cnt[i], retire_mix);
    }
    PmuLog("+----------+--------------+------------+");
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
