#***************************************************************************************
# Copyright (c) 2014-2024 Zihao Yu, Nanjing University
#
# NEMU is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#          http://license.coscl.org.cn/MulanPSL2
#
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
#
# See the Mulan PSL v2 for more details.
#**************************************************************************************/

NPC_HOME ?= $(abspath .)
NEMU_HOME ?= $(abspath ../nemu)
YSYX_SOC_HOME ?= $(abspath ../ysyxSoC)
NVBOARD_HOME ?= $(abspath ../nvboard)

ifeq ($(wildcard $(NPC_HOME)/src/npc-main.c),)
  $(error NPC_HOME=$(NPC_HOME) is not an NPC repo)
endif

-include $(NPC_HOME)/include/config/auto.conf
-include $(NPC_HOME)/include/config/auto.conf.cmd

remove_quote = $(patsubst "%",%,$(1))

GUEST_ISA := riscv32
SIM_MODE ?= $(call remove_quote,$(CONFIG_PLATFORM))
DEBUG_ENABLED := $(if $(filter 1 y yes true,$(DEBUG)),1,$(if $(filter 1 y yes true,$(debug)),1,$(if $(CONFIG_CC_DEBUG),1,)))
UART_STDOUT ?= 1
UART_STDOUT_ENABLED := $(if $(filter 0 n no false,$(UART_STDOUT)),,1)
NAME = $(GUEST_ISA)-npc$(if $(DEBUG_ENABLED),-debug,)$(if $(UART_STDOUT_ENABLED),,-no-uart-stdout)

ifeq ($(filter npc ysyxsoc,$(SIM_MODE)),)
SIM_MODE := npc
endif
ifeq ($(SIM_MODE),npc)
CONFIG_PLATFORM_NPC := y
CONFIG_PLATFORM_YSYXSOC :=
else
CONFIG_PLATFORM_NPC :=
CONFIG_PLATFORM_YSYXSOC := y
endif

FILELIST_MK = $(shell find -L ./src -name "filelist.mk")
include $(FILELIST_MK)

DIRS-BLACKLIST-y += $(DIRS-BLACKLIST)
SRCS-BLACKLIST-y += $(if $(DIRS-BLACKLIST-y), $(shell find -L $(DIRS-BLACKLIST-y) \( -name "*.c" -o -name "*.cc" -o -name "*.cpp" \)),)
SRCS-BLACKLIST-y += $(SRCS-BLACKLIST)
SRCS-y += $(if $(DIRS-y), $(shell find -L $(DIRS-y) \( -name "*.c" -o -name "*.cc" -o -name "*.cpp" \)),)
SRCS = $(filter-out $(SRCS-BLACKLIST-y),$(SRCS-y))

ifneq ($(CONFIG_CC),)
CXX = $(call remove_quote,$(CONFIG_CC))
endif
ifeq ($(CXX),clang++)
CC := clang
else
CC := gcc
endif
CFLAGS_BUILD += $(call remove_quote,$(CONFIG_CC_OPT))
CFLAGS_BUILD += $(if $(DEBUG_ENABLED),-Og -ggdb3,)
CFLAGS_BUILD += $(if $(DEBUG_ENABLED),-DDEBUG,)
CFLAGS_TRACE += -DITRACE_COND='$(if $(CONFIG_ITRACE_COND),$(subst ",,$(CONFIG_ITRACE_COND)),true)'
CFLAGS_TRACE += -DMTRACE_COND='$(if $(CONFIG_MTRACE_COND),$(subst ",,$(CONFIG_MTRACE_COND)),true)'
CFLAGS += $(CFLAGS_BUILD) $(CFLAGS_TRACE) -D__GUEST_ISA__=$(GUEST_ISA)
LDFLAGS += $(CFLAGS_BUILD)

include $(NPC_HOME)/scripts/config.mk

iverilog-targets := sim-iverilog sim-iverilog-netlist
ifneq ($(filter $(iverilog-targets),$(MAKECMDGOALS)),)
SIM_MODE ?= npc
endif
include $(NPC_HOME)/scripts/native.mk
ifneq ($(filter $(iverilog-targets),$(MAKECMDGOALS)),)
include $(NPC_HOME)/scripts/iverilog.mk
endif
