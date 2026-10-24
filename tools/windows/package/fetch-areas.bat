@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Map inbox (docs/MAP_GUIDE.md "Map inbox"): downloads the areas the server has published (the admin app, Comandos tab,
rem "Publicar areas") into mapeditor\inbox\ and opens the one you pick in the map editor (open-map-editor.bat).
rem Use:  fetch-areas.bat [ADDRESS]
rem ADDRESS is the url= line the admin app showed (Comandos tab, Mapas pedidos, Publicar areas), like https://your-site/dl/areas-0123abcd.../ ; it is kept in
rem mapeditor\inbox\source.txt after the first run, so the next runs need none. Every file is checked against the sha256
rem in its files.txt. Nothing outside mapeditor\inbox is written. Needs curl.exe and certutil (both are part of Windows 10+).
set "PKG=%~dp0"
set "INB=%PKG%mapeditor\inbox"
if not exist "%PKG%mapeditor" goto :nodir
if not exist "%INB%" mkdir "%INB%"
where curl.exe >nul 2>&1
if errorlevel 1 goto :nocurl

set "URL=%~1"
if not defined URL if exist "%INB%\source.txt" set /p URL=<"%INB%\source.txt"
if not defined URL goto :askurl
:haveurl
echo "%URL%"| findstr /r /i /x "\"https://[a-z0-9./_-]*/\"" >nul
if errorlevel 1 goto :badurl

echo Fetching the list from %URL%
curl.exe --fail --silent --show-error --proto =https --proto-redir =https --max-time 60 -o "%INB%\list.txt" "%URL%list.txt"
if errorlevel 1 goto :nolist
>"%INB%\source.txt" echo %URL%

set /a N=0
for /f "usebackq tokens=1-4 delims=|" %%A in ("%INB%\list.txt") do call :one "%%A" "%%B" "%%C" "%%D"
if %N%==0 goto :empty
echo.
echo Areas in the inbox, in mapeditor\inbox:
set /a K=0
:show
set /a K+=1
call echo   %K%. %%ID%K%%%   %%ST%K%%%   levels %%LV%K%%%   %%NM%K%%%
if %K% LSS %N% goto :show
echo.
set "PICK="
set /p PICK=Number to open in the map editor (Enter = none): 
if not defined PICK goto :done
echo "%PICK%"| findstr /r /x "\"[0-9][0-9]*\"" >nul
if errorlevel 1 goto :done
if %PICK% LSS 1 goto :done
if %PICK% GTR %N% goto :done
call set "SEL=%%ID%PICK%%%"
if not exist "%INB%\%SEL%\%SEL%.otbm" goto :done
call "%PKG%open-map-editor.bat" "%INB%\%SEL%\%SEL%.otbm"
:done
exit /b 0

:one
rem one list line: id|status|lo-hi|name. The id becomes a folder name: letters, digits and _ only.
echo "%~1"| findstr /r /x "\"[a-z][a-z0-9_]*\"" >nul
if errorlevel 1 exit /b 0
set "ONE=%~1"
if not exist "%INB%\%ONE%" mkdir "%INB%\%ONE%"
curl.exe --fail --silent --show-error --proto =https --proto-redir =https --max-time 60 -o "%INB%\%ONE%\files.txt" "%URL%%ONE%/files.txt"
if errorlevel 1 echo   %ONE%: files.txt could not be downloaded& exit /b 0
set "BAD="
for /f "usebackq tokens=1,2" %%H in ("%INB%\%ONE%\files.txt") do call :getfile "%%H" "%%I"
if defined BAD echo   %ONE%: a file failed (see above); this area is not listed& exit /b 0
set /a N+=1
set "ID%N%=%~1"
set "ST%N%=%~2"
set "LV%N%=%~3"
set "NM%N%=%~4"
exit /b 0

:getfile
rem %1 = sha256, %2 = file name (letters, digits, . _ - only)
echo "%~2"| findstr /r /x "\"[A-Za-z0-9_.-][A-Za-z0-9_.-]*\"" >nul
if errorlevel 1 set "BAD=1" & echo   refused file name & exit /b 0
curl.exe --fail --silent --show-error --proto =https --proto-redir =https --max-time 120 -o "%INB%\%ONE%\%~2" "%URL%%ONE%/%~2"
if errorlevel 1 set "BAD=1" & echo   %~2: download failed & exit /b 0
set "GOT="
for /f "skip=1 delims=" %%X in ('certutil -hashfile "%INB%\%ONE%\%~2" SHA256') do if not defined GOT set "GOT=%%X"
if not defined GOT set "BAD=1" & echo   %~2: no checksum & exit /b 0
set "GOT=%GOT: =%"
if /i not "%GOT%"=="%~1" set "BAD=1" & echo   %~2: the checksum does not match & exit /b 0
exit /b 0

:askurl
echo Paste the address the admin app showed after "Publicar areas" (the line starting with url=, without "url=").
echo It looks like https://your-site/dl/areas-0123456789abcdef0123456789abcdef/
set "URL="
set /p URL=Address: 
if not defined URL goto :end
goto :haveurl
:badurl
echo That is not an address of the form https://host/path/ (letters, digits and . / _ - only, ending in /).
echo To change the kept one, delete %INB%\source.txt
goto :end
:nolist
echo The list could not be downloaded from %URL%
echo Check the address (the admin app, Comandos, Mapas pedidos, Publicar areas, shows the current one; it changes after "Novo endereco") and your connection.
goto :end
:empty
echo The inbox is empty: no pending or approved area is published.
goto :end
:nodir
echo There is no mapeditor folder next to this file (%PKG%). Run it from the extracted package.
goto :end
:nocurl
echo curl.exe was not found. It is part of Windows 10 (1803) and later.
:end
pause
exit /b 1
