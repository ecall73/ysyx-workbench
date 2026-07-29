# Integration Contracts

## Ownership Boundaries

| Contract | Owner | Typical consumers |
|---|---|---|
| AM APIs and Context/Event semantics | `abstract-machine/` | programs, nanos-lite, RT-Thread-AM, backends |
| Platform startup, linker, trap entry | selected AM platform | all images for that `ARCH` |
| klib behavior | `abstract-machine/klib/` | bare-metal and kernel code |
| Syscall dispatch and process loading | `nanos-lite/` | Navy libos/libc and user binaries |
| File/device namespace | `nanos-lite/` plus generated Navy image inputs | userland libraries and programs |
| User ABI and runtime libraries | `navy-apps/` libraries/build rules | Navy binaries and nanos-lite boundary |
| Ramdisk contents and file table | Navy fsimg/ramdisk generation | nanos-lite image and loader |
| RT-Thread scheduler/IPC core | shared `rt-thread-am/` source | AM BSP |
| RT-Thread board/context/device bridge | `rt-thread-am/bsp/abstract-machine/` | RT-Thread core and AM platform |

## Bare-Metal Checklist

- Confirm selected `ARCH`, linker script, reset entry, stack/global-pointer
  initialization, data/BSS handling, and halt convention.
- Confirm the platform implements only the AM APIs the program requires.
- Keep platform assembly, linker placement, and C runtime assumptions aligned.
- Validate klib edge behavior separately from backend behavior when possible.

## User/Kernel Checklist

- Keep syscall numbers and argument/return conventions identical across libos
  and nanos-lite.
- Distinguish file-table compile-time entries from runtime file offsets and
  device callbacks.
- Check ELF class, machine, segments, permissions, virtual addresses, and entry
  before debugging a loader symptom.
- Regenerate the ramdisk and file header after changing installed user content.
- Follow event, timer, input, video, and audio data through every library and
  device boundary rather than patching the final caller.
- Verify VME mappings, address-space ownership, brk/heap policy, and context
  switch state together.

## RT-Thread-AM Checklist

- Treat `.config` and `rtconfig.h` as configuration inputs/outputs and
  `files.mk` as discovered build state.
- Keep AM Context lifetime and RT thread stack ownership explicit during
  switches.
- Preserve interrupt nesting, tick advancement, scheduler locking, and fresh
  thread bootstrap invariants.
- Separate AM-backed device behavior from metadata registered with RT-Thread
  device frameworks.
- Validate linker-retained init, shell, and test tables after section or linker
  changes.
- Recheck embedded workload data/BSS/heap reset when integration transforms or
  prefixes objects.

## Integration Evidence

Prefer boundary evidence: ELF/map inspection, generated image/header diff,
syscall trace, AM event trace, device trace, and controlled shell commands.
Escalate to backend waves only when software-side contracts are already
consistent.
