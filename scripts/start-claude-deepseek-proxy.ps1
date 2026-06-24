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
$logPath = Join-Path $logsDir "proxy.log"
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
  "$(Get-Date -Format s) proxy already listening on ${hostName}:${port}" | Add-Content -LiteralPath $logPath
  exit 0
}

$env:PROXY_CONFIG_PATH = Join-Path $rootDir "config\proxy-config.json"
$env:LISTEN_HOST = $hostName
$env:LISTEN_PORT = [string]$port
# DeepSeek sends an incomplete cert chain; Node.js doesn't do AIA fetching like Windows does.
# Skip TLS verification for upstream connections. Only affects this local proxy process.
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"

$process = Start-Process `
  -FilePath $nodeExe `
  -ArgumentList "`"$proxyScript`"" `
  -WorkingDirectory $rootDir `
  -WindowStyle Hidden `
  -RedirectStandardError $logPath `
  -PassThru

"$(Get-Date -Format s) started proxy pid=$($process.Id) on ${hostName}:${port}" | Add-Content -LiteralPath $logPath
