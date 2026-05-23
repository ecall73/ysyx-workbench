NAME = psram-mem-test
SRCS = src/psram-mem-test.c

include $(AM_HOME)/Makefile

# Keep this test self-contained: custom linker script + size-oriented build.
override LDSCRIPTS := $(shell pwd)/linker-psram-mem-test.ld
CFLAGS += -Os
