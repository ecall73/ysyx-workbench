---
name: ysyx-difftest-debug
description: Diagnose and change differential-testing behavior between an NPC or ysyxSoC DUT and its NEMU/selected architectural reference. Use for register or PC mismatches, reference shared-library/API failures, incorrect initial synchronization, commit-step alignment, device or nondeterministic instruction skipping, CSR/exception divergence, or uncertainty about which side first became wrong. Do not use for a failure that reproduces in only NEMU without a DUT comparison, or for cycle-level RTL timing after architectural states agree.
---

# YSYX Differential Testing Debugging

Read [the DiffTest contract checklist](references/contract-checklist.md) before
changing synchronization or skip behavior. Verify the active DUT platform,
reference build, ISA, CPU-state layout, and image-loading policy from source.

## Establish Comparable State

1. Capture the DUT image, reference shared library, active configurations, and
   exact mismatch report.
2. Confirm both sides start from the same architectural reset state and memory
   contents expected by the selected platform.
3. Prove register/state ABI byte size, field offsets, width, and copy direction
   at the API boundary. Use an explicit adapter when DUT and reference structs
   differ; never pass a compact DUT struct to a richer reference ABI.
4. Identify the DUT event that represents one committed architectural
   instruction.
5. Confirm the reference advances exactly once for that event unless an
   explicit synchronization rule applies.

## Find The First Divergence

- Reproduce with the smallest deterministic workload.
- Compare PC and architectural state immediately before and after the first
  failing commit.
- Decode the committed instruction and inspect its operands, memory effects,
  CSR/trap effects, and next PC.
- Determine whether the first wrong value originates in DUT execution,
  reference semantics, initialization, stale copied state, or step alignment.
- Treat later mismatches as consequences until the first divergence is
  explained.

## Handle Non-Comparable Effects Deliberately

- Skip or resynchronize only effects that the reference cannot model under the
  same contract, such as selected MMIO or nondeterministic inputs.
- Scope each rule to the exact instruction/effect and document the state copied
  after it.
- Immediately read state back through the reference ABI after resynchronizing
  and prove the round trip before advancing another instruction.
- Define how reference-only architectural or device state is initialized and
  advanced; a register copy cannot synchronize hidden device state.
- Never use broad skipping to hide a deterministic ISA, CSR, trap, or memory
  bug.
- Keep cycle timing, cache state, and bus microarchitecture outside the
  architectural comparison.

## Fix And Validate

Change the owning side, then rerun through the first former mismatch and beyond
it. Add a focused regression that fails without the fix. Rebuild and validate
the reference library separately when its configuration or ABI changes, then
test every direct DUT consumer. Use `ysyx-nemu-debug` or `ysyx-rtl-debug` after
the first divergence has been assigned to one side.
