#include <verilated.h>
#include <verilated_vcd_c.h>

#include <platform/platform.h>
#include <sim_top.h>

SimTop *g_top = NULL;
VerilatedContext *g_contextp = NULL;
VerilatedVcdC *g_tfp = NULL;
