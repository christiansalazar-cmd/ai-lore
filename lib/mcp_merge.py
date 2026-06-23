#!/usr/bin/env python3
"""Helpers for merging ai-lore MCP templates into a project's .cursor/mcp.json.

Subcommands:
  merge <target_mcp_json> <template_json>
      Merge the template's mcpServers into target without dropping existing servers.

  list-empty-env <target_mcp_json> <template_json>
      Print "server_name VAR_NAME" lines for env vars that exist (from the template's
      servers) in the target but currently hold an empty string.

  set-env <target_mcp_json> <server_name> <var_name>
      Read the secret VALUE from stdin and set it on target.mcpServers[server][env][var].
      Reading from stdin avoids leaking the value via argv/process list.

  list-servers <source_mcp_json>
      Print one server name per line for every server in source.mcpServers.

  extract-server <source_mcp_json> <server_name> <out_template>
      Pull one named server block out of source and write it to out_template as a
      standalone {"mcpServers": {"<name>": {...}}}, blanking every env value so no
      secret is ever written into the shared template.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def _load(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        # utf-8-sig tolerates a BOM-prefixed file (common from Windows editors /
        # PS 5.1) instead of silently returning {} and dropping the user's servers.
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def _save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def _servers(data: dict) -> dict:
    block = data.get("mcpServers")
    return block if isinstance(block, dict) else {}


def cmd_merge(target: Path, template: Path) -> int:
    data = _load(target)
    tmpl = _load(template)
    tmpl_servers = _servers(tmpl)
    if not tmpl_servers:
        print(f"merge: template has no mcpServers: {template}", file=sys.stderr)
        return 1
    data.setdefault("mcpServers", {})
    for name, cfg in tmpl_servers.items():
        # Preserve existing user-provided env values when re-installing.
        existing = data["mcpServers"].get(name)
        if isinstance(existing, dict) and isinstance(cfg, dict):
            merged = dict(cfg)
            old_env = existing.get("env")
            new_env = dict(cfg.get("env") or {})
            if isinstance(old_env, dict):
                for k, v in old_env.items():
                    if v not in (None, ""):
                        new_env[k] = v
            if new_env:
                merged["env"] = new_env
            data["mcpServers"][name] = merged
        else:
            data["mcpServers"][name] = cfg
    _save(target, data)
    print(f"merge: wrote {len(tmpl_servers)} server(s) into {target}")
    return 0


def cmd_list_empty_env(target: Path, template: Path) -> int:
    data = _load(target)
    tmpl_servers = _servers(_load(template))
    target_servers = _servers(data)
    for name, cfg in tmpl_servers.items():
        env = (cfg or {}).get("env") or {}
        if not isinstance(env, dict):
            continue
        cur = (target_servers.get(name) or {}).get("env") or {}
        for var in env:
            if not isinstance(cur, dict) or cur.get(var, "") in (None, ""):
                print(f"{name} {var}")
    return 0


def cmd_set_env(target: Path, server: str, var: str) -> int:
    value = sys.stdin.read()
    value = value.rstrip("\n")
    data = _load(target)
    data.setdefault("mcpServers", {})
    server_cfg = data["mcpServers"].setdefault(server, {})
    if not isinstance(server_cfg, dict):
        print(f"set-env: server {server} is not an object", file=sys.stderr)
        return 1
    env = server_cfg.setdefault("env", {})
    if not isinstance(env, dict):
        env = {}
        server_cfg["env"] = env
    env[var] = value
    _save(target, data)
    return 0


def cmd_list_servers(source: Path) -> int:
    for name in _servers(_load(source)):
        print(name)
    return 0


def cmd_extract_server(source: Path, server: str, out_template: Path) -> int:
    servers = _servers(_load(source))
    cfg = servers.get(server)
    if not isinstance(cfg, dict):
        print(f"extract-server: server not found: {server}", file=sys.stderr)
        return 1
    cfg = json.loads(json.dumps(cfg))  # deep copy
    env = cfg.get("env")
    if isinstance(env, dict):
        cfg["env"] = {k: "" for k in env}
    _save(out_template, {"mcpServers": {server: cfg}})
    print(f"extract-server: wrote {out_template}")
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "merge" and len(rest) == 2:
        return cmd_merge(Path(rest[0]), Path(rest[1]))
    if cmd == "list-empty-env" and len(rest) == 2:
        return cmd_list_empty_env(Path(rest[0]), Path(rest[1]))
    if cmd == "set-env" and len(rest) == 3:
        return cmd_set_env(Path(rest[0]), rest[1], rest[2])
    if cmd == "list-servers" and len(rest) == 1:
        return cmd_list_servers(Path(rest[0]))
    if cmd == "extract-server" and len(rest) == 3:
        return cmd_extract_server(Path(rest[0]), rest[1], Path(rest[2]))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
