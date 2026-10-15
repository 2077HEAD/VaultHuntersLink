@echo off
rem Puts every mod from _VH_disabled_mods back where it was.
cd /d "%~dp0"
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'" & exit /b)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VH-ModCleanup.ps1" -Restore
pause
