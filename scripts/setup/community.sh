#!/usr/bin/env bash
#
# Provision community versions of all tooling needed for the demo.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/setup/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_vars LOCAL_BIN ALIRE_SETTINGS_DIR ALIRE_PREFIX SETUP_MARKER

# Increase the solver timeout to 60 seconds (since `-n` skips the "Do you want
# to keep solving" prompt).
ALR_SOLVER_TIMEOUT=60
configure_alr() {
  header "Alire configuration"
  mkdir -p "$ALIRE_SETTINGS_DIR"
  detail "Setting solver timeout to $ALR_SOLVER_TIMEOUT seconds ..."
  set_alr_setting solver.timeout "$ALR_SOLVER_TIMEOUT"
}

# Deploy the GNAT toolchains needed by the demo and select the native one as
# alr's default. gnat_native and gnat_arm_elf both provide the abstract
# `gnat`, so this deploys all three but selects only gnat_native and
# gprbuild; the qemu crate picks up gnat_arm_elf through its own manifest.
# Always (re-)selects so that switching back from a pro setup restores the
# community selection; deployments are cached, so re-runs don't re-download.
deploy_toolchains() {
  header "GNAT toolchains (gnat_arm_elf, gnat_native, gprbuild)"

  mkdir -p "$ALIRE_SETTINGS_DIR"

  # Undo the pro setup's offline configuration, if present: restore the
  # index auto-refresh defaults. (`--unset` of a missing key is an error.)
  local key
  for key in index.auto_community index.auto_update; do
    run_alr settings --global --unset "$key" >/dev/null 2>&1 || true
  done

  # Configure the community index manually.
  # Re-adding an existing index is an error, hence the --list check.
  local indexes
  indexes=$(run_alr index --list 2>/dev/null || true)
  if grep -qE '^[0-9]+ +community ' <<<"$indexes"; then
    detail "Community index already configured."
  else
    detail "Adding the community index ..."
    run_alr index --add https://github.com/alire-project/alire-index.git \
      --name community
  fi

  # Fail early, and clearly, if this alr cannot resolve community crates
  # before toolchain selection trips over it (which has a less clear error).
  local crates
  crates=$(run_alr search --crates gnat_arm_elf 2>/dev/null || true)
  if ! grep -q '^gnat_arm_elf ' <<<"$crates"; then
    fatal "the community index is configured, but 'gnat_arm_elf' does not
resolve in it. This alr ($(run_alr --version 2>/dev/null || echo unknown))
may be incompatible with the index format."
  fi

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
configure_alr
deploy_toolchains
install_tools
write_setup_marker community
print_summary
