@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Opens the map editor of this package (mapeditor\, README.txt "Map editor") on the server's map, or on the .otbm given
rem as the first argument (an area of the map inbox, fetch-areas.bat). The editor cannot open a map from the command
rem line, so this file:
rem   - copies the server's items.otb into mapeditor\client and its items.xml into mapeditor\data\1098 (every Chaos item)
rem   - presets the editor's settings (map-editor-settings.ps1): the 10.98 client folder = mapeditor\client, the map
rem     first in "Recent maps", our area generator as the script of Tools > Lua Scripts
rem   - puts the map's path on the clipboard and starts the editor; click the map under "Recent maps" (or File > Open
rem     and paste the path).
set "PKG=%~dp0"
set "ED=%PKG%mapeditor"
set "EXE="
rem our build (Cinders Map Editor, O388), else the one program of the folder that is not the updater
if exist "%ED%\CindersMapEditor.exe" set "EXE=%ED%\CindersMapEditor.exe"
if not defined EXE for %%F in ("%ED%\*.exe") do call :pickexe "%%~fF"
if not defined EXE goto :noeditor
for %%F in ("%EXE%") do set "EXENAME=%%~nxF"
if not exist "%PKG%server\data\items\items.otb" goto :noserver
if not exist "%ED%\client\Tibia.spr" goto :noclient
set "MAP="
rem fetch-areas.bat passes an area of the map inbox: that file instead of the server's map
if not "%~1"=="" if exist "%~1" set "MAP=%~f1"
if not "%~1"=="" if not defined MAP goto :nofile
for %%F in ("%PKG%server\data\world\*.otbm") do if not defined MAP set "MAP=%%~fF"
if not defined MAP goto :nomap

rem the editor reads items.otb from the client folder and the item names from its data\1098\items.xml
copy /y "%PKG%server\data\items\items.otb" "%ED%\client\items.otb" >nul
if exist "%PKG%server\data\items\items.xml" if exist "%ED%\data\1098" copy /y "%PKG%server\data\items\items.xml" "%ED%\data\1098\items.xml" >nul

rem an open editor writes its settings back when it closes: preset them only while it is closed
tasklist /FI "IMAGENAME eq %EXENAME%" 2>nul | find /i "%EXENAME%" >nul
if not errorlevel 1 goto :running
powershell -NoProfile -ExecutionPolicy Bypass -File "%PKG%map-editor-settings.ps1" -Package "%PKG%." -Map "%MAP%"
if errorlevel 1 echo The settings could not be preset: choose mapeditor\client for 10.98 once (README.txt, "Map editor").
<nul set /p "=%MAP%" | clip
start "" /D "%ED%" "%EXE%"
echo The map editor starts. Open the map:
echo   %MAP%
echo under "Recent maps" on its start window (or File ^> Open and paste: the path is on the clipboard).
echo Client: 10.98 (mapeditor\client). Our generator: Tools ^> Lua Scripts, "Custom Lua script" (mapeditor\cinders\README.txt).
timeout /t 15 >nul
exit /b 0

:running
<nul set /p "=%MAP%" | clip
echo The map editor is already open. Open the map with File ^> Open and paste the path (it is on the clipboard):
echo   %MAP%
goto :end
:noeditor
echo The map editor is missing: there is no program in
echo   %ED%
echo Extract the whole package zip again (README.txt, "Map editor").
goto :end
:noserver
echo No server data found: %PKG%server\data\items\items.otb is missing. Extract the whole zip.
goto :end
:noclient
echo No client files found: %ED%\client\Tibia.spr is missing. Extract the whole zip.
goto :end
:nofile
echo The file %~1 does not exist.
goto :end
:nomap
echo No map found: there is no .otbm in %PKG%server\data\world.
:end
pause
exit /b 1

:pickexe
if defined EXE exit /b 0
echo %~n1| find /i "updater" >nul && exit /b 0
set "EXE=%~1"
exit /b 0
