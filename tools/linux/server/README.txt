Cinders of Chaos: Linux server
==============================

The game server, ready to run on a 64-bit Linux PC or server: Ubuntu 22.04 or newer, Debian 12 or newer (built on
Ubuntu 22.04). Nothing is installed on the system and no root rights are needed. It brings its own database.

Needs: about 6 GB of free memory (the world map is large), 2 GB of disk, ports 7171 and 7172 (TCP) for players.

1. Extract the archive into a folder you own (tar -xzf CindersOfChaos-Server-Linux.tar.gz) and go into it.
2. ./start-server.sh
   The first start creates the database (about a minute) and prints the staff account it made (also in
   first-start-account.txt). Wait for "Server Online". Ctrl+C stops the game server (it saves) and the database.
   ./start-server.sh -d runs it in the background (log: logs/server.log); ./stop-server.sh stops it.
3. Log in with the Cinders of Chaos client (CindersOfChaos-Client-Linux.tar.gz or CindersOfChaos-Client-Windows.zip
   of the same release). More accounts: ./add-account.sh ACCOUNT PASSWORD "Character Name" [warrior|ranger|mystic|thief]
   For local tests only: CHAOS_TEST_ACCOUNTS=1 ./start-server.sh at the first start adds the accounts chaos/chaos
   (staff) and test/test (one character per class), with known passwords.

Address
  Players connect to the address in server/config.lua (ip = "..."). The release sets it from the workflow input
  server_host (127.0.0.1: only this machine can play). For other players set it to this machine's public DNS name or
  IP, open TCP 7171 and 7172 in the firewall and restart. The clients of the release connect to the same address.

Client guard
  chaos.env (written at the first start, mode 600) holds the database password and CHAOS_CLIENT_KEY. Empty, the
  guard is off and any 10.98 client can log in. Put the 64 hex digits the release's clients were built with (the
  GitHub secret CHAOS_CLIENT_KEY) there and restart: then only the official client can log in.

Running it
  The daily server save (08:00, data/globalevents/globalevents.xml) saves and shuts the game server down;
  start-server.sh starts it again after 5 seconds, and after a crash (5 crashes in a row: it gives up; each one is in
  crashes/crashes.log). Logs: logs/ (server.log in the background, mariadb.err, database-setup.log).
  The database listens on 127.0.0.1:3307 only; its admin account is your system user, over the socket named in
  run/socket.txt. Back it up (while it runs) with:
    mariadb/bin/mariadb-dump --no-defaults --socket="$(cat run/socket.txt)" -u "$(id -un)" chaos > chaos.sql
  Start over: stop everything and delete database/ and chaos.env (all characters are lost).

Production
  For a public server run by systemd (its own user, the system's MariaDB, backups, monitoring, gateways) follow
  docs/LAUNCH.md in the Cinders of Chaos repository. deploy/ holds the systemd units and chaos.env.example it uses;
  server/ is the server folder it calls /opt/chaos/server (the engine is server/tfs, its libraries server/lib/).

Folders
  server/      the game server (tfs, lib/, config.lua, data/, the map, sql-setup/)
  mariadb/     portable MariaDB (official Linux build)
  database/    made at the first start: the game database
  deploy/      systemd unit examples (docs/LAUNCH.md)
  BUILD_INFO.txt says which commits this package was built from.

Problems
  "error while loading shared libraries": the system is older than Ubuntu 22.04 / Debian 12, or lacks a base library
  (sudo apt install libssl3 zlib1g libbz2-1.0 liblzma5 libzstd1). The first start shows no SQL error; one there is
  worth a report (docs/LAUNCH.md, "Database").
