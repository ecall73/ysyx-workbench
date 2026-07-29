# DiffTest Contract Checklist

## Build Identity

- Record DUT platform/configuration, ISA/register model, image type, reference
  implementation, shared-library path, and reference configuration.
- Confirm the loaded shared library was rebuilt from the source/configuration
  being inspected.
- Prove exported ABI compatibility with byte size and field-offset checks for
  every copied register/CSR field. Do not infer compatibility from similar C
  type names.
- Use a reference-sized context plus explicit DUT-to-reference and
  reference-to-DUT adapters when the reference exposes more registers, CSRs, or
  state than the DUT. Never let `regcpy` write a richer context into a compact
  DUT structure.
- Match base register model as well as XLEN and extensions; RV32E and RV32I do
  not expose the same GPR contract.

## Initialization

- Agree on reset PC and initial architectural register/CSR state.
- Copy the intended image or platform memory ranges in the correct direction.
- Handle standalone PMEM and full-SoC flash/SRAM/SDRAM policies explicitly.
- Initialize reference platform/address policy before the first comparison.
- Define initialization for reference-only architectural state and hidden
  platform/device state that is not carried by register copies.
- Confirm the first DUT event being compared is an architectural commit.

## Step Alignment

For each comparison:

1. identify DUT `pc`, committed instruction, and architectural `dnpc`;
2. advance the reference exactly once unless applying a documented rule;
3. copy reference state to a separate comparison buffer;
4. compare all contractually visible state, including PC and relevant CSRs;
5. report the first field and instruction that differ without overwriting DUT
   state prematurely.

Do not advance on fetch, issue, cache refill, stall, or speculative execution.

## Skip And Resynchronization

Use a skip only when an effect cannot be deterministically reproduced by the
reference under the chosen contract.

- Name the exact instruction or effect.
- State which side executes it and which state is copied afterward.
- Bound the rule to the minimum occurrence/window.
- Check that memory or device side effects do not leave hidden divergence.
- After copying DUT state to resynchronize, immediately copy the reference state
  back into a separate correctly sized buffer and compare the translated
  contract before returning. Do not defer the first proof until the next DUT
  commit.
- State whether skipped MMIO changes reference device/memory state. Synchronize
  that state explicitly or prove it cannot affect later architectural results.
- Never skip ordinary deterministic ISA, CSR, trap, or RAM behavior.

## First-Divergence Classification

| Symptom | Check first |
|---|---|
| Mismatch at first instruction | reset/image/state initialization and layout |
| PC differs, registers agree | branch/jump/trap next-PC or step alignment |
| One GPR differs | decode operands, ALU/load result, write enable/destination |
| CSR differs | trap entry/return, interrupt timing, CSR masks/side effects |
| Divergence after MMIO | device comparability and skip/resync policy |
| Divergence after many good steps | first hidden memory/state write before report |
| Reference API crash/assert | ABI, symbol, direction, address range, configuration |

After assigning ownership, switch to the NEMU or RTL debugging skill rather
than growing DiffTest-specific workarounds.
