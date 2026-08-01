# DiffTest Contract Checklist

## Contents

- Sources of truth and active profiles
- Interface handshake and artifact identity
- Architectural event semantics
- Observation, synchronization, and hidden state
- Typed skip ownership
- Interrupt and counter boundaries
- Status and first-divergence classification

## Sources Of Truth

| Contract | Inspect |
|---|---|
| Version, payload layouts, profiles, fields, capabilities, skip reasons | `nemu/include/riscv-difftest.h` |
| NEMU DUT event client and comparison | `nemu/src/cpu/difftest/`, `nemu/src/isa/riscv32/difftest/` |
| Spike REF adapter and reproducible identity | `nemu/tools/spike-diff/` |
| NEMU REF profile and state adapter | `nemu/src/isa/riscv32/difftest/ref.c`, `state.c` |
| NPC DUT client and profile projection | `npc/csrc/cpu/difftest/`, `npc/csrc/isa/riscv32/difftest/` |
| Platform reset, comparable memory, image transport | selected NEMU/NPC platform and memory owners |

Verify these paths against the current file lists and configurations. The
shared header is owned by NEMU and consumed by both NEMU and NPC builds.

## Select The Pair And Profile

| Pair | Expected shape |
|---|---|
| NEMU DUT -> Spike REF | Full RV32GC profile; ordered instruction/exception and local-interrupt events; active integer, floating-point, privilege, trap, counter, and selected CSR observations |
| NPC or ysyxSoC DUT -> NEMU REF | Restricted RV32E smoke profile; M-only dynamic state from committed DUT signals, profile-defined constant transport slots, no asynchronous-interrupt capability |

Derive the exact feature, field, capability, reset, and memory-map values from
the current profile macros and adapters. Do not copy snapshot addresses or
flags into a diagnosis.

The DUT image's AM `ARCH`, the DUT profile, and the REF implementation are
different identities. In particular, a richer RV32GC NEMU REF can implement an
RV32E profile through an explicit x0-x15 projection. Do not require a separate
RVE NEMU build merely because the DUT program is RV32E.

## Verify The Interface Handshake

Before executing an event:

1. Load the exact REF shared library and resolve every required versioned
   symbol. Do not silently fall back to legacy `regcpy/exec` for RISC-V.
2. Call `query_interface` with initialized version and structure-size fields.
3. Check returned version, all payload sizes, maximum GPR capacity,
   capabilities, ISA features, reserved data, and implementation ID.
4. Construct one exact profile and reject unknown fields, unsupported memory
   maps, missing capabilities, or feature mismatches by named status.
5. Initialize the profile before copying memory. Let profile initialization
   select the REF memory backend and reset policy.
6. Copy only declared physical memory ranges with explicit direction and
   bounds. Do not route initialization through the hart's active virtual MMU.
7. Apply a full profile-shaped initial sync, read back a full observation, and
   compare it before event sequence zero.

An existing shared library is identified by what it exports, not by the
producer tree's current `.config` or generated `auto.conf`. Rebuild only when
the requested artifact is absent or its exported contract/provenance is stale.

## Verify Event Semantics

| Event | Preconditions | REF action | Comparison boundary |
|---|---|---|---|
| `ARCH_STEP/EXECUTE` | sequence and current PC match; instruction metadata is profile-valid; no sync payload | independently fetch/execute one instruction-associated transition | immediate full post-transition observation |
| `ARCH_STEP/SKIP_REF` | named reason, supported instruction form, exact sparse sync masks | do not execute; apply only authorized post-state | immediate full observation, including all unsynchronized fields |
| `ASYNC_INTR` | next sequence; `pretrap_pc` equals current REF PC; DUT has already established interrupt legality | take only the supplied cause as a zero-instruction trap | immediate trap post-state observation |

Use one sequence counter across both event types. Do not associate an interrupt
with a previous commit through an extra identifier; ordering already expresses
the boundary.

For precise synchronous exceptions, keep the faulting transition in
`ARCH_STEP/EXECUTE`. Let both models independently derive cause, EPC, trap
value, delegation, privilege stack, and target PC. Mark instruction metadata
invalid only for a fetch failure that has no available instruction bits.

Repository `ebreak` and `c.ebreak` are simulation `NEMUTRAP` termination, not a
breakpoint exception or a DiffTest event. Do not wait for a REF observation
after that terminal action.

## Separate The State Planes

| Plane | Purpose | Rule |
|---|---|---|
| Observation | Compare post-event architecture | Pure, full profile field mask; never mutates either model |
| Sync state | Initialize or repair REF-owned architectural state | Explicit valid-field and GPR masks; may be sparse; never interpreted as an observation |
| Event | Order and describe an architectural transition | Contains only metadata needed for REF independent execution or validation |
| Hidden state | Reservation, TLB/cache derivations, device internals | Never copied through the generic ABI; validate later architectural consequences or model-specific tests |

Check canonical FP representation and no-F constants at the adapter boundary.
Do not dynamically disable FPR comparison because `mstatus.FS` is Off. For a
restricted profile, require every unimplemented GPR/FPR/CSR transport slot to
match its negotiated constant and reject nonzero or dynamic substitutes.

Construct CSR observations from fundamental fields and pure masks/projections.
Do not use normal CSR access functions. Exclude aliases that are fully derived
from compared owners, static profile identifiers, and DUT-owned pending/timer
views as specified by the profile. Continue comparing deterministic controls
such as interrupt enables/delegation, trap CSRs, privilege, and deterministic
counters when they are selected fields.

## Audit Typed Skip

For every skip site, prove all of the following:

1. The architectural access succeeded; any exception path remains independent.
2. The named reason describes the actual owner (`MMIO_DUT_OWNED`, pending,
   timer, `misa`, or other negotiated static state).
3. The shared instruction classifier accepts the exact encoding and derives
   only the actual destination GPR, if any.
4. The sync field mask equals the helper-defined minimum for the active
   profile; a store or `rd=x0` does not claim a GPR update.
5. The REF skips exactly that instruction, applies the sparse state, and
   returns a full observation before the next event.
6. The skipped effect does not require copying hidden RAM/device/reservation
   state. If it does, the profile is incomplete rather than broadly skippable.

Classify MMIO from the event's pre-state and the selected platform's comparable
memory owner. Reject unsupported FP/AMO/device-fetch forms instead of guessing
their effects. Never skip ordinary RAM, precise exceptions, deterministic CSR
controls, counter semantics, or A-extension RAM operations.

## Audit Interrupt And Counter Boundaries

- Keep profile-owned pending sources out of periodic observation. Keep `mie`,
  delegation, global-enable fields, vectors, and trap CSRs in normal comparison
  when the profile selects them.
- Require the DUT to validate pending, enable, delegation, privilege, and
  priority before emitting cause-only `ASYNC_INTR`. The current REF validates
  event shape and trap semantics; it does not independently arbitrate the
  pending interrupt.
- Keep REF local pending passive during ordinary steps so it cannot raise an
  event before the DUT.
- Advance retirement-controlled state only for successfully retired
  `ARCH_STEP` transitions. Precise exceptions, asynchronous interrupts, and
  terminal `NEMUTRAP` do not retire.
- Keep timer/pending behavior and hidden-state correctness covered by focused
  model tests when the profile deliberately excludes them from comparison.

## Classify Status Before Mismatch

| Result | Inspect first |
|---|---|
| Missing versioned symbol | wrong or stale REF binary; legacy artifact |
| Bad ABI version/structure size | header/artifact drift or wrong library |
| Unsupported capability/profile | requested pair/profile versus loaded artifact, not directory-name similarity |
| Bad sequence | lost, duplicated, reordered event or attach/reset bookkeeping |
| Bad event | PC/instruction/pretrap metadata, reserved data, disposition, reason |
| Bad state | field masks, GPR masks, sparse sync, profile constants |
| Bad memory | memory-map selection, physical range, copy direction and bounds |
| Observation mismatch | first incorrect independent transition or adapter projection |

After assigning the first divergence to NEMU semantics or RTL behavior, switch
to the matching specialist skill instead of adding DiffTest workarounds.
