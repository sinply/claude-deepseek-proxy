$taskName = "ClaudeModelRewriteProxyWatchdog"
$port = 8787

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$portOpen = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet
$watchdog = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -eq "powershell.exe" -and
  $_.CommandLine -like "*proxy-watchdog.ps1*" -and
  $_.CommandLine -like "*-File*"
}
$claude = Get-Process -Name Claude -ErrorAction SilentlyContinue

[pscustomobject]@{
  TaskName = $taskName
  TaskInstalled = [bool]$task
  TaskState = if ($task) { $task.State } else { "Missing" }
  WatchdogRunning = [bool]$watchdog
  WatchdogPid = if ($watchdog) { $watchdog.ProcessId } else { $null }
  ClaudeRunning = [bool]$claude
  ProxyPort = $port
  ProxyListening = $portOpen
} | Format-List
