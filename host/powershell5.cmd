@echo off
rem ---------------------------------------------------------------------------
rem powershell5.cmd -- force the real Windows PowerShell 5.1 from the cmd.exe /
rem Start-Process side. Same escape hatch as the bash-side `powershell5`.
rem ---------------------------------------------------------------------------
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" %*
exit /b %ERRORLEVEL%
