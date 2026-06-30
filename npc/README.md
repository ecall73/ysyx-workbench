# NPC

NPC is the Verilator simulation environment for the local RISC-V RTL core.
Its host-side debugger, logging, expression evaluation, register display,
DiffTest glue, and tracing code are kept close to the corresponding NEMU
modules. NPC-specific code is limited to RTL ticking, DPI commit collection,
platform memory/image loading, ysyxSoC/NVBoard integration, and iVerilog CI
entry points.

## NEMU/NPC File Correspondence

| NEMU file | NPC file | Status |
| --- | --- | --- |
| `nemu/src/nemu-main.c` | `npc/src/npc-main.c` | Same process entry shape; calls NPC monitor and cleanup. |
| `nemu/src/engine/interpreter/init.c` | `npc/src/engine/interpreter/init.c` | Same `engine_start()` entry shape; SDB still owns interactive control. |
| `nemu/src/cpu/cpu-exec.c` | `npc/src/cpu/cpu-exec.c` | Same execution-loop/logging shape; instruction execution is replaced by Verilator tick plus DPI commit. |
| `nemu/src/monitor/monitor.c` | `npc/src/monitor/monitor.c` | Same argument/log/init flow; adds Verilator top, reset, wave, and platform setup. |
| `nemu/src/monitor/sdb/*` | `npc/src/monitor/sdb/*` | Same SDB command style and watchpoint/expression modules. |
| `nemu/src/monitor/ftrace.c` | `npc/src/monitor/ftrace.c` | Same ELF symbol based function trace module. |
| `nemu/src/utils/log.c` | `npc/src/utils/log.c` | Same log and per-trace output module, minus NEMU's AM-target guard. |
| `nemu/src/utils/timer.c` | `npc/src/utils/timer.c` | Same host timer utility without AM mode. |
| `nemu/src/utils/disasm.c` | `npc/src/utils/disasm.c` | Same capstone-based disassembly path, restricted to RISC-V. |
| `nemu/src/utils/state.c` | `npc/src/utils/state.c` | Same simulator state object, renamed to NPC state. |
| `nemu/src/isa/riscv32/reg.c` | `npc/src/isa/riscv32/reg.c` | Identical register display/string lookup module. |
| `nemu/src/isa/riscv32/difftest/dut.c` | `npc/src/isa/riscv32/difftest/dut.c` | Same ISA register comparison role for NPC-vs-NEMU DiffTest. |
| `nemu/src/cpu/difftest/dut.c` | `npc/src/cpu/difftest/dut.c` | Same dynamic ref-so interface; adapted so NPC is DUT and NEMU is ref. |
| `nemu/src/memory/paddr.c` | `npc/src/memory/paddr.c` | Same paddr read/write shape; backing storage is selected by NPC platform. |
| `nemu/src/memory/vaddr.c` | `npc/src/memory/vaddr.c` | Same direct virtual-to-physical access helper. |
| `nemu/tools/kconfig` / `nemu/tools/fixdep` | `npc/tools/kconfig` / `npc/tools/fixdep` | Same tools copied under NPC; built through NPC's local `scripts/build-tool.mk`. |
| `nemu/scripts/build.mk` | `npc/scripts/build-tool.mk` | Same small host-tool build role, kept local so NPC config tools do not depend on NEMU. |

## Necessary NPC-only Files

| NPC file | Reason |
| --- | --- |
| `npc/src/cpu/dpi/commit.cpp` | Collects retired RTL state into the C-side `CPU_state`. |
| `npc/src/platform/common/sim.cpp` | Owns shared Verilator top/context/wave globals. |
| `npc/src/platform/npc/platform.cpp` | Standalone NPC PMEM, image loading, and DPI memory access. |
| `npc/src/platform/ysyxsoc/platform.cpp` | ysyxSoC flash/NVBoard/reset-pin integration and image loading. |
| `npc/include/platform/platform.h` | Minimal boundary between NEMU-style host modules and NPC platform differences. |
| `npc/include/sim_top.h` | Selects `Vtop` or `VysyxSoCFull` from Kconfig platform. |
| `npc/include/monitor/monitor.h` | C/C++ boundary for Verilator-facing code to call NEMU-style C modules. |
| `npc/scripts/iverilog.mk` | Keeps the CI iVerilog and netlist simulation entry points separate from Verilator. |

## Removed NEMU Modules

NPC does not keep NEMU modules that have no active role in RTL simulation:

| Removed module | Why NPC does not need it |
| --- | --- |
| `src/device/*` and `include/device/*` | NEMU device emulation is not used by NPC Verilator paths; device behavior is in RTL/SoC or platform glue. |
| NEMU interpreter instruction execution code | RTL executes instructions; NPC only keeps the NEMU-style `engine_start()`/SDB control entry. |
| `src/isa/riscv32/inst.c` | Instructions are executed by RTL, not by NEMU's software decoder. |
| `src/isa/riscv32/system/{intr,mmu}.c` | CSR/trap/MMU behavior comes from RTL state and NEMU ref DiffTest. |
| `src/am-bin.S` and `configs/*-am_defconfig` | NPC is not built as an AM-native executable. |
| `tools/spike-diff` | NPC DiffTest uses the NEMU shared object as reference, not Spike directly. |

## Necessary Differences

| Area | Difference | Why it is necessary |
| --- | --- | --- |
| Build language split | Most copied NEMU-style `.c` modules are compiled with `gcc`; only Verilator-facing sources are compiled as C++. | Keeps copied C code close to NEMU while still allowing Verilator/NVBoard C++ objects. |
| Build target dimension | NPC removes NEMU's `CONFIG_TARGET_AM` / `CONFIG_TARGET_NATIVE_ELF` branches. | NPC is only a host Verilator simulator; it is never built as an AM payload. Keeping those branches would be dead configuration. |
| `disasm.c` | Keeps only RISC-V capstone mode. | NPC only supports the local RISC-V RTL, so NEMU's x86/MIPS/LoongArch branches are removed. |
| `CPU_state` / DPI commit | Host state always exposes 32 GPRs; RTL commits zero for x16..x31. | Keeps SDB and DiffTest state shape aligned with NEMU while the core remains RV32E internally. |
| `cpu-exec.c` | Replaces `isa_exec_once()` with Verilator tick plus DPI commit collection. | RTL, not NEMU's software decoder, executes instructions. |
| `monitor.c` | Adds Verilator top creation/reset/wave handling and platform image loading. | NEMU does not own an RTL top; NPC must. |
| `paddr.c` | Uses platform-selected backing storage and ysyxSoC ref memory ranges. | NPC has standalone PMEM and ysyxSoC flash/SRAM/SDRAM modes. |
| `native.mk` | Keeps `sim` as an alias of `run`. | Existing AM ysyxSoC scripts call `make -C npc ... sim`; it must execute the simulator rather than only build. |
| UART stdout | `UART_STDOUT ?= 1` is a Makefile-only switch; `UART_STDOUT=0` builds a separate `*-no-uart-stdout` binary. | This preserves the previous CI knob without adding a permanent Kconfig item, and prevents stale binaries when the Verilator macro changes. |
| Debug build | `DEBUG=1` or `CONFIG_CC_DEBUG=y` selects the `*-debug` binary and adds `-Og -ggdb3 -DDEBUG`. | Matches NEMU-style debug builds while keeping AM's `DEBUG=1` meaning of non-batch SDB mode. |
| Kconfig ISA options | Removes the RVE host-side option. | The simulation environment presents an RV32I-shaped 32-GPR state; RVE is only an RTL implementation detail. |
| DiffTest | NPC loads NEMU shared object as ref; `NEMU_HOME` appears only for that ref path. | NPC is DUT, NEMU is the reference. |

## Preserved NPC Features

| Feature | Current form |
| --- | --- |
| Standalone NPC and ysyxSoC modes | `make -C npc npc_defconfig` / `ysyxsoc_defconfig`, or temporary `SIM_MODE=npc/ysyxsoc`. |
| Batch vs SDB | AM adds `-b` by default; `DEBUG=1` keeps the simulator interactive. |
| UART stdout CI switch | Default `UART_STDOUT=1`; CI can use `UART_STDOUT=0`. |
| Waveform | Kconfig `CONFIG_WAVE`; Verilator gets `--trace` and writes `waveform.vcd`. |
| Performance counters | Kconfig `CONFIG_PERF`; Verilog gets `NPC_ENABLE_PERF`. |
| Trace family | Kconfig `TRACE/ITRACE/FTRACE/MTRACE/DTRACE/ETRACE`; logs use NEMU-style `-l/-f/-F/-E/-M/-D` arguments. |
| DiffTest | Kconfig `CONFIG_DIFFTEST`; runtime accepts `-d REF_SO -p PORT`, with NEMU so as ref. |
| iVerilog CI path | `make -C npc sim-iverilog IMG=...`; netlist target is still present and requires external `NETLIST`/`CELLS`. |

## Verification Notes

Recent checks performed after the 32-GPR/RVE and target-dimension cleanup:

- `make -C npc npc_defconfig && make -C npc build`
- `make -C npc ysyxsoc_defconfig && make -C npc build`
- `make -C am-kernels/kernels/hello ARCH=riscv32e-npc run`
- `make -C am-kernels/kernels/hello ARCH=riscv32e-ysyxsoc run`
- `make -C am-kernels/benchmarks/microbench ARCH=riscv32e-npc run mainargs=test`
- `make -C am-kernels/benchmarks/microbench ARCH=riscv32e-ysyxsoc run mainargs=test`
- `make -C am-kernels/benchmarks/microbench ARCH=riscv32e-ysyxsoc run mainargs=test UART_STDOUT=0`
- `make -C npc sim-iverilog IMG=/home/ecall73/ysyx-workbench/am-kernels/kernels/hello/build/hello-riscv32e-npc.bin`

`git diff --check` is intentionally not run by the agent because git operations
are user-only in this thread. The iVerilog netlist target also requires
caller-provided `NETLIST=...` and `CELLS=...`; the target is preserved, but
those artifacts are external to this directory.
