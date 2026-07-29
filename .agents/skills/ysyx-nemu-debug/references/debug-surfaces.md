# NEMU Debug Surfaces

## Execution Layers

| Question | Inspect first |
|---|---|
| Monitor startup, image/ELF/argument handling | monitor initialization and command-line parsing |
| SDB command behavior | SDB command table and handlers |
| Expressions and watchpoints | expression tokenizer/parser and watchpoint pool/evaluation |
| Instruction semantics | selected RISC-V decode/execute implementation |
| PC/register sequencing | CPU execution loop and decode state |
| Exceptions, interrupts, CSRs | ISA trap/CSR helpers and interrupt query path |
| Sv32 translation/protection | ISA virtual-address translation and memory access path |
| RAM versus MMIO dispatch | physical memory and map/device layers |
| Timer, keyboard, VGA, audio, disk | owning device model and configured MMIO map |
| Reference shared library | DiffTest exports, reference configuration, and build target |

Always confirm the active Kconfig symbols before relying on a compiled surface.

## Evidence Selection

- **Instruction trace:** control flow, decode, operands, next PC.
- **Function trace:** call/return structure when ELF symbols match the image.
- **Memory trace:** physical/virtual access address, width, direction, data.
- **Device trace:** MMIO routing and side effects.
- **Exception trace:** trap cause, EPC, vector, status transition, return.
- **Watchpoint:** first change in an expression or architectural invariant.
- **SDB stepping/examination:** short deterministic windows.

Turn on only the evidence needed for the candidate layer. Long, unconditional
traces can perturb device timing and hide the first relevant transition.

## Architectural Transition Checklist

For the first bad instruction or event, record:

1. current PC and instruction bytes;
2. decoded operands and pre-state;
3. memory translation and physical access, if any;
4. destination register/CSR/memory effect;
5. exception or interrupt decision;
6. next PC and post-state;
7. device side effects that occur at the same boundary.

Check sign extension, truncation, alignment, privilege, and ordering explicitly.

## Reference-Mode Cautions

- A standalone executable and a DiffTest shared library may use different
  configurations and initialization paths.
- Match CPU-state layouts and platform address policy at the exported ABI.
- Do not add DUT-specific behavior to generic ISA semantics merely to silence a
  consumer mismatch.
- Rebuild the exact reference artifact used by the DUT after configuration or
  exported-state changes.
