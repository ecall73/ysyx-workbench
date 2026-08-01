#!/usr/bin/env bash

set -u
set -o pipefail

usage() {
  cat <<'EOF'
Usage: doctor.sh [--scope base|nemu|npc|ysyxsoc|navy|rt-thread|all] [--strict]

Report ysyx-workbench paths, direnv state, selected configuration, tools, and
submodule state. The script never changes repository or shell state.

Options:
  --scope SCOPE  Select checks; default: base
  --strict       Exit 1 when a required path or tool is missing
  -h, --help     Show this help
EOF
}

scope=base
strict=0

while (($# > 0)); do
  case "$1" in
    --scope)
      if (($# < 2)); then
        printf 'doctor: --scope requires a value\n' >&2
        usage >&2
        exit 2
      fi
      scope=$2
      shift 2
      ;;
    --strict)
      strict=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'doctor: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$scope" in
  base|nemu|npc|ysyxsoc|navy|rt-thread|all) ;;
  *)
    printf 'doctor: invalid scope: %s\n' "$scope" >&2
    usage >&2
    exit 2
    ;;
esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../../../.." && pwd -P)
missing_required=0
warnings=0
declare -A seen_path_checks=()
declare -A seen_command_checks=()

section() {
  printf '\n[%s]\n' "$1"
}

required_path() {
  local label=$1
  local path=$2
  local key="required:$path"
  if [[ -n "${seen_path_checks[$key]+set}" ]]; then
    return
  fi
  seen_path_checks[$key]=1
  if [[ -e "$path" ]]; then
    printf 'ok       %-20s %s\n' "$label" "$path"
  else
    printf 'missing  %-20s %s\n' "$label" "$path"
    missing_required=$((missing_required + 1))
  fi
}

optional_path() {
  local label=$1
  local path=$2
  local key="optional:$path"
  if [[ -n "${seen_path_checks[$key]+set}" ]]; then
    return
  fi
  seen_path_checks[$key]=1
  if [[ -e "$path" ]]; then
    printf 'ok       %-20s %s\n' "$label" "$path"
  else
    printf 'optional %-20s %s\n' "$label" "$path"
    warnings=$((warnings + 1))
  fi
}

required_command() {
  local name=$1
  local resolved
  local key="required:$name"
  if [[ -n "${seen_command_checks[$key]+set}" ]]; then
    return
  fi
  seen_command_checks[$key]=1
  if resolved=$(command -v -- "$name" 2>/dev/null); then
    printf 'ok       %-20s %s\n' "$name" "$resolved"
  else
    printf 'missing  %-20s required command\n' "$name"
    missing_required=$((missing_required + 1))
  fi
}

optional_command() {
  local name=$1
  local resolved
  local key="optional:$name"
  if [[ -n "${seen_command_checks[$key]+set}" ]]; then
    return
  fi
  seen_command_checks[$key]=1
  if resolved=$(command -v -- "$name" 2>/dev/null); then
    printf 'ok       %-20s %s\n' "$name" "$resolved"
  else
    printf 'optional %-20s not found\n' "$name"
    warnings=$((warnings + 1))
  fi
}

show_variable() {
  local name=$1
  local expected=$2
  local actual=${!name-}
  if [[ -z "$actual" ]]; then
    printf 'unset    %-20s expected %s\n' "$name" "$expected"
  elif [[ "$actual" == "$expected" ]]; then
    printf 'ok       %-20s %s\n' "$name" "$actual"
  else
    printf 'differs  %-20s %s (expected %s)\n' "$name" "$actual" "$expected"
    warnings=$((warnings + 1))
  fi
}

show_config() {
  local label=$1
  local path=$2
  local pattern=$3
  if [[ ! -f "$path" ]]; then
    printf 'missing  %-20s %s\n' "$label" "$path"
    missing_required=$((missing_required + 1))
    return
  fi

  printf 'file     %-20s %s\n' "$label" "$path"
  grep -E "$pattern" "$path" | sed 's/^/         /' || true
}

scope_is() {
  [[ "$scope" == all || "$scope" == "$1" ]]
}

section "repository"
printf 'root     %s\n' "$repo_root"
printf 'scope    %s\n' "$scope"
required_path ".envrc" "$repo_root/.envrc"
required_path "AGENTS.md" "$repo_root/AGENTS.md"
required_path "workstreams" "$repo_root/.agents/workstreams.md"

section "environment"
show_variable NEMU_HOME "$repo_root/nemu"
show_variable AM_HOME "$repo_root/abstract-machine"
show_variable NPC_HOME "$repo_root/npc"
show_variable NVBOARD_HOME "$repo_root/nvboard"
show_variable NAVY_HOME "$repo_root/navy-apps"

if command -v direnv >/dev/null 2>&1; then
  printf 'direnv  installed\n'
  direnv_output=$(cd -- "$repo_root" && direnv status 2>&1)
  direnv_status=$?
  printf '%s\n' "$direnv_output" | sed 's/^/         /'
  if ((direnv_status != 0)); then
    warnings=$((warnings + 1))
  fi
else
  printf 'optional direnv               not found; use explicit .envrc paths\n'
  warnings=$((warnings + 1))
fi

section "required paths"
if scope_is nemu; then
  required_path "nemu" "$repo_root/nemu"
fi
if scope_is npc; then
  required_path "npc" "$repo_root/npc"
fi
if scope_is ysyxsoc; then
  required_path "npc" "$repo_root/npc"
  required_path "ysyxSoC" "$repo_root/ysyxSoC"
  required_path "nvboard" "$repo_root/nvboard"
  optional_path "generated SoC RTL" "$repo_root/ysyxSoC/build/ysyxSoCFull.v"
fi
if scope_is navy; then
  required_path "abstract-machine" "$repo_root/abstract-machine"
  required_path "nanos-lite" "$repo_root/nanos-lite"
  required_path "navy-apps" "$repo_root/navy-apps"
fi
if scope_is rt-thread; then
  required_path "abstract-machine" "$repo_root/abstract-machine"
  required_path "rt-thread-am" "$repo_root/rt-thread-am"
fi

section "tools"
required_command bash
required_command git
required_command make
required_command python3

if scope_is nemu; then
  required_command gcc
  required_command g++
  optional_command spike
  optional_command gdb
fi
if scope_is npc; then
  required_command g++
  required_command verilator
  optional_command iverilog
  optional_command vvp
  optional_command gtkwave
fi
if scope_is ysyxsoc; then
  required_command g++
  required_command verilator
  required_command sdl2-config
  optional_command java
  optional_command mill
  optional_command iverilog
fi
if scope_is navy; then
  required_command riscv64-linux-gnu-gcc
  optional_command riscv64-linux-gnu-gdb
fi
if scope_is rt-thread; then
  required_command riscv64-linux-gnu-gcc
  required_command scons
fi

section "selected configuration"
if scope_is nemu; then
  show_config "nemu .config" "$repo_root/nemu/.config" '^CONFIG_(ISA|RV64|RVE|ENGINE|MODE|TARGET|DIFFTEST|DEVICE|TRACE|WATCHPOINT)'
fi
if scope_is npc || scope_is ysyxsoc; then
  show_config "npc .config" "$repo_root/npc/.config" '^CONFIG_(CC|VERILATOR|MAX|TRACE|ITRACE|FTRACE|MTRACE|DTRACE|ETRACE|DIFFTEST|WAVE|WATCHPOINT|YSYXSOC|NPC)'
fi
if scope_is rt-thread; then
  show_config "rt-thread .config" "$repo_root/rt-thread-am/bsp/abstract-machine/.config" '^CONFIG_(BOARD_AM|RT_THREAD_PRIORITY|RT_TICK|RT_USING|FINSH|DFS)'
  optional_path "rt-thread files.mk" "$repo_root/rt-thread-am/bsp/abstract-machine/files.mk"
fi

section "git state"
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$repo_root" status --short --branch
  git -C "$repo_root" submodule status --recursive
else
  printf 'missing  repository is not a Git worktree\n'
  missing_required=$((missing_required + 1))
fi

section "summary"
printf 'required-missing %d\n' "$missing_required"
printf 'warnings         %d\n' "$warnings"
printf 'strict           %d\n' "$strict"

if ((strict == 1 && missing_required > 0)); then
  exit 1
fi
exit 0
