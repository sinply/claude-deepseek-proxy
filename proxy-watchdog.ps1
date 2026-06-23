$ErrorActionPreference = "Continue"

# Watchdog: keeps the model-rewrite proxy in sync with the Claude Code client.
# - When at least one claude.exe (UWP Claude Code) is running, ensure the proxy is up.
# - When no claude.exe has been seen for a grace period, stop the proxy.
# - Designed to run as a hidden background process started at logon.

$scriptDir   = $PSScriptRoot
$proxyScript = Join-Path $scriptDir "model-rewrite-proxy.cjs"
$configPath  = Join-Path $scriptDir "proxy-config.json"
$logPath     = Join-Path $scriptDir "proxy.log"
$watchdogLog = Join-Path $scriptDir "watchdog.log"
$listenHost  = "127.0.0.1"
$listenPort  = 8787
# Resolve node.exe: prefer config's nodePath, fall back to common locations.
$nodeExe = $null
if (Test-Path $configPath) {
  try {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($cfg.nodePath -and (Test-Path $cfg.nodePath)) { $nodeExe = $cfg.nodePath }
  } catch { }
}
if (-not $nodeExe) {
  foreach ($candidate in @("C:\Program Files\nodejs\node.exe", "D:\Program Files\nodejs\node.exe", (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source))) {
    if ($candidate -and (Test-Path $candidate)) { $nodeExe = $candidate; break }
  }
}
if (-not $nodeExe) {
  Write-Log "ERROR: node.exe not found (set nodePath in proxy-config.json)"
  exit 1
}

# Stop grace period: how long after the last claude.exe exits before we stop the proxy.
# Covers quick restarts and the UWP multi-process shutdown chatter.
$stopGraceSeconds = 15
# Poll interval.
$pollSeconds = 5

$lastSeenClaude = $null
$watchdogPid = $PID

# Singleton guard via named mutex — atomic across concurrent startups.
$mutex = New-Object System.Threading.Mutex($false, "Global\ClaudeModelRewriteProxyWatchdog")
$acquired = $mutex.WaitOne(0, $false)
if (-not $acquired) {
  # Another watchdog holds the mutex. Exit silently.
  $mutex.Close()
  exit 0
}

function Write-Log {
  param([string]$Msg)
  "$(Get-Date -Format s) [watchdog pid=$watchdogPid] $Msg" | Add-Content -LiteralPath $watchdogLog -ErrorAction SilentlyContinue
}

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
  if ($conn) { return [int]$conn.OwningProcess }
  return $null
}

function Start-Proxy {
  $env:PROXY_CONFIG_PATH            = $configPath
  $env:LISTEN_HOST                  = $listenHost
  $env:LISTEN_PORT                  = [string]$listenPort
  $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"

  # Use a per-startup log file so Start-Process redirection doesn't conflict
  # with the watchdog's own log writes.
  $proxyLogFile = Join-Path $scriptDir ("proxy-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

  try {
    $proc = Start-Process `
      -FilePath $nodeExe `
      -ArgumentList "`"$proxyScript`"" `
      -WorkingDirectory $scriptDir `
      -WindowStyle Hidden `
      -RedirectStandardError $proxyLogFile `
      -PassThru
  } catch {
    Write-Log "ERROR starting proxy: $($_.Exception.Message)"
    return $null
  }

  Write-Log "started proxy pid=$($proc.Id) log=$proxyLogFile"
  # wait up to 5s for port to come up
  for ($i = 0; $i -lt 50; $i++) {
    if (Test-PortOpen -HostName $listenHost -Port $listenPort) {
      Write-Log "proxy listening pid=$($proc.Id)"
      return $proc.Id
    }
    Start-Sleep -Milliseconds 100
  }
  Write-Log "WARN: proxy pid=$($proc.Id) did not start listening"
  return $proc.Id
}

function Stop-Proxy {
  param([int]$PidToStop)
  if (-not $PidToStop) { return }
  $proc = Get-Process -Id $PidToStop -ErrorAction SilentlyContinue
  if ($proc) {
    Stop-Process -Id $PidToStop -Force -ErrorAction SilentlyContinue
    Write-Log "stopped proxy pid=$PidToStop"
  }
}

function Test-ClaudeRunning {
  # UWP Claude Code runs as Claude.exe under WindowsApps. Match by name to be robust
  # against version-suffixed paths.
  $procs = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
  return [bool]$procs
}

Write-Log "watchdog starting (poll=${pollSeconds}s, grace=${stopGraceSeconds}s)"

while ($true) {
  try {
    $claudeUp = Test-ClaudeRunning

    if ($claudeUp) {
      $lastSeenClaude = Get-Date
      $proxyPid = Get-ProxyPid
      if (-not $proxyPid) {
        Write-Log "claude running, proxy down -> starting"
        $null = Start-Proxy
      }
    } else {
      if ($lastSeenClaude) {
        $elapsed = ((Get-Date) - $lastSeenClaude).TotalSeconds
        if ($elapsed -ge $stopGraceSeconds) {
          $proxyPid = Get-ProxyPid
          if ($proxyPid) {
            Write-Log "claude gone for ${elapsed}s -> stopping proxy pid=$proxyPid"
            Stop-Proxy -PidToStop $proxyPid
          }
          $lastSeenClaude = $null
        }
      }
    }
  } catch {
    Write-Log "ERROR in poll loop: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds $pollSeconds
}
