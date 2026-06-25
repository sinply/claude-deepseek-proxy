@echo off
setlocal
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
echo.
echo ============== WATCHDOG ==============
"%PS%" -NoProfile -Command "$t = Get-ScheduledTask -TaskName 'ClaudeModelRewriteProxyWatchdog' -ErrorAction SilentlyContinue; if ($t) { Write-Host \"[OK] Task: $($t.State)\"; $r = Get-ScheduledTaskInfo -TaskName 'ClaudeModelRewriteProxyWatchdog'; Write-Host \"     Last run: $($r.LastRunTime)\"; $p = Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'proxy-watchdog.ps1' -and $_.ProcessId -ne $PID }; if ($p) { Write-Host \"[OK] Watchdog running - PID: $($p.ProcessId)\" } else { Write-Host \"[WARN] Watchdog not running\" } } else { Write-Host \"[FAIL] Task not installed\" }"
echo.
echo ============== PROXY ==============
"%PS%" -NoProfile -Command "$p = Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { $_.CommandLine -match 'model-rewrite-proxy.cjs' }; if ($p) { Write-Host \"[OK] Proxy running - PID: $($p.ProcessId)\"; $c = [System.Net.Sockets.TcpClient]::new(); try { $c.Connect('127.0.0.1', 8787); Write-Host \"[OK] Port 8787 reachable\"; $c.Close() } catch { Write-Host \"[WARN] Port not reachable\" } } else { Write-Host \"[FAIL] Proxy not running\" }"
echo.
echo ============== MODELS ==============
echo [deepseek]:
curl -s http://127.0.0.1:8787/deepseek/v1/models 2>nul | "%PS%" -NoProfile -Command "$input | ConvertFrom-Json | Select-Object -ExpandProperty data | Select-Object -ExpandProperty id"
echo [ark]:
curl -s http://127.0.0.1:8787/ark/v1/models 2>nul | "%PS%" -NoProfile -Command "$input | ConvertFrom-Json | Select-Object -ExpandProperty data | Select-Object -ExpandProperty id"
echo.
echo ==========================================
pause
endlocal
