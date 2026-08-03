@echo off
rem ChoomLink launcher.
rem
rem Lives in the game folder (this file sits next to bin\, r6\, archive\). Cyberpunk only joins a
rem ChoomLink server when it is started with the connect arguments below -- there is no in-game
rem server browser yet, so a normal Steam launch always starts singleplayer.
rem
rem Do not launch through the Steam UI: Steam drops the arguments.

setlocal enabledelayedexpansion
cd /d "%~dp0"

set "ADDR="
set "PORT="

if not exist "choomlink-server.txt" goto :nocfg

for /f "usebackq eol=# tokens=1,2 delims==" %%a in ("choomlink-server.txt") do (
    if /i "%%a"=="address" set "ADDR=%%b"
    if /i "%%a"=="port"    set "PORT=%%b"
)

if not defined ADDR goto :nocfg
if not defined PORT set "PORT=1337"

rem Escape hatch so the config parsing above can be checked without owning a game install
rem (set CHOOMLINK_DRYRUN=1). The launcher is the one file testers run before anything else works,
rem so it has to be verifiable on its own.
if defined CHOOMLINK_DRYRUN (
    echo DRYRUN address=%ADDR% port=%PORT%
    exit /b 0
)

if not exist "bin\x64\Cyberpunk2077.exe" goto :nogame

echo Connecting to %ADDR%:%PORT% ...
start "" "bin\x64\Cyberpunk2077.exe" --cyberverse-server-address=%ADDR% --cyberverse-server-port=%PORT%
exit /b 0

:nocfg
echo.
echo   choomlink-server.txt is missing or has no "address=" line.
echo   Open it in Notepad and put the server address there, for example:
echo.
echo       address=100.64.0.1
echo       port=1337
echo.
pause
exit /b 1

:nogame
echo.
echo   bin\x64\Cyberpunk2077.exe not found next to this file.
echo.
echo   The ChoomLink zip has to be unpacked INTO the Cyberpunk 2077 folder, so that this
echo   launcher ends up right beside the game's own bin\ and r6\ folders.
echo.
pause
exit /b 1
