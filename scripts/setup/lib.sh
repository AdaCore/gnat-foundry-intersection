# shellcheck shell=bash
#
# Shared helpers for the setup scripts under scripts/setup/.

# Colour `header` messages when in an interactive terminal (and NO_COLOR is
# unset).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _C_HEAD=$'\e[1;36m' # bold cyan
  _C_ERR=$'\e[1;31m'  # bold red
  _C_OFF=$'\e[0m'
else
  _C_HEAD='' _C_ERR='' _C_OFF=''
fi

# Section header
header() { printf '\n%s==> %s%s\n' "$_C_HEAD" "$*" "$_C_OFF"; }

# Sub-step detail line, indented under the current header.
detail() { printf '    %s\n' "$*"; }

# Fatal error: print to stderr and abort.
fatal() {
  local first=1 line
  while IFS= read -r line; do
    if [ "$first" = 1 ]; then
      printf '%sERROR:%s %s\n' "$_C_ERR" "$_C_OFF" "$line" >&2
      first=0
    else
      printf '       %s\n' "$line" >&2
    fi
  done <<<"$*"
  exit 1
}

# Abort with a message if any of a list of commands is not found on PATH.
require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      fatal "required command '$cmd' not found on PATH."
    fi
  done
}

# Abort with a message if any of a list of env vars is unset or empty.
require_vars() {
  local name missing=()
  for name in "$@"; do
    if [ -z "${!name:-}" ]; then
      missing+=("$name")
    fi
  done
  if [ ${#missing[@]} -ne 0 ]; then
    fatal "missing required environment variable(s): ${missing[*]}
These are normally supplied by running this script via the Makefile."
  fi
}

# Echo the host platform as "<arch> <os>".
detect_platform() {
  local uname_s uname_m os arch
  uname_s=$(uname -s)
  uname_m=$(uname -m)
  case "$uname_s" in
    Linux) os=linux ;;
    *) fatal "unsupported OS: $uname_s" ;;
  esac
  case "$uname_m" in
    arm64 | aarch64) arch=aarch64 ;;
    x86_64 | amd64) arch=x86_64 ;;
    *) fatal "unsupported architecture: $uname_m" ;;
  esac
  printf '%s %s\n' "$arch" "$os"
}
