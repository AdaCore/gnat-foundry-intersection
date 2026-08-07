#!/usr/bin/env bash
#
# Boot a bare-metal arm-eabi ELF on QEMU's xilinx-zynq-a9 machine, stream one of
# the two UARTs, and stop at a sentinel line or a timeout. QEMU is always killed
# on the way out: bare-metal firmware has no exit status, and the zynq7000
# runtimes restart the image when the environment task returns.
#
# Which UART carries what, hence --console:
#
#   uart0 (0xE000_0000) -- first -serial backend; the app's Display body.
#   uart1 (0xE000_1000) -- second -serial backend; the GNAT runtime console
#                          (System.Text_IO, so also Ada.Text_IO and AUnit).
#
# The unwatched UART goes to "$log.other" rather than being discarded: a fault
# under --console uart0 writes to uart1 through Last_Chance_Handler, and that is
# exactly what one wants to read after a timeout.
#
# Usage:
#   run.sh --until REGEX [--console uart0|uart1] [--timeout SECS]
#          [--log PATH] [--machine NAME] [--memory SIZE] ELF
#
# Output is echoed on stdout, truncated after the sentinel, and kept in full in
# --log. Exit status:
#
#   0   the sentinel matched
#   1   QEMU exited before matching
#   2   timed out waiting for the sentinel
#   3   qemu-system-arm is not installed
#   64  the command line is wrong

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() {
  local code=$1
  shift
  printf 'ERROR: %s\n' "$*" >&2
  exit "$code"
}

console=uart1
timeout=120
log=
machine=xilinx-zynq-a9
memory=1G
until_re=
elf=

while [ $# -gt 0 ]; do
  case $1 in
    --console)
      [ $# -ge 2 ] || die 64 "--console needs a value"
      console=$2
      shift 2
      ;;
    --until)
      [ $# -ge 2 ] || die 64 "--until needs a value"
      until_re=$2
      shift 2
      ;;
    --timeout)
      [ $# -ge 2 ] || die 64 "--timeout needs a value"
      timeout=$2
      shift 2
      ;;
    --log)
      [ $# -ge 2 ] || die 64 "--log needs a value"
      log=$2
      shift 2
      ;;
    --machine)
      [ $# -ge 2 ] || die 64 "--machine needs a value"
      machine=$2
      shift 2
      ;;
    --memory)
      [ $# -ge 2 ] || die 64 "--memory needs a value"
      memory=$2
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
[ -n "$elf" ] || die 64 "no ELF given. Usage: $0 --until REGEX [opts] ELF"
[ -n "$until_re" ] || die 64 "--until REGEX is required."
[ -f "$elf" ] || die 64 "no such executable: $elf"

case $console in
  uart0 | uart1) ;;
  *) die 64 "--console must be 'uart0' or 'uart1', got '$console'" ;;
esac

"$SCRIPT_DIR/require-qemu.sh"

log=${log:-$(dirname "$elf")/$(basename "$elf").qemu.log}
mkdir -p "$(dirname "$log")"
: >"$log"

# QEMU maps the two -serial backends onto UART0 and UART1 in order, so the one
# we want on stdout is selected by position; the other is kept on the side.
other_log=$log.other
: >"$other_log"
case $console in
  uart0) serial=(-serial stdio -serial file:"$other_log") ;;
  uart1) serial=(-serial file:"$other_log" -serial stdio) ;;
esac

# -display none -monitor none: no GUI and no monitor multiplexed onto our stdio,
# so the log holds nothing but guest UART bytes. stdin is closed so a guest that
# reads its console sees no input rather than this shell's. -no-reboot turns a
# guest-requested reset into an exit instead of a silent restart-and-repeat.
qemu-system-arm \
  -M "$machine" -m "$memory" \
  -display none -monitor none -no-reboot \
  "${serial[@]}" \
  -kernel "$elf" \
  >"$log" 2>&1 </dev/null &
qemu_pid=$!

# Kill QEMU however we leave, including on Ctrl-C or a failed grep.
cleanup() {
  if kill -0 "$qemu_pid" 2>/dev/null; then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

status=2
deadline=$((SECONDS + timeout))
while :; do
  if grep -qE -- "$until_re" "$log"; then
    status=0
    break
  fi
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    # It may have printed the sentinel and then died out from under us between
    # the grep above and now, so re-check before calling this a crash.
    if grep -qE -- "$until_re" "$log"; then status=0; else status=1; fi
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    status=2
    break
  fi
  sleep 0.2
done

cleanup
trap - EXIT

# Echo what the guest said, cut at the sentinel: past that point the board has
# simply restarted the image and is repeating itself. awk rather than sed so
# the pattern is an ERE (as in the grep above) and needs no delimiter escaping.
if [ "$status" -eq 0 ]; then
  awk -v re="$until_re" '{ print } $0 ~ re { exit }' "$log"
else
  cat "$log"
fi

case $status in
  1)
    printf 'ERROR: QEMU exited before matching /%s/ (log: %s, other UART: %s)\n' \
      "$until_re" "$log" "$other_log" >&2
    ;;
  2)
    printf 'ERROR: timed out after %ss waiting for /%s/ (log: %s, other UART: %s)\n' \
      "$timeout" "$until_re" "$log" "$other_log" >&2
    ;;
  *) ;;
esac

exit "$status"
