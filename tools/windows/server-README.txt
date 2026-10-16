Cinders of Chaos: Windows server
================================

The game server alone, for 64-bit Windows 10 or 11, with its own database. Nothing is installed.
Needs about 6 GB of free memory (the world map is large).

1. Extract the whole zip into a folder (a short path such as C:\CindersOfChaos-Server).
2. Double-click start-server.bat. The first start creates the database (about a minute); then the game server window
   shows "Server Online". Leave both windows open.
   If Windows asks whether MariaDB and ChaosServer may use the network, allow it for the networks your players use.
3. Log in with the Cinders of Chaos client (CindersOfChaos-Client-Windows.zip or CindersOfChaos-Client-Linux.tar.gz of
   the same release):
     account chaos / password chaos   staff character "Chaos Admin" (god)
     account test  / password test    Test Warrior, Test Ranger, Test Mystic, Test Thief (level 1, tutorial)
4. To stop: run stop-server.bat (do not close the game server window: Windows ends a closed console after about
   5 seconds, before the save is done). It writes server\stop.request; the game server checks for it every few
   seconds, tells the players, saves and exits. stop-server.bat waits up to 200 seconds for that before it stops
   the database; if the game server is still running then, it leaves the database running (run it again later).
   If the game server crashes, start-server.bat starts it again after 5 seconds (each crash is written to
   crashes\crashes.log); after 5 crashes in a row it stops trying and leaves the window open.

Other players
  Players connect to the address in server\config.lua (ip = "..."); BUILD_INFO.txt shows the one this zip was built
  with. For players on other PCs set it to this PC's LAN or public address, allow TCP 7171 and 7172 in the Windows
  firewall (and forward them on the router for the internet), and restart the server.
  The test accounts above have known passwords. Before anyone else can connect, change them (with the server running):
    mariadb\bin\mariadb.exe -uroot --port=3307 chaos -e "UPDATE accounts SET password = SHA1('a new password') WHERE name IN ('chaos', 'test')"
  This package is meant for a small group. A public server belongs on Linux: CindersOfChaos-Server-Linux.tar.gz of the
  same release, and docs/LAUNCH.md in the repository.

Folders
  server\     the game server (ChaosServer.exe, config.lua, data\, the map)
  mariadb\    portable MariaDB (listens on 127.0.0.1:3307 only, user root without a password)
  database\   made at the first start: the game database. Delete it (with the server and database stopped)
              to start over with a fresh database and the test accounts above.

Notes
  - Problems of the first start are logged in database-setup.log. The server window shows no SQL error at
    the first start; one there is worth a report (docs/LAUNCH.md, "Database").
  - The Visual C++ runtime is needed (most PCs have it). If ChaosServer.exe reports VCRUNTIME140.dll or
    MSVCP140.dll missing, install "Microsoft Visual C++ Redistributable x64" from microsoft.com.
  - BUILD_INFO.txt says which commits this package was built from.
