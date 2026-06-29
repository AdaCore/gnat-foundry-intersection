#!/usr/bin/env bash
#
# Provision community versions of all tooling needed for the demo.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/setup/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_vars LOCAL_BIN ALIRE_SETTINGS_DIR ALIRE_PREFIX

# Alire: install the latest official release from GitHub, locally into $LOCAL_BIN.
install_alire() {
  header "alr (Ada source package manager)"

  if [ -x "$LOCAL_BIN/alr" ]; then
    detail "Already installed locally ($LOCAL_BIN/alr) — skipping."
    return 0
  fi
  if command -v alr >/dev/null 2>&1; then
    detail "Found on PATH ($(command -v alr)) — skipping local install."
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
# Invoke after `install_alire`.
resolve_alr() {
  if [ -x "$LOCAL_BIN/alr" ]; then
    ALR=("$LOCAL_BIN/alr" -n)
  else
    ALR=(alr -n)
  fi
}

# Deploy the GNAT toolchains needed by the demo, under the local settings dir.
deploy_toolchains() {
  header "GNAT toolchains (gnat_arm_elf, gnat_native, gprbuild)"

  mkdir -p "$ALIRE_SETTINGS_DIR"

  local deployed
  deployed=$("${ALR[@]}" toolchain 2>/dev/null || true)
  if grep -q gnat_arm_elf <<<"$deployed" \
    && grep -q gnat_native <<<"$deployed" \
    && grep -q gprbuild <<<"$deployed"; then
    detail "All three already deployed — skipping."
    return 0
  fi

  detail "Deploying gnat_arm_elf, gnat_native, gprbuild ..."
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

# Echo a description of a tool's location.
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

print_summary() {
  header "setup-community complete"
  detail "uv / uvx               $(report_tool uv)"
  detail "alr                    $(report_tool alr)"
  detail "GNAT toolchains        deployed under $ALIRE_SETTINGS_DIR"
  detail "Alire-installed tools  installed in $ALIRE_PREFIX/bin"
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
print_summary
