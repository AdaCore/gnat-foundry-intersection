#!/usr/bin/env bash
#
# Provision the pro (GNAT Pro / SPARK Pro / GNAT DAS) versions of all tooling
# needed for the demo, from tarballs or zip files downloaded from GNAT Tracker
# or from tools already on PATH ('external' mode).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/setup/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_vars LOCAL_BIN ALIRE_SETTINGS_DIR PRO_DIR PRO_DOWNLOADS SETUP_MARKER
# Optional: PRO_TOOLS ('install' or 'external') forces the mode.

# The tools external mode needs on PATH (the Makefile invokes them directly).
EXTERNAL_TOOLS=(gnat gprbuild gnatformat gnattest gnatcov gnatprove arm-eabi-gnat)

# The libraries external mode needs on GPR_PROJECT_PATH, by project name.
EXTERNAL_LIBRARIES=(libadalang)

# Echo the path of library $1's project file on GPR_PROJECT_PATH; non-zero if
# there is none.
library_gpr() {
  local dir
  while IFS= read -r -d: dir; do
    if [ -n "$dir" ] && [ -f "$dir/$1.gpr" ]; then
      printf '%s\n' "$dir/$1.gpr"
      return 0
    fi
  done <<<"${GPR_PROJECT_PATH:-}:"
  return 1
}

# Echo the EXTERNAL_TOOLS that are not on PATH, space-separated (empty when
# they all are).
missing_external_tools() {
  local cmd missing=()
  for cmd in "${EXTERNAL_TOOLS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  printf '%s\n' "${missing[*]:-}"
}

# Echo the EXTERNAL_LIBRARIES that are not on GPR_PROJECT_PATH, space-separated
# (empty when they all are).
missing_external_libraries() {
  local lib missing=()
  for lib in "${EXTERNAL_LIBRARIES[@]}"; do
    library_gpr "$lib" >/dev/null || missing+=("$lib")
  done
  printf '%s\n' "${missing[*]:-}"
}

# True if $1 has a `.gpr` suffix.
is_gpr_file() {
  case "$1" in
    *.gpr) return 0 ;;
    *) return 1 ;;
  esac
}

# True if the marker file $1 proves its product installed: a plain `.gpr` file
# for the library products, an executable for the toolchains.
marker_present() {
  if is_gpr_file "$1"; then
    [ -f "$1" ]
  else
    [ -x "$1" ]
  fi
}

# True if any pro download (tarball or zipfile) is staged under $PRO_DOWNLOADS.
downloads_staged() {
  compgen -G "$PRO_DOWNLOADS/*.tar.gz" >/dev/null \
    || compgen -G "$PRO_DOWNLOADS/*.zip" >/dev/null
}

# True if a previous run installed at least one product under $PRO_DIR.
products_installed() {
  marker_present "$PRO_DIR/gnatpro/bin/gnat" \
    || marker_present "$PRO_DIR/arm-elf/bin/arm-eabi-gnat" \
    || marker_present "$PRO_DIR/spark/bin/gnatprove" \
    || marker_present "$PRO_DIR/gnatdas/bin/gnatcov" \
    || marker_present "$PRO_DIR/libadalang/share/gpr/libadalang.gpr"
}

# Print where each of the EXTERNAL_TOOLS and EXTERNAL_LIBRARIES was found,
# or that it was not.
report_environment() {
  local cmd lib
  for cmd in "${EXTERNAL_TOOLS[@]}"; do
    detail "$(printf '%-14s' "$cmd") $(command -v "$cmd" 2>/dev/null || printf 'not found on PATH')"
  done
  for lib in "${EXTERNAL_LIBRARIES[@]}"; do
    detail "$(printf '%-14s' "$lib") $(library_gpr "$lib" || printf 'not found on GPR_PROJECT_PATH')"
  done
}

# Echo the mode: $PRO_TOOLS if forced; else 'install' when downloads are
# staged or products already installed, 'external' when every tool and library
# is present, and 'install' otherwise (explain_install_mode says why).
select_mode() {
  case "${PRO_TOOLS:-}" in
    install | external)
      printf '%s\n' "$PRO_TOOLS"
      return 0
      ;;
    '') ;;
    *)
      fatal "invalid PRO_TOOLS value '${PRO_TOOLS}' (expected 'install' or 'external')."
      ;;
  esac
  if downloads_staged || products_installed; then
    printf 'install\n'
  elif [ -z "$(missing_external_tools)" ] && [ -z "$(missing_external_libraries)" ]; then
    printf 'external\n'
  else
    printf 'install\n'
  fi
}

# Explain why the auto-detection settled on 'install' rather than using the
# tools on PATH, so a user who expected their environment to be picked up can
# see what it lacked and what happens next. Silent unless it looks like they
# tried that: some (but not all) pro tools on PATH, nothing staged, nothing
# installed. A user with no pro tools on PATH is on the default path and is
# not told about the alternative.
explain_install_mode() {
  if downloads_staged || products_installed; then
    return 0
  fi
  if [ "$(missing_external_tools)" = "${EXTERNAL_TOOLS[*]}" ]; then
    return 0
  fi

  header "Pro tools from the environment"
  detail "Checking whether your environment already provides the pro tools:"
  printf '\n'
  report_environment
  printf '\n'
  detail "Your environment can only be used as is when every one of these is"
  detail "present. Some are missing, so setup-pro will attempt to install a "
  detail "complete set for you from the downloads staged under "
  detail "$PRO_DOWNLOADS instead."
  printf '\n'
  detail "To use your existing environment, put the missing tools on PATH (and"
  detail "the missing libraries on GPR_PROJECT_PATH) and re-run."
}

# Check every tool/library external mode needs is on PATH/GPR_PROJECT_PATH, and
# report where.
use_external_tools() {
  header "Pro tools from the environment"
  report_environment

  local missing_tools missing_libs problems=
  missing_tools=$(missing_external_tools)
  missing_libs=$(missing_external_libraries)
  if [ -n "$missing_tools" ]; then
    problems+="
  -  not found on PATH: $missing_tools"
  fi
  if [ -n "$missing_libs" ]; then
    problems+="
  -  not found on GPR_PROJECT_PATH: $missing_libs"
  fi
  if [ -n "$problems" ]; then
    fatal "PRO_TOOLS=external, but:$problems

Please try again from an environment that provides all the expected tools, or
stage the GNAT Tracker downloads under

    $PRO_DOWNLOADS

and re-run 'make setup-pro' to install them locally."
  fi
}

# GNAT Tracker downloads may be zipfiles wrapping the product tarball
# (alongside SBOM and certification artifacts). Look inside the staged zips,
# newest version first, for a member whose basename matches the tarball glob
# ($1) and extract the first match into $PRO_DOWNLOADS, where the caller (and
# later runs) find it directly. Returns non-zero if nothing matches.
extract_tarball_from_zip() {
  local glob=$1 zip member base
  compgen -G "$PRO_DOWNLOADS/*.zip" >/dev/null || return 1
  require_cmd unzip

  while IFS= read -r zip; do
    while IFS= read -r member; do
      base=${member##*/}
      # shellcheck disable=SC2254  # unquoted $glob: glob matching is the point
      case "$base" in
        $glob)
          detail "Extracting $base from ${zip##*/} ..."
          unzip -q -o -j "$zip" "$member" -d "$PRO_DOWNLOADS"
          return 0
          ;;
      esac
    done < <(unzip -Z1 "$zip")
  done < <(printf '%s\n' "$PRO_DOWNLOADS"/*.zip | sort -Vr)
  return 1
}

# Echo the newest staged tarball matching glob $1, extracting it from a staged
# zipfile first if none is staged directly. Non-zero (and silent) if there is
# none either way.
find_tarball() {
  local glob=$1 tarball
  # `|| true`: when $PRO_DOWNLOADS does not exist yet, find fails and pipefail
  # would abort the script before the caller can explain.
  tarball=$(find "$PRO_DOWNLOADS" -maxdepth 1 -name "$glob" 2>/dev/null | sort -V | tail -1 || true)
  if [ -z "$tarball" ] && extract_tarball_from_zip "$glob"; then
    tarball=$(find "$PRO_DOWNLOADS" -maxdepth 1 -name "$glob" 2>/dev/null | sort -V | tail -1 || true)
  fi
  [ -n "$tarball" ] && printf '%s\n' "$tarball"
}

# The pro products, one per entry, as '|'-separated fields:
#   glob    shell glob matching the tarball in $PRO_DOWNLOADS (staged directly
#           or wrapped in a staged zipfile)
#   subdir  prefix sub-directory under $PRO_DIR (also the PATH entry)
#   marker  file (relative to the prefix) proving a successful install: a
#           binary for the toolchains, a project file for the library products
#   label   human-readable name
PRO_PRODUCTS=(
  'gnatpro-*-x86_64-linux-bin.tar.gz|gnatpro|bin/gnat|GNAT Pro native (gnat, gprbuild, gnatformat, AUnit)'
  'gnatpro-*-arm-elf-*-bin.tar.gz|arm-elf|bin/arm-eabi-gnat|GNAT Pro arm-elf cross compiler'
  'spark-pro-*-x86_64-linux-bin.tar.gz|spark|bin/gnatprove|SPARK Pro (gnatprove)'
  'gnatdas-*-x86_64-linux-bin.tar.gz|gnatdas|bin/gnatcov|GNAT DAS (gnatcov, gnattest)'
  'libadalang-*-x86_64-linux-bin.tar.gz|libadalang|share/gpr/libadalang.gpr|Libadalang'
)

# Check that a tarball is staged for every product not yet installed, and
# report them all before installing anything, so one trip to GNAT Tracker
# fetches everything that is missing.
check_downloads() {
  header "Staged pro downloads"
  local created=
  if [ ! -d "$PRO_DOWNLOADS" ]; then
    mkdir -p "$PRO_DOWNLOADS"
    created=1
  fi

  local entry glob subdir marker label tarball missing=()
  for entry in "${PRO_PRODUCTS[@]}"; do
    IFS='|' read -r glob subdir marker label <<<"$entry"
    if marker_present "$PRO_DIR/$subdir/$marker"; then
      detail "$(printf '%-38s' "$glob") already installed"
    elif tarball=$(find_tarball "$glob"); then
      detail "$(printf '%-38s' "$glob") ${tarball##*/}"
    else
      detail "$(printf '%-38s' "$glob") MISSING ($label)"
      missing+=("$glob")
    fi
  done
  [ ${#missing[@]} -eq 0 ] && return 0

  local where="$PRO_DOWNLOADS"
  [ -n "$created" ] && where="$where
(the directory has just been created for you)"
  fatal "no tarball (or zipfile containing one) found in

    $where

for ${#missing[@]} of the ${#PRO_PRODUCTS[@]} pro products, marked MISSING above.

Log in to GNAT Tracker and download the x86_64-linux packages for GNAT Pro
for Ada (native and arm-elf), SPARK Pro, GNAT DAS and Libadalang, as either
the product tarballs or the zipfiles wrapping them. Copy them into the
directory above, then re-run 'make setup-pro'.

Alternatively, re-run it from an environment that already provides the pro
tools to use them directly. If you thought your environement was already setup
with the required tools, run

    make setup-pro PRO_TOOLS=external

to see a list of dependencies that were missing."
}

# Install one pro product (a PRO_PRODUCTS entry, fields as $1..$4) from its
# GNAT Tracker download into its own prefix under $PRO_DIR, using the bundled
# `doinstall` script in unattended mode.
install_product() {
  local glob=$1 subdir=$2 marker=$3 label=$4
  header "$label"

  local prefix="$PRO_DIR/$subdir"
  if marker_present "$prefix/$marker"; then
    detail "Already installed ($prefix/$marker); skipping."
    return 0
  fi

  require_cmd tar make

  local tarball
  tarball=$(find_tarball "$glob") \
    || fatal "no tarball matching '$glob' in $PRO_DOWNLOADS (it was there a moment ago)."
  detail "Tarball:  $tarball"

  local tmp srcdir log
  tmp=$(mktemp -d)
  detail "Extracting into $tmp ..."
  tar -xzf "$tarball" -C "$tmp"
  srcdir=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)

  detail "Installing into $prefix (this can take a minute) ..."
  mkdir -p "$prefix"
  # `doinstall <dir>` installs into <dir> unattended.
  log="$tmp/install.log"
  if ! (cd "$srcdir" && ./doinstall "$prefix") >"$log" 2>&1; then
    tail -n 40 "$log" >&2 || true
    fatal "doinstall failed for $label (full log: $log)."
  fi
  # Verify the marker file landed: doinstall exiting 0 without it must
  # still read as a failure.
  if ! marker_present "$prefix/$marker"; then
    fatal "doinstall for $label succeeded but $prefix/$marker is missing
(full log: $log)."
  fi
  rm -rf "$tmp"
  local version=
  if ! is_gpr_file "$marker"; then
    version=$("$prefix/$marker" --version 2>/dev/null | head -1 || true)
  fi
  detail "Installed: ${version:-(ok)}"
}

# Install every pro product needed by the demo (check_downloads has already
# accounted for all their downloads).
install_pro_products() {
  local entry glob subdir marker label
  for entry in "${PRO_PRODUCTS[@]}"; do
    IFS='|' read -r glob subdir marker label <<<"$entry"
    install_product "$glob" "$subdir" "$marker" "$label"
  done
}

# Deliberately leave alr unconfigured: no index, no toolchain selection.
# The root crate has no dependencies, so alr falls back to the tools on
# PATH; with no index there is nothing to fetch, so builds need no network
# and no stored selection can go stale.
configure_alr_offline() {
  header "Alire offline configuration"

  mkdir -p "$ALIRE_SETTINGS_DIR"
  # Remove the community index a community setup configured (`--del` of an
  # absent index is an error), and keep alr builds that know the setting
  # from silently re-adding it. No auto-refresh, no toolchain assistant.
  run_alr index --del community >/dev/null 2>&1 || true
  set_alr_setting index.auto_community false
  set_alr_setting index.auto_update 0
  set_alr_setting toolchain.assistant false
  # Clear any toolchain selection a community setup stored (`--unset` of a
  # missing key is an error, hence || true).
  local key
  for key in toolchain.use.gnat toolchain.use.gprbuild \
    toolchain.external.gnat toolchain.external.gprbuild; do
    run_alr settings --global --unset "$key" >/dev/null 2>&1 || true
  done
  detail "No index, no toolchain selection: alr resolves the pro tools on"
  detail "PATH and never touches the network."
}

print_summary() {
  header "setup-pro complete"
  detail "uv                 $(report_tool uv)"
  detail "alr                $(report_tool alr)"
  detail "GNAT Pro (native)  $PRO_DIR/gnatpro"
  detail "GNAT Pro (arm-elf) $PRO_DIR/arm-elf"
  detail "SPARK Pro          $PRO_DIR/spark"
  detail "GNAT DAS           $PRO_DIR/gnatdas"
  detail "Libadalang         $PRO_DIR/libadalang"
  printf '\n'
  detail "The Makefile detects this install automatically. To run the tools"
  detail "from your shell, add to your profile:"
  detail "  export PATH=\"$LOCAL_BIN:$PRO_DIR/gnatpro/bin:$PRO_DIR/arm-elf/bin:$PRO_DIR/spark/bin:$PRO_DIR/gnatdas/bin:\$PATH\""
  local lal_libs="$PRO_DIR/libadalang/lib:$PRO_DIR/libadalang/lib64"
  detail "  export GPR_PROJECT_PATH=\"$PRO_DIR/libadalang/share/gpr:\$GPR_PROJECT_PATH\""
  detail "  export LIBRARY_PATH=\"$lal_libs:\$LIBRARY_PATH\""
  detail "  export LD_LIBRARY_PATH=\"$lal_libs:\$LD_LIBRARY_PATH\""
  detail "  export ALIRE_SETTINGS_DIR=\"$ALIRE_SETTINGS_DIR\""
}

print_summary_external() {
  header "setup-pro complete (external tools)"
  detail "uv                 $(report_tool uv)"
  detail "alr                $(report_tool alr)"
  detail "Pro tools          from the environment (see above)"
  printf '\n'
  detail "The Makefile detects this setup automatically, but installs no"
  detail "toolchain: run make from a shell where the pro tools are available."
  detail "To match the make environment in your shell, add to your profile:"
  detail "  export PATH=\"$LOCAL_BIN:\$PATH\""
  detail "  export ALIRE_SETTINGS_DIR=\"$ALIRE_SETTINGS_DIR\""
}


mode=$(select_mode)

if [ "$mode" = external ]; then
  # Validate (and report) the ambient tools before installing anything else.
  use_external_tools
else
  # Forced install mode needs no explanation.
  if [ -z "${PRO_TOOLS:-}" ]; then
    explain_install_mode
  fi
  # The tarball globs above are x86_64-linux only; fail before installing
  # anything on other hosts.
  platform=$(detect_platform)
  if [ "$platform" != "x86_64 linux" ]; then
    fatal "setup-pro currently supports x86_64 Linux hosts only (detected: $platform)."
  fi
  # Likewise, account for every download before installing anything.
  check_downloads
fi

"$SCRIPT_DIR/common.sh"
if [ "$mode" = install ]; then
  install_pro_products
fi
configure_alr_offline
if [ "$mode" = external ]; then
  write_setup_marker external
  print_summary_external
else
  write_setup_marker pro
  print_summary
fi
