$ErrorActionPreference = "Stop"

# --- config ---
$proxyScript  = Join-Path $PSScriptRoot "model-rewrite-proxy.cjs"
$configPath   = Join-Path $PSScriptRoot "proxy-config.json"
$logPath      = Join-Path $PSScriptRoot "proxy.log"
$listenHost   = "127.0.0.1"
$listenPort   = 8787

# Resolve node.exe: prefer config's nodePath, fall back to common locations.
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
if (-not $nodeExe) { Write-Error "node.exe not found (set nodePath in proxy-config.json)"; exit 1 }

# Claude Code client (Microsoft Store install). Resolve at runtime because the
# version-suffixed path changes on every update.
$claudeExe = $null
$candidates = @()
$storeApps = Get-ChildItem "C:\Program Files\WindowsApps" -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "Claude_*_x64__*" }
foreach ($d in $storeApps) {
  $p = Join-Path $d.FullName "app\Claude.exe"
  if (Test-Path $p) { $candidates += $p }
}
if ($candidates.Count -gt 0) {
  # pick the highest version
  $claudeExe = $candidates | Sort-Object -Descending | Select-Object -First 1
}
if (-not $claudeExe) {
  Write-Error "Claude.exe not found under C:\Program Files\WindowsApps. Adjust start-claude.ps1 if installed elsewhere."
  exit 1
}

# --- helpers ---
function Test-PortOpen {
  param([string]$HostName, [int]$Port)
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

function Get-ProxyPid {
  $conn = Get-NetTCPConnection -LocalPort $listenPort -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($conn) { return $conn.OwningProcess }
  return $null
}

# --- 1. start proxy if not running ---
$proxyPid = Get-ProxyPid
$weStartedProxy = $false
if (-not $proxyPid) {
  $env:PROXY_CONFIG_PATH          = $configPath
  $env:LISTEN_HOST                = $listenHost
  $env:LISTEN_PORT                = [string]$listenPort
  $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"

  $proc = Start-Process `
    -FilePath $nodeExe `
    -ArgumentList "`"$proxyScript`"" `
    -WorkingDirectory $PSScriptRoot `
    -WindowStyle Hidden `
    -RedirectStandardError $logPath `
    -PassThru

  "$(Get-Date -Format s) wrapper started proxy pid=$($proc.Id)" | Add-Content -LiteralPath $logPath
  $weStartedProxy = $true
  $proxyPid = $proc.Id

  # wait up to 5s for port to come up
  for ($i = 0; $i -lt 50; $i++) {
    if (Test-PortOpen -HostName $listenHost -Port $listenPort) { break }
    Start-Sleep -Milliseconds 100
  }
  if (-not (Test-PortOpen -HostName $listenHost -Port $listenPort)) {
    Write-Error "Proxy failed to listen on ${listenHost}:${listenPort}. Check $logPath."
    exit 1
  }
  Write-Host "Proxy started (pid=$proxyPid) on ${listenHost}:${listenPort}"
} else {
  Write-Host "Proxy already running (pid=$proxyPid) on ${listenHost}:${listenPort}"
}

# --- 2. launch Claude Code client ---
Write-Host "Starting Claude: $claudeExe"
$claudeProc = Start-Process -FilePath $claudeExe -PassThru
Write-Host "Claude started (pid=$($claudeProc.Id))"

# --- 3. wait for Claude to exit ---
$claudeProc.WaitForExit()
"$(Get-Date -Format s) claude pid=$($claudeProc.Id) exited" | Add-Content -LiteralPath $logPath

# --- 4. stop proxy only if we started it ---
if ($weStartedProxy) {
  # small grace period in case claude relaunches immediately
  Start-Sleep -Seconds 2
  if (-not (Get-Process -Id $claudeProc.Id -ErrorAction SilentlyContinue)) {
    $current = Get-ProxyPid
    if ($current -eq $proxyPid) {
      Stop-Process -Id $proxyPid -Force -ErrorAction SilentlyContinue
      "$(Get-Date -Format s) wrapper stopped proxy pid=$proxyPid" | Add-Content -LiteralPath $logPath
      Write-Host "Proxy stopped (pid=$proxyPid)"
    } else {
      Write-Host "Proxy ownership changed (pid $current), not stopping"
    }
  } else {
    Write-Host "Claude still alive, leaving proxy running"
  }
} else {
  Write-Host "Proxy was pre-existing, leaving it running"
}
