---
name: ysyx-env-build
description: Diagnose and change ysyx-workbench environment, direnv, toolchain, Makefile, Kconfig, architecture selection, code-generation, and build flows. Use for missing variables or tools, wrong compiler/ISA flags, stale configuration or generated files, orchestration/dependency failures, and uncertainty about the correct build entrypoint. Do not use for HDL/source logic errors after the correct command begins compiling, runtime architectural bugs after a correct image builds, or Git/submodule state except where it explains a build input.
---

# YSYX Environment And Build

Establish the exact shell, configuration, and owning Makefile before changing
source. Read [build surfaces](references/build-surfaces.md) when selecting a
backend, regenerating artifacts, or diagnosing cross-component flags.

## Inspect First

Run the read-only diagnostic helper from any directory:

```bash
.agents/skills/ysyx-env-build/scripts/doctor.sh --scope <scope>
```

Use `--strict` only when missing required dependencies should fail the check.
Do not treat optional generator tools as runtime requirements.

Then:

1. Resolve the repository root and inspect `.envrc`.
2. Prefer `direnv exec <repo-root> <command>` when direnv is installed and
   allowed. Use `direnv exec .` only from the repository root; do not source
   this repository's `$PWD`-based `.envrc` from another directory.
3. Otherwise export absolute `NEMU_HOME`, `AM_HOME`, `NPC_HOME`,
   `NVBOARD_HOME`, and `NAVY_HOME` values equivalent to `.envrc`.
4. Identify the owning Makefile and run from its expected directory.
5. Inspect active `.config`, generated configuration headers, `ARCH`/`ISA`, and
   the effective compiler command before diagnosing source.

## Diagnose The Build

- Reproduce with the narrowest target and preserve the first meaningful error.
- Separate host-tool failures, target-toolchain failures, configuration
  failures, dependency failures, and source compile/link failures.
- Use Makefile inspection or a non-mutating dry run to find the command owner;
  do not replace repository build logic with an ad hoc command as a first fix.
- Compare compile and link ISA/ABI flags when objects are incompatible.
- Confirm the selected platform supports the requested feature before adding a
  workaround.
- Regenerate an artifact only through its owning target, then inspect the diff.
- Treat a DiffTest REF shared library as an independently versioned build
  artifact. Query the loaded artifact instead of using the producer's current
  `.config` as proof of its target, ISA profile, or capabilities.
- Keep the AM `ARCH`, DUT profile, REF implementation configuration, and host
  build target separate. Similar names do not require identical register or
  extension models when an explicit profile adapter exists.

## Avoid Build Side Effects

- Pass `git_commit=` to diagnostic subproject builds unless tracer commits are
  explicitly wanted.
- Do not run root `init.sh` for diagnosis.
- Do not use broad clean or distclean targets until stale output is proven and
  the affected paths are understood.
- Preserve user configuration and unrelated build artifacts.

## Finish With Evidence

Record the resolved environment, selected architecture/platform, owning target,
effective toolchain, first failure, fix, and validation command. Hand runtime
execution failures to `ysyx-nemu-debug`, `ysyx-rtl-debug`, or
`ysyx-am-integration`; hand repository-state failures to
`ysyx-submodule-git-flow`.
