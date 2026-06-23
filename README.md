# Claude Model Rewrite Proxy

Local proxy that lets Claude Code (and other Anthropic-compatible clients) keep using **official Claude model names** while routing requests to multiple third-party Anthropic-compatible upstreams (DeepSeek, Volcengine Ark / 方舟 code plan, etc.).

The Claude Code client has become stricter and requires real `claude-*` model names in its model list. This proxy keeps those names on the client side and rewrites them to the real backend model names per provider.

A watchdog keeps the proxy in sync with the Claude Code client: proxy starts when Claude runs, stops shortly after Claude exits. No manual management.

## Mapping (default `proxy-config.json`)

```text
# deepseek provider
claude-sonnet-4.6 -> deepseek-v4-flash
claude-opus-4.6  -> deepseek-v4-pro

# ark provider (Volcengine Ark code plan)
claude-sonnet-4.6 -> kimi-k2.7-code
claude-opus-4.6  -> glm-5.2
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

`proxy-watchdog.ps1` runs as a hidden background process (installed via `install-autostart.ps1` as a logon scheduled task). Every 5 seconds it polls for `Claude.exe`:

- Claude running + proxy down -> start proxy
- Claude gone for 15 seconds -> stop proxy

This means you launch Claude Code normally (Start menu, shortcut, etc.) and the proxy comes up automatically. Quit Claude and the proxy stops. No wrapper script, no manual start.

Singleton guard via named mutex prevents duplicate watchdog instances.

## Usage

### 1. Install the watchdog (one-time)

```powershell
powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1
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
  { "name": "claude-opus-4.6" }
]
```

API keys are not stored here. Claude Code sends the configured API key in the request headers, and the proxy forwards them unchanged.

### 3. Launch Claude Code normally

Start Claude Code however you normally do. The watchdog detects it within 5 seconds and starts the proxy. Quit Claude Code and the proxy stops after a 15-second grace period.

### 4. Verify

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
```

Or check logs directly:

```powershell
Get-Content .\watchdog.log -Tail 10
Get-Content .\proxy-*.log -Tail 10
```

Each request logs `[provider] original -> mapped`, e.g. `[deepseek] claude-sonnet-4.6 -> deepseek-v4-flash`.

## Configuration File

`proxy-config.json` (next to `model-rewrite-proxy.cjs`) defines providers:

```json
{
  "nodePath": "D:\\Program Files\\nodejs\\node.exe",
  "providers": {
    "deepseek": {
      "upstream": "https://api.deepseek.com/anthropic",
      "map": {
        "claude-sonnet-4.6": "deepseek-v4-flash",
        "claude-opus-4.6":  "deepseek-v4-pro"
      }
    },
    "ark": {
      "upstream": "https://ark.cn-beijing.volces.com/api/coding",
      "map": {
        "claude-sonnet-4.6": "kimi-k2.7-code",
        "claude-opus-4.6":  "glm-5.2"
      }
    }
  }
}
```

### `nodePath` (optional)

Absolute path to `node.exe`. All PowerShell scripts (`proxy-watchdog.ps1`, `start-claude-deepseek-proxy.ps1`, `start-claude.ps1`) read this field to launch the proxy. If unset or the path does not exist, they fall back to auto-detection in this order: `C:\Program Files\nodejs\node.exe`, `D:\Program Files\nodejs\node.exe`, then `node.exe` on `PATH`.

Set this when Node.js is installed in a non-standard location to avoid hard-coding paths in scripts.

Override the config path with `PROXY_CONFIG_PATH` if you want to keep a custom config elsewhere.

To add a new provider: add an entry under `providers`, then point Claude Code at `http://127.0.0.1:8787/<name>/`. The `/v1/models` response is generated from the map keys automatically.

## Modifying the Model Mapping

To change which real model a Claude name maps to, edit `proxy-config.json`:

1. Open `proxy-config.json`.
2. Under the desired `providers.<name>.map`, change the value for the official Claude model name.
   - Keys (`claude-sonnet-4.6`, `claude-opus-4.6`) are the names Claude Code sees and sends.
   - Values are the real model IDs the upstream provider expects.
3. Save the file.
4. Restart the proxy so the new config is loaded:
   - If the watchdog is running: stop the proxy process; the watchdog will restart it within a few seconds.
   - If running manually: stop the current `node` process and run `start-claude-deepseek-proxy.ps1` again.
5. Optional: if you use Claude-3p, update the `labelOverride` field in the matching configLibrary entry so the UI label matches the new model.

You can also add new providers or new Claude-name-to-real-model mappings. Each provider's `/v1/models` response is generated automatically from its map keys, so Claude Code will see any new official Claude names immediately after restart.

## TLS Note

DeepSeek's server sends an incomplete certificate chain. Node.js (unlike Windows/.NET) does not fetch missing intermediate certs via AIA, so the proxy sets `NODE_TLS_REJECT_UNAUTHORIZED=0` for upstream connections. This only affects the local proxy process's outbound TLS to upstreams, not the loopback connection from Claude Code to the proxy.

## Manual Operations

```powershell
# Install watchdog (auto-start at logon)
powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1

# Status
powershell -ExecutionPolicy Bypass -File .\status.ps1

# Uninstall (stops watchdog, kills proxy, removes task)
powershell -ExecutionPolicy Bypass -File .\uninstall-autostart.ps1

# Start proxy manually without watchdog (legacy)
powershell -ExecutionPolicy Bypass -File .\start-claude-deepseek-proxy.ps1
```

## Files

- `model-rewrite-proxy.cjs` — proxy implementation: path-routed, per-provider model rewrite, `/v1/models` interception.
- `proxy-config.json` — provider definitions (upstream URL + model map).
- `proxy-watchdog.ps1` — background watchdog that syncs proxy lifecycle to Claude Code.
- `install-autostart.ps1` / `uninstall-autostart.ps1` — install/remove the watchdog scheduled task.
- `start-claude-deepseek-proxy.ps1` — standalone proxy starter (no watchdog), kept for manual use.
- `start-claude.ps1` — alternative wrapper that starts proxy + Claude and stops proxy on Claude exit.
- `status.ps1` — check task / watchdog / proxy / Claude state.

## Notes

- This is not a system proxy.
- Only software explicitly configured to use `http://127.0.0.1:8787/<provider>/` is affected.
- Unknown model names are forwarded unchanged (no rewrite). The proxy never invents a mapping.
- Logs: `watchdog.log` for watchdog actions, `proxy-<timestamp>.log` per proxy start for proxy output. All ignored by Git.

## License

MIT. See `LICENSE`.
