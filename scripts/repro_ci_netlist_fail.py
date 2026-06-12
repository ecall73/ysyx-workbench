#!/usr/bin/env python3

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
import pathlib
import random
import re
import shutil
import string
import subprocess
import sys
import tempfile
from typing import Any


WORKFLOW_REL = pathlib.Path(".github/workflows/autotest.yml")
COMMON_ACTION_REL = pathlib.Path(".github/actions/common/action.yml")
MONITOR_REL = pathlib.Path("monitor.py")

HEX40_RE = re.compile(r"\b[0-9a-f]{40}\b")
STUID_LINE_RE = re.compile(r"^\s*STUID\s*=\s*ysyx_(\d{8})\s*$", re.MULTILINE)
AREA_RE = re.compile(r"Chip area for module '.*?': ([0-9.]+)")
FANOUT_NET_RE = re.compile(r"Find (\d+) Net with fanout violation")
FANOUT_BUF_RE = re.compile(r"Insert (\d+) Buffers")
AREA_ENV_RE = re.compile(r"\bAREA:\s*([0-9.]+)")
AREA_OLD_ENV_RE = re.compile(r"\bAREA_OLD:\s*([0-9.]+)")
TIMEOUT_CYCLE_RE = re.compile(r"TIMEOUT at cycle (\d+)")
WORKFLOW_STA_BRANCH_RE = re.compile(r"git clone -b ([^\s]+) https://github\.com/OSCPU/yosys-sta")
WORKFLOW_REVERT_RE = re.compile(r"git revert --no-edit ([0-9a-f]{40})")
WORKFLOW_RELEASE_TAG_RE = re.compile(r"OSS_CAD_SUITE_RELEASE_TAG:\s*([0-9-]+)")


@dataclasses.dataclass
class HistoricalBaseline:
    stuid: str
    repo: str
    branch: str
    comment: str
    comment_commit: str | None
    makejobs: int
    expected_syn_area: float
    expected_fanout_nets: int
    expected_inserted_buffers: int
    expected_area: float
    expected_area_old: float
    expected_failure_line: str


@dataclasses.dataclass
class StageResult:
    name: str
    ok: bool
    log_path: str
    details: dict[str, Any]


@dataclasses.dataclass
class ReproSummary:
    run_root: str
    pinned_commit: str | None
    ci_repo: str
    workflow_path: str
    common_action_path: str
    monitor_path: str
    baseline: HistoricalBaseline
    stages: list[StageResult]


class StageError(RuntimeError):
    pass


class StageLogger:
    def __init__(self, path: pathlib.Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.fp = self.path.open("w", encoding="utf-8")

    def close(self) -> None:
        self.fp.close()

    def _stamp(self) -> str:
        return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")

    def line(self, text: str = "") -> None:
        self.fp.write(f"{self._stamp()} {text}\n")
        self.fp.flush()

    def group(self, text: str) -> None:
        self.line(f"##[group]Run {text}")

    def endgroup(self) -> None:
        self.line("##[endgroup]")

    def command_output(self, text: str) -> None:
        for line in text.splitlines():
            self.line(line)


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def copytree(src: pathlib.Path, dst: pathlib.Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst, symlinks=True)


def ensure_clean_dir(path: pathlib.Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Reproduce the historical CI netlist failure in /tmp.")
    parser.add_argument(
        "--ci-repo",
        type=pathlib.Path,
        default=pathlib.Path("/home/ecall73/ysyx-submit-test"),
        help="CI repo containing autotest.yml and monitor.py",
    )
    parser.add_argument(
        "--historical-log-dir",
        type=pathlib.Path,
        default=pathlib.Path("/home/ecall73/ysyx-workbench/.tmp/ci_fail_ref"),
        help="Directory containing historical parse/setup/yosys/netlist logs",
    )
    parser.add_argument(
        "--run-root",
        type=pathlib.Path,
        help="Keep all temp outputs under this /tmp directory. Defaults to a fresh /tmp/ysyx-ci-repro-* dir.",
    )
    parser.add_argument(
        "--oss-cad-suite",
        type=pathlib.Path,
        default=pathlib.Path("/home/ecall73/oss-cad-suite"),
        help="Existing local oss-cad-suite directory used to mirror the CI PATH layout",
    )
    parser.add_argument(
        "--pin-comment-commit",
        action="store_true",
        default=True,
        help="After cloning the target branch, checkout the 40-hex commit found in the historical comment.",
    )
    parser.add_argument(
        "--no-pin-comment-commit",
        action="store_false",
        dest="pin_comment_commit",
        help="Clone the branch tip exactly as-is without pinning the historical comment commit.",
    )
    parser.add_argument(
        "--keep-run-dir",
        action="store_true",
        help="Do not delete the /tmp run root after the script exits.",
    )
    return parser.parse_args()


def now_random_key() -> str:
    return "".join(random.choice(string.ascii_uppercase + string.digits) for _ in range(8))


def parse_historical_baseline(log_dir: pathlib.Path) -> HistoricalBaseline:
    parse_log = read_text(log_dir / "parse.log")
    setup_log = read_text(log_dir / "setup.log")
    yosys_log = read_text(log_dir / "yosys-sta.log")
    netlist_log = read_text(log_dir / "iverilog-netlist-microbench.log")

    stuid = must_search(re.compile(r"^\s*2026-.*\n(?:.*\n){0,3}.*\n", re.MULTILINE), parse_log, "parse log exists")  # sanity
    del stuid

    digits = must_search(re.compile(r"^\s*2026-.*26030082$", re.MULTILINE), parse_log, "historical STUID line")
    del digits
    stuid_value = "26030082"
    repo = must_capture(re.compile(r"https://github\.com/ecall73/ysyx-workbench"), parse_log, "historical repo")
    branch = must_capture(re.compile(r"^\s*2026-.*\n(?:.*\n){0,2}.*\n", re.MULTILINE), parse_log, "historical branch line")
    del branch
    branch_value = "ci"
    comment_line = must_search(re.compile(r"B4: icache .* [0-9a-f]{40}"), parse_log, "historical comment")
    comment_commit_match = HEX40_RE.search(comment_line)
    makejobs_line = must_search(re.compile(r"MAKEFLAGS: -j(\d+)"), setup_log, "historical MAKEFLAGS")
    makejobs = int(re.search(r"-j(\d+)", makejobs_line).group(1))

    syn_area_matches = AREA_RE.findall(yosys_log)
    if len(syn_area_matches) < 2:
        raise StageError("historical yosys-sta.log does not contain enough area samples")
    syn_area = float(syn_area_matches[0])
    fanout_nets = int(must_capture(FANOUT_NET_RE, yosys_log, "historical fanout net count"))
    inserted_buffers = int(must_capture(FANOUT_BUF_RE, yosys_log, "historical inserted buffer count"))
    area = float(must_capture(AREA_ENV_RE, yosys_log, "historical AREA"))
    area_old = float(must_capture(AREA_OLD_ENV_RE, yosys_log, "historical AREA_OLD"))
    failure_line = must_search(re.compile(r"CSR mvendorid=0xTIMEOUT at cycle 2000000"), netlist_log, "historical netlist failure line")

    return HistoricalBaseline(
        stuid=stuid_value,
        repo=repo,
        branch=branch_value,
        comment=comment_line,
        comment_commit=comment_commit_match.group(0) if comment_commit_match else None,
        makejobs=makejobs,
        expected_syn_area=syn_area,
        expected_fanout_nets=fanout_nets,
        expected_inserted_buffers=inserted_buffers,
        expected_area=area,
        expected_area_old=area_old,
        expected_failure_line=failure_line,
    )


def must_capture(pattern: re.Pattern[str], text: str, desc: str) -> str:
    match = pattern.search(text)
    if not match:
        raise StageError(f"can not find {desc}")
    if match.groups():
        return match.group(1)
    return match.group(0)


def must_search(pattern: re.Pattern[str], text: str, desc: str) -> str:
    match = pattern.search(text)
    if not match:
        raise StageError(f"can not find {desc}")
    return match.group(0)


def workflow_release_tag(workflow_text: str) -> str:
    return must_capture(WORKFLOW_RELEASE_TAG_RE, workflow_text, "OSS_CAD_SUITE_RELEASE_TAG")


def build_base_env(home: pathlib.Path, oss_cad_suite: pathlib.Path) -> dict[str, str]:
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["TEST_CI"] = "true"
    env["TZ"] = "Asia/Shanghai"
    if oss_cad_suite.exists():
        env["PATH"] = f"{oss_cad_suite / 'bin'}:{env.get('PATH', '')}"
    temp_dir = str(home / "tmp")
    pathlib.Path(temp_dir).mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = temp_dir
    env["TMP"] = temp_dir
    env["TEMP"] = temp_dir
    return env


def run_script(
    logger: StageLogger,
    script: str,
    *,
    cwd: pathlib.Path,
    env: dict[str, str],
    check: bool = True,
    display: str | None = None,
) -> subprocess.CompletedProcess[str]:
    shown = display if display is not None else script
    logger.group(shown)
    proc = subprocess.run(
        ["bash", "-lc", script],
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    logger.command_output(proc.stdout)
    logger.endgroup()
    if check and proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, shown, proc.stdout)
    return proc


def copy_ci_repo_to_job(ci_repo: pathlib.Path, dst: pathlib.Path) -> pathlib.Path:
    job_repo = dst / ci_repo.name
    copytree(ci_repo, job_repo)
    return job_repo


def parse_ci_job(repo_root: pathlib.Path, baseline: HistoricalBaseline, run_root: pathlib.Path) -> StageResult:
    stage_root = run_root / "jobs" / "parse"
    ensure_clean_dir(stage_root)
    log_path = stage_root / "parse.log"
    logger = StageLogger(log_path)
    try:
        issue_body = (
            "### 一生一芯学号\n\n"
            f"{baseline.stuid}\n\n"
            "### 仓库URL\n\n"
            f"{baseline.repo}\n\n"
            "### 分支名\n\n"
            f"{baseline.branch}\n\n"
            "### 注释\n\n"
            f"{baseline.comment}\n\n"
            "### make参数\n\n"
            "- [ ] 不使用'-j'参数, 若cpu-tests等测试由于该参数而失败, 可以勾选此项\n"
        )
        logger.line("🆕 New Issue Created")
        logger.line("---------------------")
        logger.line("📌 Title: 26030082 fork smoke")
        logger.line("👤 Author: ecall73")
        logger.line("🔗 URL: https://github.com/ecall73/ysyx-submit-test/issues/2")
        logger.line("")
        logger.line("📝 Body Content:")
        for line in issue_body.splitlines():
            logger.line(line)
        logger.line(f"STUID={baseline.stuid}")
        logger.line(f"REPO={baseline.repo}")
        logger.line(f"BRANCH={baseline.branch}")
        logger.line(f"COMMENT={baseline.comment}")
        logger.line(f"MAKEJOBS={baseline.makejobs}")
        details = {
            "stuid": baseline.stuid,
            "repo": baseline.repo,
            "branch": baseline.branch,
            "comment": baseline.comment,
            "makejobs": baseline.makejobs,
        }
        return StageResult(name="parse", ok=True, log_path=str(log_path), details=details)
    finally:
        logger.close()


def install_mill(job_repo: pathlib.Path, env: dict[str, str], ysyx_home: pathlib.Path, logger: StageLogger) -> None:
    mill_dir = pathlib.Path(env["HOME"]) / ".local" / "bin"
    mill_dir.mkdir(parents=True, exist_ok=True)
    mill_bin = mill_dir / "mill"
    mill_version = "0.11.13"
    mill_version_file = ysyx_home / "npc" / ".mill-version"
    if mill_version_file.exists():
        mill_version = mill_version_file.read_text(encoding="utf-8").strip()
    if not mill_bin.exists():
        run_script(
            logger,
            "\n".join(
                [
                    "mkdir -p ~/.local/bin",
                    f'curl -L "https://github.com/com-lihaoyi/mill/releases/download/{mill_version}/{mill_version}" -o ~/.local/bin/mill',
                    "chmod +x ~/.local/bin/mill",
                ]
            ),
            cwd=job_repo,
            env=env,
            display="install mill",
        )
    env["PATH"] = f"{mill_dir}:{env.get('PATH', '')}"


def clone_yosys_sta(cache_root: pathlib.Path, branch: str, logger: StageLogger, cwd: pathlib.Path, env: dict[str, str]) -> pathlib.Path:
    cache_root.mkdir(parents=True, exist_ok=True)
    cache_dir = cache_root / "yosys-sta-cache"
    if not cache_dir.exists():
        run_script(
            logger,
            f"git clone -b {branch} https://github.com/OSCPU/yosys-sta {cache_dir}",
            cwd=cwd,
            env=env,
            display=f"git clone -b {branch} https://github.com/OSCPU/yosys-sta",
        )
        run_script(logger, "make init", cwd=cache_dir, env=env, display="make init")
    else:
        run_script(logger, f"git -C {cache_dir} fetch origin {branch}", cwd=cwd, env=env, display=f"git -C {cache_dir} fetch origin {branch}")
        run_script(logger, f"git -C {cache_dir} checkout -B {branch} origin/{branch}", cwd=cwd, env=env, display=f"git -C {cache_dir} checkout -B {branch} origin/{branch}")
    return cache_dir


def maybe_pin_commit(logger: StageLogger, env: dict[str, str], repo_dir: pathlib.Path, commit: str | None, pin: bool) -> str | None:
    if not pin or not commit:
        return None
    run_script(logger, f"git checkout {commit}", cwd=repo_dir, env=env, display=f"git checkout {commit}")
    return commit


def setup_job(
    ci_repo: pathlib.Path,
    workflow_text: str,
    baseline: HistoricalBaseline,
    run_root: pathlib.Path,
    oss_cad_suite: pathlib.Path,
    pin_comment_commit: bool,
) -> tuple[StageResult, dict[str, str]]:
    stage_root = run_root / "jobs" / "setup"
    ensure_clean_dir(stage_root)
    job_repo = copy_ci_repo_to_job(ci_repo, stage_root)
    log_path = stage_root / "setup.log"
    logger = StageLogger(log_path)
    home = stage_root / "home"
    env = build_base_env(home, oss_cad_suite)
    env["OSS_CAD_SUITE_RELEASE_TAG"] = workflow_release_tag(workflow_text)
    outputs: dict[str, str] = {}
    try:
        run_script(logger, 'git config --global user.email "ci@ysyx.org"\ngit config --global user.name "ysyx-ci"', cwd=job_repo, env=env, display='git config --global user.email "ci@ysyx.org"')
        temp_dir = pathlib.Path(tempfile.mkdtemp(prefix="tmp.", dir=job_repo))
        ysyx_home = temp_dir / "ysyx-workbench"
        outputs["YSYX_HOME"] = str(ysyx_home)
        logger.line(f"YSYX_HOME={ysyx_home}")

        run_script(
            logger,
            "\n".join(
                [
                    f"mkdir -p {ysyx_home}",
                    f"cd {ysyx_home.parent}",
                    f"git clone --depth 1 -b {baseline.branch} {baseline.repo} ysyx-workbench",
                ]
            ),
            cwd=job_repo,
            env=env,
            display=f"git clone --depth 1 -b {baseline.branch} {baseline.repo} ysyx-workbench",
        )
        pinned_commit = maybe_pin_commit(logger, env, ysyx_home, baseline.comment_commit, pin_comment_commit)
        if pinned_commit:
            outputs["PINNED_COMMIT"] = pinned_commit

        run_script(
            logger,
            "\n".join(
                [
                    f"cd {ysyx_home}",
                    "git checkout --orphan tmp-ci",
                    'git commit -m "orphan branch created by CI"',
                    f"cd {ysyx_home.parent}",
                    f"git clone -b tmp-ci file://{ysyx_home} ysyx-workbench-ci",
                    "rm -rf ysyx-workbench",
                    "mv ysyx-workbench-ci ysyx-workbench",
                    f"cd {ysyx_home}",
                    f"git remote set-url origin {baseline.repo}",
                ]
            ),
            cwd=job_repo,
            env=env,
            display='git checkout --orphan tmp-ci',
        )

        makefile_text = read_text(ysyx_home / "Makefile")
        match = STUID_LINE_RE.search(makefile_text)
        if not match:
            raise StageError("Missing STUID in Makefile")
        stuid = match.group(1)
        if stuid != baseline.stuid:
            raise StageError(f"STUID mismatch: {stuid} != {baseline.stuid}")

        tracer_script = "\n".join(
            [
                f"cd {ysyx_home}",
                "git fetch origin tracer-ysyx:tracer-ysyx",
                f"git log tracer-ysyx --author='tracer-ysyx <tracer@ysyx.org>' --grep='{baseline.stuid}' --oneline > log.txt",
                "NR_COMPILE_NEMU=$(grep 'compile NEMU' log.txt | wc -l)",
                "NR_RUN_NEMU=$(grep 'run NEMU' log.txt | wc -l)",
                "NR_GDB_NEMU=$(grep 'gdb NEMU' log.txt | wc -l)",
                "NR_SIM_RTL=$(grep 'sim RTL' log.txt | wc -l)",
                'echo "compile NEMU - $NR_COMPILE_NEMU"',
                'echo "run NEMU - $NR_RUN_NEMU"',
                'echo "gdb NEMU - $NR_GDB_NEMU"',
                'echo "sim RTL - $NR_SIM_RTL"',
                "test \"$NR_COMPILE_NEMU\" -gt 0",
                "test \"$NR_RUN_NEMU\" -gt 0",
                "test \"$NR_SIM_RTL\" -gt 0",
            ]
        )
        run_script(logger, tracer_script, cwd=job_repo, env=env, display="parse tracer-ysyx")

        outputs["NEMU_HOME"] = str(ysyx_home / "nemu")
        outputs["AM_HOME"] = str(ysyx_home / "abstract-machine")
        outputs["NAVY_HOME"] = str(ysyx_home / "navy-apps")
        outputs["NPC_HOME"] = str(ysyx_home / "npc")
        outputs["NVBOARD_HOME"] = str(ysyx_home / "nvboard")
        outputs["MAKEFLAGS"] = f"-j{baseline.makejobs}"
        env.update(outputs)

        run_script(
            logger,
            "\n".join(
                [
                    'test -e "$AM_HOME/tools/insert-arg.py"',
                    "sed -i -e 's/MAINARGS_PLACEHOLDER = .*/MAINARGS_PLACEHOLDER = the_insert-arg_rule_in_Makefile_will_insert_mainargs_here/' $AM_HOME/scripts/platform/npc.mk",
                ]
            ),
            cwd=job_repo,
            env=env,
            display='test -e "$AM_HOME/tools/insert-arg.py"',
        )
        run_script(
            logger,
            "\n".join(
                [
                    "cd $YSYX_HOME",
                    "echo '.git_commit:' >> Makefile",
                    "printf '\\t@echo git tracer is disabled\\n' >> Makefile",
                ]
            ),
            cwd=job_repo,
            env=env,
            display="disable git tracer",
        )
        run_script(
            logger,
            "\n".join(
                [
                    "SIZE=$(du -sb $YSYX_HOME/patch | grep -o '^[0-9]*')",
                    'test "$SIZE" -le 1048576',
                ]
            ),
            cwd=job_repo,
            env=env,
            display="check patch size",
        )
        install_mill(job_repo, env, ysyx_home, logger)

        run_script(logger, "make -C $NEMU_HOME clean\nmake -C $AM_HOME clean-all\nmake -C $NPC_HOME clean", cwd=job_repo, env=env, display="make clean")
        run_script(logger, "touch $NPC_HOME/.timestamp\nmake -C $NPC_HOME verilog", cwd=job_repo, env=env, display="make -C $NPC_HOME verilog")

        vfile = ysyx_home / "npc" / "build" / f"ysyx_{baseline.stuid}.v"
        vfile_sv = ysyx_home / "npc" / "build" / f"ysyx_{baseline.stuid}.sv"
        chosen = vfile_sv if vfile_sv.exists() else vfile
        if not chosen.exists():
            raise StageError(f"missing verilog file: {vfile_sv} or {vfile}")
        logger.line(f"Find {chosen}")
        if (ysyx_home / "npc" / ".timestamp").stat().st_mtime_ns > chosen.stat().st_mtime_ns:
            raise StageError(f"{chosen} is older than .timestamp")
        outputs["VFILE"] = str(chosen)
        env["VFILE"] = str(chosen)

        run_script(
            logger,
            "\n".join(
                [
                    "VFILE=$VFILE",
                    f"grep -E 'module\\s+ysyx_{baseline.stuid}' \"$VFILE\" >/dev/null",
                    '! grep "negedge" "$VFILE" >/dev/null',
                ]
            ),
            cwd=job_repo,
            env=env,
            display="verify generated verilog",
        )

        artifact_dir = stage_root / "artifacts"
        artifact_dir.mkdir(parents=True, exist_ok=True)
        verilog_artifact = artifact_dir / chosen.name
        shutil.copy2(chosen, verilog_artifact)
        logger.line(f"Artifact verilog saved to {verilog_artifact}")

        workbench_tgz = artifact_dir / "ysyx-workbench.tar.gz"
        run_script(
            logger,
            f"cd {ysyx_home.parent}\ntar -czf {workbench_tgz} ysyx-workbench",
            cwd=job_repo,
            env=env,
            display="tar workbench artifact",
        )
        logger.line(f"Artifact workbench saved to {workbench_tgz}")
        outputs["WORKBENCH_ARTIFACT"] = str(workbench_tgz)
        outputs["VERILOG_ARTIFACT"] = str(verilog_artifact)

        details = {
            "ysyx_home": outputs["YSYX_HOME"],
            "vfile": outputs["VFILE"],
            "makeflags": outputs["MAKEFLAGS"],
            "workbench_artifact": outputs["WORKBENCH_ARTIFACT"],
            "verilog_artifact": outputs["VERILOG_ARTIFACT"],
            "pinned_commit": outputs.get("PINNED_COMMIT"),
        }
        return StageResult(name="setup", ok=True, log_path=str(log_path), details=details), outputs
    except subprocess.CalledProcessError as exc:
        raise StageError(f"setup command failed: {exc.cmd}") from exc
    finally:
        logger.close()


def common_action(
    ci_repo: pathlib.Path,
    setup_outputs: dict[str, str],
    run_root: pathlib.Path,
    job_name: str,
    oss_cad_suite: pathlib.Path,
    install_toolchain: bool,
) -> tuple[pathlib.Path, pathlib.Path, StageLogger, dict[str, str]]:
    stage_root = run_root / "jobs" / job_name
    ensure_clean_dir(stage_root)
    job_repo = copy_ci_repo_to_job(ci_repo, stage_root)
    home = stage_root / "home"
    env = build_base_env(home, oss_cad_suite)
    env["OSS_CAD_SUITE_RELEASE_TAG"] = "2025-11-24"
    logger = StageLogger(stage_root / f"{job_name}.log")

    artifact_tgz = pathlib.Path(setup_outputs["WORKBENCH_ARTIFACT"])
    temp_dir = pathlib.Path(tempfile.mkdtemp(prefix="tmp.", dir=job_repo))
    ysyx_home = temp_dir / "ysyx-workbench"
    run_script(
        logger,
        f"mkdir -p {temp_dir}\ncd {temp_dir}\ntar -xzf {artifact_tgz}",
        cwd=job_repo,
        env=env,
        display="extract workbench artifact",
    )

    env["MONITOR_PY"] = str(job_repo / MONITOR_REL)
    env["YSYX_HOME"] = str(ysyx_home)
    env["NEMU_HOME"] = str(ysyx_home / "nemu")
    env["AM_HOME"] = str(ysyx_home / "abstract-machine")
    env["NAVY_HOME"] = str(ysyx_home / "navy-apps")
    env["NPC_HOME"] = str(ysyx_home / "npc")
    env["NVBOARD_HOME"] = str(ysyx_home / "nvboard")
    env["MAKEFLAGS"] = setup_outputs["MAKEFLAGS"]

    install_mill(job_repo, env, ysyx_home, logger)

    if install_toolchain:
        run_script(
            logger,
            "command -v riscv64-linux-gnu-gcc >/dev/null\ncommand -v llvm-objcopy >/dev/null || command -v llvm-objcopy-14 >/dev/null || true",
            cwd=job_repo,
            env=env,
            display="check local toolchain",
        )

    run_script(
        logger,
        "\n".join(
            [
                "git config --global user.email 'ci@ysyx.org'",
                "git config --global user.name 'ysyx-ci'",
                "cd $YSYX_HOME",
                "git clone --depth 1 -b ci https://github.com/NJU-ProjectN/am-kernels",
                "git clone --depth 1 https://github.com/NJU-ProjectN/rt-thread-am",
                "cd rt-thread-am",
                "git am $YSYX_HOME/patch/rt-thread-am/*",
            ]
        ),
        cwd=job_repo,
        env=env,
        display="common clone other repos",
    )

    return stage_root, job_repo, logger, env


def parse_area_from_file(path: pathlib.Path) -> float:
    text = read_text(path)
    matches = AREA_RE.findall(text)
    if not matches:
        raise StageError(f"missing area in {path}")
    return float(matches[-1])


def verify_yosys_strong_checkpoints(
    baseline: HistoricalBaseline,
    result_dir: pathlib.Path,
    logger: StageLogger,
) -> dict[str, Any]:
    yosys_log = result_dir / "yosys.log"
    fixfanout_log = result_dir / "fix-fanout.log"
    yosys_fixed_log = result_dir / "yosys-fixed.log"

    syn_area = parse_area_from_file(yosys_log)
    fix_text = read_text(fixfanout_log)
    fixed_text = read_text(yosys_fixed_log)
    fanout_nets = int(must_capture(FANOUT_NET_RE, fix_text, "fanout net count"))
    inserted_buffers = int(must_capture(FANOUT_BUF_RE, fix_text, "inserted buffer count"))
    fixed_area = parse_area_from_file(yosys_fixed_log)

    checks = {
        "syn_area": syn_area,
        "fanout_nets": fanout_nets,
        "inserted_buffers": inserted_buffers,
        "fixed_area": fixed_area,
    }
    logger.line(f"checkpoint syn_area={syn_area:.6f}")
    logger.line(f"checkpoint fanout_nets={fanout_nets}")
    logger.line(f"checkpoint inserted_buffers={inserted_buffers}")
    logger.line(f"checkpoint fixed_area={fixed_area:.6f}")

    if abs(syn_area - baseline.expected_syn_area) > 1e-6:
        raise StageError(f"yosys syn area diverged: {syn_area} != {baseline.expected_syn_area}")
    if fanout_nets != baseline.expected_fanout_nets:
        raise StageError(f"fanout net count diverged: {fanout_nets} != {baseline.expected_fanout_nets}")
    if inserted_buffers != baseline.expected_inserted_buffers:
        raise StageError(
            f"inserted buffer count diverged: {inserted_buffers} != {baseline.expected_inserted_buffers}"
        )
    if abs(fixed_area - baseline.expected_area) > 1e-6:
        raise StageError(f"fixed area diverged: {fixed_area} != {baseline.expected_area}")
    return checks


def yosys_sta_job(
    ci_repo: pathlib.Path,
    workflow_text: str,
    baseline: HistoricalBaseline,
    setup_outputs: dict[str, str],
    run_root: pathlib.Path,
    oss_cad_suite: pathlib.Path,
) -> tuple[StageResult, dict[str, str]]:
    stage_root, job_repo, logger, env = common_action(
        ci_repo,
        setup_outputs,
        run_root,
        "yosys-sta",
        oss_cad_suite,
        install_toolchain=False,
    )
    outputs: dict[str, str] = {}
    try:
        branch = must_capture(WORKFLOW_STA_BRANCH_RE, workflow_text, "yosys-sta branch")
        revert_commit = must_capture(WORKFLOW_REVERT_RE, workflow_text, "yosys-sta revert commit")
        yosys_sta = clone_yosys_sta(run_root / "cache", branch, logger, job_repo, env)

        run_script(logger, "make -C $NPC_HOME verilog", cwd=job_repo, env=env, display="make -C $NPC_HOME verilog")
        env["STUID"] = baseline.stuid
        env["VFILE"] = setup_outputs["VFILE"]

        run_script(
            logger,
            f"make -C {yosys_sta} sta DESIGN=ysyx_{baseline.stuid} CLK_FREQ_MHZ=500 CLK_PORT_NAME=clock RTL_FILES=$VFILE",
            cwd=job_repo,
            env=env,
            display=f"make -C {yosys_sta} sta DESIGN=ysyx_{baseline.stuid}",
        )
        result_dir = yosys_sta / "result" / f"ysyx_{baseline.stuid}-500MHz"
        checkpoint_new = verify_yosys_strong_checkpoints(baseline, result_dir, logger)

        run_script(
            logger,
            "\n".join(
                [
                    f"git -C {yosys_sta} config user.email 'ci@ysyx.org'",
                    f"git -C {yosys_sta} config user.name 'ysyx-ci'",
                    f"git -C {yosys_sta} revert --no-edit {revert_commit}",
                    f"make -C {yosys_sta} clean",
                    f"make -C {yosys_sta} sta DESIGN=ysyx_{baseline.stuid} CLK_FREQ_MHZ=500 CLK_PORT_NAME=clock RTL_FILES=$VFILE",
                ]
            ),
            cwd=job_repo,
            env=env,
            display=f"git -C {yosys_sta} revert --no-edit {revert_commit}",
        )
        result_dir_old = yosys_sta / "result" / f"ysyx_{baseline.stuid}-500MHz"
        area_old = parse_area_from_file(result_dir_old / "yosys-fixed.log")
        logger.line(f"checkpoint area_old={area_old:.6f}")
        if abs(area_old - baseline.expected_area_old) > 1e-6:
            raise StageError(f"old-flow area diverged: {area_old} != {baseline.expected_area_old}")

        artifact_dir = stage_root / "artifacts"
        artifact_dir.mkdir(parents=True, exist_ok=True)
        netlist = result_dir_old / f"ysyx_{baseline.stuid}.netlist.fixed.v"
        netlist_artifact = artifact_dir / netlist.name
        shutil.copy2(netlist, netlist_artifact)
        logger.line(f"Artifact netlist saved to {netlist_artifact}")

        outputs["NETLIST_ARTIFACT"] = str(netlist_artifact)
        outputs["YOSYS_STA_CACHE"] = str(yosys_sta)
        details = {
            "netlist_artifact": outputs["NETLIST_ARTIFACT"],
            "yosys_sta_dir": outputs["YOSYS_STA_CACHE"],
            "new_flow": checkpoint_new,
            "area_old": area_old,
        }
        return StageResult(name="yosys-sta", ok=True, log_path=str(logger.path), details=details), outputs
    except subprocess.CalledProcessError as exc:
        raise StageError(f"yosys-sta command failed: {exc.cmd}") from exc
    finally:
        logger.close()


def iverilog_netlist_job(
    ci_repo: pathlib.Path,
    workflow_text: str,
    baseline: HistoricalBaseline,
    setup_outputs: dict[str, str],
    yosys_outputs: dict[str, str],
    run_root: pathlib.Path,
    oss_cad_suite: pathlib.Path,
) -> StageResult:
    stage_root, job_repo, logger, env = common_action(
        ci_repo,
        setup_outputs,
        run_root,
        "iverilog-netlist-microbench",
        oss_cad_suite,
        install_toolchain=True,
    )
    try:
        branch = must_capture(WORKFLOW_STA_BRANCH_RE, workflow_text, "yosys-sta branch")
        yosys_sta = clone_yosys_sta(run_root / "cache", branch, logger, job_repo, env)
        netlist_artifact = pathlib.Path(yosys_outputs["NETLIST_ARTIFACT"])
        downloaded_netlist = job_repo / netlist_artifact.name
        shutil.copy2(netlist_artifact, downloaded_netlist)
        logger.line(f"Downloaded netlist artifact to {downloaded_netlist}")

        run_script(
            logger,
            "make ARCH=riscv32e-npc -C $YSYX_HOME/am-kernels/benchmarks/microbench mainargs=the_insert-arg_rule_in_Makefile_will_insert_mainargs_here",
            cwd=job_repo,
            env=env,
            display="make ARCH=riscv32e-npc -C $YSYX_HOME/am-kernels/benchmarks/microbench mainargs=the_insert-arg_rule_in_Makefile_will_insert_mainargs_here",
        )

        key = now_random_key()
        env["KEY"] = key
        env["NETLIST"] = str(downloaded_netlist)
        env["CELLS"] = str(yosys_sta / "pdk" / "nangate45" / "sim" / "cells.v")
        env["IMG"] = str(pathlib.Path(env["YSYX_HOME"]) / "am-kernels" / "benchmarks" / "microbench" / "build" / "microbench-riscv32e-npc.bin")

        run_script(
            logger,
            "\n".join(
                [
                    "make -C $NPC_HOME clean",
                    'echo "mainargs=$KEY"',
                    "python $AM_HOME/tools/insert-arg.py $IMG 64 the_insert-arg_rule_in_Makefile_will_insert_mainargs_here $KEY",
                ]
            ),
            cwd=job_repo,
            env=env,
            display="prepare microbench image",
        )
        proc = run_script(
            logger,
            "python $MONITOR_PY --good=$KEY make -C $NPC_HOME sim-iverilog-netlist IMG=$IMG NETLIST=$NETLIST CELLS=$CELLS",
            cwd=job_repo,
            env=env,
            check=False,
            display="python $MONITOR_PY --good=$KEY make -C $NPC_HOME sim-iverilog-netlist IMG=$IMG NETLIST=$NETLIST CELLS=$CELLS",
        )

        log_text = read_text(logger.path)
        failure_line = must_search(re.compile(r"CSR mvendorid=0xTIMEOUT at cycle 2000000"), log_text, "expected failure line")
        if "Keyword not detected" not in log_text:
            raise StageError("monitor.py did not print Keyword not detected")
        if "Missing netlist simulation file" in log_text:
            raise StageError("unexpected missing netlist simulation file error")
        if "Missing cells simulation file" in log_text:
            raise StageError("unexpected missing cells simulation file error")
        if "BAD RESET FETCH" in log_text:
            raise StageError("unexpected BAD RESET FETCH")
        if "+ COPY" not in log_text or "+ BIN2HEX" not in log_text or "+ IVERILOG" not in log_text:
            raise StageError("missing one of + COPY / + BIN2HEX / + IVERILOG in netlist stage log")

        details = {
            "returncode": proc.returncode,
            "failure_line": failure_line,
            "keyword_not_detected": True,
            "copy_seen": "+ COPY" in log_text,
            "bin2hex_seen": "+ BIN2HEX" in log_text,
            "iverilog_seen": "+ IVERILOG" in log_text,
        }
        return StageResult(name="iverilog-netlist-microbench", ok=True, log_path=str(logger.path), details=details)
    finally:
        logger.close()


def save_summary(summary: ReproSummary, run_root: pathlib.Path) -> pathlib.Path:
    out = run_root / "checkpoints.json"
    out.write_text(json.dumps(dataclasses.asdict(summary), indent=2) + "\n", encoding="utf-8")
    return out


def print_stage_result(stage: StageResult) -> None:
    status = "PASS" if stage.ok else "FAIL"
    print(f"{stage.name}: {status}")
    print(f"  log: {stage.log_path}")
    for key, value in stage.details.items():
        print(f"  {key}: {value}")


def main() -> int:
    args = parse_args()
    ci_repo = args.ci_repo.expanduser().resolve()
    historical_log_dir = args.historical_log_dir.expanduser().resolve()
    workflow_path = ci_repo / WORKFLOW_REL
    common_action_path = ci_repo / COMMON_ACTION_REL
    monitor_path = ci_repo / MONITOR_REL
    workflow_text = read_text(workflow_path)
    baseline = parse_historical_baseline(historical_log_dir)

    run_root = args.run_root.expanduser().resolve() if args.run_root else pathlib.Path(
        tempfile.mkdtemp(prefix="ysyx-ci-repro-", dir="/tmp")
    )
    run_root.mkdir(parents=True, exist_ok=True)

    stages: list[StageResult] = []
    setup_outputs: dict[str, str] = {}
    yosys_outputs: dict[str, str] = {}
    try:
        parse_stage = parse_ci_job(ci_repo, baseline, run_root)
        stages.append(parse_stage)

        setup_stage, setup_outputs = setup_job(
            ci_repo,
            workflow_text,
            baseline,
            run_root,
            args.oss_cad_suite.expanduser().resolve(),
            args.pin_comment_commit,
        )
        stages.append(setup_stage)

        yosys_stage, yosys_outputs = yosys_sta_job(
            ci_repo,
            workflow_text,
            baseline,
            setup_outputs,
            run_root,
            args.oss_cad_suite.expanduser().resolve(),
        )
        stages.append(yosys_stage)

        netlist_stage = iverilog_netlist_job(
            ci_repo,
            workflow_text,
            baseline,
            setup_outputs,
            yosys_outputs,
            run_root,
            args.oss_cad_suite.expanduser().resolve(),
        )
        stages.append(netlist_stage)

        summary = ReproSummary(
            run_root=str(run_root),
            pinned_commit=setup_outputs.get("PINNED_COMMIT"),
            ci_repo=str(ci_repo),
            workflow_path=str(workflow_path),
            common_action_path=str(common_action_path),
            monitor_path=str(monitor_path),
            baseline=baseline,
            stages=stages,
        )
        summary_path = save_summary(summary, run_root)
        for stage in stages:
            print_stage_result(stage)
        print(f"checkpoints: {summary_path}")
        print(f"run root: {run_root}")
        print("result: reproduced historical failure")
        return 0
    except StageError as exc:
        failed = StageResult(
            name="driver",
            ok=False,
            log_path="",
            details={"error": str(exc)},
        )
        stages.append(failed)
        summary = ReproSummary(
            run_root=str(run_root),
            pinned_commit=setup_outputs.get("PINNED_COMMIT"),
            ci_repo=str(ci_repo),
            workflow_path=str(workflow_path),
            common_action_path=str(common_action_path),
            monitor_path=str(monitor_path),
            baseline=baseline,
            stages=stages,
        )
        summary_path = save_summary(summary, run_root)
        for stage in stages:
            print_stage_result(stage)
        print(f"checkpoints: {summary_path}")
        print(f"run root: {run_root}")
        return 2
    finally:
        if not args.keep_run_dir and run_root.exists():
            # Preserve logs for the caller on failure; only auto-clean on full success and explicit opt-out.
            pass


if __name__ == "__main__":
    raise SystemExit(main())
