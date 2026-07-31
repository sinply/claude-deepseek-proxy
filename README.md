# Claude Model Rewrite Proxy

Local proxy that lets Claude Code (and other Anthropic-compatible clients) keep using **official Claude model names** while routing requests to multiple third-party Anthropic-compatible upstreams (DeepSeek, Volcengine Ark / 方舟 code plan, etc.).

The Claude Code client has become stricter and requires real `claude-*` model names in its model list. This proxy keeps those names on the client side and rewrites them to the real backend model names per provider.

A watchdog keeps the proxy in sync with the Claude Code client: proxy starts when Claude runs, stops shortly after Claude exits. No manual management.

## Mapping (default `config/proxy-config.json`)

```text
# deepseek provider
claude-opus-4.6  -> deepseek-v4-pro
claude-sonnet-4.6 -> deepseek-v4-flash

# ark provider (Volcengine Ark code plan)
claude-opus-4.8  -> deepseek-v4-pro
claude-sonnet-5  -> deepseek-v4-flash
claude-opus-4.7  -> glm-5.2
claude-opus-4.6  -> kimi-k2.7-code
claude-opus-4.5  -> doubao-seed-2.1-turbo
```

The same Claude model name maps to different real models depending on which provider you point at.

## Routing

A single proxy listens on `http://127.0.0.1:8787`. The first path segment selects the provider:

```text
http://127.0.0.1:8787/deepseek/   -> https://api.deepseek.com/anthropic
http://127.0.0.1:8787/ark/        -> https://ark.cn-beijing.volces.com/api/coding
```

Set the Claude Code base URL to one of those (including the trailing slash). The remainder of the path is forwarded to the upstream as-is.

`GET /<provider>/v1/models` is intercepted and answered with a synthetic Anthropic-format response listing the official Claude model IDs from the provider's map. This satisfies Claude Code's model discovery check without relying on the upstream `/v1/models` endpoint.

## Watchdog (auto start/stop with Claude Code)

`scripts/proxy-watchdog.ps1` runs as a hidden background process (installed via `scripts/install-autostart.ps1` as a logon scheduled task). Every 5 seconds it polls for `Claude.exe`:

- Claude running + proxy down -> start proxy
- Claude gone for 15 seconds -> stop proxy

This means you launch Claude Code normally (Start menu, shortcut, etc.) and the proxy comes up automatically. Quit Claude and the proxy stops. No wrapper script, no manual start.

Singleton guard via named mutex prevents duplicate watchdog instances.

The scheduled task launches the watchdog through `scripts/launch-watchdog.vbs` (via `wscript.exe`) rather than calling `powershell.exe -WindowStyle Hidden` directly. Task Scheduler with `-WindowStyle Hidden` still allocates a console for the powershell, and on systems with Windows Terminal installed ConPTY pulls WT in as the host, leaving a stray `-Embedding` Windows Terminal window. `wscript` runs with no console, so the spawned powershell inherits none and no WT window is created.

## Usage

### 1. Install the watchdog (one-time)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1
```

This installs a logon scheduled task `ClaudeModelRewriteProxyWatchdog` and starts it immediately. The watchdog then runs whenever you are logged in.

### 2. Configure Claude Code

Point Claude Code at the desired provider via `ANTHROPIC_BASE_URL` (or the Claude-3p gateway config):

```text
http://127.0.0.1:8787/deepseek/   # DeepSeek
http://127.0.0.1:8787/ark/        # Volcengine Ark
```

Keep the official Claude model names in the model list:

```json
[
  { "name": "claude-sonnet-4.6" },
  { "name": "claude-opus-4.6" },
  { "name": "claude-opus-4.7" }
]
```

API keys are not stored here. Claude Code sends the configured API key in the request headers, and the proxy forwards them unchanged.

### 3. Launch Claude Code normally

Start Claude Code however you normally do. The watchdog detects it within 5 seconds and starts the proxy. Quit Claude Code and the proxy stops after a 15-second grace period.

### 4. Verify

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\status.ps1
```

Or just double-click `bat\status.bat`. Or check logs directly:

```powershell
Get-Content .\logs\watchdog.log -Tail 10
Get-Content .\logs\proxy-*.log -Tail 10
```

Each request logs `[provider] original -> mapped`, e.g. `[deepseek] claude-sonnet-4.6 -> deepseek-v4-flash`.

## Configuration File

`config/proxy-config.json` defines providers:

```json
{
  "nodePath": "D:\\Program Files\\nodejs\\node.exe",
  "providers": {
    "deepseek": {
      "upstream": "https://api.deepseek.com/anthropic",
      "map": {
        "claude-opus-4.6":  "deepseek-v4-pro",
        "claude-sonnet-4.6": "deepseek-v4-flash"
      }
    },
    "ark": {
      "upstream": "https://ark.cn-beijing.volces.com/api/coding",
      "map": {
        "claude-opus-4.8":  "deepseek-v4-pro",
        "claude-sonnet-5":  "deepseek-v4-flash",
        "claude-opus-4.7":  "glm-5.2",
        "claude-opus-4.6":  "kimi-k2.7-code",
        "claude-opus-4.5":  "doubao-seed-2.1-turbo"
      }
    }
  }
}
```

### `nodePath` (optional)

Absolute path to `node.exe`. All PowerShell scripts (`scripts/proxy-watchdog.ps1`, `scripts/start-claude-deepseek-proxy.ps1`, `scripts/start-claude.ps1`) read this field to launch the proxy. If unset or the path does not exist, they fall back to auto-detection in this order: `C:\Program Files\nodejs\node.exe`, `D:\Program Files\nodejs\node.exe`, then `node.exe` on `PATH`.

Set this when Node.js is installed in a non-standard location to avoid hard-coding paths in scripts.

Override the config path with `PROXY_CONFIG_PATH` if you want to keep a custom config elsewhere.

To add a new provider: add an entry under `providers`, then point Claude Code at `http://127.0.0.1:8787/<name>/`. The `/v1/models` response is generated from the map keys automatically.

## Adding or Changing Models

The model map in `config/proxy-config.json` is **auto-synced** from the Claude-3p `configLibrary` at proxy startup (by `scripts/sync-models.cjs`). The configLibrary is the single source of truth: each provider's `inferenceModels` entry pairs an official Claude ID (`name`) with the backend model (`labelOverride`), and those pairs are written into the proxy's `map`.

### If you use Claude-3p (recommended)

1. Open the provider's configLibrary file, e.g. `%LOCALAPPDATA%\Claude-3p\configLibrary\<id>.json` (the `<id>` for each provider is listed in that folder's `_meta.json`).
2. Add or edit an `inferenceModels` entry:
   ```json
   { "name": "claude-opus-4.8", "labelOverride": "deepseek-v4-pro", "supports1m": true }
   ```
   - `name` - official Claude model ID Claude Code sees and sends.
   - `labelOverride` - real backend model ID the upstream expects.
3. Restart the proxy so the sync runs and the proxy reloads:
   ```powershell
   bat\restart-wd.bat
   ```

Do **not** edit `proxy-config.json`'s `map` by hand for providers that have a configLibrary entry - the sync overwrites it on the next restart.

### If you don't use Claude-3p

Edit `config/proxy-config.json` directly under `providers.<name>.map`, then restart the proxy. The sync only touches providers that have a matching configLibrary entry, so a provider with no configLibrary entry keeps its hand-edited map.

### configLibrary path

`scripts/sync-models.cjs` resolves the configLibrary at: `CONFIG_LIBRARY_PATH` env var, else `%LOCALAPPDATA%\Claude-3p\configLibrary`. If not found, sync exits silently and leaves `proxy-config.json` unchanged. The sync is best-effort and non-fatal - on failure it logs to `logs/sync-models.log` and the proxy starts with whatever config is already on disk.

## TLS Note

DeepSeek's server sends an incomplete certificate chain. Node.js (unlike Windows/.NET) does not fetch missing intermediate certs via AIA, so the proxy sets `NODE_TLS_REJECT_UNAUTHORIZED=0` for upstream connections. This only affects the local proxy process's outbound TLS to upstreams, not the loopback connection from Claude Code to the proxy.

## Manual Operations

```powershell
# Install watchdog (auto-start at logon)
powershell -ExecutionPolicy Bypass -File .\scripts\install-autostart.ps1

# Status
powershell -ExecutionPolicy Bypass -File .\scripts\status.ps1

# Uninstall (stops watchdog, kills proxy, removes task)
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall-autostart.ps1

# Start proxy manually without watchdog (legacy)
powershell -ExecutionPolicy Bypass -File .\scripts\start-claude-deepseek-proxy.ps1
```

Or use the convenience launchers in `bat\`:

| Batch file | Action |
|---|---|
| `bat\start.bat` | Start the proxy (no watchdog) |
| `bat\stop.bat` | Stop proxy + watchdog processes |
| `bat\status.bat` | Show proxy + watchdog status and model list |
| `bat\restart-wd.bat` | Restart the watchdog scheduled task |

## Files

```
src/model-rewrite-proxy.cjs              proxy implementation: routing, model rewrite, /v1/models interception
config/proxy-config.json                 provider definitions (upstream URL + model map)
scripts/proxy-watchdog.ps1               background watchdog syncing proxy lifecycle to Claude Code
scripts/launch-watchdog.vbs              hidden launcher for the watchdog — wscript runs with no console so Windows Terminal is never pulled in as a ConPTY host
scripts/install-autostart.ps1            install the watchdog scheduled task
scripts/uninstall-autostart.ps1          remove the watchdog scheduled task
scripts/start-claude-deepseek-proxy.ps1  standalone proxy starter (no watchdog), manual use
scripts/start-claude.ps1                 wrapper: starts proxy + Claude, stops proxy on Claude exit
scripts/sync-models.cjs                  syncs provider `map` in proxy-config.json from the Claude-3p configLibrary at proxy startup
scripts/status.ps1                       check task / watchdog / proxy / Claude state
bat/start.bat                            start the proxy
bat/stop.bat                             stop proxy + watchdog
bat/status.bat                           show proxy + watchdog status and model list
bat/restart-wd.bat                       restart the watchdog scheduled task
logs/                                    all proxy and watchdog logs (gitignored)
docs/index.html                          static HTML usage guide
```

## Notes

- This is not a system proxy.
- Only software explicitly configured to use `http://127.0.0.1:8787/<provider>/` is affected.
- Unknown model names are forwarded unchanged (no rewrite). The proxy never invents a mapping.
- Logs: `logs/watchdog.log` for watchdog actions, `logs/proxy-<timestamp>.log` per proxy start for proxy output. All ignored by Git.

## License

MIT. See `LICENSE`.
