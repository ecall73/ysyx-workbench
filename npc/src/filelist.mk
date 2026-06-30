SRCS-y += src/main.cpp
DIRS-$(CONFIG_PLATFORM_NPC) += src/memory
DIRS-y += src/cpu src/engine src/monitor src/utils
DIRS-$(CONFIG_PLATFORM_NPC) += src/platform/npc
DIRS-$(CONFIG_PLATFORM_YSYXSOC) += src/platform/ysyxsoc
