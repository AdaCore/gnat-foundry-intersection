#!/usr/bin/env bash
#
# Provision community versions of all tooling needed for the demo.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/setup/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_vars LOCAL_BIN ALIRE_SETTINGS_DIR ALIRE_PREFIX SETUP_MARKER

# Deploy the GNAT toolchains needed by the demo and select the native one as
# alr's default. gnat_native and gnat_arm_elf both provide the abstract
# `gnat`, so this deploys all three but selects only gnat_native and
# gprbuild; the qemu crate picks up gnat_arm_elf through its own manifest.
# Always (re-)selects so that switching back from a pro setup restores the
# community selection; deployments are cached, so re-runs don't re-download.
deploy_toolchains() {
  header "GNAT toolchains (gnat_arm_elf, gnat_native, gprbuild)"

  mkdir -p "$ALIRE_SETTINGS_DIR"

  # Undo the pro setup's offline configuration, if present: re-allow the
  # community index to be auto-added and auto-refreshed, so the community
  # crates resolve again. (`--unset` of a missing key is an error.)
  set_alr_setting index.auto_community true
  run_alr settings --global --unset index.auto_update >/dev/null 2>&1 || true

  detail "Deploying gnat_arm_elf. Deploying and selecting gnat_native and gprbuild ..."
  run_alr toolchain --select gnat_arm_elf gnat_native gprbuild
}

# Install the Alire-installed tools needed by the demo into the local prefix.
install_tools() {
  header "Alire-installed tools (gnattest, gnatcov, gnatformat, gnatprove)"

  mkdir -p "$ALIRE_PREFIX"

  if [ -x "$ALIRE_PREFIX/bin/gnattest" ] \
    && [ -x "$ALIRE_PREFIX/bin/gnatcov" ] \
    && [ -x "$ALIRE_PREFIX/bin/gnatformat" ] \
    && [ -x "$ALIRE_PREFIX/bin/gnatprove" ]; then
    detail "All already installed; skipping."
    return 0
  fi

  detail "Installing gnattest, gnatcov, gnatformat, gnatprove ..."
  run_alr install --prefix="$ALIRE_PREFIX" \
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
deploy_toolchains
install_tools
write_setup_marker community
print_summary
