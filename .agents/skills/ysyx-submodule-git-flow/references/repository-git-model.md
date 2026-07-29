# Repository Git Model

## Repository Layers

- The root repository owns integration files and first-level gitlinks listed in
  `.gitmodules`.
- A submodule owns files below its path; a root diff records only its gitlink
  unless the path is not actually a submodule.
- ysyxSoC contains nested submodules. Update nested code and gitlinks from the
  deepest owner outward.
- `patch/` contains integration patches for selected external components.
  Inspect bootstrap/history before deciding whether the patch or live tree is
  authoritative for a requested change.
- Build outputs and generated files may appear as submodule dirtiness. Classify
  them before staging or cleaning.

The active workflow excludes `xv6-riscv` even though it remains configured as a
submodule.

## Read-Only State Checks

Use root and recursive views together:

```bash
git status --short --branch
git submodule status --recursive
git diff --submodule=log
git diff --cached --submodule=log
git -C <path> status --short --branch
```

Also inspect `.gitmodules`, remotes, branch/upstream, and the exact target SHA
before moving a gitlink.

## Inside-Out Change Order

1. Identify the deepest owning repository.
2. Start from the intended upstream revision/branch.
3. Implement and validate within that repository.
4. Commit and make the child commit fetchable.
5. Move the immediate parent gitlink and validate that integration.
6. Repeat until the root gitlink is updated.
7. Report every old/new SHA and its validation.

Never leave a parent pointing at a local-only child commit.

## Root Tracer Model

Subproject Makefiles can call the root `git_commit` macro. It temporarily moves
through `tracer-ysyx`, saves/restores an alternate index, stages broadly, and
creates an allow-empty telemetry commit.

- Override the macro with `git_commit=` for diagnostics and tests.
- Do not assume a build is Git-read-only without inspecting its Makefiles.
- If interrupted, inspect branch, index files, lock files, and worktree before
  attempting recovery.
- Obtain explicit authorization before deleting tracer state or rewriting
  branches/indexes.

## Patch And Gitlink Handoff

State whether the durable change is a root patch, a submodule commit, or both.
Keep patch regeneration mechanical and review the complete patch delta. Do not
mix unrelated submodule bumps, generated cleanup, or formatting into the same
handoff.
