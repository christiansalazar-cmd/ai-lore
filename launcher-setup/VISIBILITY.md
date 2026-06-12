# Visibility of this folder on GitHub

**Short answer:** anything committed to a **public** repository is visible to everyone (web UI, API, `git clone`, search). Renaming the folder to start with a dot (e.g. `.launcher-setup`) only hides it from a **default** `ls` on Linux — it does **not** hide it on github.com or from clones.

**Ways to keep launcher internals off the public internet:**

1. **Make the repository private** (or use GitHub Enterprise / internal visibility policies your org defines).
2. **Keep this repo public but accept** that `launcher-setup/` is public; it should contain **no secrets** (only scripts; keys stay in Codespaces user secrets).
3. **Split tooling** into a private repo or internal package and install at container build time (more moving parts; still need something in `.devcontainer` to point at it).

This repo’s launcher is designed so **credentials never live in git** — only scripts and docs.
