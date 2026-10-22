@echo off
rem Opens the map editor (10.98). The first time it asks for the client folder of version 10.98: choose
rem mapeditor\data\1098 inside this package (the folder with Tibia.dat and Tibia.spr). See README.txt.
cd /d "%~dp0mapeditor"
start "" "%~dp0mapeditor\MapEditor.exe"
