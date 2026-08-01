---
name: ysyx-submodule-git-flow
description: Manage Git and submodule work in ysyx-workbench, including dirty nested repositories, ownership of vendored changes, gitlink updates, patch provenance, detached HEADs, fetchable commits, root tracer behavior, and safe status/diff/commit preparation. Use whenever work modifies a configured submodule or its pointer, applies repository patches, encounters tracer commits/index state, or needs inside-out contribution ordering. Do not use for ordinary source edits wholly owned by the root repository.
---

# YSYX Submodule Git Flow

Read [the repository Git model](references/repository-git-model.md) before
changing a submodule, nested gitlink, or patch. Preserve all pre-existing user
state.

## Inspect Before Editing

1. Read `.gitmodules` for the exact path, remote, and configured branch.
2. Inspect root status, recursive submodule status, and submodule-aware diffs.
3. Inspect status and branch/HEAD inside the owning submodule.
4. Distinguish modified content, untracked build output, a moved gitlink, and a
   nested-submodule change.
5. Determine whether `patch/` is the integration source or only historical
   bootstrap material for the affected component.

## Keep Ownership Separate

- Commit source changes in the repository that owns the files.
- Push or otherwise make the owning commit fetchable before recording a parent
  gitlink.
- Update nested submodules from the inside out, validating each parent layer.
- Keep parent gitlink changes separate from the child implementation commit.
- Avoid broad recursive remote updates; move only explicit requested paths.
- For a patch-backed external tool, keep one patch owner per upstream file,
  apply patches in one deterministic order, and reject partially applied trees.
  Include the upstream revision and ordered patch inputs in artifact identity.

## Handle The Root Tracer

The root Makefile's `git_commit` macro switches through `tracer-ysyx` with an
alternate saved index. Treat it as a state-changing course telemetry path.

- Pass `git_commit=` during diagnostics and validation unless tracer output is
  explicitly required.
- Check the current branch, index, tracer branch, and lock files if a traced
  build was interrupted.
- Do not delete or rewrite tracer state without explicit user authorization.

## Validate And Handoff

Validate inside the owning repository first, then validate the parent
integration. Before handing off, report child and parent SHAs, branch/detached
state, fetchability, recursive status, patch changes, and commands run. Never
reset unrelated dirtiness to produce a clean summary.
