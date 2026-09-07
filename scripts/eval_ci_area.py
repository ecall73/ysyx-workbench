#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import asdict, dataclass

try:
    from ci_support import ensure_ci_repo
except ImportError:  # pragma: no cover - supports package-style imports
    from scripts.ci_support import ensure_ci_repo


@dataclass
class CiConfig:
    yosys_sta_branch: str
    revert_commit: str
    area_budget: float
    area_old_budget: float


@dataclass
class AreaResult:
    area: float
    result_dir: str


@dataclass
class EccResult:
    fmax_mhz: float
    worst_slack_ns: float
    run_dir: str
    report: str


@dataclass
class EvalSummary:
    workbench: str
    npc_home: str
    vfile: str
    stuid: str
    design: str
    yosys_bin: str
    cache_dir: str
    run_dir: str | None
    ci_repo: str
    ci: CiConfig
    new_flow: AreaResult
    old_flow: AreaResult
    pass_ci: bool
    ecc: EccResult | None


AREA_RE = re.compile(r"Chip area for module '.*?': ([0-9.]+)")
STUID_RE = re.compile(r"^STUID\s*=\s*ysyx_(\d{8})\s*$", re.MULTILINE)
WORKFLOW_CLONE_RE = re.compile(r"git clone -b ([^\s]+) https://github\.com/OSCPU/yosys-sta")
WORKFLOW_REVERT_RE = re.compile(r"git revert --no-edit ([0-9a-f]{40})")
WORKFLOW_BUDGET_RE = re.compile(r"AREA_BUDGET=(\d+)")
WORKFLOW_OLD_BUDGET_RE = re.compile(r"AREA_OLD_BUDGET=(\d+)")
MODULE_RE = re.compile(r"Generating RTLIL representation for module `\\([^']+)'\.")


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def run(
    cmd: list[str],
    *,
    cwd: pathlib.Path | None = None,
    env: dict[str, str] | None = None,
) -> None:
    eprint("+", " ".join(cmd))
    subprocess.run(cmd, cwd=str(cwd) if cwd else None, env=env, check=True)


def parse_args() -> argparse.Namespace:
    script_path = pathlib.Path(__file__).resolve()
    default_workbench = script_path.parents[1]
    parser = argparse.ArgumentParser(description="Evaluate CI area and ECC/ECOS-Studio synthesis Fmax.")
    parser.add_argument("--workbench", type=pathlib.Path, default=default_workbench)
    parser.add_argument("--npc-home", type=pathlib.Path)
    parser.add_argument("--ci-repo", type=pathlib.Path, help="Repo containing .github/workflows/autotest.yml")
    parser.add_argument("--stuid", help="8-digit student id without ysyx_ prefix")
    parser.add_argument(
        "--refresh-verilog",
        action="store_true",
        help="Regenerate npc/build/ysyx_<stuid>.v before evaluating.",
    )
    parser.add_argument("--yosys-bin", type=pathlib.Path, help="Yosys executable; default: first yosys on PATH")
    parser.add_argument(
        "--cache-dir",
        type=pathlib.Path,
        help="Local yosys-sta cache; default: <workbench>/.tmp/ysyx-ci-tools/yosys-sta-ci",
    )
    parser.add_argument(
        "--ecc-project",
        type=pathlib.Path,
        help="ECC project; default: <workbench>/.tmp/ecc-project",
    )
    parser.add_argument(
        "--ecc-bin",
        type=pathlib.Path,
        help="ECC executable; default: ecc on PATH or a workbench-local checkout",
    )
    parser.add_argument(
        "--ecc-run-id",
        help="ECC run id; default: the run selected by flow.run in ecc.toml",
    )
    parser.add_argument(
        "--skip-ecc",
        action="store_true",
        help="Only evaluate the CI old/new area flows; do not run ECC.",
    )
    parser.add_argument("--keep-run-dir", action="store_true")
    parser.add_argument("--json-out", type=pathlib.Path)
    return parser.parse_args()


def find_ci_repo(workbench: pathlib.Path, override: pathlib.Path | None) -> pathlib.Path:
    return ensure_ci_repo(workbench, override)


def parse_ci_config(workflow_path: pathlib.Path) -> CiConfig:
    text = workflow_path.read_text()
    branch = require_match(WORKFLOW_CLONE_RE, text, f"clone branch in {workflow_path}")
    revert_commit = require_match(WORKFLOW_REVERT_RE, text, f"revert commit in {workflow_path}")
    area_budget = float(require_match(WORKFLOW_BUDGET_RE, text, f"AREA_BUDGET in {workflow_path}"))
    area_old_budget = float(
        require_match(WORKFLOW_OLD_BUDGET_RE, text, f"AREA_OLD_BUDGET in {workflow_path}")
    )
    return CiConfig(
        yosys_sta_branch=branch,
        revert_commit=revert_commit,
        area_budget=area_budget,
        area_old_budget=area_old_budget,
    )


def require_match(pattern: re.Pattern[str], text: str, desc: str) -> str:
    match = pattern.search(text)
    if not match:
        raise RuntimeError(f"can not find {desc}")
    return match.group(1)


def resolve_paths(args: argparse.Namespace) -> tuple[pathlib.Path, pathlib.Path]:
    workbench = args.workbench.expanduser().resolve()
    npc_home = args.npc_home.expanduser().resolve() if args.npc_home else workbench / "npc"
    return workbench, npc_home


def resolve_yosys_bin(workbench: pathlib.Path, override: pathlib.Path | None) -> pathlib.Path:
    if override is not None:
        return override.expanduser().resolve()

    candidates: list[pathlib.Path] = []
    path_yosys = shutil.which("yosys")
    if path_yosys:
        candidates.append(pathlib.Path(path_yosys))
    candidates.extend(
        [
            workbench / ".tmp" / "ysyx-ci-tools" / "oss-cad-suite" / "bin" / "yosys",
            pathlib.Path.home() / "oss-cad-suite" / "bin" / "yosys",
            pathlib.Path.home() / "tools" / "oss-cad-suite" / "bin" / "yosys",
        ]
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise RuntimeError("yosys not found; pass --yosys-bin or put yosys on PATH")


def resolve_cache_dir(workbench: pathlib.Path, override: pathlib.Path | None) -> pathlib.Path:
    if override is not None:
        return override.expanduser().resolve()
    return (workbench / ".tmp" / "ysyx-ci-tools" / "yosys-sta-ci").resolve()


def resolve_ecc_bin(workbench: pathlib.Path, override: pathlib.Path | None) -> pathlib.Path:
    if override is not None:
        candidate = override.expanduser().resolve()
        if candidate.is_file() and candidate.stat().st_mode & 0o111:
            return candidate
        raise RuntimeError(f"ecc executable not found or not executable: {candidate}")

    candidates: list[pathlib.Path] = []
    path_ecc = shutil.which("ecc")
    if path_ecc:
        candidates.append(pathlib.Path(path_ecc))
    candidates.extend(
        [
            workbench / ".tmp" / "ecc-bin" / "ecc",
            workbench / ".tmp" / "ecc" / "ecc",
            workbench / ".tmp" / "ecos-studio" / "ecc",
        ]
    )
    for candidate in candidates:
        if candidate.is_file() and candidate.stat().st_mode & 0o111:
            return candidate.resolve()
    raise RuntimeError("ecc not found; pass --ecc-bin or put ecc on PATH")


def load_ecc_config(project: pathlib.Path, expected_top: str | None = None) -> tuple[pathlib.Path, str]:
    config_path = project / "ecc.toml"
    if not config_path.is_file():
        raise RuntimeError(f"ECC project config does not exist: {config_path}")
    try:
        with config_path.open("rb") as fp:
            config = tomllib.load(fp)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise RuntimeError(f"can not read ECC project config: {config_path}: {exc}") from exc

    design_cfg = config.get("design")
    if not isinstance(design_cfg, dict):
        raise RuntimeError(f"ECC config has no [design] section: {config_path}")
    rtl = design_cfg.get("rtl")
    if not isinstance(rtl, list) or len(rtl) != 1 or not isinstance(rtl[0], str):
        raise RuntimeError("ECC flow wrapper requires exactly one design.rtl entry")
    top = design_cfg.get("top")
    if not isinstance(top, str) or not top:
        raise RuntimeError("ECC config has no design.top")
    if expected_top is not None and top != expected_top:
        raise RuntimeError(f"ECC design.top does not match CI design: {top} != {expected_top}")

    flow_cfg = config.get("flow")
    if not isinstance(flow_cfg, dict):
        flow_cfg = {}
    preset = flow_cfg.get("preset", "rtl2gds")
    configured_run = flow_cfg.get("run", "default")
    if not isinstance(preset, str) or not preset:
        raise RuntimeError("ECC config has an invalid flow.preset")
    if not isinstance(configured_run, str) or not configured_run:
        raise RuntimeError("ECC config has an invalid flow.run")
    if preset != "syn_sta":
        raise RuntimeError(
            f"ECC Fmax evaluation requires [flow] preset = \"syn_sta\"; "
            f"got {preset!r} in {config_path}"
        )
    return (project / rtl[0]).resolve(), configured_run


def resolve_ecc_run_dir(project: pathlib.Path, run_id: str) -> pathlib.Path:
    requested = pathlib.Path(run_id).expanduser()
    if requested.is_absolute():
        return requested.resolve()
    return (project / "runs" / requested).resolve()


def parse_ecc_synthesis_timing(run_dir: pathlib.Path) -> tuple[float, float, pathlib.Path]:
    candidates: list[tuple[float, float, pathlib.Path]] = []
    for report in sorted(run_dir.rglob("qor_summary.json")):
        relative_parts = report.relative_to(run_dir).parts
        if not any("synthesis" in part.lower() for part in relative_parts):
            continue
        try:
            data = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        summary = data.get("summary")
        if not isinstance(summary, dict):
            continue
        setup = summary.get("setup")
        if not isinstance(setup, dict):
            continue
        fmax = setup.get("frequency_mhz")
        slack = setup.get("wns")
        if (
            isinstance(fmax, (int, float))
            and not isinstance(fmax, bool)
            and fmax > 0
            and isinstance(slack, (int, float))
            and not isinstance(slack, bool)
        ):
            candidates.append((float(fmax), float(slack), report))
    if not candidates:
        raise RuntimeError(f"ECC synthesis run has no timing qor_summary.json: {run_dir}")
    # ECC can leave duplicate summaries under the synthesis stage.  Use the
    # conservative minimum frequency and ignore all physical-stage reports.
    return min(candidates, key=lambda item: (item[0], item[1]))


def run_ecc(
    *,
    project: pathlib.Path,
    ecc_bin: pathlib.Path,
    vfile: pathlib.Path,
    design: str,
    run_id: str | None,
    timeout_seconds: float | None = None,
    log_name: str = "eval_ci_area.ecc.log",
    echo: bool = True,
) -> EccResult:
    project = project.expanduser().resolve()
    if not project.is_dir():
        raise RuntimeError(f"ECC project does not exist: {project}")
    ecc_rtl, configured_run = load_ecc_config(project, design)
    ecc_rtl.parent.mkdir(parents=True, exist_ok=True)
    if ecc_rtl != vfile.resolve():
        shutil.copy2(vfile, ecc_rtl)

    effective_run = run_id or configured_run
    run_dir = resolve_ecc_run_dir(project, effective_run)
    check_cmd = [str(ecc_bin), "check", "--project", str(project), "--plain"]
    eprint("+", " ".join(check_cmd))
    try:
        check = subprocess.run(
            check_cmd,
            cwd=str(project),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
        )
        check_output = check.stdout or ""
    except subprocess.TimeoutExpired as exc:
        check_output = _timeout_output(exc)
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / log_name).write_text(check_output, encoding="utf-8")
        raise RuntimeError(f"ecc check timed out; log: {run_dir / log_name}") from exc
    if echo and check_output:
        print(check_output, end="")
    if check.returncode != 0:
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / log_name).write_text(check_output, encoding="utf-8")
        raise RuntimeError(f"ecc check failed with exit code {check.returncode}; log: {run_dir / log_name}")

    run_cmd = [str(ecc_bin), "run", "--project", str(project), "--overwrite", "--plain"]
    if run_id:
        run_cmd.extend(["--run-id", run_id])
    eprint("+", " ".join(run_cmd))
    try:
        result = subprocess.run(
            run_cmd,
            cwd=str(project),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
        )
        run_output = result.stdout or ""
    except subprocess.TimeoutExpired as exc:
        run_output = _timeout_output(exc)
        run_dir.mkdir(parents=True, exist_ok=True)
        ecc_log = run_dir / log_name
        ecc_log.write_text(check_output + run_output, encoding="utf-8")
        raise RuntimeError(f"ecc run timed out; log: {ecc_log}") from exc
    run_dir.mkdir(parents=True, exist_ok=True)
    ecc_log = run_dir / log_name
    ecc_log.write_text(check_output + run_output, encoding="utf-8")
    if echo and run_output:
        print(run_output, end="")
    if result.returncode != 0:
        raise RuntimeError(f"ecc run failed with exit code {result.returncode}; log: {ecc_log}")

    fmax_mhz, worst_slack_ns, report = parse_ecc_synthesis_timing(run_dir)
    return EccResult(
        fmax_mhz=fmax_mhz,
        worst_slack_ns=worst_slack_ns,
        run_dir=str(run_dir),
        report=str(report),
    )


def _timeout_output(exc: subprocess.TimeoutExpired) -> str:
    output = exc.output or exc.stdout or ""
    if isinstance(output, bytes):
        output = output.decode(errors="replace")
    return str(output) + "\n[timeout]\n"


def read_stuid(workbench: pathlib.Path, override: str | None) -> str:
    if override:
        digits = override
    else:
        text = (workbench / "Makefile").read_text()
        match = STUID_RE.search(text)
        if not match:
            raise RuntimeError(f"can not find STUID in {workbench / 'Makefile'}")
        digits = match.group(1)
    if not re.fullmatch(r"\d{8}", digits):
        raise RuntimeError(f"invalid STUID digits: {digits}")
    return digits


def choose_vfile(npc_home: pathlib.Path, design: str) -> pathlib.Path:
    file_sv = npc_home / "build" / f"{design}.sv"
    file_v = npc_home / "build" / f"{design}.v"
    if file_sv.is_file():
        vfile = file_sv
    elif file_v.is_file():
        vfile = file_v
    else:
        raise RuntimeError(f"{file_sv} or {file_v} does not exist")
    timestamp = npc_home / ".timestamp"
    if not timestamp.exists():
        raise RuntimeError(f"{timestamp} does not exist")
    if timestamp.stat().st_mtime_ns > vfile.stat().st_mtime_ns:
        raise RuntimeError(f"{vfile} is older than {timestamp}")
    return vfile.resolve()


def ensure_verilog(npc_home: pathlib.Path) -> None:
    timestamp = npc_home / ".timestamp"
    run(["make", "-C", str(npc_home), "clean"])
    timestamp.touch()
    run(["make", "-C", str(npc_home), "verilog"])


def ensure_cache(cache_dir: pathlib.Path, branch: str) -> None:
    cache_dir.parent.mkdir(parents=True, exist_ok=True)
    if not cache_dir.exists():
        run(["git", "clone", "-b", branch, "https://github.com/OSCPU/yosys-sta", str(cache_dir)])

    def has_local_branch() -> bool:
        result = subprocess.run(
            ["git", "-C", str(cache_dir), "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"],
            check=False,
        )
        return result.returncode == 0

    def has_toolchain() -> bool:
        return (cache_dir / "bin" / "iEDA").exists() and (cache_dir / "pdk" / "nangate45").exists()

    # The generated iEDA/PDK tree is intentionally kept outside git.  Once a
    # checkout has both it and the requested local branch, it is ready for the
    # CI flow and should not require a network round trip on every evaluation.
    if has_local_branch() and has_toolchain():
        return

    try:
        shallow_file = cache_dir / ".git" / "shallow"
        if shallow_file.exists():
            run(["git", "-C", str(cache_dir), "fetch", "--unshallow", "origin", branch])
        else:
            run(["git", "-C", str(cache_dir), "fetch", "origin", branch])
        run(["git", "-C", str(cache_dir), "checkout", "-B", branch, "FETCH_HEAD"])
    except subprocess.CalledProcessError:
        # A ready local cache is sufficient even if refreshing origin is
        # temporarily unavailable (for example, a transient TLS failure).
        if has_local_branch() and has_toolchain():
            eprint(f"warning: unable to refresh {cache_dir}; using ready local cache")
            return
        raise

    if not has_toolchain():
        run(["make", "-C", str(cache_dir), "init"])


def make_temp_clone(cache_dir: pathlib.Path, branch: str) -> pathlib.Path:
    run_dir = pathlib.Path(tempfile.mkdtemp(prefix="ysyx-ci-area-"))
    run(["git", "clone", "--shared", "--branch", branch, str(cache_dir), str(run_dir)])
    for name in ("bin", "pdk"):
        src = cache_dir / name
        dst = run_dir / name
        if src.exists() and not dst.exists():
            dst.symlink_to(src, target_is_directory=True)
    return run_dir


def build_env(yosys_bin: pathlib.Path) -> dict[str, str]:
    if not yosys_bin.exists():
        raise RuntimeError(f"yosys not found: {yosys_bin}")
    env = os.environ.copy()
    env["PATH"] = f"{yosys_bin.parent}:{env.get('PATH', '')}"
    fallback_tmp = pathlib.Path(tempfile.gettempdir()).resolve()
    if not fallback_tmp.is_dir():
        fallback_tmp = pathlib.Path("/tmp")
    for key in ("TMPDIR", "TMP", "TEMP"):
        current = env.get(key)
        if not current or not pathlib.Path(current).expanduser().is_dir():
            env[key] = str(fallback_tmp)
    return env


def run_sta(
    run_dir: pathlib.Path,
    *,
    env: dict[str, str],
    design: str,
    vfile: pathlib.Path,
) -> AreaResult:
    run(
        [
            "make",
            "-C",
            str(run_dir),
            "clean",
            "sta",
            f"DESIGN={design}",
            "CLK_FREQ_MHZ=500",
            "CLK_PORT_NAME=clock",
            f"RTL_FILES={vfile}",
        ],
        env=env,
    )
    result_dir = run_dir / "result" / f"{design}-500MHz"
    log_path = result_dir / "yosys-fixed.log"
    area = parse_area(log_path)
    return AreaResult(area=area, result_dir=str(result_dir))


def parse_area(log_path: pathlib.Path) -> float:
    text = log_path.read_text()
    matches = AREA_RE.findall(text)
    if not matches:
        raise RuntimeError(f"can not obtain area from {log_path}")
    return float(matches[-1])


def verify_module_name(log_path: pathlib.Path, design: str) -> None:
    text = log_path.read_text()
    frontend_done = "Successfully finished Verilog frontend."
    end_idx = text.find(frontend_done)
    if end_idx < 0:
        raise RuntimeError(f"can not find frontend marker in {log_path}")
    checked = text[:end_idx]
    bad_modules = [name for name in MODULE_RE.findall(checked) if not name.startswith(design)]
    if bad_modules:
        raise RuntimeError(f"there exist modules which do not start with {design}: {bad_modules}")


def verify_no_latch(stat_path: pathlib.Path) -> None:
    text = stat_path.read_text()
    if "DLL" in text or "DLH" in text:
        raise RuntimeError("the design contains latch, which is not allowed")


def copy_new_result(run_dir: pathlib.Path, design: str) -> pathlib.Path:
    src = run_dir / "result" / f"{design}-500MHz"
    dst = run_dir / "saved-result" / f"{design}-500MHz.new-flow"
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst)
    return dst


def revert_old_flow(run_dir: pathlib.Path, commit: str) -> None:
    run(["git", "-C", str(run_dir), "config", "user.email", "ci@ysyx.org"])
    run(["git", "-C", str(run_dir), "config", "user.name", "ysyx-ci"])
    run(["git", "-C", str(run_dir), "revert", "--no-edit", commit])


def print_summary(summary: EvalSummary) -> None:
    new_ok = summary.new_flow.area <= summary.ci.area_budget
    old_ok = summary.old_flow.area <= summary.ci.area_old_budget
    print(f"workbench : {summary.workbench}")
    print(f"ci repo   : {summary.ci_repo}")
    print(f"vfile     : {summary.vfile}")
    print(f"yosys     : {summary.yosys_bin}")
    print(f"new area  : {summary.new_flow.area:.3f} / {summary.ci.area_budget:.0f} ({'PASS' if new_ok else 'FAIL'})")
    print(f"old area  : {summary.old_flow.area:.3f} / {summary.ci.area_old_budget:.0f} ({'PASS' if old_ok else 'FAIL'})")
    print(f"ci result : {'PASS' if summary.pass_ci else 'FAIL'}")
    if summary.ecc is None:
        print("ecc       : skipped")
    else:
        print(
            f"ecc fmax  : {summary.ecc.fmax_mhz:.3f} MHz, "
            f"slack {summary.ecc.worst_slack_ns:.3f} ns (synthesis)"
        )
        print(f"ecc report: {summary.ecc.report}")
    if summary.run_dir:
        print(f"run dir   : {summary.run_dir}")


def maybe_write_json(summary: EvalSummary, json_out: pathlib.Path | None) -> None:
    if not json_out:
        return
    json_out.parent.mkdir(parents=True, exist_ok=True)
    json_out.write_text(json.dumps(asdict(summary), indent=2) + "\n")


def main() -> int:
    args = parse_args()
    workbench, npc_home = resolve_paths(args)
    ci_repo = find_ci_repo(workbench, args.ci_repo)
    workflow_path = ci_repo / ".github" / "workflows" / "autotest.yml"
    ci = parse_ci_config(workflow_path)
    stuid = read_stuid(workbench, args.stuid)
    design = f"ysyx_{stuid}"
    yosys_bin = resolve_yosys_bin(workbench, args.yosys_bin)
    cache_dir = resolve_cache_dir(workbench, args.cache_dir)

    if args.refresh_verilog:
        ensure_verilog(npc_home)
    vfile = choose_vfile(npc_home, design)
    ensure_cache(cache_dir, ci.yosys_sta_branch)

    env = build_env(yosys_bin)
    run_dir: pathlib.Path | None = None
    try:
        run_dir = make_temp_clone(cache_dir, ci.yosys_sta_branch)
        new_flow = run_sta(run_dir, env=env, design=design, vfile=vfile)
        verify_module_name(pathlib.Path(new_flow.result_dir) / "yosys.log", design)
        verify_no_latch(pathlib.Path(new_flow.result_dir) / "synth_stat.txt")
        new_flow = AreaResult(
            area=new_flow.area,
            result_dir=str(copy_new_result(run_dir, design)),
        )

        revert_old_flow(run_dir, ci.revert_commit)
        old_flow = run_sta(run_dir, env=env, design=design, vfile=vfile)
        verify_module_name(pathlib.Path(old_flow.result_dir) / "yosys.log", design)
        verify_no_latch(pathlib.Path(old_flow.result_dir) / "synth_stat.txt")

        ecc = None
        if not args.skip_ecc:
            ecc_project = (
                args.ecc_project.expanduser().resolve()
                if args.ecc_project is not None
                else (workbench / ".tmp" / "ecc-project").resolve()
            )
            ecc_bin = resolve_ecc_bin(workbench, args.ecc_bin)
            ecc = run_ecc(
                project=ecc_project,
                ecc_bin=ecc_bin,
                vfile=vfile,
                design=design,
                run_id=args.ecc_run_id,
            )

        summary = EvalSummary(
            workbench=str(workbench),
            npc_home=str(npc_home),
            vfile=str(vfile),
            stuid=stuid,
            design=design,
            yosys_bin=str(yosys_bin),
            cache_dir=str(cache_dir),
            run_dir=str(run_dir) if args.keep_run_dir else None,
            ci_repo=str(ci_repo),
            ci=ci,
            new_flow=new_flow,
            old_flow=old_flow,
            pass_ci=(new_flow.area <= ci.area_budget) or (old_flow.area <= ci.area_old_budget),
            ecc=ecc,
        )
        print_summary(summary)
        maybe_write_json(summary, args.json_out.expanduser().resolve() if args.json_out else None)
        return 0 if summary.pass_ci else 1
    finally:
        if run_dir and run_dir.exists() and not args.keep_run_dir:
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
