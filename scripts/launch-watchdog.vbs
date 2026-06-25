' Hidden launcher for the proxy watchdog.
' wscript.exe runs this with no console allocated, so the spawned powershell
' inherits no console and Windows Terminal is never pulled in as a ConPTY host.
' (Task Scheduler's -WindowStyle Hidden still allocates a console and pops a
' stray -Embedding WT window on systems with Windows Terminal installed.)

Set sh = CreateObject("WScript.Shell")
here = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
ps1 = here & "\proxy-watchdog.ps1"
ps  = sh.Environment("Process").Item("SystemRoot")
If ps = "" Then ps = sh.Environment("System").Item("SystemRoot")
If ps = "" Then ps = "C:\WINDOWS"
ps = ps & "\System32\WindowsPowerShell\v1.0\powershell.exe"
sh.Run """" & ps & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, False
