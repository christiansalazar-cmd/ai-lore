#!/usr/bin/env bash
# Shared helpers for the ai-lore CLI (bin/ai-lore).
# Source this file; do not execute it directly.

have_gum() { command -v gum >/dev/null 2>&1; }

ui_header() {
  if have_gum; then
    gum style --bold -- "$1" || echo "== $1 =="
  else
    echo ""
    echo "== $1 =="
  fi
}

ui_pause() {
  if have_gum; then
    gum input --placeholder "Press Enter to continue..." --prompt "" >/dev/null 2>&1 || true
  else
    read -r -p "Press Enter to continue... " _ || true
  fi
}

ui_confirm() {
  # $1 = prompt. Returns 0 for yes, 1 for no.
  local prompt="$1"
  if have_gum; then
    gum confirm "$prompt"
  else
    local ans=""
    read -r -p "$prompt [y/N]: " ans || true
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
  fi
}

# choose_one HEADER ITEM...  -> prints the chosen item on stdout (empty if none)
choose_one() {
  local header="$1"
  shift
  local items=("$@")
  [[ ${#items[@]} -eq 0 ]] && return 0
  if have_gum; then
    printf '%s\n' "${items[@]}" | gum choose --header "$header" || true
  else
    echo "" >&2
    echo "$header" >&2
    local i
    for i in "${!items[@]}"; do
      printf '  %d) %s\n' "$((i + 1))" "${items[$i]}" >&2
    done
    local pick=""
    read -r -p "Choose [1-${#items[@]}] (blank to cancel): " pick || true
    [[ -z "$pick" ]] && return 0
    if [[ "$pick" =~ ^[0-9]+$ ]] && ((pick >= 1 && pick <= ${#items[@]})); then
      printf '%s\n' "${items[$((pick - 1))]}"
    fi
  fi
}

# choose_multi HEADER ITEM...  -> prints chosen items (one per line); empty if none
choose_multi() {
  local header="$1"
  shift
  local items=("$@")
  [[ ${#items[@]} -eq 0 ]] && return 0
  if have_gum; then
    printf '%s\n' "${items[@]}" | gum choose --no-limit --header "$header" || true
  else
    echo "" >&2
    echo "$header" >&2
    local i
    for i in "${!items[@]}"; do
      printf '  %d) %s\n' "$((i + 1))" "${items[$i]}" >&2
    done
    local raw=""
    read -r -p "Choose multiple (e.g. 1 3 4 or 'all', blank to skip): " raw || true
    [[ -z "$raw" ]] && return 0
    if [[ "${raw,,}" == "all" ]]; then
      printf '%s\n' "${items[@]}"
      return 0
    fi
    local tok
    for tok in ${raw//,/ }; do
      if [[ "$tok" =~ ^[0-9]+$ ]] && ((tok >= 1 && tok <= ${#items[@]})); then
        printf '%s\n' "${items[$((tok - 1))]}"
      fi
    done
  fi
}

# read_secret_masked PROMPT -> prints secret on stdout (no echo to terminal)
read_secret_masked() {
  local prompt="${1:-Paste value (hidden): }"
  if have_gum; then
    gum input --password --prompt "$prompt"
  else
    local val=""
    read -r -s -p "$prompt" val || true
    echo "" >&2
    printf '%s' "${val:-}"
  fi
}

# ensure_gitignore_line FILE LINE  -> append LINE to FILE if not already present
ensure_gitignore_line() {
  local file="$1" line="$2"
  [[ -z "$file" || -z "$line" ]] && return 0
  mkdir -p "$(dirname "$file")"
  if [[ -f "$file" ]] && grep -qxF "$line" "$file" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$line" >>"$file"
}
