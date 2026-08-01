# YSYX Workbench Workstreams

This repository is an integration workspace, not a flat monorepo. Each
workstream has its own source of truth, configuration, artifacts, and
validation path. Use this map to place changes and to identify consumers
without copying application-specific details into skills.

## Operating Principles

1. Give each task one primary owner and write scope.
2. Treat downstream failures as evidence, not proof of ownership.
3. Change shared contracts serially from owner to consumer.
4. Derive active behavior from source, configuration, and build rules.
5. Use the fastest backend that faithfully exposes the behavior.

## Ownership Map

| Workstream | Primary paths | Owns |
|---|---|---|
| Repository base | `.envrc`, root `Makefile`, `scripts/`, `patch/`, `.gitmodules` | Environment defaults, tracer integration, repository automation, patches, submodule topology |
| ISA reference and emulator | `nemu/` | RISC-V architectural execution, monitor, traces, devices, traps, virtual memory, versioned DiffTest ABI and reference adapters |
| Abstract Machine runtime | `abstract-machine/` | AM ABI, platform startup/linkage, IOE, CTE, VME, MPE, klib, architecture/platform build rules |
| Kernel and userland integration | `nanos-lite/`, `navy-apps/` | Loader, syscall, file/device abstraction, ramdisk generation, user ABI, libraries and native compatibility |
| Standalone and SoC DUT harness | `npc/` | RV32 DUT RTL, Verilator/Icarus harnesses, commit observation, traces, DiffTest client, platform adapters |
| Full SoC and peripherals | `ysyxSoC/` | SoC generator/source, generated integration RTL, AXI interconnect, memory and peripheral models |
| AM-hosted RTOS | `rt-thread-am/bsp/abstract-machine/`, shared `rt-thread-am/` code | AM BSP, RT-Thread build discovery, context switching, board/device integration, embedded AM workloads |
| Architectural validation | `am-apps/tests/`, `am-apps/diff/`, `riscv-tests-am/`, `riscv-arch-test-am/` | General platform tests, DiffTest-only protocol checks, legacy ISA regressions, official architecture compliance tests |
| Support submodules | `am-kernels/`, `fceux-am/`, `nvboard/` | Reusable workloads, emulator frontend, and virtual-board support consumed by owning workstreams |

The active scope excludes the removed `am-apps/contracts` and `am-apps/ioe`
trees and excludes `xv6-riscv` until the user explicitly re-enables it.

## Dependency Directions

### Bare-metal execution

`toolchain -> AM/klib -> program or test -> NEMU, NPC, or ysyxSoC backend`

The AM `ARCH` selects both ISA and platform. A failure can come from the
program, AM platform layer, linker/startup contract, backend, or an unsupported
ISA assumption.

### Kernel and userland

`Navy app/library -> fsimg and ramdisk -> nanos-lite loader/syscall/fs -> AM -> backend`

Build inclusion, image generation, generated file tables, syscall numbers,
loader expectations, and runtime libraries form one integration chain.

### RTL correctness

`program image -> NPC platform adapter -> DUT visible state -> DiffTest profile adapter -> architectural events`

Derive DUT observations from committed or otherwise architecturally visible
signals. RTL timing, cache refill beats, and device transactions are evidence
for the DUT side, not state that the reference model must reproduce cycle by
cycle.

### Differential testing

`DUT transition -> ordered ARCH_STEP or ASYNC_INTR -> REF independent transition or typed repair -> REF observation -> profile comparison`

The versioned profile owns features, fields, capabilities, reset and memory-map
selection. The DUT and REF may use different internal state layouts or register
models when explicit adapters project the same profile. Serialize changes from
the shared NEMU-owned ABI through each REF and DUT consumer.

### Full-system RTL

`ysyxSoC generator/source -> generated SoC RTL -> NPC ysyxSoC harness -> NVBoard and peripherals`

Determine whether the requested change belongs to generator source, checked-in
generated RTL, the DUT core, the host harness, or a peripheral before editing.

### AM-hosted RT-Thread

`RT-Thread configuration/source discovery -> AM BSP and linker integration -> AM image -> backend`

SCons selects sources and includes; the AM Makefile performs the final target
build. Treat generated source lists as derived configuration.

## Coupled Contracts

Serialize changes that affect any of these contracts:

- ISA, CSR, exception, interrupt, or privilege semantics;
- AM Context layout, event semantics, IOE register ABI, or platform linkage;
- syscall numbering, user ABI, loader format, ramdisk/file-table generation;
- physical address map, MMIO side effects, AXI behavior, reset, or boot flow;
- DiffTest ABI, profile/capability negotiation, state layout, event order,
  initialization, memory transport, or typed-skip policy;
- generated RTL interfaces or source-to-generated-artifact provenance;
- toolchain flags and ISA strings shared by producers and consumers.

Self-contained tests, documentation, and leaf implementation changes can be
parallelized when they do not modify one of these contracts.

## Generated Artifact Rules

| Artifact | Derive it from |
|---|---|
| NEMU/NPC generated configuration headers | Kconfig `.config` and component config targets |
| NEMU or Spike DiffTest reference libraries | producer Kconfig/build target, shared ABI header, adapter sources, and locked external revision/patch inputs |
| AM images, ELF files, archives, and linker maps | Program Makefile plus selected AM `ARCH` rules |
| Navy ramdisk image and generated file table | Navy build/install targets and `fsimg` contents |
| ysyxSoC generated Verilog | ysyxSoC generator source and its build flow |
| NVBoard pin binding | NXDC constraints and NVBoard generator script |
| RT-Thread selected source list | RT-Thread configuration and BSP discovery target |

Inspect generated output when debugging, but make durable changes at the
owning source unless the repository explicitly treats the generated file as a
checked-in handoff artifact.

## Validation Mapping

| Change owner | Narrow evidence | Integration evidence |
|---|---|---|
| Repository environment/build | Parse configuration, inspect command line, leaf dry run/build | representative component build in a direnv-equivalent shell |
| NEMU | focused image and monitor/trace evidence | intended AM workload or reference shared-library consumer |
| AM/klib | native or focused platform test | same image on the intended backend |
| nanos-lite/Navy | library/app build, regenerated image inspection | boot and exercise the affected user/kernel boundary |
| NPC RTL | lint or Icarus/targeted Verilator run | focused workload, then DiffTest if architecturally comparable |
| ysyxSoC | generation/interface check or focused peripheral simulation | full SoC harness only after the failure is localized |
| RT-Thread-AM | configuration/source-list check and BSP build | scripted shell/feature smoke on the intended backend |
| Test infrastructure | one known pass and one meaningful failure path | selected suite on each supported changed backend |

Do not use one fixed command ladder for every task. Confirm the active ISA,
platform, configuration, and backend first, then stop at the least expensive
stage that proves the requested behavior and its direct contracts.

## Routing Checklist

1. Reproduce or define the requested behavior.
2. Name the primary owner and source-of-truth files.
3. Separate consumers that need validation from owners that need edits.
4. Identify generated artifacts and configuration inputs.
5. Mark any coupled contract that requires serialized updates.
6. Choose narrow and integration validation before modifying code.
