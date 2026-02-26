#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <time.h>

int main(int argc, char** argv)
{
    srand(time(NULL));
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    
    Verilated::traceEverOn(true);
    
    Vtop* top = new Vtop{contextp};
    VerilatedVcdC* tfp = new VerilatedVcdC;
    
    top->trace(tfp, 99);
    tfp->open("wave.vcd");
    
    contextp->time(0);
    // tfp->dump(contextp->time());
    
    for (int i = 0; i < 10; i++)
    {
        int a = rand() & 1;
        int b = rand() & 1;
        top->a = a;
        top->b = b;
        
        top->eval();
        
        printf("a = %d, b = %d, f = %d\n", a, b, top->f);
        assert(top->f == (a ^ b));
        
        tfp->dump(contextp->time());
        contextp->timeInc(10);
    }

    tfp->dump(contextp->time());
    
    tfp->close();
    delete top;
    delete contextp;
    return 0;
}