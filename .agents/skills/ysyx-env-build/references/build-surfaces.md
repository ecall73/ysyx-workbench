# Build Surfaces

## Environment Ownership

| Variable | Expected owner |
|---|---|
| `NEMU_HOME` | `nemu/` |
| `AM_HOME` | `abstract-machine/` |
| `NPC_HOME` | `npc/` |
| `NVBOARD_HOME` | `nvboard/` |
| `NAVY_HOME` | `navy-apps/` |

Load these through direnv at the repository root when possible. Root `.envrc`
derives defaults from `$PWD`, so do not source it from another directory. An
inherited variable that points at a different checkout is more dangerous than
an unset variable.

## Build Identities

- AM `ARCH` combines an ISA and platform. Inspect the matching rule under
  `abstract-machine/scripts/` before choosing compiler flags or a runner.
- Navy `ISA` selects userland compilation independently from an AM platform.
- NEMU and NPC use Kconfig `.config` plus generated headers. Inspect both the
  checked configuration and effective compiler command.
- NPC selects standalone versus ysyxSoC host/RTL sources through configuration
  and file lists.
- RT-Thread-AM uses SCons for source/include discovery and the AM Makefile for
  target compilation and linkage.
- ysyxSoC simulation can consume checked-in generated Verilog even when the
  Java/mill generator toolchain is unavailable. Require generator tools only
  for source regeneration.

## Generated State

| Derived state | Owning input/target |
|---|---|
| NEMU/NPC `include/generated` and `include/config` | component `.config` and config targets |
| AM archives, ELF/image, map, disassembly | program Makefile and AM platform rules |
| Navy ramdisk and file header | Navy install/fsimg/ramdisk targets |
| nanos-lite ramdisk/header links | nanos-lite image dependency wiring |
| NPC NVBoard binding | NXDC file and NVBoard binding generator |
| ysyxSoC generated RTL | ysyxSoC generator source/build |
| RT-Thread `files.mk` and `rtconfig.h` | BSP configuration and discovery targets |

## DiffTest Reference Artifacts

- Select NEMU native execution with DiffTest and NEMU shared-object output
  through Kconfig/menuconfig plus the owning sync/build targets. Do not invent
  Make command-line switches for mutually exclusive Kconfig target modes.
- Build a NEMU REF shared library while the shared target is selected. The
  resulting `.so` remains a valid artifact after NEMU is switched back to a
  native configuration; its exported ABI/profile/capabilities and file
  provenance define its identity, not the producer tree's current `.config` or
  `auto.conf`.
- Let a consumer build the NEMU REF only when the expected artifact is absent.
  Do not add a runtime guard that rejects an existing `.so` because the current
  NEMU configuration is no longer `TARGET_SHARE`.
- Keep the REF implementation richer than a DUT when the negotiated adapter
  permits it. An RV32E AM image or DUT profile does not imply that NEMU REF must
  be built with `CONFIG_RVE`; inspect the requested profile and projection.
- Treat the Spike REF as derived from the locked upstream revision, ordered
  patch bundle, shared ABI header, adapter source, and build rules. Rebuild when
  any identity input changes and record the exported implementation ID.
- Distinguish generation from consumption: NEMU native may build/use Spike REF,
  while NPC/ysyxSoC load a previously generated NEMU REF. Verify the actual
  shared-library path before diagnosing capability failures.

## Failure Classification

1. **Entry-point failure:** wrong working directory or Makefile.
2. **Environment failure:** unset, stale, or foreign checkout variables.
3. **Host-tool failure:** compiler, Verilator, Icarus, SCons, Java/mill, SDL.
4. **Target-toolchain failure:** cross compiler, ISA/ABI, linker, runtime helper.
5. **Configuration failure:** stale/mismatched `.config` or generated header.
6. **Dependency failure:** missing archive, generated image, submodule, or host
   library.
7. **Source failure:** compile, link, or runtime code after inputs are correct.

Preserve the first error in the earliest failing class. Later errors are often
secondary.

## Safe Command Shape

Use a direnv-equivalent shell and suppress tracer commits during diagnostics:

```bash
direnv exec <repo-root> make -C <owner> <target> git_commit=
```

If direnv cannot be used, export the five absolute paths from `.envrc` and run
the same owning target. Inspect before using clean targets; many components
share generated inputs or submodule state.
