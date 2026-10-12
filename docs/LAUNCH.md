# Launch checklist: from the stock downloads to a public Cinders of Chaos server

This is the order to follow on launch day, and the list of what must be checked before the doors open. Everything
here was run on the test server, except where a step says otherwise (the systemd units and the Windows client
workflow could not be run in the build environment).

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
  and both get the updater inputs.
- `CindersOfChaos-Server-Windows.zip`: the Windows server alone (engine, portable MariaDB, the start / stop .bat files,
  the test accounts; `tools/windows/server-README.txt`), `ip = server_host`.
- `CindersOfChaos-Server-Linux.tar.gz`: the engine built on Ubuntu 22.04 (runs on Ubuntu 22.04+ and Debian 12+), its
  libraries in `server/lib/`, the production `config.lua` of `prod_config.py` (`ip = server_host`), a portable MariaDB
  and `start-server.sh` / `stop-server.sh` / `add-account.sh` (`tools/linux/server/README.txt`). The first start makes
  the database, a database user with a random password (`chaos.env`) and a staff account with a random password. No
  test accounts. The client guard is on once `chaos.env` has `CHAOS_CLIENT_KEY`. Good for a small server; a public one
  follows this checklist (its `deploy/` folder holds the systemd units used below).
The inputs live on the private branch `windows-assets` (its README.md). `tools/windows/prepare_server.sh` turns the
base server into the server folder that all three servers share. `tools/linux/package_server.sh` and
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

At the first start on a fresh database the engine prints a few `Duplicate column name` errors (its own migrations add
columns the schema already has) and errors about the website's `znote_*` tables. They are harmless for the game; the
`znote_*` tables appear when the website (its own schema) is installed into the same database.

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

`server/tools/prod_config.py` (idempotent; its docstring explains every value) sets:

| Setting | Value | Why |
|---|---|---|
| `ip` | the public DNS name (`--public-host`) | the login server hands it to the client as text and the client resolves it, so a DNS change needs no restart. Behind gateways it is the gateways' name, never the real server's IP (section "Gateways and DDoS"); 127.0.0.1 only works on the machine itself |
| `loginProtocolPort` / `gameProtocolPort` / `statusProtocolPort` | 7171 / 7172 / 7171 | the stock ports (the test servers use 74xx) |
| `serverName`, `motd`, `ownerName`, `ownerEmail`, `url`, `location` | ours | the download ships its own name and someone else's contact data |
| `maxPlayers` | 400 at launch (the default), 300 for the beta | from the full-map load test (section 9): the game loop's one thread fills up at 500-600 bots on the 4-core test machine, and real players cost more than bots. Raise to 500 after a launch week whose peak kept the lag low; 0 means unlimited |
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
| `slowTaskLogMs` | 0 (not set: off), or e.g. 100 while hunting lag | the slow task log (engine patch 0027, `server/README.md` "Slow task log"): every game loop task that took this many ms or more is one console line with the Lua script and line, the database queries and the collector's sweep that took the time. On, it costs about 1 us per Lua call (well under 1% of the game loop at 200 online) |
| `loginPrefetch` | true (not set: true) | the login scripts' reads run on the login worker's own connection before the login (engine patch 0031, `server/README.md` "Login reads off the game loop"); answered from those rows only when the text is the same and no write reached a table they read since. `false` reads everything on the game loop as before. Read at startup |
| `rateSpawn` | 3 | how many monsters one spawn brings back per check (stock 1: a pack of five took five spawntimes to refill). The timers themselves are in the spawn file (install step `spawns`); engine patch 0022 lets `respawn.lua` shorten them where several players hunt together (`server/README.md` "Spawn density and respawn"). Without patch 0022 the console prints one `[ChaosRespawn]` line and the stock timers apply |

The tool refuses to run while `mapName` is a cropped test map (`zcrop_*`): set the real map name first.
Rates stay as the download has them: `rateExp` is not used (experience stages, written by `late_game.py`),
`rateSkill = 3`, `rateMagic = 2`, `rateLoot = 1`. `maxPacketsPerSecond` (50) is the engine's flood limit per connection.

Also check by hand:
- `freePremium` (false in the download): premium gates spells, items, outfits and the autoloot list size.
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
- `chaos.logrotate`: daily, 14 days, compressed, `copytruncate` (systemd keeps the files open).
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
  `/pact` (all but `info`); so do the admin panel's Economy and Store categories and its Give item / Create item.
  `/classunlock`, `/worldboss`, `/siege`, `/newplayerkit` and `/towerrun` are open to every group with access (4+);
  `/goblin`, `/blessing`, `/season start|end`, `/seasonpass` and `/journey` need a god account (type 5). Every staff
  use of a guarded command goes to the admin audit log. Who may do what, and the rules for staff:
  [docs/GM_HANDBOOK.md](GM_HANDBOOK.md) (draft).
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
  It only runs when started by hand, never on pushes or pull requests.
- Ship the client with the merged 10.98 `Tibia.dat` / `Tibia.spr` in `data/things/1098/`.
- Client updates after launch: the signed updater (section "Client updates" below). Turn it on in the package
  (`windows-package.yml` inputs `update_manifest` and `update_public_key`) before the first public download.

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
| Staff talkactions | every `/` command checks the group's access flag (`/goblin`: gods, admin panel and `/testkit`: group 4+); `/coins`, `/charm give` and `/pact` (all but `info`) need group 5 (`Chaos.staffCommand`, `Chaos.economyMinGroup`), every use in the admin audit log | safe (`tests/staff_permissions_test.lua`) |
| `clientservices.py` | no socket timeout (an idle connection held a thread); a negative `Content-Length` blocked a thread | **fixed** |
| Test servers' `zz_test_lua.lua` | `/lua` runs any Lua for any player | never ship (section 11) |

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

## 12. Open loose ends that matter for launch (ROADMAP.md)

Still open:
- **The beta weekends.** The plan, the wipe before launch and the test focus per weekend: [docs/BETA.md](BETA.md)
  (draft, every decision marked "Owner decides"). Most of the open items below are on its test list.
- Not run with a real group yet: rifts, Omens and the Ascended bosses with a full party, the Ashen Sepulchre raid, the
  Ember Descent with 2-4 players, the battleground at 5v5 and up, party credit for bounties and the bestiary.
- Keystones not verified in game: Overgrowth, both Illusionist keystones (need a party), arrow Ricochet, and the
  visuals of Bulwark / Thorns / Deadeye. The weapon (auto-attack) numbers in `server/data/spells/README.md` need a
  re-measure (ROADMAP "Open decisions").
- The class lines: the Necromancer, Monk and Templar are tested in game (phase B) and stay behind the store's class
  unlock; their price (750 Chaos Coins) is a placeholder (docs/OWNER_TODO.md). C2 / C3 polish and the C4 outfits and
  effects are still in progress (ROADMAP).
- The community (Discord) link is empty (`ChaosTopBar.COMMUNITY_URL`, the website's Discord invite).
- Staff rules, bans and mutes: [docs/GM_HANDBOOK.md](GM_HANDBOOK.md) (draft, decisions for the owner).

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
5. Remove every test-only file (section 11).
6. systemd units, logrotate, firewall (section 5); start; read the log: no `Lua Script Error`.
7. Create the staff account and characters; log in with the release client; check the login screen (boosted creature,
   events, players online), a store purchase, a crafting orb, the bank, the stash.
8. Website: character creation with the class lock (section 6). Donations: the sandbox test of "Donations" below, then
   the live credentials.
9. Backups: run `chaos-backup.service` once, check the off-site copy, do the restore drill (section 7).
   Alerts: `chaos_health.py --test-alert`, then `--dry-run` shows every check `ok` (section 9).
10. `maxPlayers` 400 (section 3; load test on the full map in section 9); `loadtest.py cleanup` if bots were run.
11. Open the firewall ports, announce.

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
2. It started after an update: roll the update back (`git -C /opt/chaos/repo checkout <last good commit>`, run
   `install_all.py` again, or restore the data archive of section 7), then `systemctl restart chaos-server`.
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

**Mail** (account recovery links, website 2FA codes; `website/README.md` "Mail"): fill `CHAOS_SMTP_HOST`,
`CHAOS_SMTP_PORT` (587), `CHAOS_SMTP_TLS` (`starttls`), `CHAOS_SMTP_USER`, `CHAOS_SMTP_PASSWORD` and `CHAOS_MAIL_FROM`
(e.g. `no-reply@<your domain>`) in `site.env` and run the installer again. Add the SPF, DKIM and DMARC records of the
From domain first. Check: ask for a recovery link for your own account; it arrives (not in spam), the link opens the
password form once, and the headers show `spf=pass dkim=pass dmarc=pass`. Without `CHAOS_SMTP_HOST` the site runs
without mail and the recovery page says recovery by e-mail is not available.

## Donations (Pix / PayPal)

Chaos Coins are a thank-you for a **voluntary donation**: nobody is required to donate and the game is fully playable for
free. The client (Store > Donate) and the website (`page.php?plugin=chaos&p=coins`) say so in English and Portuguese
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
- Publish a refund policy (Rules page): a refund or chargeback after the coins were credited takes back the coins still
  unspent (`removeCoinsOnReversal` in `shop_coins_config.lua`) and staff see it in the admin panel (Store > Donations:
  refunds and chargebacks).
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

## Client updates (signed updater)

The client checks the website for a signed manifest before login and downloads changed modules, images, fonts and
the dat/spr pair (client/MANIFEST.md "Signed updater"; files on the site: website/README.md "Client updates").
The exe and its DLLs are never updated this way: a new exe is a new Windows package (below).

**Keys (once).** On the operator's own machine, never on the game or web server and never in the repository:

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
3. Publish: `CHAOS_UPDATE_KEY=~/chaos-keys/update.key python3 -I client/tools/make_update_manifest.py build <client>
   --out <CHAOS_SITE_DIR>/updates/live` (or `--out` to a local folder and rsync it up: blobs first, `manifest.json`
   last). The version goes up by one each time; clients refuse an older manifest.
4. Check: `python3 -I client/tools/make_update_manifest.py verify <CHAOS_SITE_DIR>/updates/live --public <hex>`.
5. Start a client: it says "Update applied" and restarts, or "Your client is up to date".

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

**Production is HTTPS.** The updater warns in the client log when the manifest URL is plain HTTP;
`client/tools/serve_updates.py` (HTTP, local) is only for tests.

