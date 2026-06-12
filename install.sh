#!/usr/bin/env bash
# One-time installer: make `ai-lore` runnable from any project terminal.
# Safe to re-run. Does not touch your projects; only sets up the command.

set -euo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
BIN_SRC="${REPO_DIR}/bin/ai-lore"
LOCAL_BIN="${HOME}/.local/bin"
LINK="${LOCAL_BIN}/ai-lore"

if [[ ! -f "$BIN_SRC" ]]; then
  echo "install: cannot find ${BIN_SRC}" >&2
  exit 1
fi
chmod +x "$BIN_SRC" 2>/dev/null || true

mkdir -p "$LOCAL_BIN"
ln -sf "$BIN_SRC" "$LINK"
echo "install: linked ${LINK} -> ${BIN_SRC}"

# Detect whether ~/.local/bin is already on PATH.
on_path=0
case ":${PATH}:" in
  *":${LOCAL_BIN}:"*) on_path=1 ;;
esac

profile=""
if [[ -n "${ZSH_VERSION:-}" || "${SHELL:-}" == *zsh ]]; then
  profile="${HOME}/.zshrc"
else
  profile="${HOME}/.bashrc"
fi

if [[ "$on_path" -eq 0 ]]; then
  line='export PATH="$HOME/.local/bin:$PATH"'
  if [[ -f "$profile" ]] && grep -qF '.local/bin' "$profile" 2>/dev/null; then
    :
  else
    printf '\n# Added by ai-lore install.sh\n%s\n' "$line" >>"$profile"
    echo "install: added ~/.local/bin to PATH in ${profile}"
  fi
  echo ""
  echo "Open a new terminal (or run: source ${profile}) so 'ai-lore' is found."
else
  echo "install: ~/.local/bin already on PATH."
fi

echo ""
echo "Next:"
echo "  1) cd into one of your projects"
echo "  2) run: ai-lore setup"
