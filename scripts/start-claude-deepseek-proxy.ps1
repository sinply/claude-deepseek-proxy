$ErrorActionPreference = "Stop"

# Project layout: src/ has the proxy script, config/ has JSON config,
# logs/ holds all log files. scripts/ only holds PowerShell entry points.
$rootDir    = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $rootDir "config\proxy-config.json"
$nodeExe = $null
if (Test-Path $configPath) {
  try {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($cfg.nodePath -and (Test-Path $cfg.nodePath)) { $nodeExe = $cfg.nodePath }
  } catch { }
}
if (-not $nodeExe) {
  foreach ($c in @("C:\Program Files\nodejs\node.exe", "D:\Program Files\nodejs\node.exe", (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source))) {
    if ($c -and (Test-Path $c)) { $nodeExe = $c; break }
  }
}
if (-not $nodeExe) { throw "node.exe not found (set nodePath in proxy-config.json)" }
$proxyScript = Join-Path $rootDir "src\model-rewrite-proxy.cjs"
$logsDir = Join-Path $rootDir "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$logPath = Join-Path $logsDir ("proxy-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
# Status messages go to a separate file so they never collide with node's stderr handle on $logPath.
$statusLog = Join-Path $logsDir "proxy-start.log"
$hostName = "127.0.0.1"
$port = 8787

function Test-PortOpen {
  param(
    [string]$HostName,
    [int]$Port
  )

  try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $connected = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $connected.AsyncWaitHandle.WaitOne(300)) {
      $client.Close()
      return $false
    }
    $client.EndConnect($connected)
    $client.Close()
    return $true
  } catch {
    return $false
  }
}

if (Test-PortOpen -HostName $hostName -Port $port) {
  "$(Get-Date -Format s) proxy already listening on ${hostName}:${port}" | Add-Content -LiteralPath $statusLog
  exit 0
}

$env:PROXY_CONFIG_PATH = Join-Path $rootDir "config\proxy-config.json"
$env:LISTEN_HOST = $hostName
$env:LISTEN_PORT = [string]$port
# DeepSeek sends an incomplete cert chain; Node.js doesn't do AIA fetching like Windows does.
# Skip TLS verification for upstream connections. Only affects this local proxy process.
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"

# Best-effort: sync model map from Claude-3p configLibrary -> proxy-config.json.
# Non-fatal: on failure the proxy starts with whatever config is already on disk.
$syncScript = Join-Path $rootDir "scripts\sync-models.cjs"
$syncLog = Join-Path $logsDir "sync-models.log"
try {
  "$(Get-Date -Format s) --- sync run ---" | Add-Content -LiteralPath $syncLog
  & $nodeExe $syncScript *>> $syncLog
} catch {
  "$(Get-Date -Format s) sync error: $($_.Exception.Message)" | Add-Content -LiteralPath $syncLog
}

$process = Start-Process `
  -FilePath $nodeExe `
  -ArgumentList "`"$proxyScript`"" `
  -WorkingDirectory $rootDir `
  -WindowStyle Hidden `
  -RedirectStandardError $logPath `
  -PassThru

"$(Get-Date -Format s) started proxy pid=$($process.Id) on ${hostName}:${port}" | Add-Content -LiteralPath $statusLog
