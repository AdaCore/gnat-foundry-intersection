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

# True if every tool in EXTERNAL_TOOLS is available on PATH.
external_tools_available() {
  local cmd
  for cmd in "${EXTERNAL_TOOLS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || return 1
  done
}

# True if any pro download (tarball or zipfile) is staged under $PRO_DOWNLOADS.
downloads_staged() {
  compgen -G "$PRO_DOWNLOADS/*.tar.gz" >/dev/null \
    || compgen -G "$PRO_DOWNLOADS/*.zip" >/dev/null
}

# True if a previous run installed at least one product under $PRO_DIR.
products_installed() {
  [ -x "$PRO_DIR/gnatpro/bin/gnat" ] \
    || [ -x "$PRO_DIR/arm-elf/bin/arm-eabi-gnat" ] \
    || [ -x "$PRO_DIR/spark/bin/gnatprove" ] \
    || [ -x "$PRO_DIR/gnatdas/bin/gnatcov" ]
}

# Echo the mode: $PRO_TOOLS if forced; else 'install' when downloads are
# staged or products already installed, 'external' when the tools are on
# PATH, and 'install' otherwise (its staging instructions explain both).
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
  elif external_tools_available; then
    printf 'external\n'
  else
    printf 'install\n'
  fi
}

# Check every tool external mode needs is on PATH, and report where.
use_external_tools() {
  header "Pro tools from the environment"

  local cmd missing=()
  for cmd in "${EXTERNAL_TOOLS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [ ${#missing[@]} -ne 0 ]; then
    fatal "PRO_TOOLS=external, but not found on PATH: ${missing[*]}.
Run from an environment that provides the pro tools, or stage the GNAT
Tracker downloads under
$PRO_DOWNLOADS
and re-run 'make setup-pro' to install them locally."
  fi
  for cmd in "${EXTERNAL_TOOLS[@]}"; do
    detail "$(printf '%-14s' "$cmd") $(command -v "$cmd")"
  done
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

# Install one pro product from its GNAT Tracker download into its own prefix
# under $PRO_DIR, using the bundled `doinstall` script in unattended mode.
#
#   $1  shell glob matching the tarball in $PRO_DOWNLOADS (staged directly or
#       wrapped in a staged zipfile)
#   $2  prefix sub-directory under $PRO_DIR (also the PATH entry)
#   $3  marker binary (relative to the prefix) proving a successful install
#   $4  human-readable label
install_product() {
  local glob=$1 subdir=$2 marker=$3 label=$4
  header "$label"

  local prefix="$PRO_DIR/$subdir"
  if [ -x "$prefix/$marker" ]; then
    detail "Already installed ($prefix/$marker); skipping."
    return 0
  fi

  require_cmd tar make

  # `|| true`: when $PRO_DOWNLOADS does not exist yet, find fails and pipefail
  # would abort the script before the fatal below can explain.
  local tarball
  tarball=$(find "$PRO_DOWNLOADS" -maxdepth 1 -name "$glob" 2>/dev/null | sort -V | tail -1 || true)
  if [ -z "$tarball" ] && extract_tarball_from_zip "$glob"; then
    tarball=$(find "$PRO_DOWNLOADS" -maxdepth 1 -name "$glob" 2>/dev/null | sort -V | tail -1 || true)
  fi
  if [ -z "$tarball" ]; then
    mkdir -p "$PRO_DOWNLOADS"
    fatal "no tarball (or zipfile containing one) matching '$glob' found in
$PRO_DOWNLOADS
(the directory has just been created for you).
Log in to GNAT Tracker and download the x86_64-linux packages for GNAT Pro
for Ada (native and arm-elf), SPARK Pro and GNAT DAS, as either the product
tarballs or the zipfiles wrapping them. Copy them into the directory above,
then re-run 'make setup-pro'. Alternatively, re-run it from an environment
that already has the pro tools on PATH to use them directly."
  fi
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
  # Verify the marker binary landed: doinstall exiting 0 without it must
  # still read as a failure.
  if [ ! -x "$prefix/$marker" ]; then
    fatal "doinstall for $label succeeded but $prefix/$marker is missing
(full log: $log)."
  fi
  rm -rf "$tmp"
  local version
  version=$("$prefix/$marker" --version 2>/dev/null | head -1 || true)
  detail "Installed: ${version:-(ok)}"
}

# Install every pro product needed by the demo.
install_pro_products() {
  install_product 'gnatpro-*-x86_64-linux-bin.tar.gz' gnatpro bin/gnat \
    'GNAT Pro native (gnat, gprbuild, gnatformat, AUnit)'
  install_product 'gnatpro-*-arm-elf-*-bin.tar.gz' arm-elf bin/arm-eabi-gnat \
    'GNAT Pro arm-elf cross compiler'
  install_product 'spark-pro-*-x86_64-linux-bin.tar.gz' spark bin/gnatprove \
    'SPARK Pro (gnatprove)'
  install_product 'gnatdas-*-x86_64-linux-bin.tar.gz' gnatdas bin/gnatcov \
    'GNAT DAS (gnatcov, gnattest)'
}

# Deliberately leave alr unconfigured: no index, no toolchain selection.
# The root crate has no dependencies, so alr falls back to the tools on
# PATH; with no index there is nothing to fetch, so builds need no network
# and no stored selection can go stale.
configure_alr_offline() {
  header "Alire offline configuration"

  mkdir -p "$ALIRE_SETTINGS_DIR"
  # No auto-add/auto-refresh of the community index, no toolchain assistant.
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
  detail "alr                $(report_tool alr) (community build)"
  detail "GNAT Pro (native)  $PRO_DIR/gnatpro"
  detail "GNAT Pro (arm-elf) $PRO_DIR/arm-elf"
  detail "SPARK Pro          $PRO_DIR/spark"
  detail "GNAT DAS           $PRO_DIR/gnatdas"
  printf '\n'
  detail "The Makefile detects this install automatically. To run the tools"
  detail "from your shell, add to your profile:"
  detail "  export PATH=\"$LOCAL_BIN:$PRO_DIR/gnatpro/bin:$PRO_DIR/arm-elf/bin:$PRO_DIR/spark/bin:$PRO_DIR/gnatdas/bin:\$PATH\""
  detail "  export ALIRE_SETTINGS_DIR=\"$ALIRE_SETTINGS_DIR\""
}

print_summary_external() {
  header "setup-pro complete (external tools)"
  detail "uv                 $(report_tool uv)"
  detail "alr                $(report_tool alr) (community build)"
  detail "Pro tools          from the environment (see above)"
  printf '\n'
  detail "The Makefile detects this setup automatically, but installs no"
  detail "toolchain: run make from a shell where the pro tools are on PATH."
  detail "To match the make environment in your shell, add to your profile:"
  detail "  export PATH=\"$LOCAL_BIN:\$PATH\""
  detail "  export ALIRE_SETTINGS_DIR=\"$ALIRE_SETTINGS_DIR\""
}


mode=$(select_mode)

if [ "$mode" = external ]; then
  # Validate (and report) the ambient tools before installing anything else.
  use_external_tools
else
  # The tarball globs above are x86_64-linux only; fail before installing
  # anything on other hosts.
  platform=$(detect_platform)
  if [ "$platform" != "x86_64 linux" ]; then
    fatal "setup-pro currently supports x86_64 Linux hosts only (detected: $platform)."
  fi
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
