.DEFAULT_GOAL := build

NPC_HOME := $(abspath .)
NEMU_HOME ?= $(abspath ../nemu)

-include $(NPC_HOME)/include/config/auto.conf
-include $(NPC_HOME)/include/config/auto.conf.cmd

remove_quote = $(patsubst "%",%,$(1))

CXX ?= g++

include $(NPC_HOME)/scripts/config.mk

config-targets := menuconfig savedefconfig help distclean clean
config-targets += $(filter %defconfig,$(MAKECMDGOALS))
iverilog-targets := sim-iverilog sim-iverilog-netlist

ifeq ($(filter $(config-targets),$(MAKECMDGOALS)),)
ifneq ($(filter $(iverilog-targets),$(MAKECMDGOALS)),)
SIM_MODE ?= npc
endif
SIM_MODE ?= $(call remove_quote,$(CONFIG_PLATFORM))
ifeq ($(SIM_MODE),npc)
CONFIG_PLATFORM_NPC := y
CONFIG_PLATFORM_YSYXSOC :=
else
ifeq ($(SIM_MODE),ysyxsoc)
CONFIG_PLATFORM_NPC :=
CONFIG_PLATFORM_YSYXSOC := y
endif
endif

FILELIST_MK = $(shell find -L ./src -name "filelist.mk")
include $(FILELIST_MK)

SRCS-y += $(if $(DIRS-y),$(shell find -L $(DIRS-y) \( -name "*.cpp" -o -name "*.c" \)),)
SRCS = $(sort $(SRCS-y))

include $(NPC_HOME)/scripts/build.mk
endif

clean:
	rm -rf ./build

distclean: clean
	rm -rf include/generated include/config .config .config.old

include ../Makefile

include $(NPC_HOME)/scripts/iverilog.mk

.PHONY: clean distclean sim-iverilog sim-iverilog-netlist
