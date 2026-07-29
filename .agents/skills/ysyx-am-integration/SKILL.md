---
name: ysyx-am-integration
description: Implement and debug cross-layer software integration through Abstract Machine, klib, nanos-lite, Navy, and RT-Thread-AM. Use for AM IOE/CTE/VME/MPE and Context contracts, startup/linker issues, klib, loader/syscall/filesystem/device paths, ramdisk and generated file tables, Navy libraries/user ABI, native compatibility, RT-Thread AM BSP/context switching, or failures that cross these layers. Do not use for isolated NEMU ISA behavior, isolated RTL logic, or generic build-environment failures.
---

# YSYX AM System Integration

Read [integration contracts](references/integration-contracts.md) when a change
crosses an ABI, generated image, or RT-Thread boundary. Derive active support
from the selected AM `ARCH`, not from another platform's implementation.

## Classify The Path

Choose the smallest applicable chain:

- bare metal: program -> klib/AM -> platform -> backend;
- user/kernel: Navy app/library -> ramdisk -> nanos-lite -> AM -> backend;
- RTOS: RT-Thread configuration -> AM BSP -> AM image -> backend.

Name the owner of every boundary before editing.

## Trace The Contract

1. Start from the user-visible operation and follow data and control toward the
   backend.
2. Check ABI identifiers, structure layouts, register conventions, linker
   placement, and initialization order at each boundary.
3. Separate compile-time inclusion, image packaging, load-time behavior, and
   runtime dispatch.
4. Confirm generated headers/images correspond to the current producer input.
5. Compare native behavior only where the native shim promises equivalent
   semantics.

## Apply Durable Changes

- Modify AM contracts in Abstract Machine and update platform consumers.
- Modify syscall/file/loader ownership in nanos-lite and update Navy callers
  only when the ABI changes.
- Regenerate ramdisk images and file tables through Navy targets.
- Keep target runtime code independent of host-only conveniences.
- For RT-Thread-AM, distinguish SCons source discovery from the final AM build;
  change generated source lists only through configuration/discovery inputs.
- Preserve Context ownership and scheduler/interrupt invariants when changing
  RT-Thread switching or timer paths.

## Validate From Leaf To Boundary

Build the narrowest library or component, inspect the derived image or symbols,
run a focused operation, then boot or execute on the intended backend. Recheck
direct ABI consumers after shared changes. Use `ysyx-validation` for suite
selection and `ysyx-env-build` for environment-only failures.
