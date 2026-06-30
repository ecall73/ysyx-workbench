#include <inttypes.h>
#include <stdio.h>
#include <time.h>

#include "verilated.h"
#include "verilated_vcd_c.h"
#include "common.h"

#ifdef CONFIG_PERF
// PMU report uses magenta so it can be visually separated from normal logs.
#define PmuLog(format, ...) \
    _Log(ANSI_FMT(format, ANSI_FG_MAGENTA) "\n", ##__VA_ARGS__)
#endif

static bool g_commit_valid = false;
static uint32_t g_commit_pc = 0;
static uint32_t g_commit_inst = 0;
static uint32_t g_commit_next_pc = 0;
static DutState g_dut_state = {};
static constexpr uint32_t kEcallInst = 0x00000073u;
static constexpr uint32_t kMretInst = 0x30200073u;
static constexpr uint32_t kEbreakInst = 0x00100073u;
static constexpr uint64_t kMaxInstToPrint = 10;

static uint64_t g_timer_us = 0;
static uint64_t g_nr_sim_cycle = 0;
static bool g_print_step = false;

#ifdef CONFIG_PERF
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
    uint64_t ifetch_fire;
    uint64_t icache_miss;
    uint64_t icache_miss_cycle;
    uint64_t dcache_access;
    uint64_t dcache_store;
    uint64_t dcache_miss;
    uint64_t dcache_miss_cycle;
    uint64_t redirect;
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
#endif

extern "C" void npc_commit(
    uint32_t commit_pc,
    uint32_t commit_inst,
    uint32_t pc,
    uint32_t mstatus,
    uint32_t mtvec,
    uint32_t mepc,
    uint32_t mcause,
    const uint32_t *gpr
) {
    if (is_finished) {
        return;
    }

    g_commit_valid = true;
    g_commit_pc = commit_pc;
    g_commit_inst = commit_inst;
    g_commit_next_pc = pc;
    for (int i = 0; i < 16; i++) {
        g_dut_state.gpr[i] = gpr[i];
    }
    for (int i = 16; i < 32; i++) {
        g_dut_state.gpr[i] = 0;
    }
    g_dut_state.pc = pc;
    g_dut_state.mstatus = mstatus;
    g_dut_state.mtvec = mtvec;
    g_dut_state.mepc = mepc;
    g_dut_state.mcause = mcause;
#ifdef CONFIG_PERF
    pmu_on_commit(commit_inst);
#endif
}

void npc_read_dut_state(DutState *state) {
    *state = g_dut_state;
}

extern "C" void npc_pmu_event(int event_mask) {
#ifdef CONFIG_PERF
    if (is_finished) {
        return;
    }

    uint32_t mask = (uint32_t)event_mask;
    if (mask & NPC_PMU_EVT_IFETCH_FIRE) g_pmu.ifetch_fire++;
    if (mask & NPC_PMU_EVT_ICACHE_MISS) g_pmu.icache_miss++;
    if (mask & NPC_PMU_EVT_ICACHE_MISS_CYCLE) g_pmu.icache_miss_cycle++;
    if (mask & NPC_PMU_EVT_DCACHE_ACCESS) g_pmu.dcache_access++;
    if (mask & NPC_PMU_EVT_DCACHE_STORE) g_pmu.dcache_store++;
    if (mask & NPC_PMU_EVT_DCACHE_MISS) g_pmu.dcache_miss++;
    if (mask & NPC_PMU_EVT_DCACHE_MISS_CYCLE) g_pmu.dcache_miss_cycle++;
    if (mask & NPC_PMU_EVT_REDIRECT) g_pmu.redirect++;
#else
    (void)event_mask;
#endif
}

static uint64_t get_time_us() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

#ifdef CONFIG_PERF
static double ratio(uint64_t numerator, uint64_t denominator) {
    return denominator ? (double)numerator / (double)denominator : 0.0;
}

static void statistic() {
    uint64_t icache_hit = g_pmu.ifetch_fire;
    uint64_t icache_access = icache_hit + g_pmu.icache_miss;
    double icache_miss_rate = ratio(g_pmu.icache_miss, icache_access);
    double icache_miss_penalty = ratio(g_pmu.icache_miss_cycle, g_pmu.icache_miss);
    double icache_amat = 1.0 + icache_miss_rate * icache_miss_penalty;
    uint64_t dcache_load = (g_pmu.dcache_access >= g_pmu.dcache_store)
                               ? (g_pmu.dcache_access - g_pmu.dcache_store)
                               : 0;
    double dcache_miss_penalty = ratio(g_pmu.dcache_miss_cycle, g_pmu.dcache_miss);
    uint64_t control_flow =
        g_ret_class_cnt[PMU_CLASS_BRANCH] +
        g_ret_class_cnt[PMU_CLASS_JAL] +
        g_ret_class_cnt[PMU_CLASS_JALR] +
        g_ret_class_cnt[PMU_CLASS_SYSTEM] +
        g_ret_class_cnt[PMU_CLASS_MISC_MEM];

    PmuLog("\n=============== PMU IFU-ICache ===============");
    PmuLog("+------------------+-------------+-----------+");
    PmuLog("| %-16s | %11s | %9s |", "item", "count/value", "ratio");
    PmuLog("+------------------+-------------+-----------+");
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "access", icache_access, 100.0 * ratio(icache_access, g_nr_sim_cycle));
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "miss", g_pmu.icache_miss, 100.0 * ratio(g_pmu.icache_miss, g_nr_sim_cycle));
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "miss_cycle", g_pmu.icache_miss_cycle, 100.0 * ratio(g_pmu.icache_miss_cycle, g_nr_sim_cycle));
    PmuLog("| %-16s | %11s | %8.4f%% |",
        "hit_rate", "-", 100.0 * ratio(icache_hit, icache_access));
    PmuLog("| %-16s | %11s | %8.4f%% |",
        "miss_rate", "-", 100.0 * icache_miss_rate);
    PmuLog("| %-16s | %11.4f | %9s |",
        "avg_miss_penalty", icache_miss_penalty, "-");
    PmuLog("| %-16s | %11.4f | %9s |",
        "AMAT", icache_amat, "-");
    PmuLog("| %-16s | %11s | %9.4f |",
        "access / cycle", "-", ratio(icache_access, g_nr_sim_cycle));
    PmuLog("+------------------+-------------+-----------+\n");

    PmuLog("=============== PMU LSU-DCache ===============");
    PmuLog("+------------------+-------------+-----------+");
    PmuLog("| %-16s | %11s | %9s |", "item", "count/value", "ratio");
    PmuLog("+------------------+-------------+-----------+");
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "access", g_pmu.dcache_access, 100.0 * ratio(g_pmu.dcache_access, g_nr_sim_cycle));
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "load", dcache_load, 100.0 * ratio(dcache_load, g_nr_sim_cycle));
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "store", g_pmu.dcache_store, 100.0 * ratio(g_pmu.dcache_store, g_nr_sim_cycle));
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "miss", g_pmu.dcache_miss, 100.0 * ratio(g_pmu.dcache_miss, g_nr_sim_cycle));
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "miss_cycle", g_pmu.dcache_miss_cycle, 100.0 * ratio(g_pmu.dcache_miss_cycle, g_nr_sim_cycle));
    PmuLog("| %-16s | %11s | %8.4f%% |",
        "store_ratio", "-", 100.0 * ratio(g_pmu.dcache_store, g_pmu.dcache_access));
    PmuLog("| %-16s | %11s | %8.4f%% |",
        "miss_rate", "-", 100.0 * ratio(g_pmu.dcache_miss, g_pmu.dcache_access));
    PmuLog("| %-16s | %11.4f | %9s |",
        "avg_miss_penalty", dcache_miss_penalty, "-");
    PmuLog("| %-16s | %11s | %9.4f |",
        "access / cycle", "-", ratio(g_pmu.dcache_access, g_nr_sim_cycle));
    PmuLog("+------------------+-------------+-----------+\n");

    PmuLog("================ PMU Redirect ================");
    PmuLog("+------------------+-------------+-----------+");
    PmuLog("| %-16s | %11s | %9s |", "item", "count/value", "ratio");
    PmuLog("+------------------+-------------+-----------+");
    PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
        "redirect", g_pmu.redirect, 100.0 * ratio(g_pmu.redirect, g_nr_sim_cycle));
    PmuLog("| %-16s | %11s | %8.4f%% |",
        "redirect / inst", "-", 100.0 * ratio(g_pmu.redirect, g_nr_guest_inst));
    PmuLog("| %-16s | %11s | %8.4f%% |",
        "redirect / ctrl", "-", 100.0 * ratio(g_pmu.redirect, control_flow));
    PmuLog("+------------------+-------------+-----------+\n");

    PmuLog("============== PMU commit table ==============");
    PmuLog("+------------------+-------------+-----------+");
    PmuLog("| %-16s | %11s | %9s |", "type", "count", "ratio");
    PmuLog("+------------------+-------------+-----------+");
    for (int i = 0; i < PMU_CLASS_COUNT; i++) {
        double retire_mix = 100.0 * ratio(g_ret_class_cnt[i], g_nr_guest_inst);
        PmuLog("| %-16s | %11" PRIu64 " | %8.4f%% |",
            kPmuClassName[i], g_ret_class_cnt[i], retire_mix);
    }
    PmuLog("+------------------+-------------+-----------+\n");
}
#endif

void cpu_exec(uint64_t n) {
    g_print_step = (n < kMaxInstToPrint);

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
#ifdef CONFIG_WAVE
        if (g_tfp) g_tfp->dump(g_contextp->time());
#endif

        g_top->clock = 1;
        g_top->eval();
        g_contextp->timeInc(1);
#ifdef CONFIG_WAVE
        if (g_tfp) g_tfp->dump(g_contextp->time());
#endif

        if (g_commit_valid) {
            uint32_t commit_pc = g_commit_pc;
            uint32_t commit_inst = g_commit_inst;
            uint32_t pc = g_commit_next_pc;
            DutState dut_post = g_dut_state;
            g_commit_valid = false;

            g_nr_guest_inst++;
#ifdef CONFIG_ITRACE
            if ((ITRACE_COND)) {
                char disasm_buf[128];
                disassemble(disasm_buf, sizeof(disasm_buf), commit_pc, commit_inst);
                itrace_write("0x%08x: 0x%08x  %s\n", commit_pc, commit_inst, disasm_buf);
                if (g_print_step) {
                    printf("0x%08x: 0x%08x  %s\n", commit_pc, commit_inst, disasm_buf);
                }
            }
#endif
#ifdef CONFIG_FTRACE
            ftrace_check(commit_pc, commit_inst, pc);
#endif
#ifdef CONFIG_ETRACE
            if (commit_inst == kEcallInst) {
                etrace_write("ecall pc=0x%08x -> 0x%08x mstatus=0x%08x mepc=0x%08x mcause=0x%08x\n",
                    commit_pc, pc, dut_post.mstatus, dut_post.mepc, dut_post.mcause);
            } else if (commit_inst == kMretInst) {
                etrace_write("mret pc=0x%08x -> 0x%08x mstatus=0x%08x mepc=0x%08x mcause=0x%08x\n",
                    commit_pc, pc, dut_post.mstatus, dut_post.mepc, dut_post.mcause);
            }
#endif
            if (commit_inst == kEbreakInst) {
                is_finished = true;
                trap_pc = (int)commit_pc;
                trap_a0 = (int)dut_post.gpr[10];
            } else if (!difftest_step(commit_pc, commit_inst, pc, &dut_post)) {
                is_finished = true;
                trap_pc = (int)commit_pc;
                trap_a0 = -1;
            }
        }
        if (is_finished || g_contextp->gotFinish()) {
            need_report = is_finished;
            break;
        }

        platform_update();
        g_nr_sim_cycle++;

        if (is_finished) {
            need_report = true;
            break;
        }

        if (g_nr_sim_cycle > CONFIG_MAX_SIM_TIME) {
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
#ifdef CONFIG_PERF
        statistic();
#endif
    }
}
