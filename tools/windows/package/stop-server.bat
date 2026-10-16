@echo off
rem Stops the database of the Windows package, once the game server has saved and exited. Close the game server window
rem first (it saves the players on exit). If the game server is still running after 200 seconds the database is left
rem running (stopping it then would lose the save) and this exits with code 1.
rem (stored with LF in the repository; the package workflow writes it with CRLF, which cmd needs for its labels)
setlocal EnableExtensions
cd /d "%~dp0"

tasklist /fi "imagename eq ChaosServer.exe" 2>nul | find /i "ChaosServer.exe" >nul
if errorlevel 1 goto stopdb
echo The game server is still running. Close its window (it saves first); waiting up to 200 seconds...
set /a tries=0
:wait
timeout /t 1 /nobreak >nul
tasklist /fi "imagename eq ChaosServer.exe" 2>nul | find /i "ChaosServer.exe" >nul
if errorlevel 1 goto stopdb
set /a tries+=1
if %tries% lss 200 goto wait
echo The game server is still running after 200 seconds; it may still be saving.
echo The database is left running. Run stop-server.bat again once the game server window has closed.
pause
exit /b 1

:stopdb
"%~dp0mariadb\bin\mariadb-admin.exe" -uroot --host=127.0.0.1 --port=3307 shutdown
if errorlevel 1 (
  echo The database was not running.
) else (
  echo Database stopped.
)
pause
exit /b 0
