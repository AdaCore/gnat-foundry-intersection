#!/usr/bin/env bash
#
# Tests for the parts of pro.sh that run before anything is installed: mode
# selection, the explanation of an auto-selected install mode, and the staged
# download preflight (including tarballs wrapped in zipfiles). Everything runs
# against throwaway directories; no pro product is needed or touched.
#
# Run directly, or via `make check-setup-scripts`.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export NO_COLOR=1
export LOCAL_BIN="$tmp/bin" ALIRE_SETTINGS_DIR="$tmp/alire" PRO_DIR="$tmp/pro" \
  PRO_DOWNLOADS="$tmp/downloads" SETUP_MARKER="$tmp/setup.marker"
unset PRO_TOOLS GPR_PROJECT_PATH

# shellcheck source=scripts/setup/pro.sh
source "$SCRIPT_DIR/pro.sh"
# stage_zip builds the zipfiles the preflight has to look inside.
require_cmd zip unzip

failures=0
current=

# Start a named test case with a clean $PRO_DIR and $PRO_DOWNLOADS.
case_() {
  current=$1
  rm -rf "$PRO_DIR" "$PRO_DOWNLOADS"
}

fail() {
  printf 'FAIL [%s]: %s\n' "$current" "$*" >&2
  failures=$((failures + 1))
}

# Run "$@" in a subshell (fatal exits), capturing stdout, stderr and status.
out='' err='' rc=''
run() {
  local o="$tmp/out" e="$tmp/err"
  rc=0
  ("$@") >"$o" 2>"$e" || rc=$?
  out=$(<"$o")
  err=$(<"$e")
}

# Export the VAR=value settings before `--` and run the rest; meant to be run
# under `run`, whose subshell keeps the settings from leaking.
with_env() {
  while [ "$1" != -- ]; do
    export "${1?}"
    shift
  done
  shift
  "$@"
}

assert_eq() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "$3: missing '$2' in:
$1"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "$3: unexpected '$2' in:
$1"; }
# Number of lines of $1 containing $2.
count_lines() { grep -c -- "$2" <<<"$1" || true; }

# Stage an empty tarball named $1 directly.
stage_tarball() {
  mkdir -p "$PRO_DOWNLOADS"
  : >"$PRO_DOWNLOADS/$1"
}

# Stage zipfile $1 wrapping an empty tarball $2 under a sub-directory, as GNAT
# Tracker packages do.
stage_zip() {
  mkdir -p "$PRO_DOWNLOADS" "$tmp/wrap/${1%.zip}"
  : >"$tmp/wrap/${1%.zip}/$2"
  (cd "$tmp/wrap" && zip -q -r "$PRO_DOWNLOADS/$1" "${1%.zip}")
  rm -rf "$tmp/wrap"
}

# Mark product sub-directory $1 installed via marker file $2 (relative).
mark_installed() {
  mkdir -p "$PRO_DIR/$1/$(dirname "$2")"
  : >"$PRO_DIR/$1/$2"
  is_gpr_file "$2" || chmod +x "$PRO_DIR/$1/$2"
}

# A PATH holding fake pro tools $@ (and nothing else, so the real ones on the
# host's PATH stay out of the picture). Builtins are all the functions under
# test need.
fake_path() {
  local dir="$tmp/fakebin" cmd
  rm -rf "$dir"
  mkdir -p "$dir"
  for cmd in "$@"; do
    printf '#!/bin/sh\n' >"$dir/$cmd"
    chmod +x "$dir/$cmd"
  done
  printf '%s\n' "$dir"
}

GNATPRO='gnatpro-25.2-x86_64-linux-bin.tar.gz'
ARM_ELF='gnatpro-25.2-arm-elf-linux64-bin.tar.gz'
SPARK='spark-pro-25.2-x86_64-linux-bin.tar.gz'
GNATDAS='gnatdas-25.2-x86_64-linux-bin.tar.gz'
LIBADALANG='libadalang-25.2-x86_64-linux-bin.tar.gz'

# ---------------------------------------------------------------- find_tarball

case_ 'find_tarball: newest tarball staged directly'
stage_tarball 'gnatpro-25.1-x86_64-linux-bin.tar.gz'
stage_tarball "$GNATPRO"
run find_tarball 'gnatpro-*-x86_64-linux-bin.tar.gz'
assert_eq "$rc" 0 'status'
assert_eq "$out" "$PRO_DOWNLOADS/$GNATPRO" 'path'
assert_eq "$err" '' 'stderr'

case_ 'find_tarball: tarball wrapped in a zipfile'
stage_zip 'gnatpro-25.2-x86_64-linux.zip' "$GNATPRO"
run find_tarball 'gnatpro-*-x86_64-linux-bin.tar.gz'
assert_eq "$rc" 0 'status'
# The captured output is the path alone: a progress line here would become
# part of the file name the caller hands to tar.
assert_eq "$out" "$PRO_DOWNLOADS/$GNATPRO" 'path'
assert_contains "$err" "Extracting $GNATPRO from gnatpro-25.2-x86_64-linux.zip" 'progress line'
[ -f "$PRO_DOWNLOADS/$GNATPRO" ] || fail 'tarball not extracted'
run find_tarball 'gnatpro-*-x86_64-linux-bin.tar.gz'
assert_eq "$out" "$PRO_DOWNLOADS/$GNATPRO" 'path on the second lookup'
assert_eq "$err" '' 'no re-extraction'

case_ 'find_tarball: nothing staged'
mkdir -p "$PRO_DOWNLOADS"
run find_tarball 'gnatpro-*-x86_64-linux-bin.tar.gz'
assert_eq "$rc" 1 'status'
assert_eq "$out" '' 'stdout'

case_ 'find_tarball: downloads directory absent'
run find_tarball 'gnatpro-*-x86_64-linux-bin.tar.gz'
assert_eq "$rc" 1 'status'
assert_eq "$out" '' 'stdout'

# ------------------------------------------------------------- check_downloads

case_ 'check_downloads: nothing staged reports every product'
run check_downloads
assert_eq "$rc" 1 'status'
assert_eq "$(count_lines "$out" MISSING)" 5 'MISSING lines'
assert_contains "$err" 'for 5 of the 5 pro products' 'count'
assert_contains "$err" 'just been created' 'creation notice'
[ -d "$PRO_DOWNLOADS" ] || fail 'downloads directory not created'

case_ 'check_downloads: existing empty directory is not reported as created'
mkdir -p "$PRO_DOWNLOADS"
run check_downloads
assert_eq "$rc" 1 'status'
assert_not_contains "$err" 'just been created' 'creation notice'

case_ 'check_downloads: partial install, mixed staging, one missing'
mark_installed gnatpro bin/gnat
mark_installed libadalang share/gpr/libadalang.gpr
stage_tarball "$SPARK"
stage_zip 'gnatdas-25.2-x86_64-linux.zip' "$GNATDAS"
run check_downloads
assert_eq "$rc" 1 'status'
assert_eq "$(count_lines "$out" 'already installed')" 2 'installed lines'
assert_contains "$out" "$SPARK" 'direct tarball'
assert_contains "$out" "$GNATDAS" 'tarball from zip'
assert_eq "$(count_lines "$out" MISSING)" 1 'MISSING lines'
assert_contains "$out" 'MISSING (GNAT Pro arm-elf cross compiler)' 'the missing product'
assert_contains "$err" 'for 1 of the 5 pro products' 'count'
[ -f "$PRO_DOWNLOADS/$GNATDAS" ] || fail 'zip member not extracted'

case_ 'check_downloads: everything staged passes'
stage_tarball "$GNATPRO"
stage_tarball "$ARM_ELF"
stage_tarball "$SPARK"
stage_tarball "$GNATDAS"
stage_tarball "$LIBADALANG"
run check_downloads
assert_eq "$rc" 0 'status'
assert_not_contains "$out" MISSING 'MISSING lines'

case_ 'check_downloads: everything installed passes with nothing staged'
mark_installed gnatpro bin/gnat
mark_installed arm-elf bin/arm-eabi-gnat
mark_installed spark bin/gnatprove
mark_installed gnatdas bin/gnatcov
mark_installed libadalang share/gpr/libadalang.gpr
run check_downloads
assert_eq "$rc" 0 'status'
assert_eq "$(count_lines "$out" 'already installed')" 5 'installed lines'

# ----------------------------------------------- select_mode, explain_install_mode

case_ 'select_mode: forced'
run with_env PRO_TOOLS=external -- select_mode
assert_eq "$out" external 'PRO_TOOLS=external'
run with_env PRO_TOOLS=install -- select_mode
assert_eq "$out" install 'PRO_TOOLS=install'
run with_env PRO_TOOLS=bogus -- select_mode
assert_eq "$rc" 1 'PRO_TOOLS=bogus status'
assert_contains "$err" "invalid PRO_TOOLS value 'bogus'" 'PRO_TOOLS=bogus message'

case_ 'select_mode: no pro tools anywhere'
run with_env PATH="$(fake_path)" -- select_mode
assert_eq "$out" install 'mode'

case_ 'select_mode: complete environment'
mkdir -p "$tmp/gpr"
: >"$tmp/gpr/libadalang.gpr"
run with_env PATH="$(fake_path "${EXTERNAL_TOOLS[@]}")" GPR_PROJECT_PATH="$tmp/gpr" \
  -- select_mode
assert_eq "$out" external 'mode'

case_ 'select_mode: complete environment, but downloads staged'
stage_tarball "$GNATPRO"
run with_env PATH="$(fake_path "${EXTERNAL_TOOLS[@]}")" GPR_PROJECT_PATH="$tmp/gpr" \
  -- select_mode
assert_eq "$out" install 'mode'

case_ 'select_mode: complete environment, but a product installed'
mark_installed spark bin/gnatprove
run with_env PATH="$(fake_path "${EXTERNAL_TOOLS[@]}")" GPR_PROJECT_PATH="$tmp/gpr" \
  -- select_mode
assert_eq "$out" install 'mode'

case_ 'explain_install_mode: silent when no pro tool is on PATH'
run with_env PATH="$(fake_path)" -- explain_install_mode
assert_eq "$rc" 0 'status'
assert_eq "$out" '' 'stdout'

case_ 'explain_install_mode: silent when downloads are staged'
stage_tarball "$GNATPRO"
run with_env PATH="$(fake_path gnat)" -- explain_install_mode
assert_eq "$out" '' 'stdout'

case_ 'explain_install_mode: reports an incomplete environment'
run with_env PATH="$(fake_path gnat gprbuild)" -- explain_install_mode
assert_eq "$rc" 0 'status'
assert_contains "$out" 'Pro tools from the environment' 'header'
assert_contains "$out" "$tmp/fakebin/gnat" 'found tool'
assert_eq "$(count_lines "$out" 'not found on PATH')" 5 'missing tools'
assert_eq "$(count_lines "$out" 'not found on GPR_PROJECT_PATH')" 1 'missing libraries'
assert_contains "$out" 'Some are missing' 'explanation'

# ---------------------------------------------------------- use_external_tools

case_ 'use_external_tools: lists every gap'
run with_env PATH="$(fake_path gnat)" -- use_external_tools
assert_eq "$rc" 1 'status'
assert_contains "$err" 'not found on PATH: gprbuild gnatformat gnattest gnatcov gnatprove arm-eabi-gnat' 'tools'
assert_contains "$err" 'not found on GPR_PROJECT_PATH: libadalang' 'libraries'

case_ 'use_external_tools: complete environment passes'
mkdir -p "$tmp/gpr"
: >"$tmp/gpr/libadalang.gpr"
run with_env PATH="$(fake_path "${EXTERNAL_TOOLS[@]}")" GPR_PROJECT_PATH="$tmp/gpr" \
  -- use_external_tools
assert_eq "$rc" 0 'status'
assert_contains "$out" "$tmp/gpr/libadalang.gpr" 'library location'

# ----------------------------------------------------------------------------

if [ "$failures" -ne 0 ]; then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'pro.sh tests: ok\n'
