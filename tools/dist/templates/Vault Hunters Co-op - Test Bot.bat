@echo off
rem Vault Hunters Co-op: SOLO TEST. Adds fake players to YOUR server so you can see co-op
rem working without a second PC.
rem
rem   1. Run "Vault Hunters Co-op - Host.bat" and load a save.
rem   2. In the Vault Hunters window (CET overlay) click "Save my spot for the test bot".
rem   3. Run this file. Fake players walk in circles around the saved spot.
rem      Close this window to make them leave.
rem
rem Optional: drag nothing, just edit BOTS below (1-3; you are the 4th).

setlocal enabledelayedexpansion
cd /d "%~dp0"
set "BOTS=3"
set "PORT=1337"
if exist "vaulthunters-coop.txt" (
    for /f "usebackq eol=# tokens=1,2 delims==" %%a in ("vaulthunters-coop.txt") do (
        if /i "%%a"=="port" set "PORT=%%b"
    )
)

set "SPOTFILE=bin\x64\plugins\cyber_engine_tweaks\mods\VaultHunters\testbot_position.txt"
if not exist "%SPOTFILE%" goto :nospot
set /p SPOT=<"%SPOTFILE%"

if not exist "VaultHuntersServer\vh-testbot.exe" goto :nobot

echo Sending %BOTS% test player(s) to %SPOT% on port %PORT% ...
echo Close this window to make them leave.
"VaultHuntersServer\vh-testbot.exe" --server 127.0.0.1 --port %PORT% --count %BOTS% --pattern circle --center %SPOT% --hz 20 --jump-every 8 --vh-class 0
pause
exit /b 0

:nospot
echo.
echo   No saved spot yet. In game, open the CET overlay, and in the Vault Hunters window
echo   click "Save my spot for the test bot". Then run this again.
echo.
pause
exit /b 1

:nobot
echo.
echo   VaultHuntersServer\vh-testbot.exe is missing - unpack the latest
echo   VaultHuntersLink-Server.zip into this folder.
echo.
pause
exit /b 1
