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
  The map editor is in this zip (mapeditor\): a free program under the GNU AGPL-3.0, with its source zip in
  mapeditor\source and its licence in mapeditor\LICENSE (docs/CREDITS.md, entry under Tools; the game's Credits window
  names it too). Nothing to download. It is our own build: the editor's code with our speed patches for this big map,
  and the source zip is that patched source (our patches in its cinders-patches folder). mapeditor\CHANGES.txt says
  which build it is (the upstream commit and our patches, or the plain upstream release when ours was not ready) and
  what the package set up.
    1. Double-click open-map-editor.bat. It copies the server's items.otb and items.xml (every Chaos item) to the
       editor, sets the editor's 10.98 client folder to mapeditor\client (the Chaos Tibia.dat, Tibia.spr, items.otb
       and Tibia.otfi, which tells the editor the .spr has transparency; keep it there), puts the server's map first
       in the editor's "Recent maps" and starts the editor.
    2. On the start window, check that the client is 10.98 and click the map under "Recent maps" (the .otbm in
       server\data\world). The editor cannot open a map from the command line; if the map is not in the list, use
       File > Open: the bat put the map's path on the clipboard (Ctrl+V in the file window).
  Every monster and NPC of the server is in the creature list (mapeditor\data\1098\creatures.xml), so their spawns show
  who stands there. NPCs the server places at start (the Gambler, the Loot Buyer, the market stalls) are not in the map
  file and do not show in the editor.
  If the start window asks for the client folder of 10.98 (the first start, or the bat could not preset it): choose
  mapeditor\client of this package. Once is enough; the editor keeps it.
  The editor checks for a newer version on its start window. Its "Download & install" does not work in this package
  on purpose (the updater is left out, mapeditor\CHANGES.txt): a newer editor comes with a newer package.
  Our area generator in the editor (Tools > Lua Scripts, mapeditor\cinders\README.txt):
    - New area: mode "Custom Lua script", script mapeditor\cinders\generate_area.lua (already chosen by the bat). Set
      biome, width, height, floors, seed and level band at the top of that file (Notepad), set the Destination X / Y /
      floor in the editor window, Generate, look at the log, Apply. Undo (Ctrl+Z) takes it out again.
    - One of our area plans: script mapeditor\cinders\paint_plan.lua with plan = "<id>" at its top (the list:
      mapeditor\cinders\plans\index.txt). The log names the Destination that puts it where the server has it.
    The editor's scripts cannot place creatures, action ids, teleport targets or protection zones: the log and the
    files next to the scripts list them (generated_spawns.txt, plans\<id>-notes.txt).
  Areas asked for in chat (the map inbox, docs/MAP_GUIDE.md "Map inbox"): the owner publishes them in the admin app
  (Comandos > Mapas pedidos > Publicar areas), which shows an address (the url= line). Double-click fetch-areas.bat, paste
  that address once (it is kept in mapeditor\inbox\source.txt), and it downloads the areas into mapeditor\inbox\<id>\
  (every file checked against its sha256), lists them and opens the one you pick in the map editor (first in "Recent
  maps"). It needs curl.exe and certutil (Windows 10 and later). The area is a separate small map, not the server's: look
  at it, say in the chat what to change or "approve"; do not save it over the server's map.
  The server's map is the .otbm in server\data\world (the only one there). Stop the game server before saving over it,
  keep a copy of the old file, and restart the server to load the change. docs/MAP_GUIDE.md in the repository has the
  building rules (sizes, borders, detail) for new areas.
  To keep a change for good (next packages and the live server): send the saved .otbm to the team. It becomes the
  map master (docs/MAP_GUIDE.md "Editing the live map"). Start each edit from the newest package. Monster spawns
  and houses placed in the editor are not kept.

Folders
  server\     the game server (ChaosServer.exe, config.lua, data\, the map)
  client\     the Cinders of Chaos client (Chaos.exe and chaos.pack, which holds the game data and sprites)
  mapeditor\  the map editor (see above) with its source zip, the client files, the creature list and our
              scripts (cinders\)
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
