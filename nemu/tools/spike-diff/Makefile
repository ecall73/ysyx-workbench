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

REPO_PATH = repo
ifeq ($(wildcard repo/spike_main),)
  $(shell git clone --depth=1 git@github.com:NJU-ProjectN/riscv-isa-sim $(REPO_PATH))
endif

REPO_BUILD_PATH = $(REPO_PATH)/build
REPO_MAKEFILE = $(REPO_BUILD_PATH)/Makefile
BUILD_PATCHES = $(abspath build-riscv.mk.patch build-softfloat.mk.patch)
SOURCE_PATCHES = $(abspath riscv-processor.h.patch riscv-processor.cc.patch \
  riscv-csrs.cc.patch riscv-execute.cc.patch)
SPIKE_PATCHES = $(BUILD_PATCHES) $(SOURCE_PATCHES)
DIFFTEST_HEADER = $(NEMU_HOME)/include/riscv-difftest.h
SPIKE_REVISION = $(shell git -C $(REPO_PATH) rev-parse --short=16 HEAD 2>/dev/null)
SPIKE_BUNDLE_SHA = $(shell sha256sum $(SPIKE_PATCHES) $(DIFFTEST_HEADER) \
  $(abspath difftest.cc) $(abspath Makefile) | awk '{print $$1}' | \
  sha256sum | cut -c1-24)
SPIKE_DIFFTEST_ID = spike-$(SPIKE_REVISION)-rv32gc-sv32-sstc-svadu-$(SPIKE_BUNDLE_SHA)
PATCH_SETUP = patch-setup
$(REPO_MAKEFILE):
	@mkdir -p $(@D)
	cd $(@D) && $(abspath $(REPO_PATH))/configure
	sed -i -e 's/-g -O2/-O2/' $@

$(PATCH_SETUP): $(REPO_MAKEFILE) $(SPIKE_PATCHES)
	@set -e; changed=0; \
	apply_one() { \
	  patch_root="$$1"; patch_file="$$2"; \
	  if (cd "$$patch_root" && patch --reverse --force --silent --dry-run -p1 \
	      < "$$patch_file" >/dev/null 2>&1); then \
	    :; \
	  elif (cd "$$patch_root" && patch --force --silent --dry-run -p1 \
	      < "$$patch_file" >/dev/null 2>&1); then \
	    (cd "$$patch_root" && patch --forward --batch --silent -p1 < "$$patch_file"); \
	    changed=1; \
	  else \
	    echo "Spike patch is partially applied or incompatible: $$patch_file" >&2; \
	    exit 1; \
	  fi; \
	}; \
	for patch_file in $(BUILD_PATCHES); do \
	  apply_one "$(REPO_BUILD_PATH)" "$$patch_file"; \
	done; \
	for patch_file in $(SOURCE_PATCHES); do \
	  apply_one "$(REPO_PATH)" "$$patch_file"; \
	done; \
	if [ "$$changed" = 1 ] || \
	    ! grep -q 'DEFINE_INSN(fadd_s)' $(REPO_BUILD_PATH)/insn_list.h 2>/dev/null; then \
	  rm -f $(REPO_BUILD_PATH)/insn_list.h; \
	  $(MAKE) -C $(REPO_BUILD_PATH) insn_list.h; \
	fi

SPIKE = $(REPO_BUILD_PATH)/spike
$(SPIKE): $(PATCH_SETUP)
	CFLAGS="-fvisibility=hidden" CXXFLAGS="-fvisibility=hidden" $(MAKE) -C $(REPO_BUILD_PATH)

BUILD_DIR = ./build
$(shell mkdir -p $(BUILD_DIR))

inc_dependencies = fesvr riscv disasm customext fdt softfloat spike_main spike_dasm build
INC_PATH  = -I$(REPO_PATH) $(addprefix -I$(REPO_PATH)/, $(inc_dependencies))
INC_PATH += -I$(NEMU_HOME)/include
lib_dependencies = libspike_main.a libriscv.a libdisasm.a libsoftfloat.a libfesvr.a libfdt.a
INC_LIBS  = $(addprefix $(REPO_PATH)/build/, $(lib_dependencies))

NAME = $(GUEST_ISA)-spike-so
BINARY = $(BUILD_DIR)/$(NAME)
SRCS = difftest.cc

$(BINARY): $(SPIKE) $(SRCS) $(SPIKE_PATCHES) $(DIFFTEST_HEADER) Makefile
	@set -e; exec 9>$(BUILD_DIR)/.link.lock; \
	flock 9; \
	fresh=1; \
	for input in "$(SPIKE)" "$(SRCS)" $(SPIKE_PATCHES) \
	    "$(DIFFTEST_HEADER)" "$(abspath Makefile)"; do \
	  [ "$@" -nt "$$input" ] || fresh=0; \
	done; \
	if [ -s "$@" ] && [ "$$fresh" = 1 ]; then \
	  exit 0; \
	fi; \
	tmp="$@.tmp.$$$$"; \
	trap 'rm -f "$$tmp"' EXIT; \
	echo + CXXLD $@; \
	g++ -std=c++17 -O2 -shared -fPIC -fvisibility=hidden \
	  -DSPIKE_DIFFTEST_IMPLEMENTATION_ID=\"$(SPIKE_DIFFTEST_ID)\" \
	  $(INC_PATH) $(SRCS) $(INC_LIBS) -o "$$tmp"; \
	mv -f "$$tmp" "$@"; \
	trap - EXIT

clean:
	rm -rf $(BUILD_DIR)

all: $(BINARY)
.DEFAULT_GOAL = all

.PHONY: all clean $(SPIKE) $(PATCH_SETUP)
