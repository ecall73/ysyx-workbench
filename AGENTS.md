# YSYX Workbench Agent Guide

Treat this repository as an engineering reference implementation. Implement
authorized work directly and validate it in proportion to risk; do not impose
tutorial or exercise-solving restrictions.

## Start Here

- Read `docs/workstreams.md` before broad changes or whenever ownership is
  unclear.
- Choose one primary workstream and one primary write scope before editing.
- Change the owner of a contract before its consumers. List consumers that need
  validation separately from files that need modification.
- Inspect the selected Makefile, configuration, linker script, and generated
  artifact provenance. Do not infer the active ISA, platform, address map, or
  toolchain from directory names alone.

## Active Scope

- Exclude `am-apps/contracts` and `am-apps/ioe`; they were removed.
- Exclude `xv6-riscv` from current engineering workflows and validation.
- Do not restore, route work into, or derive reusable rules from excluded
  components unless the user explicitly changes the scope.

## Environment And Builds

- The root `.envrc` defines `NEMU_HOME`, `AM_HOME`, `NPC_HOME`,
  `NVBOARD_HOME`, and `NAVY_HOME`.
- Prefer `direnv exec <repo-root> <command>` for non-interactive commands. Use
  `direnv exec .` only while the current directory is the repository root. If
  direnv is unavailable or not allowed, export the equivalent absolute paths
  explicitly. Do not source `.envrc` from an arbitrary directory because its
  defaults are derived from `$PWD`.
- Run builds through the owning component's Makefile, usually with
  `make -C <component> ...`.
- The root `Makefile` is a course tracer, not a build orchestrator. Subproject
  builds may call its `git_commit` macro. Pass `git_commit=` during diagnostic
  or validation builds unless tracer commits are explicitly desired.
- Do not run `init.sh` for diagnosis. It clones repositories, edits shell
  configuration, and commits state.
- Treat `.config`, generated headers, generated Verilog, ramdisk images and
  headers, and copied RT-Thread source lists as derived state. Find and edit
  their owner instead of patching outputs blindly.

## Validation

- Start with the smallest test that faithfully exercises the changed owner.
- Escalate from static/configuration checks to a leaf build, a fast reference
  backend, a DUT backend, and full-system simulation only as evidence requires.
- Use architectural state and committed instructions for correctness. Use RTL
  waves and cycle-level evidence only after narrowing the failing interval.
- Revalidate every direct consumer of a changed shared contract.
- Report the exact commands, configuration, observations, skipped stages, and
  remaining risk.

## Git And Submodules

- Preserve user changes and inspect root plus recursive submodule status before
  modifying shared or vendored paths.
- Commit code in the owning submodule first; update the parent gitlink only to a
  fetchable commit. Process nested submodules from the inside out.
- Avoid broad remote submodule updates. Use explicit paths and revisions.
- Never clean, reset, or rewrite unrelated generated or submodule state.

## Skill Routing

- Use `ysyx-workstream-routing` for broad, ambiguous, or cross-component work.
- Use `ysyx-env-build` for setup, direnv, toolchain, configuration, generation,
  and build failures.
- Use `ysyx-nemu-debug` for NEMU execution, monitor, trace, device, trap, or MMU
  behavior.
- Use `ysyx-am-integration` for AM/klib, nanos-lite, Navy, ramdisk, syscall,
  loader, VME, device, or RT-Thread-AM integration.
- Use `ysyx-rtl-debug` for NPC or ysyxSoC RTL, Verilator/Icarus, waveforms,
  buses, peripherals, NVBoard, or RTL generation.
- Use `ysyx-difftest-debug` for DUT/reference divergence and synchronization.
- Use `ysyx-validation` to select tests or define regression depth.
- Use `ysyx-submodule-git-flow` for submodule, gitlink, patch, tracer, or dirty
  repository state.

Use multiple skills only when the request genuinely crosses their boundaries.
The routing skill chooses ownership; specialist skills perform the work.
