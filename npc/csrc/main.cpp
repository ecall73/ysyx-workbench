#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// Memory size 128MB
#define MEM_SIZE (128 * 1024 * 1024)
#define MAX_SIM_TIME 1000000
static uint8_t pmem[MEM_SIZE];

// Check boundary
void check_bound(int addr) {
    if (addr < 0x80000000 || addr >= 0x80000000 + MEM_SIZE) {
        printf("Error: address %x out of bound\n", addr);
        // exit(1);
    }
}

extern "C" int pmem_read(int raddr) {
    // 总是读取地址为`raddr & ~0x3u`的4字节返回
    check_bound(raddr);
    int index = (raddr - 0x80000000) & ~0x3u;
    return *(int *)&pmem[index];
}

extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    // 总是往地址为`waddr & ~0x3u`的4字节按写掩码`wmask`写入`wdata`
    check_bound(waddr);
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

extern "C" void npc_trap() {
    is_finished = true;
}

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    Vtop* top = new Vtop{contextp};

    // Enable Trace
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99); // Trace 99 levels of hierarchy
    tfp->open("waveform.vcd");

    // Load simple program: 
    // 0x80000000: auipc t0, 0          (0x00000297)
    // 0x80000004: sb zero, 16(t0)      (0x00028823) -> [0x80000000 + 16] = 0
    // 0x80000008: lbu a0, 16(t0)       (0x0102c503) -> a0 = 0
    // 0x8000000C: ebreak               (0x00100073)
    // 0x80000010: deadbeef             (0xdeadbeef)
    uint32_t *inst = (uint32_t *)&pmem[0];
    inst[0] = 0x00000297; 
    inst[1] = 0x00028823;
    inst[2] = 0x0102c503;
    inst[3] = 0x00100073;
    inst[4] = 0x00100073;
    inst[5] = 0x00100073;
    inst[6] = 0x00100073;

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

    if (is_finished) {
        printf("Simulation finished by ebreak.\n");
    } else {
        printf("Simulation finished by timeout or unknown reason.\n");
    }

    tfp->close();
    delete tfp;
    delete top;
    delete contextp;
    return 0;
}
