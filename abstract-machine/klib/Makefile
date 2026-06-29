NAME = klib
SRCS = $(shell find src/ -name "*.c")
ifeq ($(PICOLIBC),1)
SRCS = src/newlib.c src/cpp.c
else
SRCS := $(filter-out src/newlib.c,$(SRCS))
endif
include $(AM_HOME)/Makefile
