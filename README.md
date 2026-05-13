# Claude DeepSeek Model Rewrite Proxy

A small local HTTP proxy for Claude-3p / Claude Code gateway configs.

It keeps Claude-compatible model names in the Claude UI/config, then rewrites them to the real DeepSeek model names before forwarding requests to DeepSeek's Anthropic-compatible endpoint.

## Mapping

```text
claude-deepseek-v4-pro   -> deepseek-v4-pro
cluade-deepseek-v4-pro   -> deepseek-v4-pro
claude-deepseek-v4-flash -> deepseek-v4-flash
cluade-deepseek-v4-flash -> deepseek-v4-flash
```

## Runtime

Requires Node.js and Windows PowerShell.

The default local proxy address is:

```text
http://127.0.0.1:8787
```

The default upstream is:

```text
https://api.deepseek.com/anthropic
```

## Claude-3p Config

Set the Claude-3p gateway base URL to:

```text
http://127.0.0.1:8787
```

Keep Claude-compatible model names in the Claude-3p model list:

```json
[
  { "name": "claude-deepseek-v4-pro", "supports1m": true },
  { "name": "claude-deepseek-v4-flash", "supports1m": true }
]
```

## Manual Start

```powershell
powershell -ExecutionPolicy Bypass -File .\start-claude-deepseek-proxy.ps1
```

## Autostart

Install or repair the Windows scheduled task:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1
```

Check status:

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
```

Remove autostart:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-autostart.ps1
```

## Notes

- This is not a system proxy.
- It only affects software explicitly configured to use `http://127.0.0.1:8787`.
- API keys are not stored in this project. Claude-3p sends the configured API key in the request headers, and the proxy forwards it.
