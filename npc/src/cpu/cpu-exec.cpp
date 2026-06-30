#include <inttypes.h>
#include <stdio.h>
#include <time.h>

#include "verilated.h"
#include "verilated_vcd_c.h"
#include "common.h"
#include "cpu/cpu.h"
#include "cpu/difftest.h"
#include "monitor/sdb.h"
#include "platform/platform.h"
#include "utils.h"

#ifdef CONFIG_PERF
// PMU report uses magenta so it can be visually separated from normal logs.
#define PmuLog(format, ...) \
    _Log(ANSI_FMT(format, ANSI_FG_MAGENTA) "\n", ##__VA_ARGS__)
#endif

static constexpr uint32_t kEcallInst = 0x00000073u;
static constexpr uint32_t kMretInst = 0x30200073u;
static constexpr uint32_t kEbreakInst = 0x00100073u;
static constexpr uint64_t kMaxInstToPrint = 10;

static uint64_t g_timer_us = 0;
static uint64_t g_nr_sim_cycle = 0;
static bool g_print_step = false;

#ifdef CONFIG_FTRACE
static int32_t sext32(uint32_t val, int bits) {
    uint32_t mask = 1u << (bits - 1);
    return (int32_t)((val ^ mask) - mask);
}

static uint32_t jal_imm(uint32_t inst) {
    uint32_t imm =
        ((inst >> 31) & 0x1) << 20 |
        ((inst >> 21) & 0x3ff) << 1 |
        ((inst >> 20) & 0x1) << 11 |
        ((inst >> 12) & 0xff) << 12;
    return (uint32_t)sext32(imm, 21);
}

static void ftrace_commit(uint32_t pc, uint32_t inst, uint32_t dnpc) {
    uint32_t opcode = inst & 0x7f;
    uint32_t rd = (inst >> 7) & 0x1f;
    uint32_t rs1 = (inst >> 15) & 0x1f;
    int32_t imm = sext32((inst >> 20) & 0xfff, 12);

    if (opcode == 0x6f && (rd == 1 || rd == 5)) {
        ftrace_call(pc, pc + jal_imm(inst));
    } else if ((inst & 0x707f) == 0x67 && rd == 0 && rs1 == 1 && imm == 0) {
        ftrace_ret(pc);
    } else if ((inst & 0x707f) == 0x67 && (rd == 1 || rd == 5)) {
        ftrace_call(pc, dnpc);
    }
}
#endif

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

extern "C" void npc_pmu_event(int event_mask) {
#ifdef CONFIG_PERF
    if (npc_state == NPC_END || npc_state == NPC_ABORT || npc_state == NPC_QUIT) {
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

static bool trace_and_difftest(const RetiredInst *retired) {
    g_nr_guest_inst++;
#ifdef CONFIG_PERF
    pmu_on_commit(retired->commit_inst);
#endif
#ifdef CONFIG_ITRACE
    if ((ITRACE_COND)) {
        char disasm_buf[128];
        disassemble(disasm_buf, sizeof(disasm_buf), retired->commit_pc, retired->commit_inst);
        itrace_write("0x%08x: 0x%08x  %s\n", retired->commit_pc, retired->commit_inst, disasm_buf);
        if (g_print_step) {
            printf("0x%08x: 0x%08x  %s\n", retired->commit_pc, retired->commit_inst, disasm_buf);
        }
    }
#endif
#ifdef CONFIG_FTRACE
    ftrace_commit(retired->commit_pc, retired->commit_inst, retired->state.pc);
#endif
#ifdef CONFIG_ETRACE
    if (retired->commit_inst == kEcallInst) {
        etrace_write("ecall pc=0x%08x -> 0x%08x mstatus=0x%08x mepc=0x%08x mcause=0x%08x\n",
            retired->commit_pc, retired->state.pc, retired->state.mstatus, retired->state.mepc, retired->state.mcause);
    } else if (retired->commit_inst == kMretInst) {
        etrace_write("mret pc=0x%08x -> 0x%08x mstatus=0x%08x mepc=0x%08x mcause=0x%08x\n",
            retired->commit_pc, retired->state.pc, retired->state.mstatus, retired->state.mepc, retired->state.mcause);
    }
#endif
    if (retired->commit_inst == kEbreakInst) {
        npc_state = NPC_END;
        trap_pc = (int)retired->commit_pc;
        trap_a0 = (int)retired->state.gpr[10];
    }
#ifdef CONFIG_DIFFTEST
    else if (!difftest_step(retired->commit_pc, retired->commit_inst, &retired->state)) {
        npc_state = NPC_ABORT;
        trap_pc = (int)retired->commit_pc;
        trap_a0 = -1;
    }
#endif
#ifdef CONFIG_WATCHPOINT
    if (wp_check()) {
        npc_state = NPC_STOP;
        return true;
    }
#endif
    return npc_state != NPC_RUNNING;
}

#ifdef CONFIG_PERF
static double ratio(uint64_t numerator, uint64_t denominator) {
    return denominator ? (double)numerator / (double)denominator : 0.0;
}

static void pmu_statistic() {
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
#ifdef CONFIG_PERF
    pmu_statistic();
#endif
}

static void sim_cycle() {
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
}

static bool retire_pending_inst() {
    RetiredInst retired;
    if (!npc_fetch_retired_inst(&retired)) {
        return false;
    }

    return trace_and_difftest(&retired);
}

static void execute(uint64_t n) {
    bool run_forever = (n == (uint64_t)-1);
    uint64_t start_inst = g_nr_guest_inst;

    while (run_forever || g_nr_guest_inst - start_inst < n) {
        if (npc_state != NPC_RUNNING || g_contextp->gotFinish()) {
            break;
        }

        sim_cycle();
        if (retire_pending_inst()) {
            break;
        }

        if (npc_state != NPC_RUNNING || g_contextp->gotFinish()) {
            break;
        }

        platform_update();
        g_nr_sim_cycle++;

        if (npc_state != NPC_RUNNING) {
            break;
        }

        if (g_nr_sim_cycle > CONFIG_MAX_SIM_TIME) {
            Log("Simulation timed out at cycle %" PRIu64, g_nr_sim_cycle);
            npc_state = NPC_ABORT;
            trap_a0 = -1;
            trap_pc = 0;
            break;
        }
    }
}

void cpu_exec(uint64_t n) {
    g_print_step = (n < kMaxInstToPrint);

    switch (npc_state) {
        case NPC_END:
        case NPC_ABORT:
        case NPC_QUIT:
            printf("Program execution has ended. To restart the program, exit NPC and run again.\n");
            return;
        default:
            npc_state = NPC_RUNNING;
            break;
    }

    uint64_t timer_start = get_time_us();
    execute(n);
    uint64_t timer_end = get_time_us();
    g_timer_us += timer_end - timer_start;

    switch (npc_state) {
        case NPC_RUNNING:
            npc_state = NPC_STOP;
            break;
        case NPC_END:
        case NPC_ABORT:
            Log("npc: %s at pc = 0x%08x",
                (npc_state == NPC_ABORT ? ANSI_FMT("ABORT", ANSI_FG_RED) :
                 (trap_a0 == 0 ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN)
                               : ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED))),
                trap_pc);
            statistic();
            break;
        case NPC_QUIT:
            statistic();
            break;
        default:
            break;
    }
}
