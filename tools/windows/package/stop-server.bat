@echo off
rem Stops the database of the Windows package. Close the game server window first (it saves the players on exit).
cd /d "%~dp0"
"%~dp0mariadb\bin\mariadb-admin.exe" -uroot --host=127.0.0.1 --port=3307 shutdown
if errorlevel 1 (
  echo The database was not running.
) else (
  echo Database stopped.
)
pause
