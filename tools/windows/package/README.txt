Project Chaos - Windows test package
====================================

Runs the server and the client on your own computer.

1. Extract the whole zip into a folder (a short path such as C:\ProjectChaos).
2. Double-click start-server.bat. The first start creates the database (about a minute); then the game
   server window shows "Server Online". Leave both windows open.
   If Windows asks whether MariaDB and ChaosServer may use the network, "Private networks" is enough.
3. Double-click start-client.bat and log in:
     account chaos / password chaos   staff character "Chaos Admin" (god: /coins, /worldboss, admin panel)
     account test  / password test    Test Warrior, Test Ranger, Test Mystic, Test Thief (level 1, tutorial)
4. To stop: close the game server window, then run stop-server.bat.

Folders
  server\     the game server (ChaosServer.exe, config.lua, data\, the map)
  client\     the Chaos client (Chaos.exe; data\things\1098 holds the Chaos Tibia.dat and Tibia.spr)
  mariadb\    portable MariaDB (nothing is installed on Windows)
  database\   made at the first start: the game database. Delete it (with the server and database stopped)
              to start over with a fresh database and the test accounts above.

Notes
  - The database listens on 127.0.0.1:3307 only, user root without a password. This package is for playing
    locally; do not open it to the internet as it is (docs/LAUNCH.md describes a real server).
  - Problems of the first start are logged in database-setup.log. "Duplicate column name" and "znote_*"
    errors in the server window are expected (docs/LAUNCH.md, "Database").
  - The Visual C++ runtime is needed (most PCs have it). If ChaosServer.exe reports VCRUNTIME140.dll or
    MSVCP140.dll missing, install "Microsoft Visual C++ Redistributable x64" from microsoft.com.
  - BUILD_INFO.txt says which commits this package was built from.
