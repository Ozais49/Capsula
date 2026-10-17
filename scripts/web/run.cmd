@echo off
rem Runs run.ps1 (see that file for options). Double-click it, or run it
rem from cmd, PowerShell or Git Bash, passing options such as -Config emulators.
setlocal
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
if errorlevel 1 pause
