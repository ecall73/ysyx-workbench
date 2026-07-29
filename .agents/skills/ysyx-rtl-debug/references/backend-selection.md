# RTL Backend Selection

## Backend Matrix

| Path | Best for | Not sufficient for |
|---|---|---|
| Focused Icarus testbench | isolated RTL logic, quick clock/reset, simple netlist behavior | DPI-heavy host behavior or full SoC software |
| NPC standalone Verilator | core pipeline, commit, cache/local memory, host traces, focused workloads | SoC interconnect and external peripheral contracts |
| NPC ysyxSoC Verilator | generated SoC integration, AXI, boot media, peripherals, NVBoard | generator correctness without regeneration |
| ysyxSoC generation flow | Chisel/source interface and generated RTL changes | runtime correctness without a harness/workload |

Select the least expensive path that contains the failing interface.

## Source Provenance

- Inspect NPC Kconfig and file lists to learn which core, platform adapter, host
  sources, and trace options are compiled.
- Inspect ysyxSoC Makefiles/generator sources before modifying generated RTL.
- Treat the checked generated SoC Verilog as a runtime handoff when generator
  tools are unavailable, but do not claim generator-source validation.
- Derive NVBoard host sources and pin binding from its Makefile and NXDC input.
- Derive memory map and boot placement from active SoC/platform/linker sources.

## Failure Localization

1. Prove time advances and reset deasserts as intended.
2. Find the first expected request, commit, or external event that is absent or
   incorrect.
3. Check producer payload and valid, consumer ready, and response lifecycle.
4. For buses, inspect address, size, mask/strobe, burst length, ID, response,
   and outstanding-transaction ownership.
5. For caches, distinguish lookup/tag/data error, miss/refill protocol, and
   architectural commit effects.
6. For peripherals, separate RTL pins/registers from host DPI/NVBoard behavior.
7. Capture a narrow wave interval only after finding an approximate cycle or
   commit boundary.

## Evidence Boundaries

- Text traces are efficient for long-run localization.
- Waves prove signal-level protocol and temporal relationships.
- DiffTest proves deterministic architectural state, not bus timing.
- Host assertions prove harness contracts, not internal RTL correctness.
- A full-system boot proves integration but rarely identifies the owner alone.

After a fix, rerun the narrow backend and one direct integration consumer. Do
not default to full ysyxSoC simulation for a standalone core-only change.
