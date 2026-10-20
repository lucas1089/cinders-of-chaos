Cinders of Chaos: Linux server
==============================

The game server, ready to run on a 64-bit Linux PC or server: Ubuntu 22.04 or newer, Debian 12 or newer (built on
Ubuntu 22.04). Nothing is installed on the system and no root rights are needed. It brings its own database.

Needs: about 6 GB of free memory (the world map is large), 2 GB of disk, ports 7171 and 7172 (TCP) for players.

1. Extract the archive into a folder you own (tar -xzf CindersOfChaos-Server-Linux.tar.gz) and go into it.
2. ./start-server.sh
   The first start creates the database (about a minute) and prints the staff account it made (also in
   first-start-account.txt). Wait for "Server Online". Ctrl+C stops the game server (it saves) and the database.
   ./start-server.sh -d runs it in the background (log: logs/server.log); ./stop-server.sh stops it: it writes
   server/stop.request (the game server checks for it every few seconds, tells the players, saves and exits) and
   sends SIGTERM only when the game server has not taken the file after 20 seconds.
3. Log in with the Cinders of Chaos client (CindersOfChaos-Client-Linux.tar.gz or CindersOfChaos-Client-Windows.zip
   of the same release). More accounts: ./add-account.sh ACCOUNT PASSWORD "Character Name" [warrior|ranger|mystic|thief] [male|female]
   (a level 8 character in the temple of Cinderhold, as the website makes one; its kit comes at its first login)
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

Login encryption
  The base key.pem is the public default RSA key: anyone on the path can read logins made with it. Make our own
  (it stays on this machine; never copy it anywhere else):
    python3 -I server/tools/rsa_key.py gen --out "$HOME/chaos-rsa/login-$(date +%Y%m%d).pem"
  It prints the public modulus: put it into the GitHub secret CHAOS_RSA_PUBLIC and build a new release. Then set
  CHAOS_RSA_KEY_FILE=<that path>,key.pem in chaos.env (both keys while old clients are out; later only the new one)
  and restart. The console prints each key's fingerprint; the client build log prints the same one.
  Failed logins: 20 wrong passwords from one IP or 50 on one account in 10 minutes block it for 15 minutes.

Security
  harden_vps.sh (run as root on a dedicated server: firewall, fail2ban, automatic security updates, SSH keys only,
  file permission checks): sudo ./harden_vps.sh --admin-user YOURUSER --dry-run first. docs/SECURITY_CHECKLIST.md
  in the repository lists every step.

Running it
  The daily server save (08:00, data/globalevents/globalevents.xml) saves and shuts the game server down;
  start-server.sh starts it again after 5 seconds, and after a crash (5 crashes in a row: it gives up; each one is in
  crashes/crashes.log). Logs: logs/ (server.log in the background, mariadb.err, database-setup.log).
  The database listens on 127.0.0.1:3307 only; its admin account is your system user, over the socket named in
  run/socket.txt. Back it up (while it runs) with:
    mariadb/bin/mariadb-dump --no-defaults --socket="$(cat run/socket.txt)" -u "$(id -un)" chaos > chaos.sql
  Start over: stop everything and delete database/ and chaos.env (all characters are lost).

Login screen services
  start-server.sh also runs server/tools/clientservices.py on 127.0.0.1:8090 (needs python3; log
  logs/clientservices.log; CHAOS_CLIENTSERVICES=0 in chaos.env turns it off). It serves the boosted creature / boss
  and the event schedule of the client's login screen from server/data/chaos_clientservices.json, which the game
  server rewrites. Port 8090 stays closed to the internet: the website's web server forwards one path to it, so the
  client asks over HTTPS. This needs the web server on this machine (the service listens on 127.0.0.1 only; for a
  website elsewhere use the systemd unit of docs/LAUNCH.md with its own address and firewall).
  Apache (sudo a2enmod proxy proxy_http), in the site's HTTPS virtual host:
    ProxyPass        "/clientservices" "http://127.0.0.1:8090/clientservices"
    ProxyPassReverse "/clientservices" "http://127.0.0.1:8090/clientservices"
  nginx: location = /clientservices { proxy_pass http://127.0.0.1:8090/clientservices; }
  Check: curl -s -X POST -d '{"type":"boostedcreature"}' https://example.org/clientservices
  The client release built with the workflow input site_url (https://example.org) asks
  https://example.org/clientservices. Without the service the client hides that bar.

Help channel assistant
  Ember answers players' questions in the Help channel ("?question", "Ember, question", or a line that ends in "?")
  from the game's own wiki data, through the model API (paid per use; a monthly budget stops it). Off until you
  give it a key. To turn it on, in this folder:
    python3 -m venv helpai-venv && helpai-venv/bin/pip install anthropic
    add CHAOS_ANTHROPIC_API_KEY=<your key> to chaos.env (keep chaos.env mode 600), then ./stop-server.sh and
    ./start-server.sh -d. "Help channel assistant on" is printed; its log is logs/helpai.log (no names, no
    question texts unless you switch that on). The key is given to the assistant only, never to the game server.
  Off again: CHAOS_HELPAI=0 in chaos.env (or remove the key) and restart. Budget and limits:
  server/tools/helpai_config.json; CHAOS_HELPAI_MONTHLY_USD in chaos.env overrides the budget. Details:
  server/README.md "Help channel assistant" in the repository.

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
