#!/usr/bin/env python3

"""Run the ysyxsoc functional gate used after each RTL optimization."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import time

try:
    from flow_support import ProcessResult, run_logged, strip_ansi, workbench_env
except ImportError:  # pragma: no cover - supports package-style imports
    from scripts.flow_support import ProcessResult, run_logged, strip_ansi, workbench_env


RTTHREAD_SUCCESS_PATTERNS = (
    r"RT\s*-\s*Thread Operating System",
    r"Hello RISC-V!",
    r"\[I/utest\]\s+utest is initialize success",
    r"msh\s*/>help",
    r"msh\s*/>date",
    r"msh\s*/>version",
    r"msh\s*/>free",
    r"msh\s*/>ps",
    r"msh\s*/>pwd",
    r"msh\s*/>ls",
    r"msh\s*/>memtrace",
    r"msh\s*/>memcheck",
    r"msh\s*/>utest_list",
)


def parse_args() -> argparse.Namespace:
    script_path = pathlib.Path(__file__).resolve()
    workbench = script_path.parents[1]
    parser = argparse.ArgumentParser(
        description="Run rt-thread-am, cpu-tests(ALL), and hello on ysyxsoc Verilator, then check CI area."
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
    parser.add_argument("--rtthread-timeout", type=float, default=120.0)
    parser.add_argument("--cpu-tests-timeout", type=float, default=900.0)
    parser.add_argument("--hello-timeout", type=float, default=120.0)
    return parser.parse_args()


def timestamped_dir(workbench: pathlib.Path, requested: pathlib.Path | None) -> pathlib.Path:
    if requested is not None:
        path = requested.expanduser().resolve()
    else:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        path = workbench / ".tmp" / "functional" / f"{stamp}-{time.time_ns() % 1_000_000:06d}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def optional_arg(command: list[str], option: str, value: pathlib.Path | None) -> None:
    if value is not None:
        command.extend([option, str(value.expanduser().resolve())])


def run_ci_area(args: argparse.Namespace, workbench: pathlib.Path, run_root: pathlib.Path, env: dict[str, str]) -> dict:
    ci_json = run_root / "ci-area.json"
    ci_log = run_root / "ci-area.log"
    script = pathlib.Path(__file__).resolve().with_name("eval_ci_area.py")
    command = [
        sys.executable,
        str(script),
        "--workbench",
        str(workbench),
        "--npc-home",
        str((args.npc_home or workbench / "npc").expanduser().resolve()),
        "--skip-ecc",
        "--json-out",
        str(ci_json),
    ]
    optional_arg(command, "--ci-repo", args.ci_repo)
    optional_arg(command, "--yosys-bin", args.yosys_bin)
    optional_arg(command, "--cache-dir", args.cache_dir)
    if args.stuid:
        command.extend(["--stuid", args.stuid])
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


def make_command(directory: pathlib.Path, arch: str) -> list[str]:
    return ["make", "--no-print-directory", "-C", str(directory), f"ARCH={arch}", "run"]


def result_base(result: ProcessResult, *, require_exit_zero: bool) -> bool:
    if result.timed_out or result.error_lines:
        return False
    if result.stopped_on_success:
        return True
    return result.returncode == 0 if require_exit_zero else result.returncode in (0, None)


def run_hello(
    *, workbench: pathlib.Path, arch: str, stuid: str, run_root: pathlib.Path, env: dict[str, str], timeout: float
) -> dict:
    directory = workbench / "am-kernels" / "kernels" / "hello"
    command = make_command(directory, arch)
    command.insert(-1, "mainargs=" + "ysyx_" + stuid)
    result = run_logged(
        command,
        cwd=workbench,
        env=env,
        log_path=run_root / "hello.log",
        timeout_seconds=timeout,
    )
    text = strip_ansi(result.output)
    checks = {
        "hello_output": "Hello, AbstractMachine!" in text,
        "mainargs_output": f"mainargs = 'ysyx_{stuid}'." in text,
        "good_trap": "HIT GOOD TRAP" in text,
        "natural_exit": result.returncode == 0 and not result.timed_out,
    }
    return {
        "name": "hello",
        "pass": result_base(result, require_exit_zero=True) and all(checks.values()),
        "checks": checks,
        "process": result.as_dict(),
    }


def run_cpu_tests(
    *, workbench: pathlib.Path, arch: str, run_root: pathlib.Path, env: dict[str, str], timeout: float
) -> dict:
    directory = workbench / "am-kernels" / "tests" / "cpu-tests"
    command = make_command(directory, arch)
    result = run_logged(
        command,
        cwd=workbench,
        env=env,
        log_path=run_root / "cpu-tests.log",
        timeout_seconds=timeout,
    )
    text = strip_ansi(result.output)
    expected = sorted(path.stem for path in (directory / "tests").glob("*.c"))
    list_match = re.search(r"test list \[(\d+) item\(s\)\]:", text)
    listed_count = int(list_match.group(1)) if list_match else None
    passed_names: list[str] = []
    for line in text.splitlines():
        match = re.match(r"^\s*\[\s*(.*?)\s*\]\s+PASS\s*$", line)
        if match:
            passed_names.append(match.group(1).strip())
    passed_set = set(passed_names)
    checks = {
        "all_tests_discovered": listed_count == len(expected),
        "all_tests_pass": passed_set == set(expected) and len(passed_names) == len(expected),
        "good_trap_per_test": text.count("HIT GOOD TRAP") >= len(expected),
        "natural_exit": result.returncode == 0 and not result.timed_out,
    }
    return {
        "name": "cpu-tests(ALL)",
        "pass": result_base(result, require_exit_zero=True) and all(checks.values()),
        "expected_tests": expected,
        "listed_count": listed_count,
        "passed_tests": sorted(passed_set),
        "checks": checks,
        "process": result.as_dict(),
    }


def run_rtthread(
    *, workbench: pathlib.Path, arch: str, run_root: pathlib.Path, env: dict[str, str], timeout: float
) -> dict:
    directory = workbench / "rt-thread-am" / "bsp" / "abstract-machine"
    command = make_command(directory, arch)
    result = run_logged(
        command,
        cwd=workbench,
        env=env,
        log_path=run_root / "rt-thread-am.log",
        timeout_seconds=timeout,
        success_patterns=RTTHREAD_SUCCESS_PATTERNS,
    )
    text = strip_ansi(result.output)
    checks = {pattern: bool(re.search(pattern, text, re.MULTILINE | re.DOTALL)) for pattern in RTTHREAD_SUCCESS_PATTERNS}
    checks["marker_stop"] = result.stopped_on_success
    checks["not_timeout"] = not result.timed_out
    return {
        "name": "rt-thread-am",
        "pass": result_base(result, require_exit_zero=False) and all(checks.values()),
        "checks": checks,
        "process": result.as_dict(),
    }


def print_result(result: dict) -> None:
    print(f"{result['name']}: {'PASS' if result['pass'] else 'FAIL'}")
    if not result["pass"]:
        failed = [name for name, passed in result.get("checks", {}).items() if not passed]
        if failed:
            print("  failed checks: " + ", ".join(failed))
    print("  log: " + result["process"]["log"])


def main() -> int:
    args = parse_args()
    workbench = args.workbench.expanduser().resolve()
    npc_home = (args.npc_home or workbench / "npc").expanduser().resolve()
    stuid = args.stuid
    if stuid is None:
        from eval_ci_area import read_stuid

        stuid = read_stuid(workbench, None)
    if not re.fullmatch(r"\d{8}", stuid):
        raise RuntimeError(f"invalid STUID digits: {stuid}")
    run_root = timestamped_dir(workbench, args.run_root)
    env = workbench_env(workbench)
    env["NPC_HOME"] = str(npc_home)

    ci_area = run_ci_area(args, workbench, run_root, env)
    print(f"CI area: {'PASS' if ci_area['pass'] else 'FAIL'}")
    print("  log: " + ci_area["log"])

    results = [
        run_rtthread(
            workbench=workbench,
            arch=args.arch,
            run_root=run_root,
            env=env,
            timeout=args.rtthread_timeout,
        ),
        run_cpu_tests(
            workbench=workbench,
            arch=args.arch,
            run_root=run_root,
            env=env,
            timeout=args.cpu_tests_timeout,
        ),
        run_hello(
            workbench=workbench,
            arch=args.arch,
            stuid=stuid,
            run_root=run_root,
            env=env,
            timeout=args.hello_timeout,
        ),
    ]
    for result in results:
        print_result(result)

    summary = {
        "workbench": str(workbench),
        "arch": args.arch,
        "stuid": stuid,
        "npc_home": str(npc_home),
        "ci_area": ci_area,
        "tests": results,
        "pass": ci_area["pass"] and all(result["pass"] for result in results),
        "run_root": str(run_root),
    }
    json_out = args.json_out.expanduser().resolve() if args.json_out else run_root / "summary.json"
    json_out.parent.mkdir(parents=True, exist_ok=True)
    json_out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"functional gate: {'PASS' if summary['pass'] else 'FAIL'}")
    print(f"summary: {json_out}")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
