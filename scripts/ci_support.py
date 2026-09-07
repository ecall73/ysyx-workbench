#!/usr/bin/env python3

"""Small helpers shared by the two local CI flow scripts."""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile


CI_REPO_URL = "https://github.com/sashimi-yzh/ysyx-submit-test"
CI_WORKFLOW = pathlib.Path(".github/workflows/autotest.yml")
CI_REPO_DIRNAME = "ysyx-submit-test"


def default_ci_repo(workbench: pathlib.Path) -> pathlib.Path:
    """Return the ignored, workbench-local checkout used by default."""

    return workbench / ".tmp" / CI_REPO_DIRNAME


def is_ready_ci_repo(path: pathlib.Path) -> bool:
    """A checkout is ready when the workflow consumed by the scripts exists."""

    return (path / CI_WORKFLOW).is_file()


def ensure_ci_repo(workbench: pathlib.Path, requested: pathlib.Path | None = None) -> pathlib.Path:
    """Find or clone the CI repository without tracking it in the workbench.

    Existing usable checkouts are deliberately left untouched.  A missing
    checkout is cloned into a temporary sibling first, so an interrupted
    network operation cannot leave a directory that looks ready to a later
    invocation.
    """

    target = (requested.expanduser() if requested else default_ci_repo(workbench)).resolve()
    if is_ready_ci_repo(target):
        return target

    if target.exists():
        if not target.is_dir():
            raise RuntimeError(f"CI repo path exists but is not a directory: {target}")
        if any(target.iterdir()):
            raise RuntimeError(
                f"CI repo path is incomplete and non-empty: {target}; "
                "remove it or pass --ci-repo to another checkout"
            )

    target.parent.mkdir(parents=True, exist_ok=True)
    staging_root = pathlib.Path(tempfile.mkdtemp(prefix=f".{CI_REPO_DIRNAME}-", dir=target.parent))
    staging_repo = staging_root / CI_REPO_DIRNAME
    try:
        print(f"cloning CI repository {CI_REPO_URL} -> {target}", flush=True)
        subprocess.run(
            ["git", "clone", "--depth", "1", CI_REPO_URL, str(staging_repo)],
            check=True,
        )
        if not is_ready_ci_repo(staging_repo):
            raise RuntimeError(f"cloned CI repository has no {CI_WORKFLOW}: {staging_repo}")
        if target.exists():
            target.rmdir()
        staging_repo.rename(target)
    finally:
        shutil.rmtree(staging_root, ignore_errors=True)

    return target
