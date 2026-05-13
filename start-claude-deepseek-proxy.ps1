$ErrorActionPreference = "Stop"

$nodeExe = "D:\Program Files\nodejs\node.exe"
$proxyScript = Join-Path $PSScriptRoot "model-rewrite-proxy.cjs"
$logPath = Join-Path $PSScriptRoot "proxy.log"
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

$env:UPSTREAM_BASE_URL = "https://api.deepseek.com/anthropic"
$env:LISTEN_HOST = $hostName
$env:LISTEN_PORT = [string]$port

$process = Start-Process `
  -FilePath $nodeExe `
  -ArgumentList "`"$proxyScript`"" `
  -WorkingDirectory $PSScriptRoot `
  -WindowStyle Hidden `
  -RedirectStandardError $logPath `
  -PassThru

"$(Get-Date -Format s) started proxy pid=$($process.Id) on ${hostName}:${port}" | Add-Content -LiteralPath $logPath
