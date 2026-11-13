@echo off
rem Starts the Cinders of Chaos client. It connects to 127.0.0.1: run start-server.bat first.
rem The game starts only through the launcher (client base patch 0198): --play-local gives it a start ticket and updates nothing.
cd /d "%~dp0client"
start "" "%~dp0client\CindersLauncher.exe" --play-local --dir "%~dp0client"
