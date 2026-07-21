#!/usr/bin/env bash
#
# Provision the tooling that does not differ between community and pro
# configurations.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/setup/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_vars LOCAL_BIN

# uv: install the latest official release from GitHub, locally into $LOCAL_BIN.
install_uv() {
  header "uv (Python package manager)"

  if [ -x "$LOCAL_BIN/uv" ]; then
    detail "Already installed locally ($LOCAL_BIN/uv); skipping."
    return 0
  fi
  if command -v uv >/dev/null 2>&1; then
    detail "Found on PATH ($(command -v uv)); skipping local install."
    return 0
  fi

  require_cmd curl tar

  local platform arch os triple url tmp
  platform=$(detect_platform)
  arch=${platform%% *}
  os=${platform##* }
  case "$os" in
    linux) triple="$arch-unknown-linux-gnu" ;;
    *) fatal "unsupported OS: $os" ;;
  esac
  url="https://github.com/astral-sh/uv/releases/latest/download/uv-$triple.tar.gz"
  tmp=$(mktemp -d)

  detail "Downloading $url"
  detail "  to temporary dir $tmp"
  curl -fsSL "$url" -o "$tmp/uv.tar.gz"
  tar -xzf "$tmp/uv.tar.gz" -C "$tmp"

  detail "Installing uv + uvx into $LOCAL_BIN"
  mkdir -p "$LOCAL_BIN"
  mv "$tmp/uv-$triple/uv" "$tmp/uv-$triple/uvx" "$LOCAL_BIN/"
  rm -rf "$tmp"
  detail "Installed version: $("$LOCAL_BIN/uv" --version)"
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

# Install the AdaCore's Codex plugin (if the codex CLI is available)
install_codex_plugin() {
  header "AdaCore Codex plugin"

  if ! command -v codex >/dev/null 2>&1; then
    detail "codex not found on PATH; skipping AdaCore plugin install."
    return 0
  fi

  detail "Installing AdaCore Codex plugin ..."
  codex plugin marketplace add adacore/skills
  codex plugin add adacore@adacore-skills
}

install_uv
install_alire
install_codex_plugin
