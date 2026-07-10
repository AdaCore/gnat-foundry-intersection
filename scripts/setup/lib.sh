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
  uname_m=$(uname -m)
  case "$uname_m" in
    arm64 | aarch64) arch=aarch64 ;;
    x86_64 | amd64) arch=x86_64 ;;
    *) fatal "unsupported architecture: $uname_m" ;;
  esac
  uname_s=$(uname -s)
  case "$uname_s" in
    Linux) os=linux ;;
    *) fatal "unsupported OS: $uname_s" ;;
  esac
  printf '%s %s\n' "$arch" "$os"
}

# Alire: install the latest official (community) release from GitHub, locally
# into $LOCAL_BIN. Shared by both the community and pro setups until we have an
# official release.
#
# Requires $LOCAL_BIN to be set.
install_alire() {
  header "alr (Ada source package manager)"

  if [ -x "$LOCAL_BIN/alr" ]; then
    detail "Already installed locally ($LOCAL_BIN/alr); skipping."
    return 0
  fi
  if command -v alr >/dev/null 2>&1; then
    detail "Found on PATH ($(command -v alr)); skipping local install."
    return 0
  fi

  require_cmd curl unzip

  local platform arch os url tmp
  platform=$(detect_platform)
  arch=${platform%% *}
  os=${platform##* }
  detail "Querying GitHub for the latest Alire release asset ($arch-$os) ..."
  url=$(
    curl -fsSL https://api.github.com/repos/alire-project/alire/releases/latest \
      | grep -o "\"browser_download_url\": \"[^\"]*bin-$arch-${os}[^\"]*\"" \
      | grep -o 'https://[^"]*' \
      | head -1 \
      || true
  )
  if [ -z "$url" ]; then
    fatal "could not find an Alire release asset for $arch-$os."
  fi

  tmp=$(mktemp -d)
  detail "Downloading $url"
  detail "  to temporary dir $tmp"
  curl -fsSL "$url" -o "$tmp/alr.zip"
  unzip -q "$tmp/alr.zip" -d "$tmp/alr"

  detail "Installing alr into $LOCAL_BIN"
  mkdir -p "$LOCAL_BIN"
  mv "$tmp/alr/bin/alr" "$LOCAL_BIN/alr"
  chmod +x "$LOCAL_BIN/alr"
  rm -rf "$tmp"
  detail "Installed version: $("$LOCAL_BIN/alr" --version)"
}

# Resolve the base `alr` command into a global $ALR array.
#
# Invoke after `install_alire`. Requires $LOCAL_BIN to be set. $ALR is consumed
# by the sourcing script (community.sh / pro.sh), not here; hence SC2034.
# shellcheck disable=SC2034
resolve_alr() {
  if [ -x "$LOCAL_BIN/alr" ]; then
    ALR=("$LOCAL_BIN/alr" -n)
  else
    ALR=(alr -n)
  fi
}

# Record which setup provisioned install/ ($1: "community" or "pro") in
# $SETUP_MARKER, which the Makefile reads as $(SETUP). Call once the setup
# has succeeded.
write_setup_marker() {
  mkdir -p "$(dirname "$SETUP_MARKER")"
  printf '%s\n' "$1" >"$SETUP_MARKER"
}

# Echo a description of a tool's location (installed locally vs detected on
# PATH vs not found). Requires $LOCAL_BIN to be set.
report_tool() {
  local bin=$1 path
  path=$(PATH="$LOCAL_BIN:$PATH" command -v "$bin" 2>/dev/null || true)
  if [ -z "$path" ]; then
    printf 'not found'
  elif [ "$path" = "$LOCAL_BIN/$bin" ]; then
    printf 'installed at %s' "$path"
  else
    printf 'detected at %s' "$path"
  fi
}
