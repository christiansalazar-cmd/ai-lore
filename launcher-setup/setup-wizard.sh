#!/usr/bin/env bash
# Interactive setup wizard (Codespaces / devcontainer). Lives under launcher-setup/.
# API keys are collected ONLY in the MCP flow and stored as GitHub Codespaces
# user secrets via `gh secret set --user` (stdin). Never written to repo .env.

set -euo pipefail

STATE_DIR="${HOME}/.config/ai-lore"
STATE_FILE="${STATE_DIR}/wizard-state.json"

have_gum() { command -v gum >/dev/null 2>&1; }

pause() {
  if have_gum; then
    gum input --placeholder "Press Enter to continue..." --prompt "" >/dev/null 2>&1 || true
  else
    read -r -p "Press Enter to continue... " _ || true
  fi
}

menu_main() {
  if have_gum; then
    gum choose --header "ai-lore setup" \
      "Feature toggles (local only, no API keys)" \
      "MCP: enable integrations & store API keys (Codespaces secrets)" \
      "Help: where API keys should live" \
      "Exit"
  else
    echo ""
    echo "=== ai-lore setup ==="
    echo "1) Feature toggles (local only, no API keys)"
    echo "2) MCP: enable integrations & store API keys (Codespaces secrets)"
    echo "3) Help: where API keys should live"
    echo "4) Exit"
    read -r -p "Choose [1-4]: " choice
    case "$choice" in
      1) echo "Feature toggles (local only, no API keys)" ;;
      2) echo "MCP: enable integrations & store API keys (Codespaces secrets)" ;;
      3) echo "Help: where API keys should live" ;;
      *) echo "Exit" ;;
    esac
  fi
}

menu_mcp_pick() {
  if have_gum; then
    gum choose --header "Pick an MCP template (env name is suggested)" \
      "Example: EXA_API_KEY (generic search MCP)" \
      "Example: CONTEXT7_API_KEY (documentation MCP)" \
      "Custom: I will type the secret name (e.g. MY_VENDOR_TOKEN)" \
      "Back"
  else
    echo ""
    echo "=== MCP templates ==="
    echo "1) EXA_API_KEY"
    echo "2) CONTEXT7_API_KEY"
    echo "3) Custom secret name"
    echo "4) Back"
    read -r -p "Choose [1-4]: " c
    case "$c" in
      1) echo "Example: EXA_API_KEY (generic search MCP)" ;;
      2) echo "Example: CONTEXT7_API_KEY (documentation MCP)" ;;
      3) echo "Custom: I will type the secret name (e.g. MY_VENDOR_TOKEN)" ;;
      *) echo "Back" ;;
    esac
  fi
}

secret_name_from_pick() {
  case "$1" in
    *EXA_API_KEY*) echo "EXA_API_KEY" ;;
    *CONTEXT7_API_KEY*) echo "CONTEXT7_API_KEY" ;;
    *Custom*)
      if have_gum; then
        gum input --placeholder "UPPER_SNAKE_CASE e.g. STRIPE_API_KEY" --prompt "Secret name: "
      else
        read -r -p "Secret name (env var): " || true
        printf '%s' "${REPLY:-}"
      fi
      ;;
    *Back*) echo "" ;;
    *) echo "" ;;
  esac
}

read_secret_masked() {
  if have_gum; then
    gum input --password --prompt "Paste API key (hidden): "
  else
    local val=""
    read -r -s -p "Paste API key (hidden): " val || true
    echo "" >&2
    printf '%s' "${val:-}"
  fi
}

detect_repo() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo "$GITHUB_REPOSITORY"
    return
  fi
  if command -v gh >/dev/null 2>&1; then
    gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true
  fi
}

# Upload secret to GitHub Codespaces user secrets. Caller pipes secret on stdin.
gh_upload_codespaces_user_secret() {
  local secret_name="$1"
  local repo
  repo="$(detect_repo)"

  if ! command -v gh >/dev/null 2>&1; then
    echo "gh (GitHub CLI) not found. Install it or add secrets in the GitHub UI:" >&2
    echo "  https://github.com/settings/codespaces" >&2
    return 1
  fi

  # Prefer --app codespaces when supported; fall back for older gh versions.
  if [[ -n "$repo" ]]; then
    gh secret set "$secret_name" --user --app codespaces --repos "$repo" 2>/dev/null \
      || gh secret set "$secret_name" --user --repos "$repo"
  else
    echo "Could not detect repo (GITHUB_REPOSITORY unset, gh repo view failed)." >&2
    echo "Export GITHUB_REPOSITORY=owner/repo, or add the secret in:" >&2
    echo "  https://github.com/settings/codespaces" >&2
    gh secret set "$secret_name" --user --app codespaces 2>/dev/null \
      || gh secret set "$secret_name" --user
  fi
}

write_state_json() {
  mkdir -p "$STATE_DIR"
  python3 - "$STATE_FILE" "$1" "$2" "$3" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
demo, exa, ctx = sys.argv[2], sys.argv[3], sys.argv[4]
data: dict = {"version": 1, "aiFeatures": {"demoTips": False}, "mcp": {}}
if path.exists():
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        pass
data.setdefault("aiFeatures", {})
data.setdefault("mcp", {})
data["aiFeatures"]["demoTips"] = demo == "true"
data["mcp"]["EXA_API_KEY_enabled"] = exa == "true"
data["mcp"]["CONTEXT7_API_KEY_enabled"] = ctx == "true"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(path)
PY
}

read_mcp_flags() {
  local exa="false" ctx="false"
  if [[ -f "$STATE_FILE" ]]; then
    exa="$(python3 - "$STATE_FILE" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    print("false")
    raise SystemExit(0)
d = json.loads(p.read_text(encoding="utf-8"))
print("true" if d.get("mcp", {}).get("EXA_API_KEY_enabled") else "false")
PY
)"
    ctx="$(python3 - "$STATE_FILE" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    print("false")
    raise SystemExit(0)
d = json.loads(p.read_text(encoding="utf-8"))
print("true" if d.get("mcp", {}).get("CONTEXT7_API_KEY_enabled") else "false")
PY
)"
  fi
  printf '%s %s' "$exa" "$ctx"
}

feature_toggles() {
  local demo_tips="false"
  if have_gum; then
    demo_tips=$(gum confirm "Enable on-screen demo tips?" && echo true || echo false)
  else
    read -r -p "Enable demo tips? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] && demo_tips="true" || demo_tips="false"
  fi

  local flags exa ctx
  flags="$(read_mcp_flags)"
  exa="${flags%% *}"
  ctx="${flags#* }"

  write_state_json "$demo_tips" "$exa" "$ctx"
  echo "Saved local preferences to ${STATE_FILE} (no secrets stored here)."
}

merge_mcp_secret_state() {
  python3 - "$STATE_FILE" "$1" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
name = sys.argv[2]
data = {"version": 1, "aiFeatures": {"demoTips": False}, "mcp": {}}

if path.exists():

    try:

        data = json.loads(path.read_text(encoding="utf-8"))

    except json.JSONDecodeError:

        pass

data.setdefault("aiFeatures", {})

data.setdefault("mcp", {})

if name == "EXA_API_KEY":

    data["mcp"]["EXA_API_KEY_enabled"] = True

elif name == "CONTEXT7_API_KEY":

    data["mcp"]["CONTEXT7_API_KEY_enabled"] = True

else:

    data["mcp"].setdefault("custom", [])

    if name not in data["mcp"]["custom"]:

        data["mcp"]["custom"].append(name)

path.parent.mkdir(parents=True, exist_ok=True)

path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

PY

}



mcp_flow() {

  local pick name secret_val

  pick="$(menu_mcp_pick)"

  [[ -z "$pick" || "$pick" == "Back" ]] && return 0



  name="$(secret_name_from_pick "$pick")"

  name="$(printf '%s' "$name" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [[ -z "$name" ]]; then

    echo "No secret name; cancelled."

    return 0

  fi



  echo ""

  echo "This will store ONLY in your GitHub Codespaces user secrets as: ${name}"

  echo "It will NOT be written to any file in this repository."

  if ! have_gum; then

    read -r -p "Continue? [y/N]: " ok

    [[ "${ok,,}" == "y" ]] || return 0

  else

    gum confirm "Continue uploading this key as a Codespaces user secret?" || return 0

  fi



  set +o history 2>/dev/null || true

  secret_val="$(read_secret_masked)"

  set -o history 2>/dev/null || true



  if [[ -z "$secret_val" ]]; then

    echo "Empty secret; cancelled."

    return 0

  fi



  if printf '%s' "$secret_val" | gh_upload_codespaces_user_secret "$name"; then

    echo "Stored Codespaces user secret: ${name}"

    merge_mcp_secret_state "$name"

    unset secret_val 2>/dev/null || true

  else

    echo ""

    echo "If gh reported missing scopes, run:"

    echo "  gh auth refresh -h github.com -s user -s read:user"

    unset secret_val 2>/dev/null || true

    return 1

  fi

}



help_keys() {

  cat <<'EOF'



API keys — recommended order

------------------------------

1) Best: no long-lived key (OAuth / device login) when your MCP supports it.

2) Practical: GitHub Codespaces *development* (user) secrets — set once; they

   persist for future codespaces until you delete or rotate them. You do NOT

   need to re-type on every session.

3) Avoid: keeping production keys only in personal notes — sync, backups, and

   device loss usually widen risk versus GitHub-stored secrets.



This wizard never writes API keys into the repository or a repo-root .env.



EOF

  pause

}



main() {

  echo ""

  echo "ai-lore setup wizard"

  echo "---------------------"

  if ! have_gum; then

    echo "(Tip: install gum for arrow-key menus — it is added automatically in the dev container.)"

  fi



  while true; do

    local action

    action="$(menu_main)"

    case "$action" in

      *Feature*)

        feature_toggles

        ;;

      *MCP*)

        mcp_flow || true

        ;;

      *Help*)

        help_keys

        ;;

      *Exit*)

        echo "Bye."

        break

        ;;

      *)

        if [[ "$action" == "1" ]]; then feature_toggles

        elif [[ "$action" == "2" ]]; then mcp_flow || true

        elif [[ "$action" == "3" ]]; then help_keys

        else

          echo "Bye."

          break

        fi

        ;;

    esac

  done

}



main "$@"

