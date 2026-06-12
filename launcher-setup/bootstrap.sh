#!/usr/bin/env bash
# Non-interactive tooling for the ai-lore dev container (runs at postCreate).
# Invoked from .devcontainer/devcontainer.json — keep that path stable for Codespaces.
set -euo pipefail

if command -v gum >/dev/null 2>&1; then
  echo "bootstrap: gum already on PATH ($(command -v gum)), skipping install."
  exit 0
fi

GUM_VERSION="${GUM_VERSION:-0.15.2}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

arch="$(uname -m)"
case "$arch" in
  x86_64) gum_arch="x86_64" ;;
  aarch64 | arm64) gum_arch="arm64" ;;
  *)
    echo "bootstrap: unsupported architecture: $arch (gum not installed)" >&2
    exit 0
    ;;
esac

url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_${gum_arch}.tar.gz"
echo "bootstrap: downloading gum v${GUM_VERSION} (${gum_arch})..."
curl -fsSL "$url" | tar xz -C "$TMP"

gum_bin="$(find "$TMP" -type f -name gum | head -n 1)"
if [[ -z "$gum_bin" ]]; then
  echo "bootstrap: could not find gum binary in archive" >&2
  exit 1
fi

if command -v sudo >/dev/null 2>&1; then
  sudo install -m 0755 "$gum_bin" /usr/local/bin/gum
else
  local_bin="${HOME}/.local/bin"
  mkdir -p "$local_bin"
  install -m 0755 "$gum_bin" "${local_bin}/gum"
  if [[ -f "${HOME}/.bashrc" ]] && ! grep -q '\.local/bin' "${HOME}/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >>"${HOME}/.bashrc"
  fi
fi

echo "bootstrap: gum installed."

