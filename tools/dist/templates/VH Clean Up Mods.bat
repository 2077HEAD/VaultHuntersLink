@echo off
rem Sets aside every mod Vault Hunters doesn't use (into _VH_disabled_mods - nothing is deleted),
rem then checks that Vault Hunters and what it needs are installed.
cd /d "%~dp0"
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'" & exit /b)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VH-ModCleanup.ps1"
pause
