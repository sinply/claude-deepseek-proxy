$ErrorActionPreference = "Stop"

# Removes the watchdog scheduled task and stops any running watchdog + proxy processes.

$taskNames = @("ClaudeModelRewriteProxyWatchdog", "ClaudeDeepSeekModelRewriteProxy")
foreach ($taskName in $taskNames) {
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed scheduled task: $taskName"
  } else {
    Write-Host "Scheduled task not found: $taskName"
  }
}

# Kill any watchdog processes (powershell running proxy-watchdog.ps1)
Get-CimInstance Win32_Process | Where-Object {
  $_.Name -eq "powershell.exe" -and $_.CommandLine -like "*proxy-watchdog.ps1*"
} | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  Write-Host "Stopped watchdog pid=$($_.ProcessId)"
}

# Kill any running proxy
$conn = Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) {
  Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
  Write-Host "Stopped proxy pid=$($conn.OwningProcess)"
}
