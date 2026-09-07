#!/usr/bin/env python3

"""Run the CPU iteration score: CI area, train IPC, and ECC synthesis Fmax."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import pathlib
import re
import subprocess
import sys
import time

try:
    from eval_ci_area import EccResult, read_stuid, resolve_ecc_bin, run_ecc
except ImportError:  # pragma: no cover - supports package-style imports
    from scripts.eval_ci_area import EccResult, read_stuid, resolve_ecc_bin, run_ecc

try:
    from flow_support import ProcessResult, run_logged, strip_ansi, workbench_env
except ImportError:  # pragma: no cover - supports package-style imports
    from scripts.flow_support import ProcessResult, run_logged, strip_ansi, workbench_env


FMAX_CAP_MHZ = 1000.0


def parse_args() -> argparse.Namespace:
    script_path = pathlib.Path(__file__).resolve()
    workbench = script_path.parents[1]
    parser = argparse.ArgumentParser(
        description=f"Score a CPU iteration with train IPC multiplied by ECC synthesis Fmax capped at {FMAX_CAP_MHZ:g} MHz."
    )
    parser.add_argument("--workbench", type=pathlib.Path, default=workbench)
    parser.add_argument("--npc-home", type=pathlib.Path)
    parser.add_argument("--stuid", help="8-digit student id without ysyx_ prefix")
    parser.add_argument("--arch", default="riscv32e-ysyxsoc")
    parser.add_argument("--run-root", type=pathlib.Path, help="Directory for this run's logs and summary")
    parser.add_argument("--json-out", type=pathlib.Path, help="Summary JSON path")
    parser.add_argument("--ci-repo", type=pathlib.Path)
    parser.add_argument("--yosys-bin", type=pathlib.Path)
    parser.add_argument("--cache-dir", type=pathlib.Path)
    parser.add_argument("--refresh-verilog", action="store_true")
    parser.add_argument("--ci-timeout", type=float, default=900.0)
    parser.add_argument("--train-timeout", type=float, default=1800.0)
    parser.add_argument("--ecc-timeout", type=float, default=3600.0)
    parser.add_argument("--ecc-project", type=pathlib.Path)
    parser.add_argument("--ecc-bin", type=pathlib.Path)
    parser.add_argument("--ecc-run-id", help="ECC run id; default: a fresh score-* run")
    return parser.parse_args()


def fresh_run_dir(workbench: pathlib.Path, requested: pathlib.Path | None) -> pathlib.Path:
    if requested is not None:
        path = requested.expanduser().resolve()
    else:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        path = workbench / ".tmp" / "score" / f"{stamp}-{time.time_ns() % 1_000_000:06d}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def optional_arg(command: list[str], option: str, value: pathlib.Path | None) -> None:
    if value is not None:
        command.extend([option, str(value.expanduser().resolve())])


def invoke_ci_area(
    args: argparse.Namespace,
    *,
    workbench: pathlib.Path,
    npc_home: pathlib.Path,
    run_root: pathlib.Path,
    env: dict[str, str],
) -> dict:
    ci_json = run_root / "ci-area.json"
    ci_log = run_root / "ci-area.log"
    script = pathlib.Path(__file__).resolve().with_name("eval_ci_area.py")
    command = [
        sys.executable,
        str(script),
        "--workbench",
        str(workbench),
        "--npc-home",
        str(npc_home),
        "--skip-ecc",
        "--json-out",
        str(ci_json),
        "--stuid",
        args.stuid,
    ]
    optional_arg(command, "--ci-repo", args.ci_repo)
    optional_arg(command, "--yosys-bin", args.yosys_bin)
    optional_arg(command, "--cache-dir", args.cache_dir)
    if args.refresh_verilog:
        command.append("--refresh-verilog")

    started = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            cwd=str(workbench),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=args.ci_timeout,
        )
        output = completed.stdout or ""
        returncode: int | None = completed.returncode
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or "") if isinstance(exc.stdout, str) else (exc.stdout or b"").decode(errors="replace")
        output += "\n[timeout]\n"
        returncode = None
        timed_out = True
    ci_log.write_text(output, encoding="utf-8")

    summary = None
    if ci_json.is_file():
        try:
            summary = json.loads(ci_json.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            summary = None
    return {
        "pass": bool(summary and summary.get("pass_ci")),
        "returncode": returncode,
        "timed_out": timed_out,
        "elapsed_seconds": time.monotonic() - started,
        "command": command,
        "log": str(ci_log),
        "summary": summary,
    }


def make_command(directory: pathlib.Path, arch: str, *, mainargs: str | None = None) -> list[str]:
    command = ["make", "--no-print-directory", "-C", str(directory), f"ARCH={arch}"]
    if mainargs is not None:
        command.append(f"mainargs={mainargs}")
    command.append("run")
    return command


def run_train(
    *,
    workbench: pathlib.Path,
    arch: str,
    run_root: pathlib.Path,
    env: dict[str, str],
    timeout: float,
) -> dict:
    directory = workbench / "am-kernels" / "benchmarks" / "microbench"
    command = make_command(directory, arch, mainargs="train")
    result = run_logged(
        command,
        cwd=workbench,
        env=env,
        log_path=run_root / "microbench-train.log",
        timeout_seconds=timeout,
    )
    text = strip_ansi(result.output)
    ipc_matches = re.findall(r"\bIPC\s*=\s*([0-9]+(?:\.[0-9]+)?)", text)
    instruction_matches = re.findall(r"total guest instructions\s*=\s*([0-9,']+)", text)
    cycle_matches = re.findall(r"total simulation cycles\s*=\s*([0-9,']+)", text)
    ipc = float(ipc_matches[-1]) if ipc_matches else None
    checks = {
        "train_input": bool(re.search(r"Running MicroBench \[input \*train\*\]", text)),
        "microbench_pass": "MicroBench PASS" in text,
        "good_trap": "HIT GOOD TRAP" in text,
        "ipc_reported": ipc is not None and ipc > 0,
        "natural_exit": result.returncode == 0 and not result.timed_out,
    }
    passed = not result.error_lines and all(checks.values())
    return {
        "name": "microbench(train)",
        "pass": passed,
        "ipc": ipc,
        "guest_instructions": parse_integer(instruction_matches[-1]) if instruction_matches else None,
        "simulation_cycles": parse_integer(cycle_matches[-1]) if cycle_matches else None,
        "checks": checks,
        "process": result.as_dict(),
    }


def parse_integer(value: str) -> int:
    return int(value.replace(",", "").replace("'", ""))


def run_ecc_task(
    *,
    args: argparse.Namespace,
    workbench: pathlib.Path,
    vfile: pathlib.Path,
    design: str,
) -> EccResult:
    project = (
        args.ecc_project.expanduser().resolve()
        if args.ecc_project is not None
        else (workbench / ".tmp" / "ecc-project").resolve()
    )
    ecc_bin = resolve_ecc_bin(workbench, args.ecc_bin)
    run_id = args.ecc_run_id or f"score-{time.strftime('%Y%m%d-%H%M%S')}-{time.time_ns() % 1_000_000:06d}"
    return run_ecc(
        project=project,
        ecc_bin=ecc_bin,
        vfile=vfile,
        design=design,
        run_id=run_id,
        timeout_seconds=args.ecc_timeout,
        log_name="score.ecc.log",
        echo=False,
    )


def print_train(result: dict) -> None:
    print(f"train IPC : {'PASS' if result['pass'] else 'FAIL'}")
    if result["ipc"] is not None:
        print(f"IPC       : {result['ipc']:.4f}")
    if not result["pass"]:
        failed = [name for name, passed in result["checks"].items() if not passed]
        if failed:
            print("train checks: " + ", ".join(failed))
    print("train log : " + result["process"]["log"])


def print_ecc(result: EccResult | None, error: str | None) -> None:
    if result is None:
        print("ECC       : FAIL")
        print("ECC error : " + (error or "unknown error"))
        return
    print(
        f"ECC Fmax  : {result.fmax_mhz:.3f} MHz "
        f"(synthesis, slack={result.worst_slack_ns:.3f} ns)"
    )
    print("ECC report: " + result.report)


def main() -> int:
    args = parse_args()
    workbench = args.workbench.expanduser().resolve()
    npc_home = (args.npc_home or workbench / "npc").expanduser().resolve()
    stuid = args.stuid or read_stuid(workbench, None)
    if not re.fullmatch(r"\d{8}", stuid):
        raise RuntimeError(f"invalid STUID digits: {stuid}")
    args.stuid = stuid
    design = f"ysyx_{stuid}"
    run_root = fresh_run_dir(workbench, args.run_root)
    env = workbench_env(workbench)
    env["NPC_HOME"] = str(npc_home)

    ci_area = invoke_ci_area(args, workbench=workbench, npc_home=npc_home, run_root=run_root, env=env)
    print(f"CI area  : {'PASS' if ci_area['pass'] else 'FAIL'}")
    print("CI log   : " + ci_area["log"])
    ci_summary = ci_area.get("summary") or {}
    vfile_value = ci_summary.get("vfile")
    if not isinstance(vfile_value, str):
        raise RuntimeError("CI area did not produce a vfile path; inspect " + ci_area["log"])
    vfile = pathlib.Path(vfile_value).expanduser().resolve()
    if not vfile.is_file():
        raise RuntimeError(f"CI area vfile does not exist: {vfile}")

    with concurrent.futures.ThreadPoolExecutor(max_workers=2, thread_name_prefix="score") as executor:
        train_future = executor.submit(
            run_train,
            workbench=workbench,
            arch=args.arch,
            run_root=run_root,
            env=env,
            timeout=args.train_timeout,
        )
        ecc_future = executor.submit(
            run_ecc_task,
            args=args,
            workbench=workbench,
            vfile=vfile,
            design=design,
        )
        train = train_future.result()
        ecc_error = None
        try:
            ecc = ecc_future.result()
        except Exception as exc:  # keep the train result visible on ECC failure
            ecc = None
            ecc_error = str(exc)

    print_train(train)
    print_ecc(ecc, ecc_error)

    fmax_mhz = ecc.fmax_mhz if ecc is not None else None
    fmax_capped_mhz = min(fmax_mhz, FMAX_CAP_MHZ) if fmax_mhz is not None else None
    score = train["ipc"] * fmax_capped_mhz if train["pass"] and fmax_capped_mhz is not None else None
    performance_pass = train["pass"] and ecc is not None and score is not None
    overall_pass = ci_area["pass"] and performance_pass
    if score is None:
        print("score     : unavailable")
    else:
        print(f"score     : {score:.4f} = IPC {train['ipc']:.4f} * capped Fmax {fmax_capped_mhz:.3f} MHz")
    print(f"hard gate : {'PASS' if ci_area['pass'] else 'FAIL'} (CI area)")
    print(f"iteration : {'PASS' if overall_pass else 'FAIL'}")

    ecc_json = None
    if ecc is not None:
        ecc_json = {
            "fmax_mhz": ecc.fmax_mhz,
            "worst_slack_ns": ecc.worst_slack_ns,
            "run_dir": ecc.run_dir,
            "report": ecc.report,
        }
    summary = {
        "workbench": str(workbench),
        "arch": args.arch,
        "stuid": stuid,
        "design": design,
        "npc_home": str(npc_home),
        "vfile": str(vfile),
        "ci_area": ci_area,
        "train": train,
        "ecc": ecc_json,
        "ecc_error": ecc_error,
        "fmax_cap_mhz": FMAX_CAP_MHZ,
        "fmax_capped_mhz": fmax_capped_mhz,
        "score": score,
        "hard_gate_pass": ci_area["pass"],
        "performance_pass": performance_pass,
        "pass": overall_pass,
        "run_root": str(run_root),
    }
    json_out = args.json_out.expanduser().resolve() if args.json_out else run_root / "summary.json"
    json_out.parent.mkdir(parents=True, exist_ok=True)
    json_out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print("summary   : " + str(json_out))
    return 0 if overall_pass else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
