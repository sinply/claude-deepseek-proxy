# CLAUDE.md

Guidance for Claude Code and other coding agents working in this repository.

## Project Purpose

Local HTTP proxy that lets Claude Code (and other Anthropic-compatible clients) keep using official Claude model names (`claude-sonnet-4.6`, `claude-opus-4.6`) while routing to multiple third-party Anthropic-compatible upstreams.

The Claude Code client has become stricter and rejects non-official model names in its model list. This proxy keeps the official names on the client side and rewrites them to the real backend model names per provider before forwarding.

A background watchdog syncs the proxy lifecycle to the Claude Code client so the user never has to manually start/stop anything.

## Architecture

### Proxy (`src/model-rewrite-proxy.cjs`)

Single proxy listens on `http://127.0.0.1:8787`. The first path segment selects the provider:

```text
/<provider>/<rest>   ->   providers[<provider>].upstream + <rest>
```

For example:

```text
POST /deepseek/v1/messages   -> https://api.deepseek.com/anthropic/v1/messages
POST /ark/v1/messages        -> https://ark.cn-beijing.volces.com/api/coding/v1/messages
```

Per-provider `map` rewrites the JSON `model` field. Unknown model names pass through unchanged.

`GET /<provider>/v1/models` is intercepted and answered with a synthetic Anthropic-format response built from the provider's map keys. This is required because Claude Code's model discovery rejects upstreams that don't return official Claude model IDs.

### Watchdog (`scripts/proxy-watchdog.ps1`)

Hidden background PowerShell process installed as a logon scheduled task. Polls every 5 seconds:

- `Claude.exe` running + proxy down -> start proxy
- `Claude.exe` gone for 15 seconds -> stop proxy (grace period covers quick restarts and UWP multi-process shutdown chatter)

Singleton guard via named mutex (`Global\ClaudeModelRewriteProxyWatchdog`) prevents duplicate instances. Main loop wrapped in try-catch so transient errors don't kill the watchdog.

## Configuration

`config/proxy-config.json` defines providers. Override path with `PROXY_CONFIG_PATH` (set by all PowerShell scripts).

Optional top-level `nodePath` field (absolute path to `node.exe`) is read by all PowerShell scripts (`scripts/proxy-watchdog.ps1`, `scripts/start-claude-deepseek-proxy.ps1`, `scripts/start-claude.ps1`). If unset or path missing, they fall back to `C:\Program Files\nodejs\node.exe` → `D:\Program Files\nodejs\node.exe` → `node.exe` on `PATH`. Use this when Node.js is installed in a non-standard location instead of editing scripts.

Default mapping:

```text
deepseek: claude-sonnet-4.6 -> deepseek-v4-flash, claude-opus-4.6 -> deepseek-v4-pro
ark:      claude-sonnet-4.6 -> kimi-k2.7-code, claude-opus-4.6 -> doubao-seed-2.0-pro, claude-opus-4.7 -> glm-5.2
```

## TLS

DeepSeek sends an incomplete certificate chain. Node.js doesn't do AIA fetching like Windows does, so the proxy runs with `NODE_TLS_REJECT_UNAUTHORIZED=0`. This affects only the proxy's outbound TLS to upstreams, not the looptail connection from Claude Code. Both the watchdog and `scripts/start-claude-deepseek-proxy.ps1` set this env var.

## Important Rules

- Do not commit private values, Claude Code config files, local logs, or machine-specific private data.
- Do not commit anything under `logs/` (it is in `.gitignore`).
- Do not commit the user's Claude-3p `configLibrary` JSON files.
- Keep the proxy minimal: forward requests, parse JSON body only to rewrite the `model` field, intercept `/v1/models` synthetically.
- Preserve Windows PowerShell compatibility for wrapper scripts.
- Keep Node.js compatibility conservative (the original environment used Node.js 12). Avoid optional chaining, nullish coalescing, and other post-Node-12 syntax in the proxy.
- Do not reintroduce the legacy `claude-deepseek-v4-*` / `cluade-*` aliases. Only official Claude model names are supported.

## Files

```
src/model-rewrite-proxy.cjs        proxy: path routing, model rewrite, /v1/models interception
config/proxy-config.json           provider definitions
scripts/proxy-watchdog.ps1         background watchdog syncing proxy lifecycle to Claude Code
scripts/install-autostart.ps1      install watchdog scheduled task
scripts/uninstall-autostart.ps1    remove watchdog scheduled task
scripts/start-claude-deepseek-proxy.ps1  standalone proxy starter (no watchdog), manual use
scripts/start-claude.ps1           wrapper that starts proxy + Claude and stops proxy on Claude exit
scripts/status.ps1                 check task / watchdog / proxy / Claude state
bat/start.bat                      start the proxy
bat/stop.bat                       stop proxy + watchdog
bat/status.bat                     show proxy + watchdog status and model list
bat/restart-wd.bat                 restart the watchdog scheduled task
logs/                              all proxy and watchdog logs (gitignored)
docs/index.html                    static HTML usage guide
```

All PowerShell scripts resolve paths relative to the project root via `Split-Path $PSScriptRoot -Parent`, so the project root must retain its `src/`, `config/`, `logs/`, `scripts/` layout. The `.bat` files under `bat/` call into `scripts/` via `%~dp0..\scripts\...`.

## Validation Checklist

Before committing changes:

```powershell
node --check .\src\model-rewrite-proxy.cjs
git status --short
```

Smoke test (any local fake upstream will do): send a POST to `/<provider>/v1/messages` with a body containing `model: "claude-sonnet-4.6"` and confirm the upstream receives the mapped real model name. Also confirm `GET /<provider>/v1/models` returns 200 with a `data` array containing the official Claude model IDs.
