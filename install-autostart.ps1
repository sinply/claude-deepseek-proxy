$ErrorActionPreference = "Stop"

# Installs a logon scheduled task that runs proxy-watchdog.ps1 in the background.
# The watchdog keeps the model-rewrite proxy in sync with the Claude Code client:
# proxy starts when Claude is running, stops shortly after Claude exits.

$taskName = "ClaudeModelRewriteProxyWatchdog"
$scriptPath = Join-Path $PSScriptRoot "proxy-watchdog.ps1"
$powerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# Stop and remove any legacy proxy-autostart task (old name) so we don't run both.
Get-ScheduledTask -TaskName "ClaudeDeepSeekModelRewriteProxy" -ErrorAction SilentlyContinue |
  ForEach-Object {
    Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
    Write-Host "Removed legacy task: $($_.TaskName)"
  }

$action = New-ScheduledTaskAction `
  -Execute $powerShell `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -Hidden `
  -MultipleInstances IgnoreNew `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -StartWhenAvailable

Register-ScheduledTask `
  -TaskName $taskName `
  -Action $action `
  -Trigger $trigger `
  -Principal $principal `
  -Settings $settings `
  -Description "Watches for Claude Code and keeps the local model-rewrite proxy in sync." `
  -Force | Out-Null

Start-ScheduledTask -TaskName $taskName

Write-Host "Installed and started scheduled task: $taskName"
Write-Host "Watchdog will start the proxy when Claude Code runs and stop it shortly after Claude exits."
