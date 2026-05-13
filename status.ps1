$taskName = "ClaudeDeepSeekModelRewriteProxy"
$port = 8787

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$portOpen = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet

[pscustomobject]@{
  TaskName = $taskName
  TaskInstalled = [bool]$task
  TaskState = if ($task) { $task.State } else { "Missing" }
  ProxyPort = $port
  ProxyListening = $portOpen
} | Format-List
