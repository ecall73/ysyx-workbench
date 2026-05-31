#ifndef __SIM_MODE_H__
#define __SIM_MODE_H__

#include <stdint.h>

#ifdef NPC_SIM_MODE_YSYXSOC

#include "VysyxSoCFull.h"
using SimTop = VysyxSoCFull;

static inline void sim_set_external_idle(SimTop *top) {
  // PS/2 and UART RX idles high.
  top->externalPins_ps2_clk = 1;
  top->externalPins_ps2_data = 1;
  top->externalPins_uart_rx = 1;
}

#else

#ifdef NPC_SIM_MODE_NPC

#include "Vtop.h"
using SimTop = Vtop;

static inline void sim_set_external_idle(SimTop *top) { (void)top; }

#else

#error "NPC simulation mode is not set. Define NPC_SIM_MODE_NPC or NPC_SIM_MODE_YSYXSOC."

#endif

#endif

#endif
