#ifndef __SIM_TOP_H__
#define __SIM_TOP_H__

#if defined(NPC_BUILD_PLATFORM_NPC)
#include "Vtop.h"
typedef Vtop SimTop;
#elif defined(NPC_BUILD_PLATFORM_YSYXSOC)
#include "VysyxSoCFull.h"
typedef VysyxSoCFull SimTop;
#else
#error "unknown NPC platform"
#endif

#endif
