@echo off
rem Runs release.ps1 (see that file for options), e.g. release.cmd -Component app -Version 1.1.0
setlocal
set "PS=powershell"
where pwsh >/dev/null 2>/dev/null && set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0release.ps1" %*
if errorlevel 1 pause
