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
FD_BUILD_PATCH = $(abspath enable-fd.patch)
SOFTFLOAT_BUILD_PATCH = $(abspath enable-softfloat.patch)
WFI_NOP_PATCH = $(abspath enable-wfi-nop.patch)
FD_BUILD_SETUP = fd-build-setup
$(REPO_MAKEFILE):
	@mkdir -p $(@D)
	cd $(@D) && $(abspath $(REPO_PATH))/configure
	sed -i -e 's/-g -O2/-O2/' $@

$(FD_BUILD_SETUP): $(REPO_MAKEFILE) $(FD_BUILD_PATCH) $(SOFTFLOAT_BUILD_PATCH) $(WFI_NOP_PATCH)
	@set -e; changed=0; \
	if ! grep -q 'NEMU DiffTest: enable base F/D' $(REPO_BUILD_PATH)/riscv.mk; then \
	  (cd $(REPO_BUILD_PATH) && patch --forward --silent -p1 < $(FD_BUILD_PATCH)); \
	  changed=1; \
	fi; \
	if ! grep -q 'NEMU DiffTest: restore SoftFloat sources' $(REPO_BUILD_PATH)/softfloat.mk; then \
	  (cd $(REPO_BUILD_PATH) && patch --forward --silent -p1 < $(SOFTFLOAT_BUILD_PATCH)); \
	  changed=1; \
	fi; \
	if ! grep -q 'NEMU DiffTest: NEMU uses the architecturally permitted WFI-as-NOP behavior' \
	    $(REPO_PATH)/riscv/processor.h; then \
	  (cd $(REPO_PATH) && patch --forward --silent -p1 < $(WFI_NOP_PATCH)); \
	  changed=1; \
	fi; \
	if [ "$$changed" = 1 ] || \
	    ! grep -q 'DEFINE_INSN(fadd_s)' $(REPO_BUILD_PATH)/insn_list.h 2>/dev/null; then \
	  rm -f $(REPO_BUILD_PATH)/insn_list.h; \
	  $(MAKE) -C $(REPO_BUILD_PATH) insn_list.h; \
	fi

SPIKE = $(REPO_BUILD_PATH)/spike
$(SPIKE): $(FD_BUILD_SETUP)
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

$(BINARY): $(SPIKE) $(SRCS)
	@set -e; exec 9>$(BUILD_DIR)/.link.lock; \
	flock 9; \
	if [ -s "$@" ] && [ "$@" -nt "$(SPIKE)" ] && [ "$@" -nt "$(SRCS)" ]; then \
	  exit 0; \
	fi; \
	tmp="$@.tmp.$$$$"; \
	trap 'rm -f "$$tmp"' EXIT; \
	echo + CXXLD $@; \
	g++ -std=c++17 -O2 -shared -fPIC -fvisibility=hidden \
	  $(INC_PATH) $(SRCS) $(INC_LIBS) -o "$$tmp"; \
	mv -f "$$tmp" "$@"; \
	trap - EXIT

clean:
	rm -rf $(BUILD_DIR)

all: $(BINARY)
.DEFAULT_GOAL = all

.PHONY: all clean $(SPIKE) $(FD_BUILD_SETUP)
