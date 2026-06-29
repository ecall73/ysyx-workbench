NAME = klib
SRCS = $(shell find src/ -name "*.c")
ifneq ($(KLIB_IMPL),newlib)
ifneq ($(KLIB_IMPL),picolibc)
SRCS := $(filter-out src/newlib.c,$(SRCS))
endif
endif
include $(AM_HOME)/Makefile
