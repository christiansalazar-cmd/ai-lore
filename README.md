# ai-lore

The central source of truth for the company's AI logic, capabilities, and integrations. Instead of scattering prompts, system instructions, and orchestration code across separate repositories, all shared assets live here so they stay consistent across our apps and engineering pipelines.

**In plain terms:** ai-lore is a shared library of AI add-ons (skills, MCP servers, and rules). You install a small `ai-lore` command once. After that, you can walk into any project you're working on in [Cursor](https://cursor.com), run `ai-lore setup`, and pick which add-ons to drop into that project. No copying files by hand.

---

## Quick start

There are two steps, and you only do step 1 one time per computer.

1. **Install the `ai-lore` command** (one time).
2. **Run `ai-lore setup` inside a project** (any time you want to add things).

```
your-workspace/
├── ai-lore/        <- this repo, cloned once (the library)
├── project-a/      <- run "ai-lore setup" here, files land in project-a/.cursor/
├── project-b/
└── project-c/
```

### Step 1: Install the command (one time)

#### Windows

1. Clone or download this repo somewhere stable, for example `C:\Workspace\ai-lore`.
2. Open the folder in File Explorer, right-click **`install.ps1`**, and choose **"Run with PowerShell"**.
   (Prefer a terminal? Run `powershell -ExecutionPolicy Bypass -File install.ps1`.)
3. Close that window and open a **new** PowerShell or Cursor terminal. The `ai-lore` command now works from anywhere.

Nothing else to install on Windows. No Python, no WSL.

#### macOS / Linux

```bash
git clone <this-repo-url> ai-lore
cd ai-lore
bash install.sh
```

Then open a new terminal (or run `source ~/.bashrc`, or `source ~/.zshrc`). Needs `bash` and `python3`, which macOS and most Linux already have.

### Step 2: Use it in a project

Go to the project you want to add things to, then run setup:

```bash
cd path/to/your-project
ai-lore setup
```

You'll get an interactive menu:

1. Pick a category: **Skills**, **MCP servers**, **Rules**, or **Done**.
2. Choose **Install all** or **Select individually**.
3. If you're selecting individually, use the arrow keys to move, **Space** to check items on and off, and **Enter** (or **Ctrl+S**) to save. **Esc** cancels.
4. Repeat for other categories, then choose **Done**.

Everything you pick is copied into the project's `.cursor/` folder. Reload Cursor and the new skills, MCP servers, and rules are available in that project.

> If a terminal does not support the arrow-key menu, the command automatically falls back to a simple numbered list. Same choices, just type the number.

---

## Getting updates

You do **not** reinstall when the library grows. To get newly added skills, MCP servers, or rules:

```bash
cd path/to/ai-lore
git pull
```

Then run `ai-lore setup` again inside any project to add the new items (or to refresh ones you already installed, since installs are copies).

---

## Command reference

| Command | What it does |
|---------|--------------|
| `ai-lore setup` | Open the interactive menu and install into the current folder's `.cursor/`. This is the default. |
| `ai-lore setup --force` | Same, but overwrite existing files without asking. |
| `ai-lore list` | Show everything available (skills, MCP servers, rules) without installing. |
| `ai-lore help` | Show usage. |

Run `ai-lore setup` from inside one of your projects, not from inside the ai-lore repo itself (it will refuse, to avoid installing into the library).

## What gets installed where

| In ai-lore (the library) | Lands in your project | Cursor uses it as |
|--------------------------|-----------------------|-------------------|
| `skills/<name>/` (any folder with a `SKILL.md`) | `.cursor/skills/<name>/` | A project skill |
| `mcps/<name>/mcp.template.json` | merged into `.cursor/mcp.json` | A project MCP server |
| `rules/<name>.mdc` | `.cursor/rules/<name>.mdc` | A project rule |

## API keys

Some MCP servers need an API key; many do not.

- The setup only asks for a key when the server you picked actually needs one. If it doesn't, you'll see "no key needed" and it moves on.
- Keys are typed with hidden input and saved into the project's `.cursor/mcp.json`.
- That file is automatically added to the project's `.gitignore`, so keys never get committed.
- Re-running setup keeps any keys you already entered.

## Installing gum (macOS / Linux, optional)

[gum](https://github.com/charmbracelet/gum) gives the macOS/Linux command the same arrow-key menus that Windows already has built in. It is optional; without it you get the numbered fallback.

| Environment | Install |
|-------------|---------|
| macOS | `brew install gum` |
| Arch Linux | `sudo pacman -S gum` |
| Nix | `nix profile install nixpkgs#gum` |
| Any Linux with Go | `go install github.com/charmbracelet/gum@latest` (put `$(go env GOPATH)/bin` on your `PATH`) |
| Other Linux | Download a release from [charmbracelet/gum releases](https://github.com/charmbracelet/gum/releases) |

Windows does not need gum.

## Troubleshooting

- **"ai-lore is not recognized / command not found."** You opened a terminal before installing, or you skipped step 1. Open a brand new terminal after running the installer. On Windows you can also reload the current window with `. $PROFILE`.
- **The menu shows numbers instead of arrow keys (macOS/Linux).** That's the fallback. Install `gum` (see above) for the arrow-key version. Everything still works either way.

---

## Repository structure

For engineers browsing or contributing to the library itself:

| Folder | Purpose |
|--------|---------|
| `/models` | Provider configurations (Claude, OpenAI, Codex): default system prompts, temperature baselines, model version pinning. |
| `/plugins` | Code, manifests, and integrations connecting our models to internal dashboards and third-party tools. |
| `/mcps` | Model Context Protocol setups that bridge LLMs to local dev environments and internal databases. |
| `/skills` | Library of reusable prompt chains for specific, repeatable tasks. |
| `/agents` | Autonomous agent definitions, multi-agent orchestration, and state/memory configs. |
| `/hooks` | Event-driven webhooks that trigger automated AI workflows from internal system events. |
| `/guards` | PII scrubbing, input/output moderation, and compliance guardrails. |
| `/evals` | Test suites, prompt benchmarks, and regression tests run before changes ship. |
| `/telemetry` | OpenTelemetry hooks, logging schemas, and trace formats for auditing agent runs. |

Supporting pieces: `bin/` holds the `ai-lore` launchers (`ai-lore` for bash, `ai-lore.ps1` for PowerShell), `lib/` holds shared helpers, and `install.sh` / `install.ps1` register the command.
