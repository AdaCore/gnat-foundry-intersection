#!/usr/bin/env bash
#
# Provision community versions of all tooling needed for the demo.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/setup/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_vars LOCAL_BIN ALIRE_SETTINGS_DIR ALIRE_PREFIX SETUP_MARKER

# `install_alire`, `resolve_alr`, `write_setup_marker` and `report_tool` are
# shared with the pro setup and live in lib.sh.

# Deploy the GNAT toolchains needed by the demo and select them as alr's
# default. Always (re-)selects so that switching back from a pro setup
# restores the community selection; deployments are cached, so re-runs don't
# re-download.
deploy_toolchains() {
  header "GNAT toolchains (gnat_arm_elf, gnat_native, gprbuild)"

  mkdir -p "$ALIRE_SETTINGS_DIR"

  detail "Deploying and selecting gnat_arm_elf, gnat_native, gprbuild ..."
  "${ALR[@]}" toolchain --select gnat_arm_elf gnat_native gprbuild
}

# Install the Alire-installed tools needed by the demo into the local prefix.
install_tools() {
  header "Alire-installed tools (gnattest, gnatcov, gnatformat, gnatprove)"

  mkdir -p "$ALIRE_PREFIX"

  if [ -x "$ALIRE_PREFIX/bin/gnattest" ] \
    && [ -x "$ALIRE_PREFIX/bin/gnatcov" ] \
    && [ -x "$ALIRE_PREFIX/bin/gnatformat" ] \
    && [ -x "$ALIRE_PREFIX/bin/gnatprove" ]; then
    detail "All already installed — skipping."
    return 0
  fi

  detail "Installing gnattest, gnatcov, gnatformat, gnatprove ..."
  "${ALR[@]}" install --prefix="$ALIRE_PREFIX" \
    gnattest_bin gnatcov_bin gnatformat_bin gnatprove
}

print_summary() {
  header "setup-community complete"
  detail "uv                           $(report_tool uv)"
  detail "alr                          $(report_tool alr)"
  detail "GNAT toolchains              deployed under $ALIRE_SETTINGS_DIR"
  detail "gnat{test,cov,format,prove}  installed in $ALIRE_PREFIX/bin/"
  printf '\n'
  detail "The Makefile uses these automatically. To run the tools from your"
  detail "shell, add to your profile:"
  detail "  export PATH=\"$LOCAL_BIN:$ALIRE_PREFIX/bin:\$PATH\""
  detail "  export ALIRE_SETTINGS_DIR=\"$ALIRE_SETTINGS_DIR\""
}


"$SCRIPT_DIR/common.sh"
install_alire
resolve_alr
deploy_toolchains
install_tools
write_setup_marker community
print_summary
