@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Opens the map editor (10.98) on the map of this package. The editor itself is not in the package (its licence,
rem docs/CREDITS.md): unpack its download into the mapeditor folder first (README.txt, "Map editor"). This file sets
rem the editor's folders for you: client = mapeditor\client (Tibia.dat and Tibia.spr), server = server\ (items.otb,
rem items.xml, the map in data\world). With a file as the first argument it opens that .otbm instead (an area of the map
rem inbox, fetch-areas.bat). It writes mapeditor\editor.cfg when there is none, or when the package was moved.
set "PKG=%~dp0"
set "ED=%PKG%mapeditor"
set "EXE="
for %%F in ("%ED%\*.exe") do if not defined EXE set "EXE=%%~fF"
if not defined EXE goto :noeditor
if not exist "%PKG%server\data\items\items.otb" goto :noserver
if not exist "%ED%\client\Tibia.spr" goto :noclient
set "MAP="
rem fetch-areas.bat passes an area of the map inbox: that file instead of the server's map
if not "%~1"=="" if exist "%~1" set "MAP=%~f1"
if not "%~1"=="" if not defined MAP goto :nofile
for %%F in ("%PKG%server\data\world\*.otbm") do if not defined MAP set "MAP=%%~fF"
if not defined MAP goto :nomap

rem the editor reads its folders from editor.cfg next to it; forward slashes need no escaping there
set "SRV=%PKG%server"
set "CLI=%ED%\client"
set "SRV=%SRV:\=/%"
set "CLI=%CLI:\=/%"
set "OLD="
if exist "%ED%\workspace.stamp" set /p OLD=<"%ED%\workspace.stamp"
if not exist "%ED%\editor.cfg" goto :write
if /i not "%OLD%"=="%SRV%" goto :write
goto :run
:write
>"%ED%\editor.cfg" echo [Workspace]
>>"%ED%\editor.cfg" echo WORKSPACE_CLIENT_ROOT=%CLI%
>>"%ED%\editor.cfg" echo WORKSPACE_SERVER_ROOT=%SRV%
>"%ED%\workspace.stamp" echo %SRV%
:run
start "" /D "%ED%" "%EXE%" "%MAP%"
exit /b 0

:noeditor
echo The map editor is not in the package yet: there is no program in
echo   %ED%
echo Download it once, extract it into that folder, and run this file again.
echo README.txt, "Map editor", has the steps (its source is named in docs/CREDITS.md, entry under Tools).
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
