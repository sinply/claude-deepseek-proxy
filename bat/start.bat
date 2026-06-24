@echo off
setlocal
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\start-claude-deepseek-proxy.ps1"
if errorlevel 1 (
    echo Failed to start proxy. Press any key to exit.
    pause >nul
)
endlocal
