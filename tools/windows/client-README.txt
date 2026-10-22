Cinders of Chaos: Windows client
================================

The game client alone, for 64-bit Windows 10 or 11. Nothing is installed.

1. Extract the whole zip into a folder (a short path such as C:\CindersOfChaos-Client).
2. Double-click Chaos.exe and log in. The client connects to the server address the release was built for
   (BUILD_INFO.txt, "server host"; 127.0.0.1 means a server on this same PC, such as CindersOfChaos-Server-Windows.zip).
   Another server: open init.lua in Notepad and change host = "..." (and the two http://...:8090/clientservices
   addresses) to that server's name or IP.

Notes
  - If Windows SmartScreen warns about an unknown app: "More info", then "Run anyway".
  - chaos.pack holds the game data and sprites; keep it next to Chaos.exe, the client cannot start without it.
  - Settings, logs and crash reports are in %APPDATA% (the client's folder there).
  - BUILD_INFO.txt says which commits this client was built from and its client build number.
