@echo off
rem Stops the Windows package: asks the game server to save and shut down (it writes server\stop.request; the server
rem checks for it every few seconds, tells the players, saves and exits cleanly), waits up to 200 seconds for it to
rem exit, then stops the database. Closing the game server window does not save reliably: Windows ends a closed
rem console after about 5 seconds. If the game server is still running after 200 seconds the database is left running
rem (stopping it then would lose the save) and this exits with code 1.
rem (stored with LF in the repository; the package workflow writes it with CRLF, which cmd needs for its labels)
setlocal EnableExtensions
cd /d "%~dp0"

tasklist /fi "imagename eq ChaosServer.exe" 2>nul | find /i "ChaosServer.exe" >nul
if errorlevel 1 goto stopdb
rem a fixed file in the package's own server folder; its content is not read
echo stop> "%~dp0server\stop.request"
if errorlevel 1 (
  echo Could not write server\stop.request. Type /shutdown in game as staff, then run stop-server.bat again.
  pause
  exit /b 1
)
echo Asked the game server to save and stop; waiting up to 200 seconds for it to exit...
set /a tries=0
:wait
timeout /t 1 /nobreak >nul
tasklist /fi "imagename eq ChaosServer.exe" 2>nul | find /i "ChaosServer.exe" >nul
if errorlevel 1 goto stopdb
set /a tries+=1
if %tries% lss 200 goto wait
echo The game server is still running after 200 seconds; it may still be saving.
echo The database is left running. Run stop-server.bat again once the game server has exited.
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
