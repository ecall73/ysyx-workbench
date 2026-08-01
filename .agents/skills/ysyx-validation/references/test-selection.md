# Test Selection

## Test Families

| Family | Select it for | Selection constraint |
|---|---|---|
| Native/unit checks | pure library logic, parsers, host scripts, generated metadata | native semantics must match the target contract being claimed |
| `am-apps/tests/` | focused klib, memory, device, cache, counter, and platform behavior | choose only tests supported by the selected AM platform |
| `am-apps/diff/` | self-checking DiffTest protocol, ownership, trap-boundary, and synchronization behavior | use only with a DUT/reference pair that implements the required profile |
| `riscv-tests-am/` | compact legacy ISA instruction regressions | match XLEN, implemented extensions, and wrapper exclusions |
| `riscv-arch-test-am/` | official architecture-test coverage | select the exact ISA/profile subset; the tree contains unsupported extensions |
| NEMU workloads | software/runtime/reference execution | use the intended NEMU config and reference requirements |
| NPC workloads | core/DUT and standalone platform integration | match RV32 register model and NPC configuration |
| ysyxSoC workloads | full SoC boot, address map, AXI, peripherals, NVBoard | use only when the contract requires full-system behavior |
| RT-Thread-AM smoke | BSP, scheduler, IPC, filesystem, device and shell integration | use deterministic commands/features tied to the change |

Do not derive a universal `all` target from this table. Inspect each current
Makefile and configuration.

## Selection Inputs

Record before running tests:

- changed owner and contract;
- XLEN, base register model, extensions, privilege and virtual-memory needs;
- AM `ARCH` and platform;
- memory/device requirements;
- reference/DUT backend availability;
- expected runtime and stop condition;
- whether generated artifacts are current.

## Escalation Patterns

### ISA or CSR semantics

Run one focused self-checking case, nearby boundary cases, the matching ISA
suite subset, then a direct DUT/reference consumer if the contract changed.

### AM, klib, or platform

Run a native/focused test where meaningful, build the selected AM image, run it
on the fastest faithful backend, then the changed target backend.

### User/kernel integration

Build the leaf library/program, regenerate and inspect the image, exercise the
boundary on NEMU, then use DUT/full SoC only if their contract changed.

### RTL

Run lint/focused simulation, a minimal workload, interface-level evidence,
DiffTest when comparable, then full-system execution only if required.

### Shared build or generated contract

Check generation/configuration, rebuild one producer and consumer from cleanly
understood state, then sample every affected backend.

## Acceptance Record

For every stage, retain command, active configuration, artifact identity,
pass/fail count or observable result, timeout meaning, and skipped scope. A
timeout is acceptable only when the intended evidence occurred before it and
the reason for stopping is explicit.
