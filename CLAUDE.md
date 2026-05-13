# CLAUDE.md

Guidance for Claude Code and other coding agents working in this repository.

## Project Purpose

This project provides a small local HTTP proxy for Claude-3p / Claude Code gateway configurations.

Claude keeps using Claude-compatible model aliases, while the proxy rewrites those aliases to real DeepSeek model names before forwarding requests to DeepSeek's Anthropic-compatible endpoint.

## Important Rules

- Do not commit private values, Claude-3p config files, local logs, or machine-specific private data.
- Do not add the user's `configLibrary` JSON files to this repository.
- Keep the proxy minimal: it should forward requests and only rewrite the JSON `model` field when it matches a known alias.
- Preserve Windows PowerShell compatibility.
- Keep Node.js compatibility conservative; the original environment used Node.js 12.

## Current Mapping

```text
claude-deepseek-v4-pro   -> deepseek-v4-pro
cluade-deepseek-v4-pro   -> deepseek-v4-pro
claude-deepseek-v4-flash -> deepseek-v4-flash
cluade-deepseek-v4-flash -> deepseek-v4-flash
```

The `cluade-*` entries intentionally support a common typo.

## Files

- `model-rewrite-proxy.cjs`: Local HTTP proxy implementation.
- `start-claude-deepseek-proxy.ps1`: Starts the proxy as a hidden background process.
- `install-autostart.ps1`: Installs or repairs the Windows scheduled task.
- `uninstall-autostart.ps1`: Removes the scheduled task.
- `status.ps1`: Checks scheduled task and port status.
- `docs/index.html`: Static HTML usage guide.

## Validation Checklist

Before committing changes:

```powershell
node --check .\model-rewrite-proxy.cjs
rg -n -i "<sensitive-value-patterns>" .
git status --short
```

If the proxy is running locally, a minimal runtime check should confirm that `claude-deepseek-v4-pro` returns `deepseek-v4-pro` from the upstream response.
