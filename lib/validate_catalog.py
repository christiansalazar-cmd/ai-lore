#!/usr/bin/env python3
"""Validate the ai-lore catalog before contributions merge.

Run from the repo root (CI does this):

    python lib/validate_catalog.py

Checks (any failure exits non-zero with a clear message):
  - mcps/**/mcp.template.json: valid JSON, has mcpServers, every env value is an
    empty string (blocks committed API keys).
  - skills/: every leaf folder (has files, no subdirs) contains a SKILL.md.
  - rules/*.mdc: each is a readable file.
  - Light secret scan across skills/, rules/, mcps/ for obvious key patterns.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Obvious credential shapes. Kept deliberately narrow to avoid false positives.
SECRET_PATTERNS = [
    re.compile(r"sk-[A-Za-z0-9]{16,}"),       # OpenAI-style
    re.compile(r"ghp_[A-Za-z0-9]{20,}"),      # GitHub PAT
    re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),          # AWS access key id
    re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"),  # Slack token
]

SCAN_DIRS = ("skills", "rules", "mcps")
TEXT_SUFFIXES = {".md", ".mdc", ".json", ".txt", ".py", ".sh", ".ps1", ".yml", ".yaml", ".toml", ".cfg", ".ini", ""}


def _err(errors: list[str], msg: str) -> None:
    errors.append(msg)


def check_mcps(root: Path, errors: list[str]) -> None:
    mcps = root / "mcps"
    if not mcps.is_dir():
        return
    for tmpl in sorted(mcps.rglob("mcp.template.json")):
        rel = tmpl.relative_to(root)
        try:
            data = json.loads(tmpl.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            _err(errors, f"{rel}: invalid JSON ({exc})")
            continue
        servers = data.get("mcpServers") if isinstance(data, dict) else None
        if not isinstance(servers, dict) or not servers:
            _err(errors, f"{rel}: missing or empty 'mcpServers' object")
            continue
        for name, cfg in servers.items():
            env = (cfg or {}).get("env") if isinstance(cfg, dict) else None
            if isinstance(env, dict):
                for var, val in env.items():
                    if val not in (None, ""):
                        _err(
                            errors,
                            f"{rel}: server '{name}' env '{var}' must be empty in a "
                            f"committed template (found a value; strip the key)",
                        )


def _inside_skill(d: Path, skills: Path) -> bool:
    """True if any ancestor folder (up to but excluding skills/) has a SKILL.md,
    meaning d is a support folder (e.g. scripts/) inside a skill."""
    for parent in d.parents:
        if parent == skills:
            break
        if (parent / "SKILL.md").is_file():
            return True
    return False


def check_skills(root: Path, errors: list[str]) -> None:
    skills = root / "skills"
    if not skills.is_dir():
        return
    for d in sorted(p for p in skills.rglob("*") if p.is_dir()):
        # A folder that holds a SKILL.md is a valid skill; its subfolders are support.
        if (d / "SKILL.md").is_file():
            continue
        if _inside_skill(d, skills):
            continue
        # A group/container folder (a descendant is a skill) is fine.
        if any(d.rglob("SKILL.md")):
            continue
        # Otherwise: a folder with its own files but no SKILL.md is a malformed skill.
        if any(c.is_file() for c in d.iterdir()):
            _err(errors, f"{d.relative_to(root)}: skill folder is missing SKILL.md")


def check_rules(root: Path, errors: list[str]) -> None:
    rules = root / "rules"
    if not rules.is_dir():
        return
    for f in sorted(rules.glob("*.mdc")):
        if not f.is_file():
            _err(errors, f"{f.relative_to(root)}: not a readable file")


def scan_secrets(root: Path, errors: list[str]) -> None:
    for sub in SCAN_DIRS:
        base = root / sub
        if not base.is_dir():
            continue
        for f in sorted(base.rglob("*")):
            if not f.is_file() or f.suffix.lower() not in TEXT_SUFFIXES:
                continue
            try:
                text = f.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            for i, line in enumerate(text.splitlines(), start=1):
                for pat in SECRET_PATTERNS:
                    if pat.search(line):
                        _err(
                            errors,
                            f"{f.relative_to(root)}:{i}: possible secret matching "
                            f"/{pat.pattern}/ - remove it before contributing",
                        )
                        break


def main(argv: list[str]) -> int:
    root = Path(argv[0]) if argv else Path.cwd()
    root = root.resolve()
    errors: list[str] = []

    check_mcps(root, errors)
    check_skills(root, errors)
    check_rules(root, errors)
    scan_secrets(root, errors)

    if errors:
        print("Catalog validation FAILED:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print("Catalog validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
