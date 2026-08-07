#!/usr/bin/env bash
#
# Exit 0 if qemu-system-arm is on PATH, otherwise say how to get it and exit 3.
# Shared by run.sh and the Makefile's `run-target`, which rolls its own QEMU
# command line and would otherwise fail without the hint.

set -euo pipefail

if command -v qemu-system-arm >/dev/null 2>&1; then
  exit 0
fi

printf 'ERROR: %s\n' "qemu-system-arm not found on PATH.
It is not provisioned by 'make setup-community' / 'make setup-pro': install it
from your distribution (Debian/Ubuntu: the qemu-system-arm package)." >&2
exit 3
