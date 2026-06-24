@echo off
setlocal
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
echo.
echo Restarting watchdog scheduled task...
"%PS%" -NoProfile -Command "Stop-ScheduledTask -TaskName 'ClaudeModelRewriteProxyWatchdog' -ErrorAction SilentlyContinue; Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'proxy-watchdog.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep 1; Start-ScheduledTask -TaskName 'ClaudeModelRewriteProxyWatchdog'; Write-Host 'Done - watchdog will start polling within 5 seconds'"
echo.
pause
endlocal
