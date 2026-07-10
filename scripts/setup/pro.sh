#!/usr/bin/env bash
#
# Provision the pro (GNAT Pro / SPARK Pro / GNATDAS) versions of all tooling
# needed for the demo, from tarballs or zip files downlaoded from GNAT Tracker

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/setup/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_vars LOCAL_BIN ALIRE_SETTINGS_DIR PRO_DIR PRO_DOWNLOADS SETUP_MARKER

# GNAT Tracker downloads may be zipfiles wrapping the product tarball
# (alongside SBOM and certification artifacts). Look inside the staged zips,
# newest version first, for a member whose basename matches the tarball glob
# ($1); extract the first match into $PRO_DOWNLOADS, where later runs find it
# directly, and echo its path. Returns non-zero if nothing matches.
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
          detail "Extracting $base from ${zip##*/} ..." >&2
          unzip -q -o -j "$zip" "$member" -d "$PRO_DOWNLOADS"
          printf '%s\n' "$PRO_DOWNLOADS/$base"
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

  require_cmd tar make tee clear

  # `|| true`: when $PRO_DOWNLOADS does not exist yet, find fails and pipefail
  # would abort the script before the fatal below can explain.
  local tarball
  tarball=$(find "$PRO_DOWNLOADS" -maxdepth 1 -name "$glob" 2>/dev/null | sort -V | tail -1 || true)
  if [ -z "$tarball" ]; then
    tarball=$(extract_tarball_from_zip "$glob" || true)
  fi
  if [ -z "$tarball" ]; then
    mkdir -p "$PRO_DOWNLOADS"
    fatal "no tarball (or zipfile containing one) matching '$glob' found in
$PRO_DOWNLOADS
(the directory has just been created for you).
Log in to GNAT Tracker and download the x86_64-linux packages for GNAT Pro
(native and arm-elf), SPARK Pro and GNATDAS, as either the product tarballs
or the zipfiles wrapping them. Copy them into the directory above, then
re-run 'make setup-pro'."
  fi
  detail "Tarball:  $tarball"

  local tmp srcdir log
  tmp=$(mktemp -d)
  detail "Extracting into $tmp ..."
  tar -xzf "$tarball" -C "$tmp"
  srcdir=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)

  detail "Installing into $prefix (this can take a minute) ..."
  mkdir -p "$prefix"
  # `doinstall <dir>` runs `make ins-all prefix=<dir>` unattended.
  log="$tmp/install.log"
  if ! (cd "$srcdir" && ./doinstall "$prefix") >"$log" 2>&1; then
    tail -n 40 "$log" >&2 || true
    fatal "doinstall failed for $label (full log: $log)."
  fi
  rm -rf "$tmp"
  detail "Installed: $("$prefix/$marker" --version 2>/dev/null | head -1 || echo '(ok)')"
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
    'GNATDAS (gnatcov, gnattest)'
}

# Select the external toolchain as alr's default
configure_alr_external() {
  header "Alire external-toolchain configuration"

  mkdir -p "$ALIRE_SETTINGS_DIR"
  PATH="$PRO_DIR/gnatpro/bin:$PATH" \
    "${ALR[@]}" toolchain --select --disable-assistant gnat_external gprbuild
  detail "External toolchain selected; alr builds against the pro GNAT on PATH."
}

print_summary() {
  header "setup-pro complete"
  detail "uv                 $(report_tool uv)"
  detail "alr                $(report_tool alr) (community build)"
  detail "GNAT Pro (native)  $PRO_DIR/gnatpro"
  detail "GNAT Pro (arm-elf) $PRO_DIR/arm-elf"
  detail "SPARK Pro          $PRO_DIR/spark"
  detail "GNATDAS            $PRO_DIR/gnatdas"
  printf '\n'
  detail "The Makefile detects this install automatically (SETUP=pro). To run"
  detail "the tools from your shell, add to your profile:"
  detail "  export PATH=\"$LOCAL_BIN:$PRO_DIR/gnatpro/bin:$PRO_DIR/arm-elf/bin:$PRO_DIR/spark/bin:$PRO_DIR/gnatdas/bin:\$PATH\""
  detail "  export ALIRE_SETTINGS_DIR=\"$ALIRE_SETTINGS_DIR\""
}


"$SCRIPT_DIR/common.sh"
install_alire
resolve_alr
install_pro_products
configure_alr_external
write_setup_marker pro
print_summary
