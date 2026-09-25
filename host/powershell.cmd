@echo off
rem ---------------------------------------------------------------------------
rem powershell.cmd -- the weakly-global router for the cmd.exe / Start-Process
rem side. The extension-less `powershell` next to this file is only found by
rem Git Bash (exact-name match); cmd.exe and Start-Process resolve through
rem PATHEXT, so they need this name.
rem
rem There used to be an MSYS shell script named powershell.exe here instead.
rem Windows-side callers did find it and then failed with "not a valid
rem application", so it was withdrawn (see _old-shims). Deliberately no PE:
rem putting an unsigned executable that shadows a system shell name on PATH is
rem not worth it. When a script must run under PowerShell 7 no matter who
rem launches it, use the in-script re-exec snippet instead.
rem
rem Decision, identical to the bash-side shim:
rem   MSYSTEM defined   -> caller is inside the Git Bash process tree -> pwsh
rem   otherwise         -> the real Windows PowerShell 5.1, untouched
rem The default branch is 5.1 on purpose: this is a routing whitelist, not a
rem hijack. Exit code and the original argument text are both passed through.
rem Comments are ASCII on purpose: batch files with UTF-8 text read as noise
rem under a GBK code page.
rem ---------------------------------------------------------------------------
setlocal
set "PS5=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

set "PS7="
if exist "%ProgramW6432%\PowerShell\7\pwsh.exe" set "PS7=%ProgramW6432%\PowerShell\7\pwsh.exe"
if not defined PS7 if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS7=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PS7 if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PS7=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"

if defined MSYSTEM if defined PS7 (
  "%PS7%" %*
  exit /b %ERRORLEVEL%
)

"%PS5%" %*
exit /b %ERRORLEVEL%
