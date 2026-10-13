@echo off
rem Vault Hunters Co-op launcher: JOIN a friend's game.
rem
rem Lives in the Cyberpunk 2077 folder (next to bin\, r6\, archive\). The game only joins a co-op
rem server when it is started with the connect arguments below, so a normal launch from your
rem store app is always single player. Do not launch through Steam/Epic: they drop the arguments.
rem
rem Put your host's address in vaulthunters-coop.txt (see the comments in that file).

setlocal enabledelayedexpansion
cd /d "%~dp0"

set "ADDR="
set "PORT="

if not exist "vaulthunters-coop.txt" goto :nocfg

for /f "usebackq eol=# tokens=1,2 delims==" %%a in ("vaulthunters-coop.txt") do (
    if /i "%%a"=="address" set "ADDR=%%b"
    if /i "%%a"=="port"    set "PORT=%%b"
)

if not defined ADDR goto :nocfg
if not defined PORT set "PORT=1337"

rem set VH_DRYRUN=1 to check the config parsing without starting the game.
if defined VH_DRYRUN (
    echo DRYRUN address=%ADDR% port=%PORT%
    exit /b 0
)

if not exist "bin\x64\Cyberpunk2077.exe" goto :nogame

echo Joining Vault Hunters co-op at %ADDR%:%PORT% ...
start "" "bin\x64\Cyberpunk2077.exe" --cyberverse-server-address=%ADDR% --cyberverse-server-port=%PORT%
exit /b 0

:nocfg
echo.
echo   vaulthunters-coop.txt is missing or has no "address=" line.
echo   Open it in Notepad and put your host's address there, for example:
echo.
echo       address=100.64.0.1
echo       port=1337
echo.
pause
exit /b 1

:nogame
echo.
echo   bin\x64\Cyberpunk2077.exe not found next to this file.
echo   Unpack the Vault Hunters Co-op zip INTO your Cyberpunk 2077 folder, so this file
echo   sits right beside the game's own bin\ and r6\ folders.
echo.
pause
exit /b 1
