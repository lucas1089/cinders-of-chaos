# Launch checklist: from the stock downloads to a public Project Chaos server

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

To play it on one Windows PC first, without any of this: run the **Windows package** workflow (Actions -> Windows
package -> Run workflow) and download the `ProjectChaos-Windows` artifact from the run. It holds the patched engine
(`ChaosServer.exe`), the Chaos client, the merged dat/spr, a portable MariaDB and `start-server.bat` /
`start-client.bat` (`tools/windows/package/README.txt`). Its inputs live on the private branch `windows-assets`
(its README.md); `tools/windows/prepare_server.sh` turns the base server into the package's server folder. It has
test accounts with known passwords: local play only.

## 1. Engine

1. Build the engine from the base sources with our patches applied, in the source root:
   `patch -p1 < server/src-patches/0001-critical-hit-to-lua.patch` and
   `patch -p1 < server/src-patches/0002-dual-wield-and-vocation-attack-speed.patch`, then the usual CMake build.
   The Windows binary in the download has neither patch (no "CRIT!" visual, no off-hand sword for the Ninja).
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
sudo cp server/deploy/chaos.env.example /etc/chaos/chaos.env      # fill in CHAOS_DB_* (never commit it)
sudo chmod 600 /etc/chaos/chaos.env
python3 -I server/tools/prod_config.py /opt/chaos/server --ip play.example.org --name Chaos \
    --motd "Welcome to Chaos." --max-players 300 --pvp pvp --save-time 06:00 --owner "..." --url "https://..."
```

`server/tools/prod_config.py` (idempotent; its docstring explains every value) sets:

| Setting | Value | Why |
|---|---|---|
| `ip` | the public DNS name or IP | the login server hands it to the client; 127.0.0.1 only works on the machine itself |
| `loginProtocolPort` / `gameProtocolPort` / `statusProtocolPort` | 7171 / 7172 / 7171 | the stock ports (the test servers use 74xx) |
| `serverName`, `motd`, `ownerName`, `ownerEmail`, `url`, `location` | ours | the download ships its own name and someone else's contact data |
| `maxPlayers` | e.g. 300 | 0 means unlimited; pick a number from the load test (section 9) |
| `worldType` | `pvp` (or `no-pvp`, `pvp-enforced`) | the arena and the guild siege never use real deaths, so they work in every type |
| `allowClones`, `onePlayerOnlinePerAccount` | false, false | the multi-client rules live in `multiclient.lua` (2 characters per IP; the second cannot attack players or enter dungeons) |
| `serverSaveShutdown` | **true** (kept) | the daily save shuts the engine down; systemd starts it again (section 5), so each day starts with a fresh process |
| Server Save time | `--save-time 06:00` | `data/globalevents/globalevents.xml`; the download uses 08:00. Keep the backup timer 15 minutes after it |
| `mysqlHost` ... `mysqlDatabase` | `os.getenv("CHAOS_DB_*") or ...` | the engine runs `config.lua` as Lua, so the credentials come from `/etc/chaos/chaos.env`; no password in any file of the repo or the server folder |
| `startupDatabaseOptimization`, `showScriptsLogInConsole` | false | faster start, quieter console |

The tool refuses to run while `mapName` is a cropped test map (`zcrop_*`): set the real map name first.
Rates stay as the download has them: `rateExp` is not used (experience stages, written by `late_game.py`),
`rateSkill = 3`, `rateMagic = 2`, `rateLoot = 1`. `maxPacketsPerSecond` (50) is the engine's flood limit per connection.

Also check by hand:
- `freePremium` (false in the download): premium gates spells, items, outfits and the autoloot list size.
- `passwordType = "sha1"`: the website must hash passwords the same way.
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
9. `spells`: `register_spells.py`, then the class hook (every `server/tools/install_class_*.py`), then
   `rename_spells.py --sql`
10. `autoloot`: the stock XML `!autoloot` talkaction is commented out (autoloot.lua's own one refreshes the window)
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
        server/deploy/chaos-backup.service server/deploy/chaos-backup.timer /etc/systemd/system/
sudo cp server/deploy/chaos.logrotate /etc/logrotate.d/chaos
sudo systemctl daemon-reload
sudo systemctl enable --now chaos-server chaos-clientservices chaos-backup.timer
```

- `chaos-server.service`: `Restart=always` brings the engine back after the daily save (which shuts it down on
  purpose) and after a crash. `systemctl stop` sends SIGTERM: the engine saves and shuts down (180 s allowed).
  `systemctl kill -s SIGUSR1 chaos-server` saves without stopping. The console goes to `/var/log/chaos/server.log`.
- `chaos-clientservices.service`: the login-screen endpoint (`server/tools/clientservices.py`, port 8090) that serves
  `data/chaos_clientservices.json`, which the game server rewrites every 5 minutes.
- `chaos.logrotate`: daily, 14 days, compressed, `copytruncate` (systemd keeps the files open).

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

## 6. Accounts, staff and the website

- **Characters are created on the website** (the base server has no in-game account manager). The website must:
  - offer only the base classes: Warrior 4, Ranger 3, Mystic 1, Thief 11; the ascended classes come from `!ascend`;
    the retired ids 2, 6 and 9 never;
  - offer the **locked classes** (Necromancer 20, Monk 17, Templar 23; ids in `docs/CLASSES.md`) only to accounts that
    have a row in `chaos_class_unlocks` for that class (`class_key` necromancer / monk / templar). The server enforces
    the lock anyway at login (`class_unlocks.lua`: the character is restricted or logged out), so a website that gets
    this wrong produces unplayable characters, not a bypass;
  - create level 1 characters with `lastlogin = 0` and no starting items: the server gives the class kit and runs
    the tutorial island at the first login (`newplayer*.lua`);
  - hash passwords with SHA-1 (`passwordType`), and never show or log them.
  The website in `website/` (being built at the time of writing) has a Chaos plugin that reads `chaos_class_unlocks`;
  check its character creation against this list before launch.
- **Staff**: group 4 (gamemaster) to 6 (god) on `players.group_id`, account type 5 for gods. The admin panel (opcode 120)
  needs group 4+, some actions more. Staff characters are left out of every leaderboard (`staffGroup = 4`).
  Use a separate staff account; `/coins` (Chaos Coins), `/classunlock`, `/worldboss`, `/siege`, `/newplayerkit` and
  `/towerrun` are open to every group with access (4+), `/goblin` to gods only.
- Start from a **fresh database**: the test databases have accounts with known passwords (`test`, `test2`, ...).

## 7. Backups

`server/tools/backup.sh` (tested against the test database: dump, data archive, retention, restore):
- asks the engine to save (`--save-service chaos-server`: SIGUSR1, then 15 s),
- `mysqldump --single-transaction` of the game database, gzip, `DIR/db/chaos-db-<db>-<timestamp>.sql.gz`, checked with
  `gzip -t` and mysqldump's "Dump completed" line,
- `config.lua` + `data/` (without the map and logs) as `DIR/data/chaos-data-<timestamp>.tar.gz`, only when it changed,
- removes files older than `CHAOS_BACKUP_KEEP_DAYS` (14), always keeping the newest dump.

`chaos-backup.timer` runs it at 00:15, 06:15 (15 minutes after the daily save), 12:15 and 18:15. Cron instead:
`15 0,6,12,18 * * * root set -a; . /etc/chaos/chaos.env; /opt/chaos/repo/server/tools/backup.sh --save-service chaos-server >> /var/log/chaos/backup.log 2>&1`

Copy `/var/backups/chaos` off the machine as well (rsync or object storage): a backup on the same disk does not survive
the disk.

**Restore**:
```
sudo systemctl stop chaos-server                      # saves, then stops
set -a; . /etc/chaos/chaos.env; set +a
mysql -e "DROP DATABASE $CHAOS_DB_NAME; CREATE DATABASE $CHAOS_DB_NAME"      # as a user that may do this
zcat /var/backups/chaos/db/chaos-db-<db>-<timestamp>.sql.gz | mysql "$CHAOS_DB_NAME"
# only if the server folder is lost or damaged (the map .otbm is not in the archive: copy it from the download):
sudo tar -C /opt/chaos/server -xzf /var/backups/chaos/data/chaos-data-<timestamp>.tar.gz
sudo systemctl start chaos-server
```
Test a restore into a scratch database once before launch (the dump of the test database restored with the same tables
and rows).

## 8. Client

- Linux: `client/LINUX.md`. Windows: the manual workflow **Windows client** (`.github/workflows/windows-client.yml`,
  Actions -> Windows client -> Run workflow). It fetches the base client sources (input `base_repo` / variable
  `CHAOS_BASE_CLIENT_REPO`, pinned with `base_ref` / `CHAOS_BASE_CLIENT_REF` to the commit the patches were made
  against), applies `client/base-patches/*` and the overlay with `client/tools/assemble_client.sh`, builds with MSVC +
  vcpkg (x64-windows-static) and uploads `Chaos.exe` and a runnable folder. Set `server_host` to the public host.
  It only runs when started by hand, never on pushes or pull requests.
- Ship the client with the merged 10.98 `Tibia.dat` / `Tibia.spr` in `data/things/1098/`.

## 9. Monitoring

- `systemctl status chaos-server chaos-clientservices`, `systemctl list-timers chaos-backup.timer`.
- The console log: `grep -c "Lua Script Error" /var/log/chaos/server.log` after every restart and every update; a new
  error is a bug. The known base server noise on the full map is listed in the first-start log; keep a copy of it to
  compare against.
- Players online: the status protocol on 7171, e.g.
  `python3 -c "import socket;s=socket.create_connection(('127.0.0.1',7171));s.send(b'\x06\x00\xff\xffinfo');print(s.recv(4096))"`
  (XML with `<players online=...>`), or `data/chaos_clientservices.json` (`cacheinfo`).
- Freshness checks for an external monitor: `data/chaos_clientservices.json` changes every 5 minutes; the newest file in
  `/var/backups/chaos/db` is younger than 7 hours; free disk space; the MariaDB process.
- Load: `server/tools/loadtest.py` (bots over the real protocol) with the TEST ONLY probe `server/tools/loadtest_probe.lua`.
  Measured on the test server (cropped map, so no monsters; the real map adds spawn and monster AI work): 30 bots walking
  every second and talking every 20 s took 4.5 % of one core (p95 7.9 %), the engine stayed at 192 MB RSS, and the
  game loop lag stayed at the idle level (about 53 ms on a 50 ms timer; max 122 ms); 30 bots walking 4 steps per
  second and talking every 3 s: 7.0 % (max 11 %). Logins took 0.5 s (p95 1.2 s). Run it again on the full map with
  50-100 bots before setting `maxPlayers`.

## 10. Security review (launch)

What was read: every `db.query` / `db.storeQuery` / `db.asyncQuery` / `Chaos.select` of `data/scripts/chaos` (157
call sites), every extended-opcode handler, every talkaction, and the item paths of stash, bank, loot filter (click to
loot), autoloot, crafting, store, auto seller, loot pouch, daily reward, tower milestones, bounty and rifts.

| Area | Finding | Result |
|---|---|---|
| SQL, all modules | strings from players (names, titles, keys, reasons) go through `db.escapeString`; numbers are engine ids (guid, account id) or pass `Chaos.toInt` / `%d` | safe |
| Admin panel (opcode 120) | admin check on every message, group per action, typed and bounded parameters, 150 ms throttle, audit log | safe |
| Stash (opcode 110) | **a floor item of a house could be stashed, i.e. taken, from outside the house through the wall** (`Item:remove` skips the engine's house rule); not movable map items were accepted | **fixed** (`stash.lua`, test `server/tests/security_test.lua`) |
| Stash, dungeons, crafting, store | list / history / state requests read the database or walk the backpack on every packet | **fixed**: per-player rate limits (`ratelimit.lua`) |
| Dungeons (opcode 109) | **queueing in a fight teleported the player out of it** (no protection-zone rule by design) | **fixed**: refused while in a fight or protection-zone locked, checked again on every queue tick (test) |
| Bank (opcode 60) | amounts `Chaos.toInt` 1..2e9; balance checked before every change; stars charged only for what was handed over | safe; a rate limit is proposed (the file was being changed by the seasons work) |
| Loot filter click to loot (238) | the kill record belongs to the requester, corpse owner / party, reach, item signature; a split stack goes back or is lost, never doubled | safe |
| Crafting (232) | backpack path validated, orb counted before and removed after the roll, 250 ms between orbs | safe |
| Store (218) | offer by index with title + cost echo, owned check, coins taken with a guarded UPDATE, refund on a failed delivery | safe while only the game spends coins (a website must only add coins) |
| Passive tree, Paragon, respec, build codes (65) | saves and imports validated (known nodes, connected, point cap; Paragon keys, caps, no take-back) | safe |
| Daily, tower milestones, bounty | server-side state decides; rewards all or nothing | safe |
| Party invites (151) | accept only with a pending invitation | safe |
| Leaderboard (229) | the class ladder counts the players ahead on every request | proposed rate limit (file being changed by other work) |
| Staff talkactions | every `/` command checks the group's access flag (`/goblin`: gods, admin panel and `/testkit`: group 4+) | safe; see `/coins` below |
| `clientservices.py` | no socket timeout (an idle connection held a thread); a negative `Content-Length` blocked a thread | **fixed** |
| Test servers' `zz_test_lua.lua` | `/lua` runs any Lua for any player | never ship (section 11) |

Open, decide before launch:
- Rifts refund the key after any restart during a run (`rift.lua` crash marker), the daily save restart included: a
  run opened just before the save keeps its loot and gets the key back. Either clear the markers in an `onShutdown`
  global event (only a real crash refunds) or refuse to open a rift in the last 10 minutes before the save.
- `/coins` is open to every group with access (gamemasters included); restrict it to gods if gamemasters should not mint
  Chaos Coins.

## 11. Never ship (test only)

Check the server folder before the first start (`ls data/scripts data/scripts/talkactions data/monster/monsters`):
- `ztest/` in the server root and every `data/scripts/zz_*` / `data/scripts/talkactions/zz_*` file of the test servers,
  above all **`zz_test_lua.lua`: `/lua <code>` runs any Lua for any player, no access check at all**;
  `zz_balance_harness.lua`, `zz_ztest_arena_startup.lua`, a copy of `server/tools/loadtest_probe.lua`;
- `data/monster/monsters/ztest_chaos_dummy.xml` (and its line in `monsters.xml`);
- the cropped test map: `mapName = "zcrop_..."` (`prod_config.py` refuses it) and its `.otbm`;
- test switches, all off by default; never set them on the live server: the global storage
  `Chaos.arenaConfig.testNoPzStorage` (7100345, the arena queue without a protection zone),
  `Chaos.multiClient.offStorage` (7100990, multi-client blocks off), `/leaderboard shift <days>` (moves the leaderboard
  clock; `shift 0` puts it back);
- `admin/testkit.lua` (`/testkit`: gear kits for admins, a balance-test tool): remove it from the live server, or keep it
  only if staff giving themselves gear is accepted;
- the load-test bots: `server/tools/loadtest.py cleanup` removes the `loadbot*` accounts.

## 12. Open loose ends that matter for launch (ROADMAP.md)

- The base client's healing helper replays missed cycles after a client stall and can flood spell casts until the engine's
  packet limit kicks the player; needs a base patch (ROADMAP "Open decisions").
- The base server's rarity element script zeroes damage when a player wears two different rarity elements.
- `/testkit` health refill (`addHealth`) and the toast background are being fixed.
- The class lines C2-C8, seasons, login streaks, patch notes and name plates are in progress: launch with what is done
  and tested, and keep the locked classes locked until they are tested in game.
- Keystones not verified in game (Overgrowth, the Illusionist ones, arrow Ricochet), weapon numbers to re-measure.
- Two world-boss timers (the base server's own and the Chaos one): decide which one runs.
- The community (Discord) link is empty.

## 13. Launch day, in order

1. Fresh database, base schema (section 2).
2. Engine built with the patches (section 1); server folder in `/opt/chaos/server` with the real map.
3. `prod_config.py`, `/etc/chaos/chaos.env` (section 3).
4. `install_all.py --dry-run`, then for real, then once more (0 changes) (section 4).
5. Remove every test-only file (section 11).
6. systemd units, logrotate, firewall (section 5); start; read the log: no `Lua Script Error`.
7. Create the staff account and characters; log in with the release client; check the login screen (boosted creature,
   events, players online), a store purchase, a crafting orb, the bank, the stash.
8. Website: character creation with the class lock (section 6).
9. Backups: run `chaos-backup.service` once, restore the dump into a scratch database (section 7).
10. Load test on the full map, then set `maxPlayers` (section 9).
11. Open the firewall ports, announce.
