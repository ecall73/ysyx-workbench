#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
ARCH=${1:-}
shift || true

if [[ -z "$ARCH" ]]; then
  echo "usage: $0 ARCH [contract ...]" >&2
  exit 2
fi

case "$ARCH" in
  riscv32-nemu) TIMEOUT=30 ;;
  riscv32e-npc|riscv32e-ysyxsoc) TIMEOUT=60 ;;
  *)
    echo "unsupported ARCH: $ARCH" >&2
    exit 2
    ;;
esac

declare -A DEPRECATED=(
  [00-trm-putch-halt]=core/trm-putch-halt
  [01-sections-data-bss]=core/sections-data-bss
  [02-heap-window]=core/heap-window
  [03-klib-string]=klib/string
  [04-klib-stdio]=klib/stdio
  [05-klib-stdlib]=klib/stdlib
  [06-libgcc-rv32e]=klib/int64-rv32e
  [07-ioe-config]=ioe/config
  [08-timer-uptime]=ioe/timer-uptime
  [09-timer-rtc]=ioe/timer-rtc
  [10-cte-yield]=cte/yield
  [11-cte-syscall]=cte/syscall
  [12-cte-kcontext]=cte/kcontext
  [13-uart-tx]=ioe/uart-tx
  [14-gpu-config]=ioe/gpu-smoke
  [15-gpu-fbdraw-smoke]=ioe/gpu-smoke
  [16-input-idle]=ioe/input-idle
  [17-ysyxsoc-layout]=platform/ysyxsoc-layout-default
  [18-gpio-config]=ioe/gpio-smoke
)

read_var() {
  local file=$1
  local var=$2
  sed -n "s/^${var}[[:space:]]*=[[:space:]]*//p" "$file" | head -n1
}

supports_arch() {
  local test=$1
  local mk="$ROOT/$test/Makefile"
  local archs
  archs=$(read_var "$mk" CONTRACT_ARCHS)
  [[ " $archs " == *" $ARCH "* ]]
}

test_group() {
  read_var "$ROOT/$1/Makefile" CONTRACT_GROUP
}

discover_tests() {
  find "$ROOT" -mindepth 2 -maxdepth 2 -name Makefile \
    | sed "s#^$ROOT/##; s#/Makefile\$##" \
    | sort
}

normalize_test() {
  local t=$1
  if [[ -n ${DEPRECATED[$t]:-} ]]; then
    echo "[contract] deprecated name '$t'; use '${DEPRECATED[$t]}'" >&2
    return 1
  fi
  echo "$t"
}

ALL_INPUT=("$@")
TESTS=()

if ((${#ALL_INPUT[@]} > 0)); then
  for raw in "${ALL_INPUT[@]}"; do
    t=$(normalize_test "$raw") || exit 2
    TESTS+=("$t")
  done
else
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    [[ -n "${GROUP:-}" && "$(test_group "$t")" != "$GROUP" ]] && continue
    supports_arch "$t" && TESTS+=("$t")
  done < <(discover_tests)
fi

if ((${#TESTS[@]} == 0)); then
  echo "[contract] no tests selected for ARCH=$ARCH GROUP=${GROUP:-all}" >&2
  exit 2
fi

LOG_DIR="$ROOT/build"
mkdir -p "$LOG_DIR"

pass=0
fail=0

for t in "${TESTS[@]}"; do
  dir="$ROOT/$t"
  log_name=${t//\//__}
  log="$LOG_DIR/contract-$ARCH-$log_name.log"

  if [[ ! -d "$dir" ]]; then
    echo "[contract] FAIL $t: directory missing"
    fail=$((fail + 1))
    continue
  fi

  if ! supports_arch "$t"; then
    echo "[contract] FAIL $t: unsupported ARCH=$ARCH"
    fail=$((fail + 1))
    continue
  fi

  echo "[contract] RUN  $ARCH $t"

  if [[ "$t" == "core/mainargs" ]]; then
    cases=("" "alpha-42" "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abc")
    : >"$log"
    status=0
    for arg in "${cases[@]}"; do
      {
        echo "[contract] mainargs case='$arg'"
        timeout "${TIMEOUT}s" make -B -C "$dir" ARCH="$ARCH" run mainargs="$arg"
      } >>"$log" 2>&1 || { status=$?; break; }
    done
  else
    timeout "${TIMEOUT}s" make -C "$dir" ARCH="$ARCH" run >"$log" 2>&1
    status=$?
  fi

  if [[ $status -ne 0 ]]; then
    echo "[contract] FAIL $t: command status=$status log=$log"
    tail -n 40 "$log"
    fail=$((fail + 1))
    continue
  fi

  if ! grep -q "CONTRACT $t PASS" "$log"; then
    echo "[contract] FAIL $t: PASS token missing log=$log"
    tail -n 40 "$log"
    fail=$((fail + 1))
    continue
  fi

  required_token=
  case "$t" in
    core/trm-putch-halt) required_token=TRM_PUTCH_TOKEN ;;
    klib/stdio) required_token=KLIB_PRINTF_TOKEN ;;
    ioe/uart-tx) required_token=UART_TX_TOKEN ;;
  esac

  if [[ -n "$required_token" ]] && ! grep -q "$required_token" "$log"; then
    echo "[contract] FAIL $t: required token '$required_token' missing log=$log"
    tail -n 40 "$log"
    fail=$((fail + 1))
    continue
  fi

  echo "[contract] PASS $t"
  pass=$((pass + 1))
done

echo "[contract] SUMMARY arch=$ARCH pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
