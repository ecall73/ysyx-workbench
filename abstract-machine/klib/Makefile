NAME = klib
SRCS = $(shell find src/ -name "*.c")
ifeq ($(KLIB_IMPL),newlib)
SRCS = src/newlib.c src/cpp.c
else ifeq ($(KLIB_IMPL),picolibc)
SRCS = src/newlib.c src/cpp.c
else
SRCS := $(filter-out src/newlib.c,$(SRCS))
endif
include $(AM_HOME)/Makefile
