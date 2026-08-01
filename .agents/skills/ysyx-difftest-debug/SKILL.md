---
name: ysyx-difftest-debug
description: Diagnose and evolve versioned RISC-V differential testing across NEMU DUT to Spike REF and NPC or ysyxSoC DUT to NEMU REF. Use for architectural observation mismatches, ABI/profile/capability failures, reference shared-library identity, initialization and memory transport, ARCH_STEP or ASYNC_INTR ordering, pure state projection, typed skip and sparse resynchronization, CSR/trap divergence, or uncertainty about which side first became wrong. Do not use for a failure that reproduces in one model without a DUT/REF comparison, or for cycle-level RTL timing after architectural observations agree.
---

# YSYX Differential Testing Debugging

Read [the DiffTest contract checklist](references/contract-checklist.md) before
changing the ABI, profile, event flow, state projection, memory transport, or
skip behavior. Treat the shared header and the loaded REF artifact as the
contract sources of truth; do not infer them from an AM `ARCH` name.

## Identify The Active Contract

1. Record the DUT, REF, platform, image, reset policy, memory-map profile, and
   exact shared-library path.
2. Inspect the versioned ABI header, both profile adapters, and the event call
   sites that are actually compiled.
3. Query the loaded REF for its ABI version, payload sizes, implementation ID,
   ISA features, and capabilities before interpreting an execution failure.
4. Verify profile initialization, physical image transport, full initial
   synchronization, and initial observation in that order.
5. Treat the REF's exported identity as artifact evidence. The producer's
   current `.config` may have changed since that shared library was built.

## Follow The Architectural Event Stream

- Reconstruct the single monotonically ordered stream of `ARCH_STEP` and
  `ASYNC_INTR` events. Diagnose a missing, duplicated, or reordered event before
  comparing instruction semantics.
- Treat `ARCH_STEP` as one instruction-associated architectural transition,
  not necessarily a retired instruction. A precise synchronous exception is
  an `ARCH_STEP` even though the faulting instruction does not retire.
- Require ordinary and faulting instructions to be executed independently by
  the REF. For an instruction-fetch fault, accept an invalid instruction
  description only when the profile permits it.
- Treat `ASYNC_INTR` as an independent zero-instruction transition. Use
  `pretrap_pc` only to prove the REF is at the same boundary; never inject DUT
  EPC, delegation, target privilege, or trap post-state into the REF.
- After every event, compare the REF observation returned by the API with a
  separately built, pure DUT observation. Do not use an observation as a
  synchronization payload.

## Preserve State Ownership

- Compare profile-defined architectural fields and masks, never raw
  `CPU_state` layouts. Use adapters when a richer REF serves a smaller DUT
  profile.
- Build observations directly from fundamental model state and pure
  projections. Do not call architectural CSR read/write paths; they may check
  privilege, mark a skip, advance state, or touch a device.
- Keep derived aliases, profile-owned identifiers, pending views, timer state,
  and static transport slots out of periodic comparison when the profile says
  so. Keep deterministic interrupt controls and trap CSRs comparable.
- Represent unsupported static state with profile-defined constants only.
  Reject a profile when dynamic state has no committed or visible DUT source;
  do not hide it behind constants.
- Leave reservation, TLB/cache derivations, and device internals outside the
  generic ABI. Diagnose them at the first later architectural observation they
  affect.

## Apply Typed Skip Narrowly

- Use a named skip reason only for a successful instruction whose effect is
  explicitly owned by the DUT or differs by profile. Never skip its privilege,
  address, alignment, or other precise exception path.
- Validate that the exact instruction form is supported by the reason. Derive
  the destination GPR mask and sync fields through the shared protocol helpers.
- Send only the sparse post-state authorized by that reason. Require the REF to
  apply it without executing the instruction, then return a full observation
  for immediate comparison of every unsynchronized field.
- Prove that hidden RAM, device, timer, or reservation effects remain valid for
  later execution. A register repair cannot synchronize unmodeled state.
- Never turn deterministic RAM, ISA, CSR, trap, or counter behavior into a skip
  merely to pass a mismatch.

## Classify The First Failure

- Missing symbols or payload-size errors: inspect stale headers, wrong REF
  artifacts, and rebuild provenance.
- Missing capability or unsupported profile: compare the requested profile
  with the loaded implementation; do not assume the DUT and REF need identical
  internal register models.
- Bad sequence: inspect event emission order and reset/attach state.
- Bad event: inspect PC, instruction description, reserved fields, disposition,
  skip reason, and interrupt metadata.
- Bad state: inspect valid-field/GPR masks, virtual constants, and sparse sync
  construction.
- Observation mismatch: locate the first wrong post-transition field, then
  assign it to DUT execution, REF semantics, adapter projection, or hidden
  state before changing code.

## Fix And Validate

Change the owning layer first, preserve ABI compatibility deliberately, and add
a focused regression that fails without the fix. Exercise protocol rejection
paths for ABI/profile changes, then rerun the affected `am-apps/diff` case and
every direct DUT/REF consumer. Hand an assigned model bug to `ysyx-nemu-debug`
or `ysyx-rtl-debug`; use `ysyx-validation` to select broader regressions.
