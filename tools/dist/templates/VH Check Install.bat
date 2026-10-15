@echo off
rem Checks that Vault Hunters and everything it needs is installed. Changes nothing.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VH-ModCleanup.ps1" -Check
pause
