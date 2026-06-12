# Codespaces launcher (`launcher-setup`)

This folder holds the **interactive setup wizard** and **bootstrap** script used when developing in [GitHub Codespaces](https://github.com/features/codespaces).

| File | Role |
|------|------|
| `bootstrap.sh` | Runs once after the dev container is created (`postCreateCommand`). Installs [gum](https://github.com/charmbracelet/gum) for TUI menus. |
| `setup-wizard.sh` | Interactive wizard (feature toggles, MCP-only API key upload via `gh secret set --user`). |

**Not moved here (on purpose):** `.devcontainer/devcontainer.json` and `.vscode/tasks.json` stay at their **standard paths** so GitHub Codespaces and VS Code discover them automatically.

See the root [README.md](../README.md) for the full launch sequence and [VISIBILITY.md](VISIBILITY.md) for what “hidden from the public” can and cannot mean on GitHub.
