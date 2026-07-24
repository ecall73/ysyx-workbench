# Berkeley SoftFloat provides only IEEE-754 arithmetic.  RISC-V instruction
# semantics (NaN-boxing, fcsr, rounding-mode validation and exception accrual)
# remain in NEMU.

SOFTFLOAT_REV := a0c6494cdc11865811dec815d5c0049fba9d82a8
SOFTFLOAT_SHA256 := 1f719bcc8878be9627f6cfc44a0d6dbddf32bacc70ac81193bcbf2c62f97cbe9
SOFTFLOAT_ROOT := $(NEMU_HOME)/resource/softfloat
SOFTFLOAT_TARBALL := $(SOFTFLOAT_ROOT)/berkeley-softfloat-3-$(SOFTFLOAT_REV).tar.gz
SOFTFLOAT_DIR := $(SOFTFLOAT_ROOT)/berkeley-softfloat-3-$(SOFTFLOAT_REV)
SOFTFLOAT_HEADER := $(SOFTFLOAT_DIR)/source/include/softfloat.h
SOFTFLOAT_STAMP := $(SOFTFLOAT_DIR)/.nemu-extracted
SOFTFLOAT_BUILD := $(SOFTFLOAT_DIR)/build/Linux-x86_64-GCC
SOFTFLOAT_LIB := $(SOFTFLOAT_BUILD)/softfloat.a

INC_PATH += $(SOFTFLOAT_DIR)/source/include
ARCHIVES += $(SOFTFLOAT_LIB)
BUILD_DEPS += $(SOFTFLOAT_STAMP)

$(SOFTFLOAT_TARBALL):
	@mkdir -p $(dir $@)
	@echo + DOWNLOAD Berkeley SoftFloat $(SOFTFLOAT_REV)
	@curl --fail --location --silent --show-error \
	  https://codeload.github.com/ucb-bar/berkeley-softfloat-3/tar.gz/$(SOFTFLOAT_REV) \
	  --output $@.tmp
	@echo "$(SOFTFLOAT_SHA256)  $@.tmp" | sha256sum --check --status
	@mv $@.tmp $@

$(SOFTFLOAT_STAMP): $(SOFTFLOAT_TARBALL)
	@echo + EXTRACT Berkeley SoftFloat $(SOFTFLOAT_REV)
	@tar -xzf $< -C $(SOFTFLOAT_ROOT)
	@test -f $(SOFTFLOAT_HEADER)
	@touch $@

$(SOFTFLOAT_LIB): $(SOFTFLOAT_STAMP)
	@echo + BUILD Berkeley SoftFloat $(SOFTFLOAT_REV)
	@$(MAKE) -s -C $(SOFTFLOAT_BUILD) SPECIALIZE_TYPE=RISCV \
	  SOFTFLOAT_OPTS="-DSOFTFLOAT_ROUND_ODD -DINLINE_LEVEL=5 \
	  -DSOFTFLOAT_FAST_DIV32TO16 -DSOFTFLOAT_FAST_DIV64TO32 -fPIC"
	@touch $@
