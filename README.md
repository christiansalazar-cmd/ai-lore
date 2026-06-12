# ai-lore

The central source of truth for the company's AI logic, capabilities, and integrations. Instead of scattering prompts, system instructions, and orchestration code across isolated repositories, all shared assets live here to ensure consistency across our applications and engineering pipelines.

### 📁 Core Structure

*   **`/models`** – Foundational provider configurations (Claude, OpenAI, Codex) including default system prompts, temperature baselines, and model version pinning.
*   **`/plugins`** – Code, manifests, and integrations connecting our core models to internal dashboards and third-party enterprise tools.
*   **`/mcps`** – Model Context Protocol setups that securely bridge LLMs to local developer environments and internal company databases.
*   **`/skills`** – Our library of atomic, reusable prompt chains designed to execute specific, deterministic tasks.
*   **`/agents`** – Full autonomous agent definitions, multi-agent orchestration frameworks, and state/memory management configurations.
*   **`/hooks`** – Middleware and event-driven webhooks used to trigger automated AI workflows directly from internal system events.
*   **`/guards`** – PII scrubbing logic, input/output moderation filters, and compliance guardrails.
*   **`/evals`** – Test suites, prompt benchmarks, and regression tests used to validate updates before they hit production.
*   **`/telemetry`** – OpenTelemetry hooks, standardized logging schemas, and trace formats to audit agent reasoning loops and prompt performance.

### GitHub Codespaces

This repo includes a [Dev Container](https://containers.dev/) at `.devcontainer/devcontainer.json` and launcher scripts under [`launcher-setup/`](launcher-setup/README.md).

#### Launch process (what happens when you open a Codespace)

1. **GitHub builds the dev container** from the image in `devcontainer.json` (and runs the `features` you declared, e.g. GitHub CLI).
2. **`postCreateCommand` runs once** after the container is created: `bash launcher-setup/bootstrap.sh` installs **gum** (arrow-key menus) — no interactive prompts there.
3. **The editor attaches** to the Codespace. VS Code then evaluates **automatic tasks**.
4. **First time in this workspace**, VS Code may ask you to **Trust** the folder and to **Allow automatic tasks** — choose **Allow** for the setup wizard task.
5. The task **`AI Lore: setup wizard`** runs with **`runOn: folderOpen`**, which starts **`bash launcher-setup/setup-wizard.sh`** in a terminal. That is the interactive launcher (not the container build itself).

If you skipped “Allow automatic tasks,” open **Terminal → Run Task… → “AI Lore: setup wizard (rerun)”** anytime.

**API keys (important):**

- The wizard **does not** ask for API keys unless you enter **MCP → store API keys**.
- Keys are stored as **GitHub Codespaces user secrets** via `gh secret set --user` (with `--app codespaces` when your `gh` version supports it). They are **not** written to a repo-root `.env` or any tracked file.
- **Security tiers:** prefer OAuth / no static key when your MCP supports it; otherwise Codespaces user secrets (set once — they **persist** for future codespaces until you rotate or delete them). Keeping production keys only in personal notes is **not** safer than GitHub-managed secrets for most teams.
- If `gh` reports missing permissions: `gh auth refresh -h github.com -s user -s read:user`
- Manual alternative: [GitHub → Settings → Codespaces → Secrets](https://github.com/settings/codespaces).

**Is the launcher “hidden” on a public repo?** No — committed files are always visible. See [`launcher-setup/VISIBILITY.md`](launcher-setup/VISIBILITY.md).

#### Gum vs “Choose [1–4]” in the task terminal

If you see the numeric fallback, **`gum` is not on `PATH`** for that shell (often after `gum` was installed under `~/.local/bin`). Tasks now prepend that to `PATH`. If it still happens, run **`bash launcher-setup/bootstrap.sh`** once in a normal terminal, or **rebuild the container** so `postCreateCommand` runs again.

#### Local laptop (Terminal.app, Windows Terminal, WSL, etc.)

VS Code / Codespaces **does not** offer a built-in “run this task in the macOS/Windows *external* terminal app” switch. The supported pattern is the same script in **your** terminal:

1. Clone the repo and `cd` into it.
2. Install **gum** for your OS (the devcontainer `bootstrap.sh` only installs the **Linux** binary; on macOS use e.g. `brew install gum`, on Windows use WSL or another install path you standardize).
3. Run: `bash launcher-setup/setup-wizard.sh`

That gives the same TUI in iTerm, Terminal.app, Windows Terminal, etc.—outside VS Code if you want.

#### Wizard did not open automatically?

1. **Trust the workspace** when VS Code asks — automatic tasks **never** run in an untrusted workspace.
2. **Allow automatic tasks:** `Ctrl+Shift+P` (or `Cmd+Shift+P`) → **Tasks: Manage Automatic Tasks in Folder** → **Allow Automatic Tasks in Folder**.  
   (VS Code often **does not** show a toast for this until you have run a task at least once — see [vscode#143298](https://github.com/microsoft/vscode/issues/143298).)
3. This repo sets [`task.allowAutomaticTasks`](.vscode/settings.json) to **`on`** in **`.vscode/settings.json`** so the folder-open task can run without that extra prompt when the workspace is trusted.
4. **Manual run:** **Terminal → Run Task… → “AI Lore: setup wizard”** (or the **(rerun)** variant).
5. After each attach, `postAttachCommand` prints the same hint in the log output for **Codespaces**.
