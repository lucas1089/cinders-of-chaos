# Launch checklist: from the stock downloads to a public Cinders of Chaos server

This is the order to follow on launch day, and the list of what must be checked before the doors open. Everything
here was run on the test server, except where a step says otherwise (the systemd units and the Windows client
workflow could not be run in the build environment).

After launch, every update goes through "Updating the live server" at the end.

What you need:
- the base server download (TFS 1.4 based, protocol 10.98): its `config.lua`, `data/`, `key.pem`, `SQL_Server/` and
  the engine sources;
- the base client sources (`client/BASE.md`) and the 10.98 `Tibia.dat` / `Tibia.spr` pair with the Chaos sprites
  (`server/data/monster/CUSTOM_MONSTERS.md`);
- a Linux machine (the test server runs Ubuntu 24.04), MariaDB 10.x, Python 3.7+ and the `mysql` client;
- a checkout of this repository, for example in `/opt/chaos/repo`.

To play it first without any of this: run the **Windows package** workflow (Actions -> Windows package -> Run
workflow). Its prerelease `winpkg-<run number>` (Releases; the run's Summary links each file; the newest 3 are kept) has
five ready-to-use downloads, listed in the release notes:
- `CindersOfChaos-Windows.zip`: the whole game for one Windows PC. The patched engine (`ChaosServer.exe`), the client,
  the merged dat/spr, a portable MariaDB, the map editor and `start-server.bat` / `start-client.bat`
  (`tools/windows/package/README.txt`). Test accounts with known passwords: local play only.
- `CindersOfChaos-Client-Windows.zip` and `CindersOfChaos-Client-Linux.tar.gz`: the client alone (`Chaos.exe`, or
  `run-client.sh` with its libraries in `lib/`), pointed at the workflow input `server_host` (default 127.0.0.1;
  `client/tools/set_server_host.py`). Both are built with the secret `CHAOS_CLIENT_KEY` and the input `client_build`,
  and both get the updater inputs. The optional input `site_url` (the website, `https://example.org`; empty by default)
  writes `Services.account = "<site_url>/chaos_client_api.php"` (the character select's looks and "Create character";
  empty keeps both off) and points the login-screen services at `<site_url>/clientservices`, which the site's web
  server forwards to `clientservices.py` (below and `tools/linux/server/README.txt`). It must be `https://` (`http://`
  only for 127.0.0.1 / localhost).
- `CindersOfChaos-Server-Windows.zip`: the Windows server alone (engine, portable MariaDB, the start / stop .bat files,
  the test accounts; `tools/windows/server-README.txt`), `ip = server_host`.
- `CindersOfChaos-Server-Linux.tar.gz`: the engine built on Ubuntu 22.04 (runs on Ubuntu 22.04+ and Debian 12+), its
  libraries in `server/lib/`, the production `config.lua` of `prod_config.py` (`ip = server_host`), a portable MariaDB
  and `start-server.sh` / `stop-server.sh` / `add-account.sh` (`tools/linux/server/README.txt`). The first start makes
  the database, a database user with a random password (`chaos.env`) and a staff account with a random password. No
  test accounts. The client guard is on once `chaos.env` has `CHAOS_CLIENT_KEY`. Good for a small server; a public one
  follows this checklist (its `deploy/` folder holds the systemd units used below).
The inputs live on the private branch `windows-assets` (its README.md). `tools/windows/prepare_server.sh` turns the
base server into the server folder that all three servers share; the map master of `world/` (the owner's edited map,
server/README.md "Map master") replaces the base map first when the branch has one. `tools/linux/package_server.sh` and
`tools/linux/package_client.sh` put the Linux downloads together.

## 1. Engine

1. Build the engine from the base sources with every engine patch of `server/src-patches/` applied, in number order,
   in the source root: `for p in server/src-patches/*.patch; do patch -p1 < "$p"; done`. The folder holds the whole
   numbered chain (`NNNN-<name>.patch`, from 0001 up); each patch says at its top what it changes, and
   `server/README.md` has a section for each. Patches build on the context of the earlier ones, so apply all of them,
   in order, and never skip one; a hunk that fails means the base sources are not the ones the chain was made
   against. Some patches add source files that `src/CMakeLists.txt` lists, so re-run CMake, then do a full build
   (several change `Game`, `Item`, `Player` and `ProtocolGame`). The Windows binary in the download has none of them
   (no "CRIT!" visual, no off-hand sword for the Ninja, no client guard, no item lock, crit / leech chances fire less
   often than the rescaled values say, and more).
2. Put the binary into the server folder as `/opt/chaos/server/tfs` (the path the service file uses).

## 2. Database

1. `CREATE DATABASE chaos;` and a user with rights on that database only, for example
   `GRANT ALL PRIVILEGES ON chaos.* TO 'chaos'@'localhost' IDENTIFIED BY '<a long random password>';`.
   MariaDB listens on 127.0.0.1 only (`bind-address = 127.0.0.1`); port 3306 is never opened to the internet.
2. Load the base schema: `SQL_Server/schema.sql` and the other `SQL_Server/schema_*.sql` / `sql_*.sql` files of the
   download. Do not load `SQL_ONLY_for_existing_server-*.sql` into a fresh database.
3. The Chaos tables come with step 4 (`install_all.py`, step `sql`).
4. **Hosting requirement: the database files on a local NVMe or SSD** (owner decision 2026-10-12). Not a network
   volume, not a disk shared with other busy machines. Keep MariaDB's default `innodb_flush_log_at_trx_commit = 1`
   (every COMMIT is on disk; do not set 2). Why: the engine saves on the game loop. Each autosave step and each
   logout ends with a COMMIT, and the COMMIT waits for the disk's flush (fsync) before the game goes on. On a slow
   shared disk the full-map load test measured autosave ticks of 0.3-0.8 s (the whole game frozen that long); on a
   calm disk the same COMMITs took 12-55 ms (server/README.md "Load test on the full map"). Check the disk before
   launch, in a folder on the database's disk:
   `fio --name=fsync --rw=write --bs=4k --size=64m --fsync=1 --filename=/var/lib/mysql-fio.tmp; rm /var/lib/mysql-fio.tmp`.
   The fsync latencies it prints should be a few ms or less; tens of ms means a shared or network disk. After launch
   `chaos_health.py` warns when COMMITs get slow (section 9; needs the slow task log).

The first start on a fresh database prints no SQL error: `install_all.py` step `migrations` makes the engine's own
migrations skip the columns the schema already has, and step `sql` (`server/sql/chaos_website_tables.sql`) creates the
six website tables the base scripts use (`znote_*`, empty; the website's installer keeps them and fills them). Check a
set of SQL files before a launch: `python3 -I server/tools/fresh_db_check.py <server> --sql SQL_Server/schema.sql
--sql ...` (server/README.md "Base server start warnings").

## 3. Production config

```
sudo install -d -m 0755 /etc/chaos
sudo cp server/deploy/chaos.env.example /etc/chaos/chaos.env      # fill in CHAOS_DB_* and CHAOS_CLIENT_KEY (never commit it)
sudo chmod 600 /etc/chaos/chaos.env
python3 -I server/tools/prod_config.py /opt/chaos/server --public-host play.example.org --name "Cinders of Chaos" \
    --motd "Welcome to Cinders of Chaos." --max-players 400 --pvp pvp --save-time 06:00 --owner "..." --url "https://..." \
    [--client-url https://.../download] [--client-builds 4,5] [--client-manifest /path/updates/live/manifest.json] \
    [--proxy-trusted GW1,GW2,GW3 --proxy-required yes]
```
(`--ip` is the old name of `--public-host` and still works.)

For the beta run the same command with `--max-players 300` (owner decision 2026-10-12: 300 for the beta, 400 at launch;
docs/BETA.md section 2). Run it again with `--max-players 400` (or without the option) before the launch.

`server/tools/prod_config.py` (idempotent; its docstring explains every value) sets:

| Setting | Value | Why |
|---|---|---|
| `ip` | the public DNS name (`--public-host`) | the login server hands it to the client as text and the client resolves it, so a DNS change needs no restart. Behind gateways it is the gateways' name, never the real server's IP (section "Gateways and DDoS"); 127.0.0.1 only works on the machine itself |
| `loginProtocolPort` / `gameProtocolPort` / `statusProtocolPort` | 7171 / 7172 / 7171 | the stock ports (the test servers use 74xx) |
| `serverName`, `motd`, `ownerName`, `ownerEmail`, `url`, `location` | ours | the download ships its own name and someone else's contact data. `install_all.py` (step `servername`) already turns the base `serverName` into "Cinders of Chaos"; `--name` overrides it, and a later install never touches a name that is not the base value |
| `maxPlayers` | 400 at launch (the default), 300 for the beta (`--max-players 300`; owner decision 2026-10-12) | from the full-map load test (section 9): the game loop's one thread fills up at 500-600 bots on the 4-core test machine, and real players cost more than bots. Raise to 500 after a launch week whose peak kept the lag low; 0 means unlimited |
| `worldType` | `pvp` (or `no-pvp`, `pvp-enforced`) | the arena and the guild siege never use real deaths, so they work in every type |
| `allowClones`, `onePlayerOnlinePerAccount` | false, false | the multi-client rules live in `multiclient.lua` (2 characters per IP; the second cannot attack players or enter dungeons) |
| `serverSaveShutdown` | **true** (kept) | the daily save shuts the engine down; systemd starts it again (section 5), so each day starts with a fresh process |
| Server Save time | `--save-time 06:00` | `data/globalevents/globalevents.xml`; the download uses 08:00. Keep the backup timer 15 minutes after it |
| `mysqlHost` ... `mysqlDatabase` | `os.getenv("CHAOS_DB_*") or ...` | the engine runs `config.lua` as Lua, so the credentials come from `/etc/chaos/chaos.env`; no password in any file of the repo or the server folder |
| `startupDatabaseOptimization`, `showScriptsLogInConsole` | false | faster start, quieter console |
| `passwordType`, `passwordHashIterations` | `"pbkdf2-sha256"`, 120000 | salted PBKDF2 account passwords (engine patch 0014, `server/README.md` "Account passwords"); the iterations are the engine's, `passwordType` only names the scheme |
| `armorPercent`, `armorPercentConstant`, `armorPercentMax` | true, 250, 80 | percent armour for players (engine patch 0016, `server/README.md` "Percent armour"); `armorPercent = false` goes back to the stock flat formula |
| `energyShieldRechargeDelay`, `energyShieldOpcode` | 2000, 224 | the energy shield's recharge delay in ms and its client opcode (engine patch 0015, `server/README.md` "Energy shield") |
| `clientGuardMode`, `clientGuardKey`, `clientGuardAllowDevKey`, `clientGuardTimeout`, `clientGuardDownloadUrl`, `clientGuardBuilds`, `clientGuardManifest`, `clientGuardStaffIps` | `"enforce"`, `os.getenv("CHAOS_CLIENT_KEY") or ""`, false, 10, the options | only the official client plays (engine patch 0021, `server/README.md` "Client guard"): the key is the GitHub secret `CHAOS_CLIENT_KEY` the Windows client is built with, in `/etc/chaos/chaos.env`; without it every player is kicked (the console says so at start). `clientGuardMode = "log"` for a log-only first week or an emergency |
| `minPlayerSpeed`, `maxPlayerSpeed`, `playerSpeedBonus`, `playerSpeedPerTenLevels`, `playerSpeedSoftLevel`, `playerSpeedPerTenLevelsAbove` | 120, 2600, 50, 25, 300, 10 | movement speed (engine patch 0018, `server/README.md` "Movement speed"): walk speed held between about 1 and 10 tiles/s on normal ground; base speed = vocation + 50, 2.5 per level up to 300, 1 per level after. The client needs base patch 0029 (same step times) |
| `proxyProtocolTrusted`, `proxyProtocolRequired` | the gateways' IPs, true (or `""`, false without gateways) | the gateways in front of the server (engine patch 0025, section "Gateways and DDoS"): a connection from a listed gateway must start with a PROXY header and the engine takes the player's real IP from it; `true` refuses every other address except 127.0.0.0/8. Not given: the value already in `config.lua` stays |
| `rsaKeyFile` | `os.getenv("CHAOS_RSA_KEY_FILE") or "key.pem"` | the login's RSA key (engine patch 0046, `server/README.md` "Login encryption (RSA, XTEA)"): our own key made on this machine with `server/tools/rsa_key.py gen`, its path in `/etc/chaos/chaos.env`; the client is built with its public modulus (secret `CHAOS_RSA_PUBLIC`). Without it the base `key.pem`, the public default key (the console warns) |
| `loginFailMaxPerIp`, `loginFailMaxPerAccount`, `loginFailWindow`, `loginFailBlock` | not written: 20, 50, 600, 900 | failed-login limits of the game logins (engine patch 0047, `server/README.md` "Failed-login limits") |
| `slowTaskLogMs` | 0 (not set: off), or e.g. 100 while hunting lag; 200 or less for the slow COMMIT warning of section 9 | the slow task log (engine patch 0027, `server/README.md` "Slow task log"): every game loop task that took this many ms or more is one console line with the Lua script and line, the database queries and the collector's sweep that took the time. On, it costs about 1 us per Lua call (well under 1% of the game loop at 200 online) |
| `loginPrefetch` | true (not set: true) | the login scripts' reads run on the login worker's own connection before the login (engine patch 0031, `server/README.md` "Login reads off the game loop"); answered from those rows only when the text is the same and no write reached a table they read since. `false` reads everything on the game loop as before. Read at startup |
| `rateSpawn` | 3 | how many monsters one spawn brings back per check (stock 1: a pack of five took five spawntimes to refill). The timers themselves are in the spawn file (install step `spawns`); engine patch 0022 lets `respawn.lua` shorten them where several players hunt together (`server/README.md` "Spawn density and respawn"). Without patch 0022 the console prints one `[ChaosRespawn]` line and the stock timers apply |

The tool refuses to run while `mapName` is a cropped test map (`zcrop_*`): set the real map name first.
Rates stay as the download has them: `rateExp` is not used (experience stages, written by `late_game.py`),
`rateSkill = 3`, `rateMagic = 2`, `rateLoot = 1`. `maxPacketsPerSecond` (50) is the engine's flood limit per connection.

Also check by hand:
- `freePremium` (false in the download): premium gates items, outfits and the autoloot list size. Spells and runes
  are free for everyone (`patch_free_spells.py`, server/README.md "Free spells").
- Passwords: `passwordType = "pbkdf2-sha256"`. The engine needs patch 0014 (`server/src-patches/0014-salted-password-hashes.patch`)
  and the website its password patch (`website/install_site.sh` applies it); both write
  `pbkdf2-sha256$<iterations>$<salt>$<key>` into `accounts.password` (`server/sql/chaos_passwords.sql` widens the column
  to VARCHAR(255)). Old unsalted SHA-1 passwords still log in and are re-hashed at that login. Keep the website's
  `CHAOS_PASSWORD_ITERATIONS` equal to `passwordHashIterations` (both 120000 by default).
- `client`: the client's `init.lua` points at 127.0.0.1 (client/base-patches/0001-init.patch). Build the release client
  with the Windows workflow's `server_host` input (section 8) or edit `host`, `status` and `clientServicesLink` there.
- `ChaosTopBar.COMMUNITY_URL` (`client/overlay/modules/client_chaos_topbar/chaos_topbar.lua`): the Discord link.

## 4. Install the Chaos content

```
python3 -I server/tools/install_all.py /opt/chaos/server --dry-run      # what would change, on a temporary copy
python3 -I server/tools/install_all.py /opt/chaos/server                # CHAOS_DB_* from the environment or config.lua
python3 -I server/tools/install_all.py /opt/chaos/server                # a second run must report 0 files changed
```

The order (server/README.md "Install" and each system's section), every step idempotent:

1. `files`: `data/scripts/chaos`, `data/lib/chaos_*.lua`, the Chaos monsters (XML and Lua), `data/spells/chaos`,
   `data/patchnotes`
2. `lib`: `lib.lua` loads `chaos_unique_items.lua`
3. `vocations`: `add_vocations.py` (the classes; `class_migration.lua` moves old characters at the next start)
4. `events`: `patch_base_events.py` (experience, loot, siege, login demotion), `patch_season_events.py`
5. `weapons`: `two_handed.py`
6. `lategame`: `late_game.py` (experience stages in `config.lua`, late game spawns in the map's spawn file)
7. `crafting`: `install_crafting.py`
8. `monsters`: `register_monsters.py` for every folder under `monsters/chaos` (world bosses, goblin, ...)
   then `spawns`: `patch_base_spawns.py` (dead monster registrations, glitched spawntimes, the 300-600 band's respawn,
   spawns added in thin areas; `server/README.md` "Spawn density and respawn")
9. `spells`: `register_spells.py`, then the class hook (every `server/tools/install_class_*.py`), then
   `rename_spells.py --sql`
10. `autoloot`: the stock XML `!autoloot` talkaction is commented out (the Auto Loot window talks to autoloot.lua over its opcode)
11. `sql`: `server/sql/chaos.sql`, every other `server/sql/*.sql`, and the `player_spells` renames

Tested end to end on a clean copy of the base data: the first run changed 494 files and created 29 tables, the second
run changed nothing, and the server started with no Lua error (only the fresh-database messages of section 2).

The engine patch, the client and the website are not part of `install_all.py`.

## 5. Running it (systemd)

```
sudo useradd --system --home /opt/chaos --shell /usr/sbin/nologin chaos
sudo chown -R chaos:chaos /opt/chaos/server
sudo install -d -m 0755 /var/log/chaos
sudo cp server/deploy/chaos-server.service server/deploy/chaos-clientservices.service \
        server/deploy/chaos-backup.service server/deploy/chaos-backup.timer \
        server/deploy/chaos-watchdog.service server/deploy/chaos-watchdog.timer \
        server/deploy/chaos-health.service server/deploy/chaos-health.timer /etc/systemd/system/
sudo cp server/deploy/chaos.logrotate /etc/logrotate.d/chaos
sudo systemctl daemon-reload
sudo systemctl enable --now chaos-server chaos-clientservices chaos-backup.timer chaos-watchdog.timer \
        chaos-health.timer
```

- `chaos-server.service`: `Restart=always` brings the engine back after the daily save (which shuts it down on
  purpose) and after a crash. `systemctl stop` sends SIGTERM: the engine saves and shuts down (180 s allowed).
  `systemctl kill -s SIGUSR1 chaos-server` saves without stopping. The console goes to `/var/log/chaos/server.log`.
- **Crashes and hangs.** A crash (any stop that is not clean) is restarted 5 s later by `Restart=always`, without a
  retry limit (`StartLimitIntervalSec=0`). Before that `server/tools/chaos_crashlog.sh` (`ExecStopPost`) keeps the
  last 200 console lines in `/var/log/chaos/crashes/crash-<time>.log` (newest 50 kept) and, when
  `CHAOS_ALERT_WEBHOOK` is set in `/etc/chaos/chaos.env` (a webhook that takes `{"content": ...}`, such as a Discord
  channel webhook), posts an alert. A clean stop (the daily server save, `systemctl stop`) records nothing. A hang,
  where the process lives but the game loop is stuck, is caught by `chaos-watchdog.timer`: once a minute
  `server/tools/chaos_watchdog.py` asks the status protocol (port 7171) for its info document, which the engine
  answers from the game's dispatcher; after 3 misses in a row it restarts `chaos-server` and notes it in
  `/var/log/chaos/crashes/watchdog.log`. The first 5 minutes after a start are skipped (map load). Check:
  `systemctl list-timers chaos-watchdog.timer`, `journalctl -u chaos-watchdog`.
- `chaos-clientservices.service`: the login-screen endpoint (`server/tools/clientservices.py`, port 8090) that serves
  `data/chaos_clientservices.json`, which the game server rewrites every 5 minutes.
  A client built with `site_url` asks `https://<site>/clientservices`: forward that path to it in the site's web server
  (Apache `ProxyPass "/clientservices" "http://127.0.0.1:8090/clientservices"` with `proxy` and `proxy_http`; nginx
  `location = /clientservices { proxy_pass http://127.0.0.1:8090/clientservices; }`) and keep 8090 closed. The Linux
  server package starts it on 127.0.0.1 itself (`start-server.sh`). Without it the client hides the login screen's bar.
- `chaos-helpai.service` (optional, not in the `enable` line above): Ember, the Help channel assistant
  (`server/tools/helpai.py`, server/README.md "Help channel assistant"). It answers players' questions in the Help
  channel through the model API, paid per use with a monthly budget (`server/tools/helpai_config.json`). The key goes in
  its own file, never in `/etc/chaos/chaos.env` (the game server reads that one):
  ```
  sudo install -m 600 -o root -g root /dev/null /etc/chaos/helpai.env
  echo 'CHAOS_ANTHROPIC_API_KEY=<your key>' | sudo tee /etc/chaos/helpai.env >/dev/null
  sudo python3 -m venv /opt/chaos/helpai-venv && sudo /opt/chaos/helpai-venv/bin/pip install anthropic
  sudo cp server/deploy/chaos-helpai.service /etc/systemd/system/
  sudo systemctl daemon-reload && sudo systemctl enable --now chaos-helpai
  ```
  Log: `/var/log/chaos/helpai.log` (rotated by `chaos.logrotate`). Without a key it exits at once and
  the Help channel works as before; off again: `sudo systemctl disable --now chaos-helpai`.
- `chaos.logrotate`: daily, 14 days, compressed, `copytruncate` (systemd keeps the files open). Also the client guard's
  `data/logs/clientguard.log` (IPs, accounts), as the privacy policy says (docs/legal/).
- `chaos-health.timer`: every 5 minutes `server/tools/chaos_health.py` checks the services, ports, status protocol,
  database, disk, backups and new log errors, and posts to `CHAOS_ALERT_WEBHOOK` when something fails or recovers,
  plus a daily summary at 09:00 (section 9).

Firewall (ufw example):

| Port | What | Open to |
|---|---|---|
| 7171/tcp | login server and status protocol | everyone |
| 7172/tcp | game server | everyone |
| 8090/tcp | login-screen services (HTTP) | everyone (or put it behind a reverse proxy on 443 and change the client URLs) |
| 22/tcp | SSH | your addresses only |
| 3306/tcp | MariaDB | nobody (localhost only) |

```
sudo ufw default deny incoming && sudo ufw allow 22/tcp && sudo ufw allow 7171/tcp && sudo ufw allow 7172/tcp \
  && sudo ufw allow 8090/tcp && sudo ufw enable
```

Behind gateways (section "Gateways and DDoS") 7171, 7172 and 8090 are open to the gateways only:
`server/deploy/firewall/setup_backend_firewall.sh` adds that on top of this table.

## 6. Accounts, staff and the website

- **Characters are created on the website** (the base server has no in-game account manager). The website must:
  - offer only the base classes: Warrior 4, Ranger 3, Mystic 1, Thief 11; the ascended classes come from the Ascendant Oracle;
    the retired ids 2, 6 and 9 never;
  - offer the **locked classes** (Necromancer 20, Monk 17, Templar 23; ids in `docs/CLASSES.md`) only to accounts that
    have a row in `chaos_class_unlocks` for that class (`class_key` necromancer / monk / templar). The server enforces
    the lock anyway at login (`class_unlocks.lua`: the character is restricted or logged out), so a website that gets
    this wrong produces unplayable characters, not a bypass;
  - create level 1 characters with `lastlogin = 0` and no starting items: the server gives the class kit and runs
    the tutorial island at the first login (`newplayer*.lua`);
  - hash passwords with salted PBKDF2-SHA256 in the engine's format (`passwordType`, section 3; the website in
    `website/` does), and never show or log them.
  The website in `website/` (ROADMAP #28, done; install: "Website" below) has a Chaos plugin that reads
  `chaos_class_unlocks`; check its character creation against this list before launch.
- **Staff**: group 4 (gamemaster) to 6 (god) on `players.group_id`, account type 5 for gods. The admin panel (opcode 120)
  needs group 4+, some categories and actions 5 or 6. Staff characters are left out of every leaderboard
  (`staffGroup = 4`). Use a separate staff account. Commands that create economy value need group 5 or higher
  (`Chaos.economyMinGroup` in `chaos_constants.lua`, checked by `Chaos.staffCommand`): `/coins`, `/charm give` and
  `/pact` (all but `info`); so do the admin panel's Economy and Store categories and its Give item / Create item, and
  every command that hands out value (`/rift key`, `/ascended sigil`, `/classunlock`, `/cosmetic`, `/pet give`, the
  `/newplayerkit` kit and the others in docs/GM_HANDBOOK.md section 2). `/worldboss`, `/siege`, `/towerrun` and the
  looking and testing parts of the others are open to every group with access (4+);
  `/goblin`, `/blessing`, `/season start|end`, `/seasonpass` and `/journey` need a god account (type 5). Every staff
  use of a guarded command goes to the admin audit log. Who may do what, and the rules for staff:
  [docs/GM_HANDBOOK.md](GM_HANDBOOK.md) (decided 2026-10-12).
- Start from a **fresh database**, or from the beta database after its wipe (docs/BETA.md "Wipe procedure"); never from
  a test database: those have accounts with known passwords (`test`, `test2`, ...).

## 7. Backups

`server/tools/backup.sh` (tested against the test database: dump, data archive, retention, restore):
- asks the engine to save (`--save-service chaos-server`: SIGUSR1, then 15 s). With engine src-patch 0026 SIGUSR1 is
  the autosave in steps (server/README.md "Autosave in steps"): a few players per tick, no freeze, so the backups at
  12:15 and 18:15 no longer stop the game. The pass takes about 3.5 s at 200 online and 7-8 s at 400, inside the 15 s; a
  dump that starts earlier still holds every character as of its last save (one transaction per character),
- the hourly autosave and this one write only the houses that changed; a shutdown, `/closeserver` and `/save` still
  save everything in one go (the daily 06:00 save: the players are kicked and saved one by one anyway),
- `mysqldump --single-transaction` of the game database, gzip, `DIR/db/chaos-db-<db>-<timestamp>.sql.gz`, checked with
  `gzip -t` and mysqldump's "Dump completed" line,
- `config.lua` + `data/` (without the map and logs) as `DIR/data/chaos-data-<timestamp>.tar.gz`, only when it changed,
- removes files older than `CHAOS_BACKUP_KEEP_DAYS` (14), always keeping the newest dump.

`chaos-backup.timer` runs it at 00:15, 06:15 (15 minutes after the daily save), 12:15 and 18:15. Cron instead:
`15 0,6,12,18 * * * root set -a; . /etc/chaos/chaos.env; /opt/chaos/repo/server/tools/backup.sh --save-service chaos-server >> /var/log/chaos/backup.log 2>&1`
Read the result in `/var/log/chaos/backup.log`; `systemctl status chaos-backup` shows the last run's exit status.

### Off-site copy

A backup on the same disk does not survive the disk. `chaos-backup.service` runs `server/tools/backup_offsite.sh`
right after `backup.sh`. It sends the newest dump and the newest data archive, each file once (`DIR/.offsite_sent`),
encrypted when a key is set, then deletes `chaos-*` files older than `CHAOS_BACKUP_REMOTE_KEEP` days (30) on the
target. Success writes `DIR/.offsite_last`; the health check alerts when that is older than 26 h. With no target set
it logs one line ("not configured") and exits 0. Encryption writes a temporary copy in `DIR` first, so `DIR` needs free
space for one more dump. Settings: `server/deploy/chaos.env.example`.

Owner setup, once, as root:
1. **A target.** Either or both:
   - rclone (S3, Backblaze B2, Google Drive, any rclone backend): `sudo apt install rclone`, then
     `sudo rclone config --config /etc/chaos/rclone.conf` (make a remote, e.g. `b2`), `sudo chmod 600 /etc/chaos/rclone.conf`,
     and set `CHAOS_BACKUP_REMOTE=b2:chaos-backups` (remote name, colon, bucket or folder). Use a bucket key that can
     write and delete in that bucket only. Check: `sudo rclone --config /etc/chaos/rclone.conf lsf b2:chaos-backups`.
   - a machine you control over ssh: `sudo ssh-keygen -t ed25519 -f /etc/chaos/backup_ssh -N ''`, put
     `/etc/chaos/backup_ssh.pub` in the target user's `~/.ssh/authorized_keys`, create the folder there, accept the
     host key once (`sudo ssh -i /etc/chaos/backup_ssh backup@host true`), then set
     `CHAOS_BACKUP_RSYNC=backup@host:/srv/chaos-backups` and `CHAOS_BACKUP_SSH_KEY=/etc/chaos/backup_ssh`. The target
     needs rsync (or set `CHAOS_BACKUP_RSYNC_TOOL=scp`) and `find` for the retention.
2. **A key** (the dump holds password hashes and emails: encrypt anything that leaves your own machines):
   - age (simplest): on your own computer, not the server, `age-keygen -o chaos-backup.key`; store that file in your
     password manager; set `CHAOS_BACKUP_AGE_RECIPIENT=age1...` (the public key it printed). `sudo apt install age`.
   - or gpg: `gpg --export --armor KEYID > pub.asc` on your computer, then on the server
     `sudo install -d -m 700 /etc/chaos/gnupg && sudo gpg --homedir /etc/chaos/gnupg --import pub.asc`, and set
     `CHAOS_BACKUP_GPG_RECIPIENT=KEYID`.
   - or a passphrase: `sudo sh -c 'openssl rand -base64 32 > /etc/chaos/backup.pass' && sudo chmod 600 /etc/chaos/backup.pass`,
     `CHAOS_BACKUP_PASSPHRASE_FILE=/etc/chaos/backup.pass`. Copy the passphrase to your password manager too: a lost
     server loses this file with it.
3. Test: `sudo sh -c 'set -a; . /etc/chaos/chaos.env; /opt/chaos/repo/server/tools/backup_offsite.sh --dry-run'`, then
   `sudo systemctl start chaos-backup` and read `/var/log/chaos/backup.log` (lines `offsite: ...`).

### Restore

A full rollback with exact commands is in "Incident runbook" below. In short:
```
sudo systemctl stop chaos-server                      # saves, then stops
set -a; . /etc/chaos/chaos.env; set +a
sudo mysql -e "DROP DATABASE $CHAOS_DB_NAME; CREATE DATABASE $CHAOS_DB_NAME"      # as a user that may do this
zcat /var/backups/chaos/db/chaos-db-<db>-<timestamp>.sql.gz | sudo mysql "$CHAOS_DB_NAME"
# only if the server folder is lost or damaged (the map .otbm is not in the archive: copy it from the download):
sudo tar -C /opt/chaos/server -xzf /var/backups/chaos/data/chaos-data-<timestamp>.tar.gz
sudo systemctl start chaos-server
```
An off-site copy first comes back and is decrypted:
```
sudo rclone --config /etc/chaos/rclone.conf copy b2:chaos-backups/chaos-db-<db>-<timestamp>.sql.gz.age /tmp/  # or scp
age -d -i chaos-backup.key -o chaos-db.sql.gz /tmp/chaos-db-<db>-<timestamp>.sql.gz.age      # age
gpg -o chaos-db.sql.gz -d /tmp/chaos-db-<db>-<timestamp>.sql.gz.gpg                          # gpg (key or passphrase)
```

### Restore drill

Before launch and then once a month, restore the newest dump into a scratch database, from the off-site copy (that also
proves the key works):
```
sudo mysql -e "CREATE DATABASE chaos_drill"
zcat chaos-db.sql.gz | sudo mysql chaos_drill
sudo mysql -e "SELECT COUNT(*) FROM chaos_drill.accounts; SELECT COUNT(*) FROM chaos_drill.players;
               SELECT MAX(lastlogin) FROM chaos_drill.players"       # counts close to live, last login recent
sudo mysql -e "DROP DATABASE chaos_drill"
```
Write down the date and how long it took; that time is the rollback time.

## 8. Client

- Linux: `client/LINUX.md`. Windows: the manual workflow **Windows client** (`.github/workflows/windows-client.yml`,
  Actions -> Windows client -> Run workflow). It fetches the base client sources (input `base_repo` / variable
  `CHAOS_BASE_CLIENT_REPO`, pinned with `base_ref` / `CHAOS_BASE_CLIENT_REF` to the commit the patches were made
  against), applies `client/base-patches/*` and the overlay with `client/tools/assemble_client.sh`, builds with MSVC +
  vcpkg (x64-windows-static) and uploads `Chaos.exe` and a runnable folder. Set `server_host` to the public host.
- Keys of a release client (docs/SECURITY_CHECKLIST.md): the secret `CHAOS_CLIENT_KEY` (client guard) and the secret
  or variable `CHAOS_RSA_PUBLIC` (the game server's login key, `server/tools/rsa_key.py public`).
  `windows-package.yml` fails without them unless its input `allow_dev_key` is ticked (a test build only).
  It only runs when started by hand, never on pushes or pull requests.
- Ship the client with the merged 10.98 `Tibia.dat` / `Tibia.spr` in `data/things/1098/`.
- Client updates after launch: the signed updater (section "Client updates" below). Turn it on in the package
  (`windows-package.yml` inputs `update_manifest` and `update_public_key`) before the first public download.
- Character select and Create character (client/MANIFEST.md "Character select"): set the website's account API URL
  in the client's `init.lua` (`Services.account`, base patch 0050) before packing:
  `python3 -I client/tools/set_account_api.py <client> https://<site>/chaos_client_api.php`, or for a release the
  workflow input `site_url` (`client/tools/set_server_host.py --site-url`, section 1). Empty (the default) keeps
  the character select working with the login server's looks only (no wings, aura or shader) and the Create character
  button off; characters are then made on the website. The site must serve it over HTTPS (section "Website").

## 9. Monitoring

**Alerts** (`chaos-health.timer`, every 5 minutes, `server/tools/chaos_health.py`). Every message goes to
`CHAOS_ALERT_WEBHOOK` (the crash alerts use the same hook), prefixed `Cinders of Chaos health (<host>):`. A check posts
only when it changes state: `FAIL <check>: <detail>` when it starts failing, `OK <check>: <detail>` when it recovers;
nothing while a state holds, so a FAIL without a later OK means it is still broken. Set the webhook (a Discord channel
webhook, or anything that takes `{"content": "..."}`) in `/etc/chaos/chaos.env`, then
`sudo sh -c 'set -a; . /etc/chaos/chaos.env; python3 -I /opt/chaos/repo/server/tools/chaos_health.py --test-alert'`.

| Check | Fails when | First look |
|---|---|---|
| `service chaos-server`, `mariadb`, `chaos-clientservices`, `chaos-payworker`, `nginx`, `php*-fpm` | the unit is not `active` (nginx and PHP-FPM only when installed; the list: `CHAOS_HEALTH_UNITS`) | `systemctl status <unit>`, `journalctl -u <unit> -n 50` |
| `login port` / `game port` | 7171 / 7172 refuse a TCP connection | the engine log; the firewall |
| `status protocol` | no status document on 7171 (the watchdog restarts a hang after 3 minutes) | `/var/log/chaos/crashes/watchdog.log` |
| `database` | `SELECT 1` with the `CHAOS_DB_*` credentials fails (the detail has the client's error) | `systemctl status mariadb`, runbook "DB down" |
| `disk /`, `disk /var/backups/chaos` | less than 10 % or 5 GB free (`CHAOS_HEALTH_MIN_FREE_PCT`, `_GB`) | runbook "Disk full" |
| `local backup` | the newest dump is older than 26 h, or there is none | `/var/log/chaos/backup.log` |
| `off-site backup` | `.offsite_last` older than 26 h (only when a target is set) | the `offsite:` lines in `backup.log` |
| `WARN slow database COMMITs` | 3 or more COMMITs of 200 ms or more within an hour in the slow task log (`slowTaskLogMs` 200 or less in `config.lua`; `CHAOS_HEALTH_SLOW_COMMIT_MS`); a warning, at most once per 6 h, and a count in the daily summary | the database disk (section 2 step 4): `iostat -x 5`, other jobs writing to it, the host's disk type |

The game checks (chaos-server, both ports, status) alert after 2 failed runs in a row and are skipped in the first
5 minutes after a start, so the daily restart is silent. Crashes alert on their own (`chaos_crashlog.sh`).

**Error lines.** New lines in `/var/log/chaos/server.log` that match `Lua Script Error`, `stack traceback`, `[Error`,
`attempt to index/call/...` or a segfault are counted each run and posted as `N error line(s) in the server log` with
the first 5 lines, at most once per 30 minutes (more errors in between wait and go out together). The first run starts at
the end of the log. A burst right after an update is a bug in that update; the same line every 30 minutes is a loop to
fix or a script to roll back.

**Daily summary**, with the first run after 09:00 server time (`CHAOS_HEALTH_SUMMARY_HOUR`): the online peak of the last
24 h (from the status replies, every 5 minutes) and the number online now, the dumps written in 24 h and the age of the
newest local and off-site copy, crashes (`/var/log/chaos/crashes/crash-*.log`) and watchdog restarts, the count of error
lines, free disk, and what is failing now. A day without a summary means the timer or the webhook is broken:
`systemctl list-timers chaos-health.timer`, `journalctl -u chaos-health -n 30`. A post that fails is kept and sent
again by the next run.

By hand: `sudo sh -c 'set -a; . /etc/chaos/chaos.env; python3 -I /opt/chaos/repo/server/tools/chaos_health.py --dry-run'`
prints every check and what it would post (`--summary-now` adds the summary). State: `/var/lib/chaos/health.json`
(delete it to start fresh; the next run posts only what fails).

Other manual checks:
- `systemctl status chaos-server chaos-clientservices`, `systemctl list-timers 'chaos-*'`.
- After every restart and update: `grep -c "Lua Script Error" /var/log/chaos/server.log`. The known base server noise
  on the full map is listed in the first-start log; keep a copy of it to compare against.
- Players online: the status protocol on 7171, e.g.
  `python3 -c "import socket;s=socket.create_connection(('127.0.0.1',7171));s.send(b'\x06\x00\xff\xffinfo');print(s.recv(4096))"`
  (XML with `<players online=...>`), or `data/chaos_clientservices.json` (`cacheinfo`).
- Load: `server/tools/loadtest.py` (bots over the real protocol) with the TEST ONLY probe `server/tools/loadtest_probe.lua`.
  Measured on the test server (cropped map, so no monsters; the real map adds spawn and monster AI work): 30 bots walking
  every second and talking every 20 s took 4.5 % of one core (p95 7.9 %), the engine stayed at 192 MB RSS, and the
  game loop lag stayed at the idle level (about 53 ms on a 50 ms timer; max 122 ms); 30 bots walking 4 steps per
  second and talking every 3 s: 7.0 % (max 11 %). Logins took 0.5 s (p95 1.2 s).
  **On the full map** (server/README.md "Load test on the full map"; engine 0001-0032, every install step, a fresh
  database, 4 vCPU Xeon 2.1 GHz shared with other jobs): bots spread over the towns and hunting areas, walking, talking
  and fighting (`setup --spread`, `run --hunt` with the TEST ONLY `server/tools/loadtest_hunt.lua`). The game loop was
  busy 11% at 100, 19% at 200, 39-79% at 300 (6 runs), 83% at 400-499 and 96-99% from 500 up; the timer lag stayed
  51-75 ms on average up to 499 and went to 150-200 ms (maxima 0.6-1.5 s) above 500. RSS 4.6-4.7 GB (the map is
  4.55 GB), 0.6-1.3 KB/s per player to the clients, the database at 5 connections and 5-40 queries a second. A rush of
  300 first logins 0.2 s apart into the fresh database: login p50 0.33 s, p90 0.58 s, 300 of 300. The limit is the
  game loop's one thread; slow COMMITs (an autosave tick of 0.3-0.8 s) came from a shared disk. Engine patch 0032 came
  out of it (a quarter of the game loop was spent clearing 90 KB network buffers). `maxPlayers`: 300 for the beta, 400
  at launch (section 3), on a VPS with a fast core (3 GHz or more), 16 GB RAM and a local NVMe disk for MariaDB.

## 10. Security review (launch)

What was read: every `db.query` / `db.storeQuery` / `db.asyncQuery` / `Chaos.select` of `data/scripts/chaos` (157
call sites), every extended-opcode handler, every talkaction, and the item paths of stash, bank, loot filter (click to
loot), autoloot, crafting, store, auto seller, store pouches, daily reward, tower milestones, bounty and rifts.

| Area | Finding | Result |
|---|---|---|
| SQL, all modules | strings from players (names, titles, keys, reasons) go through `db.escapeString`; numbers are engine ids (guid, account id) or pass `Chaos.toInt` / `%d` | safe |
| Admin panel (opcode 120) | admin check on every message, group per action, typed and bounded parameters, 150 ms throttle, audit log | safe |
| Stash (opcode 110) | **a floor item of a house could be stashed, i.e. taken, from outside the house through the wall** (`Item:remove` skips the engine's house rule); not movable map items were accepted | **fixed** (`stash.lua`, test `server/tests/security_test.lua`) |
| Stash, dungeons, crafting, store | list / history / state requests read the database or walk the backpack on every packet | **fixed**: per-player rate limits (`ratelimit.lua`) |
| Dungeons (opcode 109) | **queueing in a fight teleported the player out of it** (no protection-zone rule by design) | **fixed**: refused while in a fight or protection-zone locked, checked again on every queue tick (test) |
| Bank (opcode 60) | amounts `Chaos.toInt` 1..2e9; balance checked before every change; stars charged only for what was handed over | safe; rate limited: one request per action every 150 ms (`bank.lua`, `ratelimit.lua`) |
| Loot filter click to loot (238) | the kill record belongs to the requester, corpse owner / party, reach, item signature; a split stack goes back or is lost, never doubled | safe |
| Crafting (232) | backpack path validated, orb counted before and removed after the roll, 250 ms between orbs | safe |
| Store (218) | offer by index with title + cost echo, owned check, coins taken with a guarded UPDATE, refund on a failed delivery | safe while only the game spends coins (a website must only add coins) |
| Passive tree, Paragon, respec, build codes (65) | saves and imports validated (known nodes, connected, point cap; Paragon keys, caps, no take-back) | safe |
| Daily, tower milestones, bounty | server-side state decides; rewards all or nothing | safe |
| Party invites (151) | accept only with a pending invitation | safe |
| Leaderboard (229) | the class ladder counts the players ahead on every request | safe; rate limited: one `get` every 150 ms (`leaderboard.lua`) |
| Staff talkactions | every `/` command checks the group's access flag (`/goblin`: gods, admin panel and `/testkit`: group 4+); `/coins`, `/charm give`, `/pact` (all but `info`) and every command that hands out value need group 5 (`Chaos.staffCommand`, `Chaos.economyMinGroup`), every use in the admin audit log | safe (`tests/staff_permissions_test.lua`) |
| `clientservices.py` | no socket timeout (an idle connection held a thread); a negative `Content-Length` blocked a thread | **fixed** |
| Test servers' `zz_test_lua.lua` | `/lua` runs any Lua for any player | never ship (section 11) |
| Login encryption (review 2026-10-16) | **the server and client used the public default RSA key** (anyone on the path reads every account and password), and **the client's XTEA session key came from the current second** (a recorded session could be decrypted) | **fixed**: our own key (engine patch 0046, `rsa_key.py`, `CHAOS_RSA_PUBLIC`), random XTEA keys (client base patch 0072); owner steps in docs/SECURITY_CHECKLIST.md |
| Game logins (review 2026-10-16) | no limit on wrong passwords at 7171 / 7172 (the stock throttle stops only 6 connections in 500 ms) | **fixed**: failed-login limits per IP and account (engine patch 0047) |
| Release workflow (review 2026-10-16) | a release without the `CHAOS_CLIENT_KEY` secret only warned, so the published beta client had the public development key (client guard effectively off) | **fixed**: the run fails without the secrets unless `allow_dev_key` is ticked; release notes name the keys |

Settled since the review:
- **Rifts at the daily save.** `rift.lua` ends every open run at a clean shutdown or a closed server (the daily save,
  SIGTERM, `/closeserver`, the admin panel's shutdown) before the players are kicked (`ChaosRift.interrupt`; server/README.md
  "Rifts", Restart and crash refund; `tests/rift_refund_test.lua`). Everyone goes to the temple and is saved there.
  - Guardian alive: the key's owner, if still in the run, gets the same key back once (an omen arena its Omen Key).
  - Guardian dead (chest up): no key; the unclaimed chest shares of the players online are handed out as at a normal
    exit.
  - Loot: what a player picked up during the run stays theirs (the character is saved at the temple). Corpses and
    items still lying in the rift are lost with the instance. Chest shares of finishers who were offline at that
    moment are lost too (they live only in memory).
  - A crash (no event) refunds the key at the next login through the run marker.
  - So a run opened just before the save keeps what it picked up and gets the key back. Owner decides: accept that
    (recommended: a key is one run of at most 10 minutes, and the save time is public), or add a rule that refuses
    to open a rift in the last 10 minutes before the save (not built).
- **`/coins`** needs group 5 or higher (`Chaos.economyMinGroup`), like `/charm give` and `/pact`; gamemasters (group 4)
  cannot mint Chaos Coins.

## 11. Never ship (test only)

Check the server folder before the first start (`ls data/scripts data/scripts/talkactions data/monster/monsters`):
- `ztest/` in the server root and every `data/scripts/zz_*` / `data/scripts/talkactions/zz_*` file of the test servers,
  above all **`zz_test_lua.lua`: `/lua <code>` runs any Lua for any player, no access check at all**;
  `zz_balance_harness.lua`, `zz_ztest_arena_startup.lua`, a copy of `server/tools/loadtest_probe.lua` or
  `server/tools/loadtest_hunt.lua`;
- `data/monster/monsters/ztest_chaos_dummy.xml` (and its line in `monsters.xml`);
- the cropped test map: `mapName = "zcrop_..."` (`prod_config.py` refuses it) and its `.otbm`;
- test switches, all off by default; never set them on the live server: the global storage
  `Chaos.arenaConfig.testNoPzStorage` (7100345, the arena queue without a protection zone),
  `Chaos.multiClient.offStorage` (7100990, multi-client blocks off), `/leaderboard shift <days>` (moves the leaderboard
  clock; `shift 0` puts it back);
- `admin/testkit.lua` (`/testkit`: gear kits for admins, a balance-test tool): remove it from the live server, or keep it
  only if staff giving themselves gear is accepted;
- the load-test bots: `server/tools/loadtest.py cleanup` removes the `loadbot*` accounts.
- the **mock donation provider**: `CHAOS_PAY_PIX_PROVIDER=mock` / `CHAOS_PAY_PAYPAL_PROVIDER=mock` in
  `/etc/chaos/payments.env` approve every donation by themselves after a few seconds (free Chaos Coins). Live values:
  `mercadopago` / `paypal` (or `off`); see "Donations" below.
- the **beta switch**: `server/data/scripts/chaos/beta_config.lua` `enabled = true` gives every account 5,000 free
  Chaos Coins at its first new character (server/README.md "Beta starter coins"). Set `enabled = false` on the launch
  server before the first start; check with `grep -n "enabled" data/scripts/chaos/beta_config.lua`. The beta coins, the
  purchases made with them and the grant rows (`chaos_shop_coins`, `chaos_shop_purchases`, `chaos_shop_history`,
  `chaos_beta_grants`) are wiped with the beta (docs/BETA.md section 9; only the beta coins: the snippet in docs/BETA.md
  section 4).

## 12. Open loose ends that matter for launch (ROADMAP.md)

Still open:
- **The beta weekends.** The plan, the wipe before launch and the test focus per weekend: [docs/BETA.md](BETA.md)
  (draft, every decision marked "Owner decides"). Most of the open items below are on its test list.
- Not run with a real group yet: rifts, Omens and the Ascended bosses with a full party, the Ashen Sepulchre raid, the
  Ember Descent with 2-4 players, the battleground at 5v5 and up, party credit for bounties and the bestiary.
- Keystones: verified in game 2026-10-12 (Ricochet, Deadeye, Bulwark, both Illusionist keystones in a party; Overgrowth
  and Thorns belonged to no class then, now the Iron Sage's and the Sentinel's, computed, not measured). Weapon numbers re-measured. The Bone Lord with Covenant of the Grave and the Ninja
  with Blackblood Creed broke the Deadeye's single-target lead: fixed 2026-10-12, computed (ROADMAP "Open
  decisions"). Open: measure the fix on the dummies.
- The class lines: the Necromancer, Monk and Templar are tested in game (phase B) and stay behind the store's class
  unlock: free at account level 200, not sold (docs/PRICES.md). C2 / C3 polish and the C4 outfits and
  effects are still in progress (ROADMAP).
- The community (Discord) link is empty (`ChaosTopBar.COMMUNITY_URL`, the website's Discord invite).
- Staff rules, bans and mutes: [docs/GM_HANDBOOK.md](GM_HANDBOOK.md) (decided 2026-10-12; the ladder is on the Rules page).
- Legal texts: [docs/legal/](legal/README.md) (drafts: placeholders to fill, a lawyer's review, then the installer again).
  Built 2026-10-12: the daily purge of moderation records (`moderation_purge_config.lua` `days` must equal the Privacy
  Policy's `[PRAZO DOS REGISTROS DE MODERAÇÃO]`), the acceptance of the current texts by existing accounts (website
  accept page at the next login, an in-game notice with the link), chargeback fraud in the penalty ladder (Rules 7.9).
  Run `website/install_site.sh` after the texts change: it writes the texts' version for the in-game notice.

Done or decided since the first version of this list (ROADMAP "Open decisions and loose ends"):
- The base client's healing helper no longer replays missed cycles or floods casts (client base patch 0026).
- Two different rarity elements no longer zero the damage (`patch_base_events.py` step 9, `rarity_elements.lua`).
- `/testkit` refills health again (`Chaos.heal`), and the toasts have their background.
- Seasons, login streaks, patch notes and name plates are done (ROADMAP #12, #20, #23, #25).
- World-boss timers: decided, both run (the base server's weekly island bosses and the Chaos arena event; server/README.md
  "World bosses" says how to remove the base one).

## 13. Launch day, in order

1. Fresh database, base schema (section 2).
2. Engine built with the patches (section 1); server folder in `/opt/chaos/server` with the real map.
3. `prod_config.py`, `/etc/chaos/chaos.env` (section 3).
4. `install_all.py --dry-run`, then for real, then once more (0 changes) (section 4).
5. Remove every test-only file and turn the beta switch off (`beta_config.lua` `enabled = false`; section 11). Also
   remove the beta coin top-up cron, if the beta used one (`rm /etc/cron.d/chaos-beta-coins`; docs/BETA.md section 4):
   left in place it refills every account's coins every minute after the wipe.
6. systemd units, logrotate, firewall (section 5); start; read the log: no `Lua Script Error`.
7. Create the staff account and characters; log in with the release client; check the login screen (boosted creature,
   events, players online), a store purchase, a crafting orb, the bank, the stash.
8. Website: character creation with the class lock (section 6). Donations: the sandbox test of "Donations" below, then
   the live credentials.
9. Backups: run `chaos-backup.service` once, check the off-site copy, do the restore drill (section 7).
   Alerts: `chaos_health.py --test-alert`, then `--dry-run` shows every check `ok` (section 9).
10. `maxPlayers` 400 (section 3; load test on the full map in section 9); `loadtest.py cleanup` if bots were run.
11. Open the firewall ports, announce.
12. From then on, every update: "Updating the live server" below (`server/deploy/chaos_update.sh`).

## Incident runbook

First: read the alert, then `systemctl status chaos-server mariadb` and `tail -n 100 /var/log/chaos/server.log`. Tell
the players early (Discord, the website) and post when it is fixed. Every command below runs as root on the server
with the settings loaded: `sudo -i`, then `set -a; . /etc/chaos/chaos.env; set +a`.

**Server down** (`FAIL service chaos-server`, the ports, the status protocol):
1. `systemctl status chaos-server`. `activating (auto-restart)` means it is crashing: see "Crash loop".
2. `inactive` or `failed` with no crash: someone stopped it. `systemctl start chaos-server`, then
   `tail -f /var/log/chaos/server.log` until the map is loaded (a few minutes).
3. Running but the ports fail: `ss -ltnp | grep -E ':717[12]'` (is the engine listening?), `ufw status` (is it open?),
   then test from outside: `nc -vz <public ip> 7172`. Nothing local is wrong: see "DDoS".
4. Running, ports open, no status answer: a hang. The watchdog restarts it within 3 minutes
   (`/var/log/chaos/crashes/watchdog.log`); if not, `systemctl restart chaos-server`.

**Crash loop** (several crash alerts in a few minutes):
1. `ls -t /var/log/chaos/crashes/ | head` and read the newest `crash-*.log`: the last lines before the stop show the
   script or the action. `coredumpctl list tfs` when core dumps are kept (`LimitCORE=infinity`).
2. It started after an update: roll the update back with `chaos_update.sh --rollback --now` ("Updating the live
   server", "Rollback"). By hand: `git -C /opt/chaos/repo checkout <last good commit>`, run `install_all.py` again, or
   restore the data archive of section 7, then `systemctl restart chaos-server`.
3. It started with no update: a player action or a bad row. Close the server to players while you look:
   `ufw insert 1 deny 7172/tcp` (the login still answers), fix, `ufw delete deny 7172/tcp`.
4. To stop the loop while you work: `systemctl stop chaos-server` (it stays down until you start it).

**DB down** (`FAIL database`, `FAIL service mariadb`):
1. `systemctl status mariadb`, `journalctl -u mariadb -n 100`. Start it: `systemctl start mariadb`.
2. It does not start: `df -h /var/lib/mysql` (a full disk is the usual cause: see "Disk full"), then the error log
   (`/var/log/mysql/error.log` or the journal). InnoDB corruption: do not delete files; restore (rollback below).
3. Up but `Access denied`: the `CHAOS_DB_*` credentials do not match the user in MariaDB. Check
   `mysql -u "$CHAOS_DB_USER" -p"$CHAOS_DB_PASS" "$CHAOS_DB_NAME" -e 'SELECT 1'`.
4. When the database is back, restart the game server so it reconnects: `systemctl restart chaos-server`.

**Disk full** (`FAIL disk ...`):
1. `df -h`, then the biggest: `du -xh --max-depth=2 /var | sort -h | tail -20`.
2. Usual causes: `/var/log/chaos/server.log` growing from an error loop (fix the loop; `logrotate -f /etc/logrotate.d/chaos`),
   old dumps (`ls -lh /var/backups/chaos/db`; lower `CHAOS_BACKUP_KEEP_DAYS` once the off-site copy works; never delete
   the newest), core dumps (`coredumpctl list`; `journalctl --vacuum-size=500M`), MariaDB binary logs
   (`mysql -e "PURGE BINARY LOGS BEFORE NOW() - INTERVAL 2 DAY"` when binary logging is on).
3. A full disk can stop saves: once there is space, `systemctl kill -s SIGUSR1 chaos-server` (save now) and read the log.

**Rollback to the last backup** (data loss up to the dump time; announce it first):
```
systemctl stop chaos-health.timer chaos-backup.timer          # no alerts or new dumps while you work
ufw insert 1 deny 7171/tcp && ufw insert 1 deny 7172/tcp      # nobody logs in (before the allow rules)
systemctl stop chaos-server                                   # saves, then stops
ls -lt /var/backups/chaos/db | head                           # pick the dump (newest before the incident)
DUMP=/var/backups/chaos/db/chaos-db-$CHAOS_DB_NAME-YYYYmmdd-HHMMSS.sql.gz
gzip -t "$DUMP" && zcat "$DUMP" | tail -n 1                   # must end with "Dump completed"
/opt/chaos/repo/server/tools/backup.sh --no-data             # keep the broken state too, for the investigation
mysql -e "DROP DATABASE \`$CHAOS_DB_NAME\`; CREATE DATABASE \`$CHAOS_DB_NAME\`"
zcat "$DUMP" | mysql "$CHAOS_DB_NAME"
mysql "$CHAOS_DB_NAME" -e "SELECT COUNT(*) FROM players; SELECT MAX(lastlogin) FROM players"
# only if the server folder is damaged (the map .otbm is not in the archive):
# tar -C /opt/chaos/server -xzf /var/backups/chaos/data/chaos-data-YYYYmmdd-HHMMSS.tar.gz && chown -R chaos:chaos /opt/chaos/server
systemctl start chaos-server && tail -f /var/log/chaos/server.log    # wait for the map, log in with a staff character
ufw delete deny 7171/tcp && ufw delete deny 7172/tcp
systemctl start chaos-health.timer chaos-backup.timer
```
The safety dump taken before the drop is the newest file in `db/` now: the rollback dump is the second newest. Donations
paid after the dump time are not in the restored database: compare the provider's list with `chaos_coin_orders` and
credit them again (admin panel, Store > Donations).

**Suspected exploit or dupe** (gold or items appearing, a report):
1. Do not restart or roll back yet: the evidence is in the database and the log.
2. Find who: admin panel (opcode 120) `Player info`, `Account lookup`, `Active sessions` (same IP on many accounts);
   richest players: `mysql "$CHAOS_DB_NAME" -e "SELECT name, level, balance FROM players ORDER BY balance DESC LIMIT 20"`.
3. Market: every listing, sale, cancel, expiry, delivery and refusal is a row in `chaos_market_log` (`action`:
   list, buy, cancel, expire, deliver, fill, order, ordercancel, orderexpire, recover, error):
   `SELECT FROM_UNIXTIME(at), action, offer_id, player_id, other_id, item_id, count, name, currency, amount, text FROM chaos_market_log WHERE player_id = <id> OR other_id = <id> ORDER BY id DESC LIMIT 200`.
   A dupe shows as two `deliver` rows for one `offer_id`, or `recover` / `error` rows around the time. The console
   has the same events as `[Chaos market]` lines: `grep '\[Chaos market\]' /var/log/chaos/server.log`.
4. Orb exchange: `chaos_orbx_log` (`action`: place, take, fill, merge, cancel, expire, deliver, recover, error), the
   same query with `order_id`; console lines `[Chaos orb exchange]`.
5. Staff: every admin panel action and staff talkaction is logged by `ChaosAdmin.log` to `chaos_admin_log` and as
   `[ChaosAdmin]` console lines: the `Admin log viewer` in the panel, or
   `SELECT FROM_UNIXTIME(created_at), player_name, action, target, params, status FROM chaos_admin_log ORDER BY id DESC LIMIT 100`
   (look for `give_*`, `stash_give`, `give_coins`, `set_*` you did not expect), and `grep '\[ChaosAdmin\]' /var/log/chaos/server.log*`.
6. Contain: `Ban account` / `IP ban` in the panel; `Remove gold` / `Remove item` for what was duped. If the hole is
   still open and you do not know it, close the server to players (`Open / close server` in the panel) until it is
   found and fixed.
7. Only if the damage is wide and cannot be cleaned by hand: the rollback above, to a dump before the first bad row.
   Fix the hole before reopening.

**DDoS** (players lag or drop, ports fail from outside, the machine itself is fine):
1. Confirm: `ss -s` and `ss -tn state syn-recv | wc -l` (a SYN flood), `iftop` / `nload` (traffic far above normal),
   `journalctl -k | grep -i drop`.
2. Contact the hosting provider at once through its panel or support ticket: report the attack on the server's IP and
   ask for (or turn on) its DDoS filtering for game traffic (TCP 7171, 7172). Write the provider's support contact,
   its panel URL and the account owner's name here before launch: ______.
3. On the machine: keep SSH limited to your addresses (section 5); turn on SYN cookies
   (`sysctl -w net.ipv4.tcp_syncookies=1`); limit new connections per address, e.g.
   `iptables -I INPUT -p tcp --syn -m multiport --dports 7171,7172 -m connlimit --connlimit-above 10 -j DROP`
   (remove with `-D` instead of `-I` afterwards). A volume attack that fills the uplink can only be stopped by the
   provider.
4. Behind gateways (section "Gateways and DDoS"): the attack hits a gateway, not this machine. Replace that gateway
   ("Replace a gateway under attack" there). Without gateways the game ports cannot sit behind a web proxy or CDN, so the
   provider's filtering is what protects them. Tell the players on Discord.

## Gateways and DDoS

Players never connect to the real game server. They connect to 2 or 3 small DDoS-protected VPS, the **gateways**. Each
gateway runs HAProxy in TCP mode and forwards the game ports to the real server, the **backend**. The backend's IP is
never published, and its firewall takes the game ports from the gateways only. An attack then hits a gateway, which
can be filtered by its provider or replaced in minutes.

```
 players --> play.example.org (DNS: one A record per gateway, TTL 300)
               |                 |                 |
          gateway 1          gateway 2         gateway 3       HAProxy + nftables (server/deploy/gateway/)
          7171 7172 8090     7171 7172 8090    7171 7172 8090  per-IP limits, PROXY v2 header on 7171 / 7172
               |                 |                 |
               +-----------------+-----------------+
                                 |
                                 v
                     backend (IP never published)            nftables: 7171 / 7172 / 8090 from the gateways only
                     game server, MariaDB (127.0.0.1)        (server/deploy/firewall/), engine patch 0025
```

**How the player's IP survives the proxy.** The engine uses the client's IP for bans, its connection throttle, the
status query limit, the 2-characters-per-IP rule (`multiclient.lua`), the client guard's staff IPs and the logs. The
gateways put a PROXY protocol v2 header in front of each connection. Engine patch 0025 reads it, but only from the
addresses in `proxyProtocolTrusted`, and uses its address as the connection's IP. A PROXY header from any other address
is refused and never believed. With `proxyProtocolRequired = true` the engine also refuses every connection that does
not come from a gateway, so a wrong firewall rule cannot expose the game. 127.0.0.0/8 always connects directly (the
watchdog and the health check ask the status protocol on 127.0.0.1). Details: `server/README.md` "Gateways and the PROXY
protocol".

**The world address.** The login server tells the client where the game world is: `ip` and `gameProtocolPort` from
`config.lua`. `ip` must be the gateways' public name (`prod_config.py --public-host play.example.org`), never the
backend's IP. The engine sends the name as text and the client resolves it itself, so DNS changes need no restart. The
gateways listen on the same port numbers as the backend (7171, 7172), because the client uses the game port the login
server names.

**Limits per source IP** (edit the numbers at the top of `setup_gateway.sh`, then run it again):

| Where | Login 7171 | Game 7172 | Services 8090 |
|---|---|---|---|
| gateway kernel (nftables) | 10 new connections/s (burst 20), 24 open, both ports together | (same) | 10 new/s (burst 20) |
| gateway HAProxy | 8 open, 20 new per 10 s; first bytes within 5 s | 10 open, 15 new per 10 s | 8 open, 20 new per 10 s |
| gateway HAProxy, flood | more than 60 new per 10 s: silently dropped | (same) | (same) |
| backend kernel (nftables) | a gateway: 300 new/s; others: dropped | (same) | from the gateways only |
| engine | the stock throttle (5 quick reconnects) and status limit, now per real IP | | |

A household or mobile carrier that puts many players behind one IP (CGNAT) shares these limits. The multi-client rule
already allows only 2 characters per IP, so the limits leave room for that and for reconnects.

### Setting it up (owner)

1. **Buy 2 or 3 gateway VPS.** 1 vCPU and 1 GB RAM are enough for 300 players. Pick providers that filter DDoS on
   TCP game traffic, not only on web traffic, and with good routes to the players and to the backend (a gateway adds
   one hop). Different providers or regions survive more. Debian 12 or Ubuntu 24.04, IPv4.
2. **Give the backend an IP nobody knows.** If players ever connected to the backend's current IP, an attacker may
   have it, and a flood can fill its uplink even when the firewall drops it. Ask the host for a new IP (or move to a
   new machine) before you switch, and never put the new one in DNS, on the website, in the client or in a mail.
   Run the website on its own host.
3. **Set up each gateway** (as root, from a copy of the repository's `server/deploy/gateway/` folder):
   ```
   scp -r server/deploy/gateway root@GATEWAY:/root/
   ssh root@GATEWAY /root/gateway/setup_gateway.sh BACKEND_IP --admin-ips YOUR_HOME_IP
   ```
   It installs HAProxy and nftables, writes `/etc/haproxy/haproxy.cfg`, `/etc/nftables.d/chaos-gateway.nft` and
   `/etc/sysctl.d/90-chaos-gateway.conf`, and checks each file before it uses it. It forwards 7171 and 7172 with a
   PROXY header and 8090 (the login-screen services) without one. Run it again after any change: it is idempotent and
   reloads HAProxy without dropping players. `--admin-ips any` keeps SSH open to all (rate limited) if your home IP
   changes.
4. **Trust the gateways on the backend**, still without locking anything:
   ```
   python3 -I server/tools/prod_config.py /opt/chaos/server --public-host play.example.org \
       --proxy-trusted GW1_IP,GW2_IP,GW3_IP --proxy-required no
   sudo systemctl restart chaos-server
   ```
   The console then says `>> PROXY protocol from 3 trusted gateway entries (...)`.
5. **Test one gateway by its IP** before DNS: a client built for that IP logs in, and the status check answers:
   `python3 -I -c "import sys; sys.path.insert(0, 'server/tools'); import chaos_watchdog as w; print(w.ask_status('GW1_IP', 7171, 5))"`.
6. **DNS:** one A record per gateway for `play.example.org`, TTL 300 seconds (60 if the DNS host allows it). No AAAA
   record: the engine stores IPv4 addresses only and refuses IPv6 clients. Set the website's `CHAOS_GAME_HOST` to the
   same name.
7. **Client:** build it with `server_host` = `play.example.org` (section 8). Its login host and its login-screen
   services URL (port 8090) then both go through the gateways.
8. **Lock the backend:**
   ```
   sudo server/deploy/firewall/setup_backend_firewall.sh GW1_IP,GW2_IP,GW3_IP --admin-ips YOUR_HOME_IP \
       --services GW1_IP,GW2_IP,GW3_IP
   python3 -I server/tools/prod_config.py /opt/chaos/server --public-host play.example.org --proxy-required yes
   sudo systemctl restart chaos-server
   ```
   7171, 7172 and 8090 now answer the gateways only. 3306 stays closed (MariaDB listens on 127.0.0.1). If ufw is on as
   well (section 5), keep its allow rules: a packet must pass both firewalls, and this table is the narrower one. A
   website on the same machine: add `--web-ports 80,443`. Another machine that must query the status protocol
   directly: `--extra-ips`, and keep `--proxy-required no` (or point it at a gateway instead).

### Check it

- **Real IPs reach the engine:** after a few logins, `SELECT name, INET_NTOA(lastip) FROM players ORDER BY lastlogin
  DESC LIMIT 5;` shows the players' addresses with the bytes reversed (the engine stores them in network order), not
  the gateways'. `data/logs/clientguard.log` shows `ip=` with the players' addresses. On a gateway,
  `/var/log/haproxy.log` lists each connection with the player's address.
- **A direct connection is refused:** from your PC, `nc -vz -w 3 BACKEND_IP 7172` must time out (firewall). With the
  firewall off for a moment, the console prints `[PROXY protocol] direct connection refused (proxyProtocolRequired)`.
- **A forged header is refused:** a connection from an address outside `proxyProtocolTrusted` that sends a PROXY header
  is closed with `[PROXY protocol] PROXY header from an address that is not in proxyProtocolTrusted, refused`.
- **Health:** on a gateway, `systemctl status haproxy`; `/var/log/haproxy.log` says `Server be_game/game is DOWN` when
  the backend stops answering and `UP` when it is back. Live counters:
  `echo "show stat" | sudo socat stdio /run/haproxy/admin.sock` (install `socat`), or
  `curl -s http://127.0.0.1:8404/stats` on the gateway itself. Per-IP state: `show table fe_game`.
- Console lines of patch 0025 are limited to one per kind every 10 seconds, so a flood cannot fill the log.

### Replace a gateway under attack

1. Delete its A record. New logins go to the other gateways once the TTL runs out. Players on it lose their connection
   and log in again through another gateway.
2. Order a new VPS (another provider or region if the attacker follows) and run `setup_gateway.sh` on it (step 3).
3. On the backend, put the new IP in place of the old one in both lists, then add its A record:
   ```
   python3 -I server/tools/prod_config.py /opt/chaos/server --public-host play.example.org --proxy-trusted GW2_IP,GW3_IP,NEW_IP
   sudo server/deploy/firewall/setup_backend_firewall.sh GW2_IP,GW3_IP,NEW_IP --admin-ips YOUR_HOME_IP --services GW2_IP,GW3_IP,NEW_IP
   ```
   The engine reads `proxyProtocolTrusted` again on `/reload config` (a god character), so no restart is needed; a
   restart also works.
4. Cancel the old VPS. Its IP is out of both lists, so it can no longer reach the game.

Keep one spare gateway set up but out of DNS: then step 2 is only a DNS change.

### Failover

DNS round-robin spreads players over the gateways. Expect the client to use one address of the answer and not to try
the next one when it fails (the base client's network code is not in this repository, so this was not checked). While a
dead gateway is still in DNS, some logins then fail until the player tries again.
Delete a dead gateway's record at once (an external uptime check per gateway IP helps). A client-side list of hosts,
where the login window tries the next host when one does not answer, needs a client change (`init.lua` `Servers` has
one `host` per entry): a proposal, not built.

## Website

**Cloudflare** (docs/SECURITY_CHECKLIST.md "Cloudflare"): the orange cloud (proxy) only on `@` and `www`, with SSL/TLS
mode **Full (strict)** (the Let's Encrypt certificate stays on the server); the game host (`play`) is always **DNS only**
(grey): Cloudflare's proxy carries web traffic, not the game's TCP ports. With the proxy on, run
`tools/linux/harden_vps.sh --cloudflare` so Apache sees the visitor's address (the site's login limits count per
address). The game host's record still shows the machine's IP, so the proxy does not hide this machine.

The account site is `website/` (ZnoteX with our layout and plugin; details in `website/README.md`). Install it after
the database (section 2) on the web host, outside the repository:

```
sudo cp website/site.env.example /etc/chaos/site.env && sudo chmod 600 /etc/chaos/site.env   # fill in the placeholders
website/install_site.sh /etc/chaos/chaos.env /etc/chaos/site.env                             # again: no changes
```

It covers section 6's rules: the four base classes only, the Monk / Necromancer / Templar for accounts with a
`chaos_class_unlocks` row (checked server-side), level 1 characters with `lastlogin = 0` and no items. Set
`CHAOS_SERVER_DATA` to `/opt/chaos/server/data` (patch notes, seasons), the site and game addresses, the client
download links and the Discord invite, and `CHAOS_ADMIN_ACCOUNTS`; then edit the Rules page in the admin panel.

**Client API** (`chaos_client_api.php`, `website/README.md` "Client API"): on by default (`CHAOS_CLIENT_API=0` in
`site.env` turns it off). It is what the client's `Services.account` points at (section 8). Check after the install:
`curl -s -X POST https://<site>/chaos_client_api.php -d '{"action":"state","token":"x"}'` answers
`{"ok":false,"error":"token",...}` (401). With nginx add its `location` block with `limit_req` (website/README.md
"Web server"). New characters, from the site or the client, wear their class look from creation and a season chosen
in the client is joined at the first login (needs the server's `sql/chaos_season.sql` table `chaos_season_requests`;
the server and the site's plugin both create it).

**Mail** (account recovery links, website 2FA codes; `website/README.md` "Mail"): fill `CHAOS_SMTP_HOST`,
`CHAOS_SMTP_PORT` (587), `CHAOS_SMTP_TLS` (`starttls`), `CHAOS_SMTP_USER`, `CHAOS_SMTP_PASSWORD` and `CHAOS_MAIL_FROM`
(e.g. `no-reply@<your domain>`) in `site.env` and run the installer again. Add the SPF, DKIM and DMARC records of the
From domain first. Check: ask for a recovery link for your own account; it arrives (not in spam), the link opens the
password form once, and the headers show `spf=pass dkim=pass dmarc=pass`. Without `CHAOS_SMTP_HOST` the site runs
without mail and the recovery page says recovery by e-mail is not available.

**Pre-deploy check** (before every website or beta deploy; `website/README.md` "Smoke test"): run
`website/tests/e2e/run.sh` on the commit to deploy (a throwaway local site, about 30 s), then
`E2E_BASE_URL=https://<staging site>/ website/tests/e2e/run.sh` against staging. Both must end with `# fail 0`. They
cover the home page, account creation, login, character creation and page, the Donate page (voluntary donation label,
Pix and PayPal buttons), the wiki with the pt-BR / en switch and the Character Bazaar. Never run it against the live
site: it creates an account and a character.

## Donations (Pix / PayPal)

Chaos Coins are a thank-you for a **voluntary donation**: nobody is required to donate and the game is fully playable for
free. The client (Store > Donate) and the website (`page?plugin=chaos&p=coins`) say so in English and Portuguese
before a pack is picked, every button says "Donate", and the thank-you after the donation repeats it. Pix goes through
Mercado Pago in BRL, PayPal in USD; one USD price table (`shop_coins_config.lua` `usdCents`), Pix = USD x 5. How it works:
`website/README.md` "Donations", `server/README.md` "Store".

**Legal and money (the operator's job, not the code's).**
- The operator needs their own **Mercado Pago** account (Brazil; Pix keys registered) and a **PayPal Business** account.
  The money goes to those accounts; this repository never holds money or credentials.
- Taxes, invoices and bookkeeping of the donations are the operator's responsibility (in Brazil: income from the
  Mercado Pago account; abroad: whatever the operator's country requires).
- PayPal's donation category (`CHAOS_PAYPAL_CATEGORY=DONATION`) may require a registered charity or nonprofit in some
  countries; if PayPal refuses it, set `DIGITAL_GOODS`: the item stays labelled "voluntary donation".
- The refund policy is in the Donation Terms (docs/legal/donations.*.md, linked from the donation page): a refund or chargeback after the coins were credited takes back the coins still
  unspent (`removeCoinsOnReversal` in `shop_coins_config.lua`) and staff see it in the admin panel (Store > Donations:
  refunds and chargebacks). Chargeback fraud: the account is locked until the dispute is settled, fraud again is a
  permanent ban by an administrator (docs/GM_HANDBOOK.md section 4, Rules 7.9, Donation Terms section 6).
- Set the real prices (`usdCents` of each pack) before launch: the ones in the repository are placeholders.

**Go-live steps.**
1. Mercado Pago: Your integrations > create an application (Checkout Transparente / Payments API). Copy the **test**
   access token first. Webhooks > Configure notifications: URL `https://<site>/chaos_pay_webhook.php?psp=mercadopago`,
   event "Payments"; copy the secret.
2. PayPal: developer dashboard > Apps & Credentials > create an app (sandbox first): Client ID and Secret. Add a webhook
   `https://<site>/chaos_pay_webhook.php?psp=paypal` with the events CHECKOUT.ORDER.APPROVED, PAYMENT.CAPTURE.COMPLETED,
   PAYMENT.CAPTURE.DENIED, PAYMENT.CAPTURE.PENDING, PAYMENT.CAPTURE.REFUNDED, PAYMENT.CAPTURE.REVERSED,
   CUSTOMER.DISPUTE.CREATED; copy its Webhook ID.
3. `sudo cp website/payments.env.example /etc/chaos/payments.env && sudo chown root:www-data /etc/chaos/payments.env &&
   sudo chmod 640 /etc/chaos/payments.env`; fill in the sandbox values (`CHAOS_PAYPAL_ENV=sandbox`), the providers
   `mercadopago` / `paypal`, `CHAOS_PAY_SITE_URL`. Never commit it (`payments.env` is git-ignored).
4. Web server: the site must be HTTPS; `chaos_pay_webhook.php` must be reachable from the internet (POST).
5. Worker: `sudo cp server/deploy/chaos-payworker.service /etc/systemd/system/ && sudo systemctl daemon-reload &&
   sudo systemctl enable --now chaos-payworker`; `php /var/www/chaos/plugins/chaos/pay/worker.php --site /var/www/chaos
   --status` prints the methods that are on.
6. **Sandbox test**, in the client and on the website: a Pix donation with Mercado Pago's test users (the QR code and copy
   and paste appear, the payment approved in the sandbox credits the coins within seconds, toast + balance without
   relog); a PayPal donation with a sandbox buyer (browser opens, approval, capture, coins); cancel one; let one expire
   (30 minutes); refund one in each dashboard after crediting and check Store > Donations: refunds and chargebacks in
   the admin panel and the coins taken back; send a webhook with a wrong signature (curl) and get 401.
7. Live: the live access token and webhook secret (Mercado Pago production credentials), the live PayPal app's client
   id, secret and webhook id, `CHAOS_PAYPAL_ENV=live`; `sudo systemctl restart chaos-payworker`. One small real donation
   of each kind, refunded afterwards.
8. Watch `/var/log/chaos/payworker.log` and `CHAOS_PAY_LOG` the first days (order ids and amounts only, no personal data).

## Discord announcements

The game posts records, realm firsts, world boss spawns and kills, Ascended and Cinderheart kills, levels 500 and
1000, season start and end, server up / daily restart / down, and the Character Bazaar's new auctions and sales to
Discord channel **webhooks**. No bot, no token in the repository, no account linking. The game only writes rows to
`chaos_discord_queue`; the website's worker posts them. How it works: server/README.md "Discord announcements",
website/README.md "Discord announcements".

1. In Discord, Server Settings > Integrations > Webhooks: one webhook per channel you want, e.g. `#records`,
   `#bosses`, `#players`, `#announcements`, `#server-status`, `#bazaar` (one webhook for all also works). Copy each URL.
   A webhook URL is a password: anyone with it can post as it.
2. `sudo install -m 600 -o www-data -g www-data /dev/null /etc/chaos/discord.env` and fill it in:
   ```
   CHAOS_DISCORD_WEBHOOK_RECORDS=https://discord.com/api/webhooks/...
   CHAOS_DISCORD_WEBHOOK_BOSSES=...
   CHAOS_DISCORD_WEBHOOK_PLAYERS=...
   CHAOS_DISCORD_WEBHOOK_ANNOUNCE=...
   CHAOS_DISCORD_WEBHOOK_STATUS=...
   CHAOS_DISCORD_WEBHOOK_BAZAAR=...
   # CHAOS_DISCORD_WEBHOOK_DEFAULT=...     every channel without its own
   # CHAOS_DISCORD_OFF=level,bazaar_list   event kinds not to post
   CHAOS_SITE_URL=https://<site>
   ```
3. `sudo cp server/deploy/chaos-discord.service server/deploy/chaos-discord.timer /etc/systemd/system/ &&
   sudo systemctl daemon-reload && sudo systemctl enable --now chaos-discord.timer` (and copy `server/deploy/chaos.logrotate`
   again: it now rotates `/var/log/chaos/discord.log`).
4. Test: restart the game server (a "Server online" post in the status channel within a minute), then
   `sudo -u www-data sh -c 'set -a; . /etc/chaos/discord.env; php /var/www/chaos/plugins/chaos/discord_worker.php --site /var/www/chaos'`
   by hand and check `SELECT kind, status, error FROM chaos_discord_queue ORDER BY id DESC LIMIT 10;`.
5. Switch event types on or off in `server/data/scripts/chaos/discord_config.lua` `events` (a `/reload` or restart),
   or without a restart with `CHAOS_DISCORD_OFF` in `discord.env`.

## Balance telemetry

Staff charts of experience and gold per hour, boss kills and times, deaths, spell casts, gold faucets and sinks, store
coins and online counts: `page?plugin=chaos&p=telemetry` (Admin Panel > Balance Telemetry; admin accounts with a
character of group 5 or higher). Nothing to set up: the game server creates the `chaos_telemetry_*` tables at its start
(or the install step `sql`) and writes one row per bucket every hour. Hourly rows are kept 90 days, then daily rows
730 days. Aggregates only, no names or ids (privacy policy section 2, "Game statistics"). Details: server/README.md
"Balance telemetry". `/telemetry` in game shows the hour in memory.

## Client updates (signed updater)

The client checks the website for a signed manifest before login and downloads changed modules, images, fonts and
the dat/spr pair (client/MANIFEST.md "Signed updater"; files on the site: website/README.md "Client updates").
The exe and its DLLs are never updated this way: a new exe is a new Windows package (below).

**The update files are encrypted (client build 13 on, base patch 0103).** Every file is published as an AES-256-GCM
blob keyed from the client guard secret `CHAOS_CLIENT_KEY` (the same 64 hex digits as the GitHub secret and the game
server's `/etc/chaos/chaos.env`), so the website and the players' user folders hold only ciphertext
(client/BASE.md "Encrypted updates"). The machine that publishes needs that key: `make_update_manifest.py build` reads
it from the environment variable `CHAOS_CLIENT_KEY` (never from an argument, never printed) and refuses to publish
without it (there is no plain fallback); `publish_client_update.sh` reads it from `/etc/chaos/chaos.env` when the
variable is not set. Encrypted updates need `--min-package 13` or more: older clients cannot decrypt them and are sent
to the download page. The Python package `cryptography` must be installed (`apt install python3-cryptography`).

**Keys (once).** Never in the repository. Two places, the owner picks one (owner, 2026-10-20: the VPS, below
"Publishing a client update"): the operator's own machine (offline, the safest), or the web server as root
(`/etc/chaos/update-key.hex`, so `chaos-ctl.sh publish-update` can sign there). On the server, anyone who becomes root
there can sign an update for every player: keep root logins to ssh keys and back the key up offline. On your own machine:

```
python3 -I client/tools/make_update_manifest.py keygen --private ~/chaos-keys/update.key --public ~/chaos-keys/update.pub
```

- `update.key` is the Ed25519 private key (mode 600). Anyone holding it can ship code to every player: keep it
  offline (an encrypted USB stick and a second copy in a safe place), never in a CI secret, a chat or a cloud drive.
  The tool refuses to write or read a key inside a git work tree.
- `update.pub` (64 hex digits) goes into the client: `windows-package.yml` input `update_public_key`, or
  `client/tools/set_update_config.py <client> --manifest https://<site>/updates/live/manifest.json --public-key <hex>`.
- Lost key: make a new pair and ship a new package with the new public key; clients with the old key keep
  playing with their files but get no more updates. Leaked key: the same, at once, and tell the players to
  download the new package; a leaked key can sign anything the old clients accept.

**Publishing an update.**

1. Assemble the client as for a package (`client/tools/assemble_client.sh`, the dat/spr pair in `data/things/1098/`).
2. Dry run: `python3 -I client/tools/make_update_manifest.py build <client> --dry-run` (no key, writes nothing).
3. Publish: `CHAOS_UPDATE_KEY=~/chaos-keys/update.key CHAOS_CLIENT_KEY=<64 hex> python3 -I
   client/tools/make_update_manifest.py build <client> --out <CHAOS_SITE_DIR>/updates/live --min-package 13` (set
   `CHAOS_CLIENT_KEY` from a file, e.g. `CHAOS_CLIENT_KEY=$(cat ~/chaos-keys/client.key)`, so it stays out of the shell
   history; or `--out` to a local folder and rsync it up with `--delete`: blobs first, `manifest.json` last). A packed
   build-13 package is opened first with `make_update_manifest.py unpack <client>/chaos.pack <tree>`. The version goes up by one each time; clients refuse an older manifest. A package built with a baseline
   (`Services.update.baseline`, base patch 0101; `windows-package.yml` writes its run number) is published as exactly
   that version (`--version` must match).
4. Check: `python3 -I client/tools/make_update_manifest.py verify <CHAOS_SITE_DIR>/updates/live --public <hex>` (with
   `CHAOS_CLIENT_KEY` set it also decrypts every blob and checks the signed content).
5. Start a client: it says "Update applied" and restarts, or "Your client is up to date". An exe without base patch
   0101 (client build 11 and older) does not restart itself: it asks the player to close it and start it again.

Options: `--min-version N` (clients below update N may not play offline), `--min-package N` (clients whose
package number, `Services.update.package`, is below N are told to download the new package and cannot log in),
`--parallel N` (download requests at once, default 4; a player can set `chaos-update-parallel` in the client
settings). `Services.update.required = true` in a package makes the update server mandatory to play.

**When a new package is needed** (the exe changed: a new base patch, an engine fix): build it with
`windows-package.yml`, raise `Services.update.package` in it, then publish an update with `--min-package` set to
that number so older clients send their players to the download page (`Services.update.download`). The workflow input
`client_build` is that number in the exe too, and the game server checks it (`server/README.md` "Client guard"): list the
old and new build in `clientGuardBuilds` for the switch, or point `clientGuardManifest` at the published manifest so its
`min_package` refuses the old exe on the server as well.

**Sprites in shards** (client/MANIFEST.md "Sharded sprites", client/BASE.md 0048). Whole files are compared by
SHA-256, so a change to the single 600 MB `Tibia.spr` makes every player download all of it again. Split it instead:
assemble with the pair as third argument (`client/tools/assemble_client.sh <base> <client> <things-dir>`, which writes
`data/things/1098/Tibia.sprshards` and `Tibia.000.spr` .. `Tibia.045.spr` and checks them against the spr), or run
`python3 -I client/tools/sprites/spr_shards.py split Tibia.spr <client>/data/things/1098` and `verify` and remove
`Tibia.spr` there. Each shard (16384 sprite ids, 10-30 MB) is its own manifest file: a new pair that appends sprites
re-sends the index, the dat and the last shard or two, not 600 MB. Rules the build step enforces:
- The first update with shards needs `--min-package N`, N the first package whose exe has base patch 0048: an older
  exe ignores the shards and would draw the new dat with its old spr. Players on that package download all shards
  once (about 572 MB); their package's own `Tibia.spr` stays on disk unused.
- Never publish the shards and `Tibia.spr` together (refused: both would be downloaded); `--with-single-spr` does it
  on purpose while packages without 0048 must still be served.
- Once players have shards, keep publishing shards: a client with an index loads its shards before any `Tibia.spr`
  (the build warns when it publishes a single spr with no shard set).
- No file over 1 GiB, ever (refused): the updater of every client build out refuses a whole manifest that lists one.
  Since pair 37 (2026-10-22, its `Tibia.spr` is over 1 GiB) `windows-package.yml` ships the shards inside both
  clients' `chaos.pack`; only the map editor keeps the single `Tibia.spr` (`mapeditor\data\1098`).
  `server/deploy/publish_client_update.sh` splits a single spr it finds in a package, so the live update is always
  sharded.

**Production is HTTPS.** The updater warns in the client log when the manifest URL is plain HTTP;
`client/tools/serve_updates.py` (HTTP, local) is only for tests.

### Publishing a client update

`server/deploy/publish_client_update.sh` publishes one Windows client package of a release (`winpkg-N`) as the
signed update, on the VPS that holds the site (`/var/www/chaos`, `install_site.sh`). `chaos-ctl.sh publish-update` runs
it in the background (so the admin app can start it too) and `chaos-ctl.sh publish-log` shows its log.

**The blob key (client build 13 on).** `/etc/chaos/chaos.env` must hold `CHAOS_CLIENT_KEY` (it does for the game
server's client guard; "old,new" during a rotation is fine: the key that opens the package's `chaos.pack` is used).
`publish_client_update.sh` reads only that line (`CHAOS_ENV`, default `/etc/chaos/chaos.env`; `chaos-ctl.sh` passes
its own `CHAOS_ENV`) and exports it to the Python tools; it is never printed. Without it the script stops before
anything is published.

**Once, as root on the VPS** (owner, 2026-10-20: done; the public key is
`7f4ae1b812e3ca86ac4551683b987b8bf68d2256b36b1785c07cb4f3ffb72224`):

```
sudo python3 -I /opt/chaos/repo/client/tools/make_update_manifest.py keygen \
    --private /etc/chaos/update-key.hex --public /etc/chaos/update-key.pub
sudo chmod 600 /etc/chaos/update-key.hex          # keygen writes it 600 already; root only
sudo python3 -I /opt/chaos/repo/client/tools/make_update_manifest.py pubkey --private /etc/chaos/update-key.hex
```

The last line prints the public key of an existing key file (when no `.pub` was written; writing it is optional:
`... pubkey --private /etc/chaos/update-key.hex | sudo tee /etc/chaos/update-key.pub`). Copy the key file to an
offline place. Then build the package with the updater on: Actions -> Windows package with `update_manifest`
`https://www.cindersofchaos.com/updates/live/manifest.json`, `update_public_key` (that key) and `client_build` (11 for
the first updater build). Only a package built with both inputs ever checks for updates.

**Every update** (as root, or as `chaosadmin` through `chaos-ctl.sh`):

```
sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh publish-update winpkg-46     # background; then:
sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh publish-log
# or in the foreground, with its output on the terminal:
sudo /opt/chaos/repo/server/deploy/publish_client_update.sh winpkg-46
```

What it does: downloads `CindersOfChaos-Client-Windows.zip` of the release (`curl -fL`, https only) into a new folder
under `/var/tmp`, refuses a download under 50 MB, prints its size and SHA-256; extracts it with `python3 -I zipfile`,
refusing absolute paths, `..`, links and more than 8 GB; finds the client: a packed build-13 package (the exe and
`chaos.pack`) is decrypted with `CHAOS_CLIENT_KEY` into the work folder (`make_update_manifest.py unpack`; a
development pack, `allow_dev_key`, is refused), an older loose one is used as it is (`init.lua`, `modules/`,
`data/things/1098/`); checks that the public key in the package's `init.lua` is the one of `/etc/chaos/update-key.hex`
(and of `CHAOS_UPDATE_PUBLIC` or `/etc/chaos/update-key.pub` when set); runs `make_update_manifest.py build` into
`/var/www/chaos/updates/live` (every blob encrypted, blobs first, `manifest.json` last, then every older or plain blob
removed from `files/`) and `verify` (decrypts every blob); then checks the web server: a GET of the
package's manifest URL must give HTTP 200, the same bytes as the file just written, `application/json` and
`no-cache`, and a `Range` request on the largest blob must give 206. A failed web check only warns (the update is
published); `publish_client_update.sh --check-only` with `CHAOS_UPDATE_URL` repeats it. The work folder is removed.

Numbers, and why a client of build N accepts the update:
- **version** = the package's baseline (`Services.update.baseline` in its `init.lua`, base patch 0101: the run
  number `windows-package.yml` built it as, `winpkg-47` -> 47), so the files of release N are always update N. A tag or
  `--version` of another number is refused for such a package. A package without a baseline (built before 0101): the
  tag's number (`winpkg-46` -> 46), `--version N` to choose. The client refuses a version below the update it applied
  last, and skips (never applies) one below its own package's baseline: a package built after an update went live
  has newer files than that update (2026-10-21: the winpkg-47 start test applied the live winpkg-46 files). The
  version has nothing to do with the build number. Each publish must be above the last one (the script stops before
  signing otherwise): an older package than the live update cannot be published; build a new one. Republishing the
  same package (to change min_package) is not possible with a baseline; build a new package.
- **min_package** = the package's own client build (`Services.update.package` in its `init.lua`; `BUILD_INFO.txt`
  "client build: N" of a package before build 13, the script refuses when they differ), `--min-package N` to choose,
  at least 13 (the update files are encrypted; builds 12 and older cannot decrypt them). A client accepts the update when its package (build) is at least min_package; an older
  updater client is told "A new client download is required" and cannot log in, and the game server refuses its exe
  too when `clientGuardManifest` names this manifest (server/README.md "Client guard"). Publishing the files of a
  newer package to an older exe is what min_package prevents: the modules may need the newer exe.
- **Sprites:** the package keeps the single `Tibia.spr`, so no shard rule applies. A package with a shard set needs
  min_package at least the first build with base patch 0048 (the build step refuses a shard set with min_package 0).
- **A client without the updater** (built without `update_manifest` / `update_public_key`, or an exe without base
  patch 0031) never asks for the manifest: it keeps its files, is never blocked by the updater, and gets the update
  only by downloading a new package. Only the game server's client guard can turn it away (`clientGuardBuilds`, or
  `clientGuardManifest` with a min_package above its build).

Settings: `/etc/chaos/ctl.conf` keys `CHAOS_SITE_DIR` (`/var/www/chaos`), `CHAOS_UPDATE_KEY`
(`/etc/chaos/update-key.hex`), `CHAOS_UPDATE_PUBLIC` (empty: derived from the key), `CHAOS_UPDATE_REPO`
(`lucas1089/cinders-of-chaos`), `CHAOS_UPDATE_URL` (the manifest URL for the check; empty: the package's own),
`CHAOS_WORK_DIR` (`/var/tmp`, needs about three times the zip size free), `CHAOS_PUBLISH_LOG`
(`/var/log/chaos/publish-update.log`). A local zip (`publish_client_update.sh /path/client.zip`) works from the shell as
root only: `chaos-ctl.sh` takes release tags only, so the admin user can never sign a file of its own.
The web server: Apache reads `updates/.htaccess` (`install_site.sh` copies it); nginx needs the `location` block of
website/README.md "Client updates". The site's `dl` folder is not involved.

**Packaging never uses the live update.** The `windows-package.yml` start test runs the client with
`CHAOS_UPDATE_OFF=1` (no manifest request, no update folder mounted) and fails when the log lacks
`updater: off (CHAOS_UPDATE_OFF is set)`. The same switch works for any local test run of a package.

**Client build 11 and the restart.** Build 11's `g_app.restart()` aborted the client after starting the new one
(base patch 0101, client/BASE.md). Build 12 (an exe with 0101) restarts cleanly. A build-11 client applying the next
update still runs its old `updater.lua` at that moment: it may close with a crash report, but the update is in place
and loads when the player starts the game again; from then on its updater asks the player to close and start the
game instead. Build 12 is a new exe: build it with `client_build` 12 and list 11 and 12 in `clientGuardBuilds`. Its
update defaults to `--min-package 12`, which sends build-11 players to the download page; give `--min-package 11` to
let build 11 keep updating (its updater copes without 0101).


## Updating the live server

Every update after launch follows this routine. `server/deploy/chaos_update.sh` runs it on the game server, as root.
Its test drives stubs, not a real systemd (`server/deploy/chaos_update_test.py`): watch the first live run closely.

### Kinds of update

| Kind | Changed in the release | What it needs |
|---|---|---|
| Lua and data | `server/data/`, `server/tools/` | `install_all.py`, then a restart. A small Lua fix can go out with `/reload` instead (below). |
| Read only at start | `config.lua` values, `items.otb`, the map, its spawn and house files, vocations | `install_all.py` writes them; the engine reads them at the next start. |
| Engine | `server/src-patches/` | A rebuild of the engine from the release (section 1), into a new file such as `/opt/chaos/build/tfs`, never over the running `/opt/chaos/server/tfs`. The script takes it with `--engine` and swaps it in while the server is down. |
| Database | `server/sql/` | The `sql` step applies it: `CREATE TABLE IF NOT EXISTS` and plain updates, safe to repeat. A rollback does not undo it. |
| Client files | `client/overlay/` | A signed client update: a Windows package, then `chaos-ctl.sh publish-update winpkg-N` ("Publishing a client update"). |
| Client exe | `client/base-patches/` | A new package from `windows-package.yml` with a higher `Services.update.package`, then a signed update with `--min-package` set to it. List the new `client_build` in `clientGuardBuilds` first. |
| systemd units, logrotate | `server/deploy/*.service`, `*.timer`, `chaos.logrotate` | Copy them again and `systemctl daemon-reload` (section 5). |
| Website | `website/` | Its own install ("Website"). |

The script lists the kinds found in the release before it asks to go on.

### When

**Default: at the daily save** (06:00, section 3). The engine saves, kicks everyone and stops then anyway, after the
save warnings. `chaos_update.sh --at-save` waits for that stop, holds off systemd's restart meanwhile, installs and
starts the server. Nobody loses progress.

**Sooner:** start the in-game warning yourself: admin panel (opcode 120) > Server > Restart (countdown), a few minutes,
reason "update". It warns at 60, 30, 10, 5, 2 and 1 minutes, at 30 and 10 seconds and the last five, then saves and
stops. `--at-save` catches that stop the same way. "Cancel countdown" leaves the script waiting; Ctrl-C ends it and puts
everything back.

**`--now`** stops at once with `systemctl stop`. The engine saves every player first. Only for an empty or closed
server, or an urgent fix after a Broadcast in the admin panel.

**Hotfix without a restart: `/reload`.** It covers Lua the engine loads again: the revscripts of `data/scripts`
(`/reload scripts`), creaturescripts, actions, movements, talkactions, globalevents, spells, monsters, NPCs and the
`config.lua` keys read on `/reload config`. Engine patch 0012 makes `/reload scripts`, `creaturescripts` and
`all` safe with players online (server/README.md "Engine: reloads and oversize messages"). It does not cover the engine,
the items (`items.otb`, `items.xml`), the map, spawns, houses, vocations, any `install_all.py` step but `files`, or the database. A reload runs
every script file again, so state a system keeps only in memory can reset: read its section in server/README.md first.
The steps, as root:
```
git -C /opt/chaos/repo fetch --tags && git -C /opt/chaos/repo checkout --detach <tag>
python3 -I /opt/chaos/repo/server/tools/install_all.py /opt/chaos/server --only files --dry-run
python3 -I /opt/chaos/repo/server/tools/install_all.py /opt/chaos/server --only files
chown -R chaos:chaos /opt/chaos/server/data
```
Then `/reload scripts` with a god character, or admin panel > Server > Reload system, and read the log for
`Lua Script Error`. Run `chaos_update.sh --ref <tag> --at-save` for the same tag afterwards: it runs every step at the
next save and records the release.

### The routine

On the owner's machine:
1. **The patch note.** One player-facing file per update in `server/data/patchnotes/<date>.md` (format:
   server/README.md "Patch notes"). Only what is live after this update: nothing still in testing, nothing turned
   off. Drafts start with `_` and are skipped. It goes out with the release's data, so a rollback takes it back too.
2. **The release.** CI green on `main`, then a tag on that commit: `git tag -a live-2026-11-05 -m "..."` and
   `git push origin live-2026-11-05`. The server only installs tags.
3. **The engine**, only when `server/src-patches/` changed: build it from the tag (section 1) and copy the binary to the
   server, for example `/opt/chaos/build/tfs`.

On the game server, as root, inside `tmux` (an `--at-save` run waits for hours):
```
/opt/chaos/repo/server/deploy/chaos_update.sh --ref live-2026-11-05 --check-only    # any time: what changes, the dry run
/opt/chaos/repo/server/deploy/chaos_update.sh --ref live-2026-11-05 --at-save       # [--engine /opt/chaos/build/tfs]
```
The script, in order:
1. Refuses a checkout with uncommitted or untracked files. The server runs a release exactly as it is in git.
2. Records the deployed commit (`/var/lib/chaos/deploy/state`) and fetches the tag. Refuses a branch or a commit
   without a tag, and engine patches without `--engine`.
3. Backup first: `server/tools/backup.sh` with the SIGUSR1 save and the data archive (section 7). Stops if it fails.
4. Checks out the tag and shows `install_all.py --dry-run`. A failed dry run puts the checkout back.
5. Asks (`--yes` skips the question).
6. Waits for the stop (`--at-save`) or stops (`--now`), holds the health, watchdog and backup timers, and dumps the
   stopped database (`backup.sh --no-data`): the exact state before the install.
7. Swaps in the new engine (the old one stays in `/var/lib/chaos/deploy/`), runs `install_all.py`, gives the server
   folder back to the unit's user, starts the server and the timers.
8. The checks of section 9 "After every restart and update": waits for the status protocol (the map load), counts new
   `Lua Script Error` lines since the start, and prints `chaos_health.py --dry-run`. Exit status 2 when one fails.

Until step 7 any failure leaves the old release running. Each run is logged in `/var/lib/chaos/deploy/update-*.log`
and `history.log`. A second run for the same tag does nothing.

After it:
- Log in with a staff character and try what the update changed. Watch the health alerts for the next hour: a burst of
  error lines right after an update is a bug in that update (section 9).
- **Client files changed:** build a Windows package from the same commit, then publish it as the signed update:
  `chaos-ctl.sh publish-update winpkg-N` ("Publishing a client update"), or from the owner's machine with an offline key
  ("Client updates (signed updater)": assemble, dry run, publish, verify).
- **A new exe:** the package first, then the update with `--min-package`.
- Delete old engines from `/var/lib/chaos/deploy/` now and then; keep the newest.

### Rollback

```
/opt/chaos/repo/server/deploy/chaos_update.sh --rollback --now       # or --at-save
```
It backs up the broken state first (`--no-backup` skips that in an emergency), stops the server, checks out the
recorded previous commit, puts back the old engine when the update replaced it, and restores `config.lua` and `data/`
from the pre-update data archive. The maps, logs and reports are carried over; the replaced folder stays as
`data.before-rollback-<time>`. Then it starts the server and runs the checks.

The database is never restored by the script. Restore it only when the update damaged data: bad saves, or a
`server/sql/` change the old release cannot read. That loses everything played since the dump. The script prints the
dump of the stopped server taken right before the install; use it with "Incident runbook", "Rollback to the last
backup".

The towns and worldtexts steps change the map `.otbm` itself, and the rollback keeps the map as it is. When their lines
in the dry run report a change, copy the map aside before the update (`cp -p`).

**If the script died** while waiting with `--at-save` (a lost SSH session outside tmux), remove its drop-in, or the
server stays down after the next daily save:
`rm /run/systemd/system/chaos-server.service.d/50-chaos-update.conf && systemctl daemon-reload`, then put the checkout back
(`git -C /opt/chaos/repo checkout --detach <the deployed commit in /var/lib/chaos/deploy/state>`).

### Updating the kit server (admin app)

The beta VPS runs the Linux kit (`/opt/chaos-trial`, unit `chaos-server`, its own MariaDB inside the unit) with the
checkout `/opt/chaos/repo` following a branch (`main`), and its engine comes from the `winpkg-N` releases, not from a
local build. For that layout the admin app's Painel > Atualizar servidor runs `server/deploy/chaos_kit_update.sh`
through `chaos-ctl.sh update-check`, `update-apply`, `update-rollback` (docs/ADMIN_APP.md, "Atualizar servidor"). The
install step also brings the kit's helper files up to date from the checkout (`clientservices.py`, the Help channel
assistant, `start-server.sh` / `stop-server.sh` / `add-account.sh`), so a kit made from an older package gets the
login-screen services too (the web server still has to forward `/clientservices`, tools/linux/server/README.txt). By
hand, as root:

```
/opt/chaos/repo/server/deploy/chaos-ctl.sh update-check            # what is new: commits, releases, client, downloads
/opt/chaos/repo/server/deploy/chaos-ctl.sh update-apply            # in the background; --no-client --no-downloads --no-site --no-map
/opt/chaos/repo/server/deploy/chaos-ctl.sh update-log 100          # progress: STEP n/10 lines, the last line RESULT ...
/opt/chaos/repo/server/deploy/chaos-ctl.sh update-rollback         # back to before the last apply
```

It does what was done by hand before: fetch and check out the branch; when a newer release exists, download
`CindersOfChaos-Server-Linux.tar.gz` (https, size and SHA-256 against GitHub's), take out `server/tfs`, `ldd` it, back
up the old one as `tfs.antes-N`; when the map master (the owner's edited map on `windows-assets`, server/README.md
"Map master") is newer than the installed map, fetch and check it and put it in place of the map with the server
stopped (the old map kept in `map-backups`); a backup first (`backup.sh`, server up); `install_all.py --no-sql` with the server
stopped; then the server started (that starts the kit's database), `install_all.py --only sql`, a restart, and the
wait for `Server Online`. A failed start rolls back the engine, `config.lua`, `data/` and the commit by itself. The
XP rates of `config.lua` (the `experienceStages` table and the `rate*` lines) are kept across `install_all.py`, whose
lategame step would put the release's table back. After the server: the signed client update of the release
(`publish_client_update.sh`, when newer than the live one), the site's client downloads (`CHAOS_DL_DIR`, with
`NAME.prev`, `NAME.sha256` and `downloads.json` for the downloads page) and `website/install_site.sh` when `website/`
changed. Settings: `server/deploy/ctl.conf.trial.example`. Test: `server/deploy/chaos_kit_update_test.py` (stubs, not a
real systemd or GitHub: watch the first live run).
