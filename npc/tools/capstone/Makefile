REPO_PATH = repo
ifeq ($(wildcard repo/include/capstone/capstone.h),)
  $(shell git clone --depth=1 -b 5.0.6 https://github.com/capstone-engine/capstone.git $(REPO_PATH))
endif

ifeq ($(shell uname -s),Linux)
suffix = so.5
else ifeq ($(shell uname -s),Darwin)
suffix = 5.dylib
else
  $(error Unsupported OS ($(shell uname -s)))
endif

CAPSTONE = $(REPO_PATH)/libcapstone.$(suffix)
$(CAPSTONE):
	cd $(REPO_PATH) && CAPSTONE_ARCHS="riscv" bash make.sh

clean:
	$(MAKE) -C $(REPO_PATH) clean

all: $(CAPSTONE)
.DEFAULT_GOAL = all

.PHONY: all clean
