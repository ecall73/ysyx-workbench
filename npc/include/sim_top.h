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

#ifdef NPC_BUILD_TRACE
#undef CONFIG_TRACE
#if NPC_BUILD_TRACE
#define CONFIG_TRACE 1
#endif
#endif

#ifdef NPC_BUILD_ITRACE
#undef CONFIG_ITRACE
#if NPC_BUILD_ITRACE
#define CONFIG_ITRACE 1
#endif
#endif

#ifdef NPC_BUILD_FTRACE
#undef CONFIG_FTRACE
#if NPC_BUILD_FTRACE
#define CONFIG_FTRACE 1
#endif
#endif

#ifdef NPC_BUILD_MTRACE
#undef CONFIG_MTRACE
#if NPC_BUILD_MTRACE
#define CONFIG_MTRACE 1
#endif
#endif

#ifdef NPC_BUILD_DTRACE
#undef CONFIG_DTRACE
#if NPC_BUILD_DTRACE
#define CONFIG_DTRACE 1
#endif
#endif

#ifdef NPC_BUILD_ETRACE
#undef CONFIG_ETRACE
#if NPC_BUILD_ETRACE
#define CONFIG_ETRACE 1
#endif
#endif

#ifndef CONFIG_TRACE_START
#define CONFIG_TRACE_START 0
#endif

#ifndef CONFIG_TRACE_END
#define CONFIG_TRACE_END 10000
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
