#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// Memory size 128MB
#define MEM_SIZE 0x8000000
#define MAX_SIM_TIME 10000
static uint8_t pmem[MEM_SIZE];
static Vtop* g_top = NULL;

// Check boundary
bool check_bound(int addr, const char* type) {
    if (addr < 0x80000000 || addr >= 0x80000000 + MEM_SIZE) {
        return false;
    }
    return true;
}

extern "C" int pmem_read(int raddr) {
    // 总是读取地址为`raddr & ~0x3u`的4字节返回
    if (!check_bound(raddr, "READ")) return 0;
    int index = (raddr - 0x80000000) & ~0x3u;
    return *(int *)&pmem[index];
}

extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    // 总是往地址为`waddr & ~0x3u`的4字节按写掩码`wmask`写入`wdata`
    if (!check_bound(waddr, "WRITE")) return;
    int index = (waddr - 0x80000000) & ~0x3u;
    uint32_t *p = (uint32_t *)&pmem[index];
    uint32_t orig = *p;
    uint32_t mask = 0;
    if (wmask & 0x1) mask |= 0x000000FF;
    if (wmask & 0x2) mask |= 0x0000FF00;
    if (wmask & 0x4) mask |= 0x00FF0000;
    if (wmask & 0x8) mask |= 0xFF000000;
    *p = (orig & ~mask) | (wdata & mask);
}

bool is_finished = false;
int trap_a0 = 0;
int trap_pc = 0;

extern "C" void npc_trap(int pc, int a0) {
    is_finished = true;
    trap_pc = pc;
    trap_a0 = a0;
}

long load_image(char *img_file) {
    if (img_file == NULL) {
        printf("No image file specified.\n");
        return 0;
    }

    FILE *fp = fopen(img_file, "rb");
    if (fp == NULL) {
        printf("Can not open '%s'\n", img_file);
        return 0;
    }

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);

    printf("The image is %s, size = %ld\n", img_file, size);

    fseek(fp, 0, SEEK_SET);
    int ret = fread(pmem, size, 1, fp);
    assert(ret == 1);

    fclose(fp);
    return size;
}

const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    Vtop* top = new Vtop{contextp};
    g_top = top;

    // Enable Trace
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99); // Trace 99 levels of hierarchy
    tfp->open("waveform.vcd");

    if (argc > 1) {
        load_image(argv[1]);
    } else {
        // Load default program: 
        // 0x80000000: auipc t0, 0          (0x00000297)
        // 0x80000004: sb zero, 16(t0)      (0x00028823) -> [0x80000000 + 16] = 0
        // 0x80000008: lbu a0, 16(t0)       (0x0102c503) -> a0 = 0
        // 0x8000000C: ebreak               (0x00100073)
        // 0x80000010: deadbeef             (0xdeadbeef)
        uint32_t *inst = (uint32_t *)&pmem[0];
        inst[0] = 0x00900293; 
        inst[1] = 0xfff00313;
        inst[2] = 0x00000393;
        inst[3] = 0x00200e13;
        inst[4] = 0x01c30333;
        inst[5] = 0x006383b3;
        inst[6] = 0xfe629ce3;
        inst[7] = 0x00100073;
    }

    top->clk = 0;
    top->rst = 1;
    top->eval();
    contextp->timeInc(1);
    tfp->dump(contextp->time());
    
    // Reset for a few cycles
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        contextp->timeInc(1);
        tfp->dump(contextp->time());
    }
    top->rst = 0;

    printf("Simulation started. Waiting for ebreak...\n");

    while (!is_finished && !contextp->gotFinish()) {
        top->clk = !top->clk;
        top->eval();
        contextp->timeInc(1);
        tfp->dump(contextp->time());
        if (contextp->time() > MAX_SIM_TIME) {
            printf("Simulation timed out at time %ld\n", contextp->time());
            break;
        }
    }

    int exit_code = 0;

    if (is_finished) {
        if (trap_a0 == 0) {
            printf("npc: HIT GOOD TRAP at pc = 0x%08x\n", trap_pc);
            exit_code = 0;
        } else {
            printf("npc: HIT BAD TRAP at pc = 0x%08x\n", trap_pc);
            exit_code = -1;
        }
        printf("Simulation finished by ebreak.\n");
    } else {
        printf("Simulation finished by timeout or unknown reason.\n");
        exit_code = -1;
    }

    // Print register values
    printf("Register File Content:\n");
    for (int i = 0; i < 32; i++) {
        printf("\033[1;31m(x%02d) \033[1;32m%-4s \033[1;34m0x%08x\033[0m\t", i, regs[i], top->debug_reg_file[i]);
        if (i % 4 == 3) {
            printf("\n");
        }
    }

    tfp->close();
    delete tfp;
    delete top;
    delete contextp;
    return exit_code;
}
