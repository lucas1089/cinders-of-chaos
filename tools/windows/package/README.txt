Cinders of Chaos - Windows test package
=======================================

Runs the server and the client on your own computer.

1. Extract the whole zip into a folder (a short path such as C:\CindersOfChaos).
2. Double-click start-server.bat. The first start creates the database (about a minute); then the game
   server window shows "Server Online". Leave both windows open.
   If Windows asks whether MariaDB and ChaosServer may use the network, "Private networks" is enough.
3. Double-click start-client.bat and log in:
     account chaos / password chaos   staff character "Chaos Admin" (god: /coins, /worldboss, admin panel)
     account test  / password test    Test Warrior, Test Ranger, Test Mystic, Test Thief (level 1: class kit, Cinderhold temple)
4. To stop: run stop-server.bat (do not close the game server window: Windows ends a closed console after about
   5 seconds, before the save is done). It writes server\stop.request; the game server checks for it every few
   seconds, tells the players, saves and exits. stop-server.bat waits up to 200 seconds for that before it stops
   the database; if the game server is still running then, it leaves the database running (run it again later).
   If the game server crashes, start-server.bat starts it again after 5 seconds (each crash is written to
   crashes\crashes.log); after 5 crashes in a row it stops trying and leaves the window open.

Map editor
  The map editor is not in this zip: its licence lets copies be passed on only unmodified, with its own licence
  text, so you download it once from its source (docs/CREDITS.md, entry under Tools; the game's Credits window shows
  the same link). It is free. You need a GitHub account to download from the Actions page.
    1. Open the source's "Actions" tab, "Build Windows", the newest run with a green check.
    2. Download the x64 artifact (its name ends in "Windows-x64-Release"; a zip inside a zip: extract both).
    3. Copy what is inside (the program, its DLLs and its data folder) into the mapeditor folder of this package, next
       to the client folder that is already there (the folder must hold that one program and no other
       .exe). If Windows asks about merging the data folder, say yes.
    4. Double-click open-map-editor.bat. It opens the editor on the server's map, with the 10.98 client files
       (mapeditor\client: the Chaos Tibia.dat and Tibia.spr) and the server folder (server\: items.otb and items.xml
       with every Chaos item, the map in server\data\world) already chosen. The Chaos monsters are in the creature
       list (mapeditor\data\user\data\1098\creatures.xml).
  If the editor opens empty or asks for folders (Client + Server Workspace), choose mapeditor\client as the client
  folder and the server folder of this package as the server folder, then open the .otbm in server\data\world.
  The server's map is that .otbm (the only one there). Stop the game server before saving over it, keep a copy of the
  old file, and restart the server to load the change. docs/MAP_GUIDE.md in the repository has the building rules
  (sizes, borders, detail) for new areas.
  To keep a change for good (next packages and the live server): send the saved .otbm to the team. It becomes the
  map master (docs/MAP_GUIDE.md "Editing the live map"). Start each edit from the newest package. Monster spawns
  and houses placed in the editor are not kept.

Folders
  server\     the game server (ChaosServer.exe, config.lua, data\, the map)
  client\     the Cinders of Chaos client (Chaos.exe and chaos.pack, which holds the game data and sprites)
  mapeditor\  where the map editor goes (see above), with the client files and the creature list it reads
  mariadb\    portable MariaDB (nothing is installed on Windows)
  database\   made at the first start: the game database. Delete it (with the server and database stopped)
              to start over with a fresh database and the test accounts above.

Notes
  - The database listens on 127.0.0.1:3307 only, user root without a password. This package is for playing
    locally; do not open it to the internet as it is (docs/LAUNCH.md describes a real server).
  - Problems of the first start are logged in database-setup.log. The server window shows no SQL error at
    the first start; one there is worth a report (docs/LAUNCH.md, "Database").
  - The Visual C++ runtime is needed (most PCs have it). If ChaosServer.exe reports VCRUNTIME140.dll or
    MSVCP140.dll missing, install "Microsoft Visual C++ Redistributable x64" from microsoft.com.
  - BUILD_INFO.txt says which commits this package was built from.
  - The same release also has the client and the server as separate downloads, for Windows and for Linux
    (CindersOfChaos-Client-Windows.zip, CindersOfChaos-Server-Windows.zip, CindersOfChaos-Client-Linux.tar.gz,
    CindersOfChaos-Server-Linux.tar.gz; the release notes say what each one holds).
