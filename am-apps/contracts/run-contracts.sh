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
  riscv32-nemu)
    TIMEOUT=30
    DEFAULT_TESTS=(
      00-trm-putch-halt
      01-sections-data-bss
      02-heap-window
      03-klib-string
      04-klib-format
      05-klib-stdlib
      08-timer-uptime
      10-cte-yield
      11-cte-syscall
      12-cte-kcontext
    )
    ;;
  riscv32e-npc)
    TIMEOUT=60
    DEFAULT_TESTS=(
      00-trm-putch-halt
      01-sections-data-bss
      02-heap-window
      03-klib-string
      04-klib-format
      05-klib-stdlib
      06-libgcc-rv32e
      07-ioe-config
      08-timer-uptime
      09-timer-rtc
      10-cte-yield
      11-cte-syscall
      12-cte-kcontext
      13-uart-tx
    )
    ;;
  riscv32e-ysyxsoc)
    TIMEOUT=60
    DEFAULT_TESTS=(
      00-trm-putch-halt
      01-sections-data-bss
      02-heap-window
      03-klib-string
      04-klib-format
      05-klib-stdlib
      06-libgcc-rv32e
      07-ioe-config
      08-timer-uptime
      09-timer-rtc
      10-cte-yield
      11-cte-syscall
      12-cte-kcontext
      13-uart-tx
      14-gpu-config
      15-gpu-fbdraw-smoke
      16-input-idle
      17-ysyxsoc-layout
      18-gpio-config
    )
    ;;
  *)
    echo "unsupported ARCH: $ARCH" >&2
    exit 2
    ;;
esac

if (($# > 0)); then
  TESTS=("$@")
else
  TESTS=("${DEFAULT_TESTS[@]}")
fi

LOG_DIR="$ROOT/build"
mkdir -p "$LOG_DIR"

pass=0
fail=0

for t in "${TESTS[@]}"; do
  dir="$ROOT/$t"
  log="$LOG_DIR/contract-$ARCH-$t.log"
  if [[ ! -d "$dir" ]]; then
    echo "[contract] FAIL $t: directory missing"
    fail=$((fail + 1))
    continue
  fi

  echo "[contract] RUN  $ARCH $t"
  timeout "${TIMEOUT}s" make -C "$dir" ARCH="$ARCH" run >"$log" 2>&1
  status=$?

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
    00-trm-putch-halt) required_token=TRM_PUTCH_TOKEN ;;
    13-uart-tx) required_token=UART_TX_TOKEN ;;
  esac
  if [[ -n "$required_token" ]] \
      && ! grep -q "CONTRACT $t SKIP" "$log" \
      && ! grep -q "$required_token" "$log"; then
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
