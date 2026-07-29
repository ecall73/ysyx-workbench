---
name: ysyx-workstream-routing
description: Route broad, ambiguous, or cross-component engineering work in ysyx-workbench to one primary owner and a bounded validation path. Use for requests that ask where a change belongs, span multiple top-level components, alter a shared contract, or need safe parallel/serial decomposition. Do not use for a narrow task whose owning component is already explicit; invoke the matching specialist skill directly instead.
---

# YSYX Workstream Routing

Read [`docs/workstreams.md`](../../../docs/workstreams.md) before proposing
edits. Treat it as a routing map, then verify every selected path against the
current tree and configuration.

## Route The Request

1. Restate the observable behavior or requested contract change.
2. Select one primary workstream that owns the behavior.
3. Identify the source files or build inputs that define the behavior.
4. List downstream consumers separately; do not edit a consumer merely because
   it is where the failure appears.
5. Identify generated artifacts and the source that produces each one.
6. Mark shared contracts that require serialized changes.
7. Choose the smallest specialist skill and validation path that can complete
   the work.

## Apply Ownership Rules

- Route ISA and architectural state semantics to NEMU unless the evidence
  isolates a DUT implementation error.
- Route AM ABI and platform behavior to Abstract Machine before patching an AM
  consumer.
- Route user/kernel image and syscall integration to nanos-lite/Navy rather
  than to the execution backend.
- Route DUT logic and bus timing to NPC or ysyxSoC; route only architectural
  disagreement to DiffTest analysis.
- Route test-selection questions to `ysyx-validation`; tests do not become the
  source of truth for the behavior they check.
- Route repository state and gitlink changes to
  `ysyx-submodule-git-flow`.

## Bound The Work

- Keep one primary write scope per phase.
- Serialize changes to ISA, AM ABI, syscall ABI, address maps, RTL interfaces,
  DiffTest state, and generated-artifact contracts.
- Parallelize only disjoint leaf changes or read-only investigation with no
  shared contract.
- Stop routing into excluded components listed in the root `AGENTS.md`.

## Produce A Handoff

Before implementation, state:

- primary owner and likely write paths;
- consumers that require validation but not initial edits;
- configuration and generated artifacts that must be inspected;
- specialist skills to use;
- narrow and integration validation stages;
- unresolved ownership evidence, if any.

Do not turn the handoff into a repository inventory. Include only facts that
change the implementation decision.
