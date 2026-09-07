#!/usr/bin/env python3

"""Generate the netlist artifact used by the CI netlist simulation.

The CI workflow uploads the netlist produced after reverting yosys-sta to its
older commit.  This script intentionally runs only that reverted flow.  It
does not read or generate an ECC netlist.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import subprocess
import sys

try:
    from ci_support import ensure_ci_repo
except ImportError:  # pragma: no cover - supports package-style imports
    from scripts.ci_support import ensure_ci_repo

try:
    from eval_ci_area import (
        build_env,
        choose_vfile,
        ensure_cache,
        ensure_verilog,
        make_temp_clone,
        parse_ci_config,
        read_stuid,
        resolve_cache_dir,
        resolve_paths,
        resolve_yosys_bin,
        revert_old_flow,
        run_sta,
        verify_module_name,
        verify_no_latch,
    )
except ImportError:  # pragma: no cover - supports package-style imports
    from scripts.eval_ci_area import (
        build_env,
        choose_vfile,
        ensure_cache,
        ensure_verilog,
        make_temp_clone,
        parse_ci_config,
        read_stuid,
        resolve_cache_dir,
        resolve_paths,
        resolve_yosys_bin,
        revert_old_flow,
        run_sta,
        verify_module_name,
        verify_no_latch,
    )


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def require_file(path: pathlib.Path, description: str) -> pathlib.Path:
    resolved = path.expanduser().resolve()
    if not resolved.is_file():
        raise RuntimeError(f"missing {description}: {resolved}")
    return resolved


def parse_args() -> argparse.Namespace:
    script_path = pathlib.Path(__file__).resolve()
    parser = argparse.ArgumentParser(
        description="Generate the old-yosys-sta netlist used by CI netlist simulation."
    )
    parser.add_argument("--workbench", type=pathlib.Path, default=script_path.parents[1])
    parser.add_argument("--npc-home", type=pathlib.Path)
    parser.add_argument("--ci-repo", type=pathlib.Path)
    parser.add_argument("--stuid", help="8-digit student id without ysyx_ prefix")
    parser.add_argument("--vfile", type=pathlib.Path, help="Use an explicit local build Verilog file.")
    parser.add_argument(
        "--refresh-verilog",
        action="store_true",
        help="Regenerate npc/build/ysyx_<stuid>.v before synthesis.",
    )
    parser.add_argument("--yosys-bin", type=pathlib.Path)
    parser.add_argument("--cache-dir", type=pathlib.Path)
    parser.add_argument("--output-netlist", type=pathlib.Path)
    parser.add_argument("--keep-run-dir", action="store_true")
    parser.add_argument("--json-out", type=pathlib.Path)
    return parser.parse_args()


def write_json(path: pathlib.Path | None, data: dict) -> None:
    if path is None:
        return
    path = path.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    workbench, npc_home = resolve_paths(args)
    ci_repo = ensure_ci_repo(workbench, args.ci_repo)
    ci = parse_ci_config(ci_repo / ".github" / "workflows" / "autotest.yml")
    stuid = read_stuid(workbench, args.stuid)
    design = f"ysyx_{stuid}"

    if args.refresh_verilog:
        ensure_verilog(npc_home)
    if args.vfile is not None:
        vfile = require_file(args.vfile, "explicit build Verilog")
    else:
        vfile = choose_vfile(npc_home, design)

    yosys_bin = resolve_yosys_bin(workbench, args.yosys_bin)
    cache_dir = resolve_cache_dir(workbench, args.cache_dir)
    ensure_cache(cache_dir, ci.yosys_sta_branch)
    env = build_env(yosys_bin)

    run_dir: pathlib.Path | None = None
    try:
        run_dir = make_temp_clone(cache_dir, ci.yosys_sta_branch)
        # This is the exact CI artifact source: the flow after the CI revert.
        revert_old_flow(run_dir, ci.revert_commit)
        old_flow = run_sta(run_dir, env=env, design=design, vfile=vfile)
        result_dir = pathlib.Path(old_flow.result_dir)
        verify_module_name(result_dir / "yosys.log", design)
        verify_no_latch(result_dir / "synth_stat.txt")

        source_netlist = require_file(
            result_dir / f"{design}.netlist.fixed.v",
            "CI old-flow netlist",
        )
        output_netlist = (
            args.output_netlist.expanduser().resolve()
            if args.output_netlist is not None
            else (workbench / ".tmp" / source_netlist.name).resolve()
        )
        output_netlist.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_netlist, output_netlist)

        summary = {
            "design": design,
            "vfile": str(vfile),
            "ci_repo": str(ci_repo),
            "yosys_sta_branch": ci.yosys_sta_branch,
            "reverted_commit": ci.revert_commit,
            "source_flow": "CI yosys-sta after revert",
            "source_result_dir": str(result_dir),
            "source_area": old_flow.area,
            "output_netlist": str(output_netlist),
            "ecc_netlist_used": False,
            "run_dir": str(run_dir) if args.keep_run_dir else None,
        }
        print(f"design        : {design}")
        print(f"source flow   : {summary['source_flow']}")
        print(f"source area   : {old_flow.area:.3f}")
        print(f"output netlist: {output_netlist}")
        print("ecc netlist   : not used")
        if args.keep_run_dir:
            print(f"run dir       : {run_dir}")
        write_json(args.json_out, summary)
        return 0
    finally:
        if run_dir is not None and run_dir.exists() and not args.keep_run_dir:
            shutil.rmtree(run_dir)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        eprint(f"command failed with exit code {exc.returncode}")
        raise SystemExit(exc.returncode)
    except RuntimeError as exc:
        eprint(f"error: {exc}")
        raise SystemExit(2)
