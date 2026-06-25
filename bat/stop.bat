@echo off
setlocal
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
echo.
echo Stopping watchdog scheduled task...
"%PS%" -NoProfile -Command "Stop-ScheduledTask -TaskName 'ClaudeModelRewriteProxyWatchdog' -ErrorAction SilentlyContinue"
echo Stopping proxy process...
"%PS%" -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { $_.CommandLine -match 'model-rewrite-proxy.cjs' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host \"stopped proxy pid=$($_.ProcessId)\" }"
echo Stopping watchdog process...
"%PS%" -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'proxy-watchdog.ps1' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host \"stopped watchdog pid=$($_.ProcessId)\" }"
echo Done.
echo.
endlocal
