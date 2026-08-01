---
name: ysyx-validation
description: Select and execute the smallest sufficient validation strategy for ysyx-workbench changes. Use when choosing among focused AM tests, am-apps tests, riscv-tests-am, riscv-arch-test-am, NEMU, NPC, ysyxSoC, RT-Thread-AM, native checks, or when defining regression depth and acceptance evidence from ISA/platform/backend/risk. Do not use as the primary debugging workflow when a concrete failing layer is already known.
---

# YSYX Validation Selection

Read [test selection](references/test-selection.md) before choosing a suite or
backend. Inspect current suite Makefiles and active configurations; never run
all discovered tests merely because they exist.

## Define The Validation Contract

1. Name the changed owner and observable behavior.
2. Record the active ISA, ABI, AM `ARCH`, platform, backend, and required
   devices or privilege features.
3. Identify direct consumers and shared contracts touched by the change.
4. Define pass/fail evidence before running tests.

## Select Evidence By Risk

- Start with syntax, configuration, generation, or a focused unit when it can
  disprove the most likely failure cheaply.
- Use a self-checking ISA test for instruction semantics.
- Use an AM/platform test for runtime, memory, or device contracts.
- Use a user/kernel integration test for loader, syscall, filesystem, ramdisk,
  or library behavior.
- Use a reference backend before RTL for software-heavy behavior when the
  reference implements the required contract.
- Use NPC for core/DUT integration and ysyxSoC only for full-SoC contracts.
- Use DiffTest when both sides have comparable deterministic architectural
  state.
- For a DiffTest ABI or profile change, run interface rejection probes and one
  focused `am-apps/diff` contract case before broad ISA or system suites.

## Control Scope

- Filter suites to implemented ISA extensions and the selected register model.
- Do not interpret unsupported extension failures as regressions.
- Add nearby and boundary cases after the focused reproducer passes.
- Broaden to full component regression only for shared or high-fanout changes.
- Revalidate every backend whose source or interface contract changed.

## Report Acceptance

Report commands, configuration, exact passed/failed counts, expected timeouts,
intentionally skipped tests, generated artifacts inspected, and residual risk.
Do not claim a backend or contract was validated from compilation alone unless
compilation is the complete requested behavior.
