#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import subprocess
import sys


IPC_RE = re.compile(r"IPC = ([0-9.]+)")
CYCLES_RE = re.compile(r"total simulation cycles = (\d+)")
INST_RE = re.compile(r"total guest instructions = (\d+)")


def run_capture(cmd: list[str], cwd: pathlib.Path) -> str:
    print("+", " ".join(cmd), file=sys.stderr)
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if proc.returncode not in (0, 1):
        raise subprocess.CalledProcessError(proc.returncode, cmd, output=proc.stdout)
    return proc.stdout


def parse_args() -> argparse.Namespace:
    script_dir = pathlib.Path(__file__).resolve().parent
    workbench = script_dir.parent
    parser = argparse.ArgumentParser(description="Evaluate one icache/fetch variant with area and ysyxsoc IPC.")
    parser.add_argument("--label", required=True, help="Short variant label used in output directory and logs")
    parser.add_argument("--notes", default="", help="Free-form notes written into the experiment log")
    parser.add_argument("--workbench", type=pathlib.Path, default=workbench)
    parser.add_argument("--ci-repo", type=pathlib.Path, default=workbench.parent / "ysyx-submit-test")
    parser.add_argument("--yosys-bin", type=pathlib.Path, default=pathlib.Path.home() / "oss-cad-suite" / "bin" / "yosys")
    parser.add_argument("--cache-dir", type=pathlib.Path, default=pathlib.Path.home() / ".cache" / "ysyx-ci-area" / "yosys-sta")
    parser.add_argument(
        "--output-root",
        type=pathlib.Path,
        default=workbench / "out" / "icache-opt",
        help="Directory used to store raw logs and summaries",
    )
    parser.add_argument(
        "--log-md",
        type=pathlib.Path,
        default=workbench / "out" / "icache-opt" / "experiment_log.md",
        help="Markdown log file to append one summary row into",
    )
    parser.add_argument("--mainargs", default="test")
    parser.add_argument("--skip-area", action="store_true")
    parser.add_argument("--skip-ipc", action="store_true")
    return parser.parse_args()


def sanitize_label(label: str) -> str:
    cleaned = re.sub(r"[^0-9A-Za-z._-]+", "-", label).strip("-")
    if not cleaned:
        raise ValueError("label becomes empty after sanitization")
    return cleaned


def parse_metric(pattern: re.Pattern[str], text: str, name: str) -> str:
    matches = pattern.findall(text)
    if not matches:
        raise RuntimeError(f"can not find {name} in command output")
    return matches[-1]


def append_markdown_row(log_md: pathlib.Path, row: list[str]) -> None:
    log_md.parent.mkdir(parents=True, exist_ok=True)
    if not log_md.exists():
        log_md.write_text(
            "# icache/fetch 优化实验记录\n\n"
            "| 时间 | 标签 | new area | old area | CI 面积结论 | IPC(ysyxsoc microbench) | 指令数 | 周期数 | 备注 |\n"
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n"
        )
    with log_md.open("a") as fp:
        fp.write("| " + " | ".join(row) + " |\n")


def main() -> int:
    args = parse_args()
    workbench = args.workbench.expanduser().resolve()
    ci_repo = args.ci_repo.expanduser().resolve()
    output_root = args.output_root.expanduser().resolve()
    log_md = args.log_md.expanduser().resolve()
    label = sanitize_label(args.label)

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = output_root / f"{stamp}-{label}"
    run_dir.mkdir(parents=True, exist_ok=False)

    summary: dict[str, object] = {
        "timestamp": stamp,
        "label": label,
        "notes": args.notes,
        "workbench": str(workbench),
        "ci_repo": str(ci_repo),
    }

    area_json_path = run_dir / "area.json"
    ipc_log_path = run_dir / "microbench-ysyxsoc.log"

    if not args.skip_area:
        area_cmd = [
            "python3",
            str(workbench / "scripts" / "eval_ci_area.py"),
            "--workbench",
            str(workbench),
            "--npc-home",
            str(workbench / "npc"),
            "--ci-repo",
            str(ci_repo),
            "--yosys-bin",
            str(args.yosys_bin.expanduser().resolve()),
            "--cache-dir",
            str(args.cache_dir.expanduser().resolve()),
            "--json-out",
            str(area_json_path),
        ]
        area_output = run_capture(area_cmd, workbench)
        (run_dir / "area.stdout.log").write_text(area_output)
        area = json.loads(area_json_path.read_text())
        summary["area"] = area
    else:
        area = None

    if not args.skip_ipc:
        microbench_dir = workbench / "am-kernels" / "benchmarks" / "microbench"
        ipc_cmd = [
            "make",
            "ARCH=riscv32e-ysyxsoc",
            "run",
            "DIFFTEST=1",
            f"mainargs={args.mainargs}",
        ]
        ipc_output = run_capture(ipc_cmd, microbench_dir)
        ipc_log_path.write_text(ipc_output)
        ipc = parse_metric(IPC_RE, ipc_output, "IPC")
        cycles = parse_metric(CYCLES_RE, ipc_output, "simulation cycles")
        insts = parse_metric(INST_RE, ipc_output, "guest instructions")
        summary["ipc"] = {
            "ipc": float(ipc),
            "cycles": int(cycles),
            "instructions": int(insts),
        }
    else:
        ipc = cycles = insts = None

    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")

    new_area = old_area = ci_pass = "-"
    if area is not None:
        new_area = f"{area['new_flow']['area']:.3f}"
        old_area = f"{area['old_flow']['area']:.3f}"
        ci_pass = "PASS" if area["pass_ci"] else "FAIL"
    ipc_text = "-" if ipc is None else str(ipc)
    inst_text = "-" if insts is None else str(insts)
    cycle_text = "-" if cycles is None else str(cycles)
    append_markdown_row(
        log_md,
        [
            stamp,
            label,
            new_area,
            old_area,
            ci_pass,
            ipc_text,
            inst_text,
            cycle_text,
            args.notes or "-",
        ],
    )

    print(f"saved under: {run_dir}")
    if area is not None:
        print(f"new area  : {new_area}")
        print(f"old area  : {old_area}")
        print(f"ci result : {ci_pass}")
    if ipc is not None:
        print(f"ipc       : {ipc_text}")
        print(f"insts     : {inst_text}")
        print(f"cycles    : {cycle_text}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
