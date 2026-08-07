#!/usr/bin/env bash
#
# Run the bare-metal AUnit harness under QEMU and turn its UART output into an
# exit status, which bare-metal firmware cannot report itself. The verdict is
# AUnit's closing line ("11 tests run: 11 passed; 0 failed; 0 crashed."); a
# missing summary counts as a failure, not as nothing to report.
#
# --expected guards the size of the suite: a shorter run than asked for is a
# failure, because an ignore-list typo or a unit that stops being picked up
# would otherwise pass quietly.
#
# Usage: test-target.sh [--timeout SECS] [--expected N] ELF [LOG]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() {
  local code=$1
  shift
  printf 'ERROR: %s\n' "$*" >&2
  exit "$code"
}

timeout=${QEMU_TEST_TIMEOUT:-120}
expected=${QEMU_TEST_EXPECTED:-}

while [ $# -gt 0 ]; do
  case $1 in
    --timeout)
      [ $# -ge 2 ] || die 64 "--timeout needs a value"
      timeout=$2
      shift 2
      ;;
    --expected)
      [ $# -ge 2 ] || die 64 "--expected needs a value"
      expected=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*) die 64 "unknown option '$1'" ;;
    *) break ;;
  esac
done

elf=${1:-}
[ -n "$elf" ] || die 64 "usage: $0 [--timeout SECS] [--expected N] ELF [LOG]"
log=${2:-$(dirname "$elf")/test-target.log}

SUMMARY_RE='^[0-9]+ tests run:'

run_status=0
"$SCRIPT_DIR/run.sh" \
  --console uart1 \
  --until "$SUMMARY_RE" \
  --timeout "$timeout" \
  --log "$log" \
  "$elf" || run_status=$?

# 3 is a missing QEMU, which run.sh has already explained; 64 is our own bug.
if [ "$run_status" -eq 3 ] || [ "$run_status" -eq 64 ]; then
  exit "$run_status"
fi

if [ "$run_status" -ne 0 ]; then
  printf 'ERROR: the target testsuite did not report a summary.\n' >&2
  exit 1
fi

counts=$(
  sed -nE \
    's/^([0-9]+) tests run: ([0-9]+) passed; ([0-9]+) failed; ([0-9]+) crashed.*/\1 \2 \3 \4/p' \
    "$log" | head -1
)

if [ -z "$counts" ]; then
  printf 'ERROR: could not parse the AUnit summary line (log: %s)\n' "$log" >&2
  exit 1
fi

read -r total passed failed crashed <<<"$counts"

if [ -n "$expected" ] && [ "$total" -ne "$expected" ]; then
  printf 'ERROR: expected %s tests on target but the harness ran %s (log: %s).\n' \
    "$expected" "$total" "$log" >&2
  printf '       Check the cross harness ignore list, or update QEMU_TEST_EXPECTED.\n' >&2
  exit 1
fi

if [ "$total" -eq 0 ]; then
  printf 'ERROR: the target harness ran no tests at all (log: %s)\n' "$log" >&2
  exit 1
fi

if [ "$failed" -ne 0 ] || [ "$crashed" -ne 0 ]; then
  printf 'FAILED on target: %s of %s tests failed, %s crashed (log: %s)\n' \
    "$failed" "$total" "$crashed" "$log" >&2
  exit 1
fi

printf 'PASSED on target: %s of %s tests (log: %s)\n' "$passed" "$total" "$log"
