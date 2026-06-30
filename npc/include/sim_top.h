#ifndef __NPC_SIM_TOP_H__
#define __NPC_SIM_TOP_H__

#include "generated/autoconf.h"

#ifdef NPC_BUILD_PLATFORM_NPC
#undef CONFIG_PLATFORM_NPC
#undef CONFIG_PLATFORM_YSYXSOC
#define CONFIG_PLATFORM_NPC 1
#endif

#ifdef NPC_BUILD_PLATFORM_YSYXSOC
#undef CONFIG_PLATFORM_NPC
#undef CONFIG_PLATFORM_YSYXSOC
#define CONFIG_PLATFORM_YSYXSOC 1
#endif

#ifdef NPC_BUILD_WAVE
#undef CONFIG_WAVE
#if NPC_BUILD_WAVE
#define CONFIG_WAVE 1
#endif
#endif

#ifdef NPC_BUILD_PERF
#undef CONFIG_PERF
#if NPC_BUILD_PERF
#define CONFIG_PERF 1
#endif
#endif

class VerilatedContext;
class VerilatedVcdC;

#ifdef CONFIG_PLATFORM_YSYXSOC
#include "VysyxSoCFull.h"
using SimTop = VysyxSoCFull;
#else
#ifdef CONFIG_PLATFORM_NPC
#include "Vtop.h"
using SimTop = Vtop;
#else
#error "NPC platform is not configured."
#endif
#endif

#endif
