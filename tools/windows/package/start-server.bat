@echo off
rem Cinders of Chaos, Windows package: starts the database (MariaDB on 127.0.0.1:3307) and the game server.
rem The first start creates the database and loads server\sql-setup\*.sql (about a minute).
rem (stored with LF in the repository; the package workflow writes it with CRLF, which cmd needs for its labels)
setlocal EnableExtensions
cd /d "%~dp0"
set "ROOT=%~dp0"
set "MDB=%ROOT%mariadb\bin"
set "DATA=%ROOT%database"

if not exist "%MDB%\mariadbd.exe" (
  echo MariaDB is missing: %MDB%\mariadbd.exe
  goto fail
)

if not exist "%DATA%\mysql" (
  echo First start: creating the database folder...
  "%MDB%\mariadb-install-db.exe" --datadir="%DATA%" --port=3307
  if errorlevel 1 goto fail
)

tasklist /fi "imagename eq mariadbd.exe" 2>nul | find /i "mariadbd.exe" >nul
if errorlevel 1 (
  echo Starting the database...
  start "Cinders of Chaos database - stop it with stop-server.bat" /min "%MDB%\mariadbd.exe" --defaults-file="%DATA%\my.ini" --bind-address=127.0.0.1 --console
)

set /a tries=0
:wait
"%MDB%\mariadb-admin.exe" -uroot --host=127.0.0.1 --port=3307 ping >nul 2>&1
if not errorlevel 1 goto up
set /a tries+=1
if %tries% geq 60 (
  echo The database did not start within 60 seconds. See the "Cinders of Chaos database" window.
  goto fail
)
timeout /t 1 /nobreak >nul
goto wait

:up
if exist "%DATA%\chaos-setup-done.txt" goto run
echo Loading the game database from server\sql-setup ...
"%MDB%\mariadb.exe" -uroot --host=127.0.0.1 --port=3307 -e "CREATE DATABASE IF NOT EXISTS chaos CHARACTER SET utf8mb4"
if errorlevel 1 goto fail
for %%f in ("%ROOT%server\sql-setup\*.sql") do (
  echo   %%~nxf
  "%MDB%\mariadb.exe" -uroot --host=127.0.0.1 --port=3307 --force chaos < "%%f" >> "%ROOT%database-setup.log" 2>&1
)
echo done> "%DATA%\chaos-setup-done.txt"
echo Database ready. Accounts: chaos / chaos (staff), test / test (one character per class).

:run
echo Starting the game server. Stop it with stop-server.bat (it saves first).
cd /d "%ROOT%server"
rem a stop request left from before (stop-server.bat) must not stop this start at once
if exist "%ROOT%server\stop.request" del /q "%ROOT%server\stop.request"
if not exist "%ROOT%crashes" mkdir "%ROOT%crashes"
set /a crashes=0
:serve
ChaosServer.exe
set "code=%errorlevel%"
rem a clean exit (code 0: /shutdown, a server save shutdown) ends here; anything else is a crash and starts it again
if "%code%"=="0" goto stopped
set /a crashes+=1
echo %date% %time% exit code %code% >> "%ROOT%crashes\crashes.log"
echo.
echo The game server crashed (exit code %code%). Restart %crashes% of 5; see crashes\crashes.log.
rem five crashes without a clean stop in between: something is wrong with the data, stop retrying
if %crashes% geq 5 (
  echo It crashed 5 times. Not restarting again: read the window above and crashes\crashes.log.
  goto stopped
)
timeout /t 5 /nobreak >nul
echo Restarting the game server...
goto serve

:stopped
echo.
echo The game server stopped. The database keeps running until stop-server.bat.
pause
exit /b 0

:fail
pause
exit /b 1
