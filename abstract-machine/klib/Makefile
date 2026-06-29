NAME = klib
SRCS = $(shell find src/ -name "*.c")
ifeq ($(PICOLIBC),1)
SRCS = src/newlib.c src/cpp.c
else
SRCS := $(filter-out src/newlib.c,$(SRCS))
endif
include $(AM_HOME)/Makefile

$(ARCHIVE): .EXTRA_PREREQS = force-clean-klib-archive
force-clean-klib-archive:
	@rm -f $(ARCHIVE)
.PHONY: force-clean-klib-archive
