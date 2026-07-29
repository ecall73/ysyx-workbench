---
name: ysyx-nemu-debug
description: Debug NEMU execution and reference-model behavior in ysyx-workbench, including instruction decode/execute, CPU state, SDB commands, expressions, watchpoints, instruction/function/memory/device/exception traces, devices, interrupts, exceptions, CSRs, Sv32 virtual memory, monitor startup, and DiffTest reference builds. Use when NEMU itself fails, hangs, reports wrong architectural behavior, or needs instrumentation. Use ysyx-difftest-debug instead when the primary symptom is a DUT/reference mismatch.
---

# YSYX NEMU Debugging

Read [NEMU debug surfaces](references/debug-surfaces.md) when choosing a trace,
monitor path, or architectural subsystem. Verify feature names against the
active NEMU configuration.

## Establish The Case

1. Capture the exact image, ELF symbols, arguments, NEMU configuration, and
   expected halt or observable result.
2. Reproduce with the smallest image that preserves the failure.
3. Determine the last correct architectural state and first incorrect state
   transition.
4. Classify the transition as instruction semantics, trap/CSR state, address
   translation, memory/MMIO, monitor control, or host integration.

## Use The Narrowest Evidence

- Use SDB stepping and register/memory examination for a short failing window.
- Use expressions and watchpoints for state-dependent failures.
- Use instruction or function trace for control-flow divergence.
- Use memory or device trace for address-routing and side-effect failures.
- Use exception trace and CSR inspection for trap-entry/return problems.
- Add assertions around invariants before adding broad logging.

Correlate every trace line to one architectural transition. Avoid reasoning
from a long log without first identifying a candidate boundary.

## Fix At The Owner

- Keep ISA semantics in the selected ISA implementation.
- Keep virtual-to-physical translation and protection in the memory subsystem.
- Keep device side effects in device/MMIO ownership paths.
- Keep monitor parsing and debugger behavior outside the execution engine.
- Preserve the exported DiffTest ABI when changing internal CPU state; if that
  ABI must change, use `ysyx-difftest-debug` and update consumers serially.

## Validate

Run a focused reproducer first, then a nearby architectural regression and the
direct reference-model consumer if applicable. Confirm both success behavior
and the failure/reporting path. Use `ysyx-validation` when the affected ISA or
platform surface requires a wider suite.
