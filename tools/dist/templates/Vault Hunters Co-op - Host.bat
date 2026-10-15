@echo off
rem Vault Hunters Co-op launcher: HOST a game for your friends.
rem
rem Starts the small co-op server (VaultHuntersServer\) in its own window, then starts the game
rem connected to it. Your friends use "Vault Hunters Co-op - Join.bat" with YOUR address in their
rem vaulthunters-coop.txt. The first player in the world is the party host.
rem
rem Reaching you over the internet: easiest is a free virtual LAN that everyone joins
rem (Tailscale, ZeroTier or Radmin VPN) - then give friends your address from that app.
rem Otherwise forward UDP port 1337 on your router to this PC.

setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PORT=1337"
if exist "vaulthunters-coop.txt" (
    for /f "usebackq eol=# tokens=1,2 delims==" %%a in ("vaulthunters-coop.txt") do (
        if /i "%%a"=="port" set "PORT=%%b"
    )
)

if not exist "VaultHuntersServer\Cyberverse.Server.exe" goto :noserver
if not exist "bin\x64\Cyberpunk2077.exe" goto :nogame

if defined VH_DRYRUN (
    echo DRYRUN host port=%PORT%
    exit /b 0
)

rem Apply a pending update: server files that could not be replaced while it was running.
if exist "VaultHuntersServer\_update\" (
    echo Applying a Vault Hunters co-op update ...
    robocopy "VaultHuntersServer\_update" "VaultHuntersServer" /MOVE /R:1 /W:1 /NFL /NDL /NJH /NJS >nul
    if exist "VaultHuntersServer\_update\" (
        echo.
        echo   Note: could not apply a pending update in VaultHuntersServer\_update.
        echo   If co-op misbehaves, close all co-op windows and run this file once with
        echo   right-click - "Run as administrator". Starting anyway ...
        echo.
        timeout /t 5 >nul
    )
)

echo Starting the Vault Hunters co-op server on UDP port %PORT% ...
start "Vault Hunters Co-op Server - close this window to end the session" /d "%~dp0VaultHuntersServer" "%~dp0VaultHuntersServer\Cyberverse.Server.exe" --port=%PORT%

rem Give the server a moment to open its port before the game tries to connect.
timeout /t 3 /nobreak >nul

echo Starting the game ...
start "" "bin\x64\Cyberpunk2077.exe" --cyberverse-server-address=127.0.0.1 --cyberverse-server-port=%PORT%
exit /b 0

:noserver
echo.
echo   VaultHuntersServer\Cyberverse.Server.exe not found.
echo   Unpack the Vault Hunters Co-op SERVER zip into your Cyberpunk 2077 folder as well.
echo.
pause
exit /b 1

:nogame
echo.
echo   bin\x64\Cyberpunk2077.exe not found next to this file.
echo   Unpack the Vault Hunters Co-op zips INTO your Cyberpunk 2077 folder.
echo.
pause
exit /b 1
