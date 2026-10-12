@echo off
rem Starts the Cinders of Chaos client. It connects to 127.0.0.1: run start-server.bat first.
cd /d "%~dp0client"
start "" "%~dp0client\Chaos.exe"
