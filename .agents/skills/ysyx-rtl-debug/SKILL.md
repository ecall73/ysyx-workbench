---
name: ysyx-rtl-debug
description: Build, inspect, implement, and debug NPC or ysyxSoC RTL in ysyx-workbench, including Verilog/Chisel ownership, generated RTL, Verilator and Icarus harnesses, waves, commit observation, caches, buses, AXI, memories, peripherals, reset/boot behavior, and NVBoard integration. Use for HDL/source compile errors, RTL simulation failures, wrong signals or transactions, hangs, and cycle-level hardware behavior. Use ysyx-env-build when tools, configuration, or orchestration fail before the RTL source is reached, and ysyx-difftest-debug when architectural DUT/reference divergence is primary.
---

# YSYX RTL Debugging

Read [RTL backend selection](references/backend-selection.md) before choosing a
harness, source layer, or trace. Inspect NPC `.config` and the selected platform
before assuming which RTL or host code is active.

## Select The Faithful Backend

1. Use a focused Icarus or module-level path for isolated combinational,
   sequential, or netlist behavior when supported.
2. Use standalone NPC for core, cache, local memory, and commit behavior that
   does not require the full SoC.
3. Use the ysyxSoC platform only for SoC address routing, AXI, boot media,
   external peripherals, or NVBoard behavior.
4. Distinguish Chisel/generator source changes from checked-in generated RTL
   inspection and runtime simulation.

## Narrow The Failure

- Capture image, ELF, configuration, simulator, reset sequence, and expected
  architectural event.
- Find the last correct committed instruction or externally visible bus event.
- Use textual traces for broad localization, then collect a narrow waveform
  around the candidate interval.
- Follow valid/ready, request/response, IDs, masks, sizes, bursts, and reset
  state across one interface at a time.
- Check host DPI and platform adapters when RTL signals are correct but observed
  memory, device, or commit state is wrong.
- Prove clock/reset progress before debugging a simulation that appears blank
  or hung.

## Respect Source Ownership

- Change generator source when it owns generated logic; regenerate through the
  documented flow and inspect the generated delta.
- Change standalone core RTL in NPC when the same core behavior is independent
  of the SoC wrapper.
- Change ysyxSoC interconnect/peripheral ownership in ysyxSoC, not in a host
  workaround.
- Change NVBoard bindings from their NXDC/source inputs rather than generated
  binding output.
- Derive address maps and boot placement from current linker, platform, and SoC
  sources instead of embedding remembered constants.

## Validate

Run the narrow reproducer, then the nearest interface-level test. Add DiffTest
only when the workload and reference model share an architectural contract.
Escalate to full ysyxSoC/NVBoard execution only when the changed behavior needs
it. Use `ysyx-validation` to choose broader regressions.
