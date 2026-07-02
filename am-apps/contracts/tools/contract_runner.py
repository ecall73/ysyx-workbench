#!/usr/bin/env python3
import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ARCH_TIMEOUT = {
    "riscv32-nemu": 30,
    "riscv32e-npc": 60,
    "riscv32e-ysyxsoc": 60,
}

GROUP_ORDER = ["preflight", "core", "klib", "cte", "ioe-auto", "platform-layout"]
SUITE_ORDER = [
    "preflight-run-command",
    "core-suite",
    "core-halt-nonzero",
    "klib-suite",
    "cte-basic-suite",
    "cte-gpr-suite",
    "cte-csr-suite",
    "cte-context-suite",
    "ioe-suite",
    "platform-npc-suite",
    "platform-ysyxsoc-default-suite",
    "platform-ysyxsoc-flash-sram-suite",
    "platform-ysyxsoc-flash-sdram-suite",
]
FOUNDATIONAL = ["preflight-run-command", "core-suite"]

DEPRECATED = {
    "core/trm-putch-halt": "core-suite",
    "core/mainargs": "core-suite",
    "core/sections-data-bss": "core-suite",
    "core/heap-window": "core-suite",
    "core/heap-boundary": "core-suite",
    "klib/string": "klib-suite",
    "klib/stdio": "klib-suite",
    "klib/stdlib": "klib-suite",
    "klib/int64-rv32e": "klib-suite",
    "cte/yield": "cte-basic-suite",
    "cte/syscall": "cte-basic-suite",
    "cte/interrupt-control": "cte-basic-suite",
    "cte/kcontext": "cte-context-suite",
    "ioe/config": "ioe-suite",
    "ioe/device-absence": "ioe-suite",
    "ioe/timer-uptime": "ioe-suite",
    "ioe/timer-rtc": "ioe-suite",
    "ioe/uart-tx": "ioe-suite",
    "ioe/input-idle": "ioe-suite",
    "ioe/gpu-smoke": "ioe-suite",
    "ioe/gpio-smoke": "ioe-suite",
    "platform/ysyxsoc-layout-default": "platform-ysyxsoc-default-suite",
    "platform/ysyxsoc-layout-flash-sram": "platform-ysyxsoc-flash-sram-suite",
    "platform/ysyxsoc-layout-flash-sdram": "platform-ysyxsoc-flash-sdram-suite",
    "00-trm-putch-halt": "core-suite",
    "01-sections-data-bss": "core-suite",
    "02-heap-window": "core-suite",
    "03-klib-string": "klib-suite",
    "04-klib-stdio": "klib-suite",
    "05-klib-stdlib": "klib-suite",
    "06-libgcc-rv32e": "klib-suite",
    "07-ioe-config": "ioe-suite",
    "08-timer-uptime": "ioe-suite",
    "09-timer-rtc": "ioe-suite",
    "10-cte-yield": "cte-basic-suite",
    "11-cte-syscall": "cte-basic-suite",
    "12-cte-kcontext": "cte-context-suite",
    "13-uart-tx": "ioe-suite",
    "14-gpu-config": "ioe-suite",
    "15-gpu-fbdraw-smoke": "ioe-suite",
    "16-input-idle": "ioe-suite",
    "17-ysyxsoc-layout": "platform-ysyxsoc-default-suite",
    "18-gpio-config": "ioe-suite",
}

@dataclass
class Suite:
    name: str
    group: str
    archs: list[str]
    points: list[str]
    path: Path


def parse_make_var(text: str, name: str) -> str:
    m = re.search(rf"^{re.escape(name)}\s*=\s*(.*)$", text, re.M)
    return m.group(1).strip() if m else ""


def discover(root: Path) -> dict[str, Suite]:
    suites = {}
    for mk in sorted((root / "suites").glob("*/Makefile")):
        text = mk.read_text()
        sid = parse_make_var(text, "CONTRACT_ID")
        group = parse_make_var(text, "CONTRACT_GROUP")
        archs = parse_make_var(text, "CONTRACT_ARCHS").split()
        points = parse_make_var(text, "CONTRACT_POINTS").split()
        if sid:
            suites[sid] = Suite(sid, group, archs, points, mk.parent)
    return suites


def split_selection(raw: str) -> list[str]:
    if not raw:
        return []
    raw = raw.replace(",", " ")
    return [x for x in raw.split() if x]


def fmt_point(name: str, status: str) -> str:
    label = "FAIL" if status == "***FAIL***" else status
    return f"[{label}] {name}"


def fmt_suite(name: str) -> str:
    return f"[    ] {name}"


def parse_results(output: str, suite: Suite):
    results = {}
    details = {}
    for line in output.splitlines():
        prefix = f"CONTRACT {suite.name} TEST "
        if not line.startswith(prefix):
            continue
        rest = line[len(prefix):]
        parts = rest.split(maxsplit=2)
        if len(parts) < 2:
            continue
        point, status = parts[0], parts[1]
        stage = parts[2] if len(parts) > 2 else ""
        if status in {"PASS", "FAIL", "BLOCKED"}:
            results[point] = status
            details[point] = stage
    return results, details


def run_suite(root: Path, suite: Suite, arch: str, timeout_s: int):
    log_dir = root / "build"
    log_dir.mkdir(exist_ok=True)
    log = log_dir / f"contract-{arch}-{suite.name}.log"
    cmd = ["make", "-C", str(suite.path), f"ARCH={arch}", "run"]
    if suite.name == "core-suite":
        cmd.append("mainargs=contract-mainargs-0123456789abcdef0123456789abcdef")
    env = os.environ.copy()
    env["CONTRACT_RUNNER_ARCH"] = arch
    try:
        cp = subprocess.run(cmd, cwd=root, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=timeout_s)
        output = cp.stdout
        status = cp.returncode
    except subprocess.TimeoutExpired as e:
        output = e.stdout or ""
        status = 124
        output += f"\n[contract-runner] timeout after {timeout_s}s\n"
    log.write_text(output)
    return status, log, output


def suite_command_ok(suite: Suite, status: int, output: str) -> bool:
    if suite.name != "core-halt-nonzero":
        return status == 0
    return status != 0 and "CORE_HALT_NONZERO_TOKEN" in output and (
        "HIT BAD TRAP" in output or "BAD TRAP" in output or "bad trap" in output.lower()
    )


def host_preflight(root: Path, arch: str):
    log_dir = root / "build"
    log_dir.mkdir(exist_ok=True)
    log = log_dir / f"contract-{arch}-preflight-host.log"
    lines = []
    ok = True
    point_status = {}

    def check(point, cond, msg):
        nonlocal ok
        lines.append(f"CONTRACT preflight-host TEST {point} BEGIN")
        if cond:
            lines.append(f"CONTRACT preflight-host TEST {point} PASS")
            point_status[point] = "PASS"
        else:
            lines.append(f"CONTRACT preflight-host TEST {point} FAIL {msg}")
            point_status[point] = "FAIL"
            ok = False

    am_home = Path(os.environ.get("AM_HOME", root.parent.parent / "abstract-machine"))
    check("build-arch", (am_home / "scripts" / f"{arch}.mk").exists(), f"missing scripts/{arch}.mk")
    if arch == "riscv32-nemu":
        check("link-libgcc-rv32e", True, "not-rv32e")
    else:
        libgcc = am_home / "am" / "src" / "riscv" / "npc" / "libgcc"
        need = ["div.S", "muldi3.S", "multi3.c", "ashldi3.c"]
        check("link-libgcc-rv32e", all((libgcc / x).exists() for x in need), "missing-rv32e-libgcc-source")
    check("image-rule", (am_home / "tools" / "insert-arg.py").exists(), "missing-insert-arg")
    for script in ("linker.ld", "linker-ysyxsoc.ld"):
        if arch == "riscv32e-ysyxsoc" or script == "linker.ld":
            check("mainargs-rule" if script == "linker.ld" else "image-rule-ysyxsoc", (am_home / "scripts" / script).exists(), f"missing-{script}")
    lines.append("CONTRACT preflight-host PASS" if ok else "CONTRACT preflight-host FAIL")
    log.write_text("\n".join(lines) + "\n")
    return ok, log, point_status


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--arch", required=True)
    ap.add_argument("--all", default="")
    ap.add_argument("--group", default="")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    arch = args.arch
    if arch not in ARCH_TIMEOUT:
        print(f"unsupported ARCH: {arch}", file=sys.stderr)
        return 2
    suites = discover(root)

    selected_names = split_selection(args.all)
    if selected_names:
        for name in selected_names:
            if name in DEPRECATED:
                print(f"[contract] old contract name '{name}' is deprecated; use '{DEPRECATED[name]}'", file=sys.stderr)
                return 2
            if name not in suites and name != "preflight-host":
                print(f"[contract] unknown suite '{name}'", file=sys.stderr)
                return 2
        names = selected_names
    else:
        names = ["preflight-host"]
        for name in SUITE_ORDER:
            if name in suites:
                s = suites[name]
                if args.group and s.group != args.group:
                    continue
                if arch in s.archs:
                    names.append(name)
        if args.group == "preflight" and "preflight-host" not in names:
            names.insert(0, "preflight-host")
        if args.group and args.group != "preflight":
            names = [n for n in names if n != "preflight-host"]

    if not names:
        print(f"[contract] no suites selected for ARCH={arch} GROUP={args.group or 'all'}", file=sys.stderr)
        return 2

    for name in names:
        if name == "preflight-host":
            continue
        s = suites[name]
        if arch not in s.archs:
            print(f"[contract] suite {name} does not support ARCH={arch}; supported: {' '.join(s.archs)}", file=sys.stderr)
            return 2

    failed = False
    blocked_by = None
    executed = []

    for name in names:
        if blocked_by:
            if name == "preflight-host":
                continue
            suite = suites[name]
            print(fmt_suite(name))
            for point in suite.points:
                print(fmt_point(point, "BLOCKED"))
            continue

        if name == "preflight-host":
            ok, log, point_status = host_preflight(root, arch)
            print(fmt_suite("preflight-host"))
            for point in ["build-arch", "link-libgcc-rv32e", "image-rule", "mainargs-rule", "image-rule-ysyxsoc"]:
                if point in point_status:
                    print(fmt_point(point, "PASS" if point_status[point] == "PASS" else "***FAIL***"))
            if not ok:
                failed = True
                blocked_by = "preflight-host"
            executed.append((name, log))
            continue

        suite = suites[name]
        status, log, output = run_suite(root, suite, arch, ARCH_TIMEOUT[arch])
        results, details = parse_results(output, suite)
        command_ok = suite_command_ok(suite, status, output)
        suite_failed = not command_ok
        missing = []
        for point in suite.points:
            if point not in results:
                results[point] = "BLOCKED" if suite_failed else "FAIL"
                details[point] = "missing-result"
                missing.append(point)
                suite_failed = True
        if any(results[p] in {"FAIL", "BLOCKED"} for p in suite.points):
            suite_failed = True
        print(fmt_suite(name))
        for point in suite.points:
            st = results[point]
            out = "PASS" if st == "PASS" else ("BLOCKED" if st == "BLOCKED" else "***FAIL***")
            print(fmt_point(point, out))
        if suite_failed:
            failed = True
            print(f"[contract] log: {log}")
            if missing:
                print(f"[contract] missing result points: {' '.join(missing)}")
            if name in FOUNDATIONAL:
                blocked_by = name
        executed.append((name, log))

    return 1 if failed else 0

if __name__ == "__main__":
    raise SystemExit(main())
