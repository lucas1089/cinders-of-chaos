# Open beta plan (draft for the owner)

Status: **draft, nothing here is decided.** Every choice is marked **Owner decides**, with a recommendation. The dates
are the proposal of docs/OWNER_TODO.md and are not confirmed. All times are UTC-3 (`America/Sao_Paulo`, the server's
timezone; docs/OWNER_TODO.md "On the live server").

Related: docs/LAUNCH.md (install, backups, launch day), docs/GM_HANDBOOK.md (staff rules), ROADMAP.md (what is open),
server/README.md "Patch notes" (the notes players see).

## 1. Dates and times

**Owner decides.** Recommendation:

| When | What |
|---|---|
| Fri 30 Oct, 20:00 | Beta server up for staff only (`/closeserver` state or the admin panel's Server > Open / close). Smoke test: log in, store, crafting orb, bank, stash, a rift. |
| **Sat 31 Oct, 15:00** | **Beta weekend 1 opens.** The Open Beta patch note (`server/data/patchnotes/2026-10-31.md`) opens at every first login. |
| Sun 1 Nov, 06:00 | Daily server save and restart (as every day). |
| Sun 1 Nov, 23:00 | Weekend 1 closes (server closed for players, staff stay). |
| Mon 2 Nov to Fri 6 Nov | Fixes. A short patch note for weekend 2 (`2026-11-07.md`). Characters are kept between the weekends. |
| **Sat 7 Nov, 15:00** | **Beta weekend 2 opens.** |
| Sun 8 Nov, 23:00 | Weekend 2 closes. Final beta backup. |
| Mon 9 Nov to Tue 17 Nov | Fixes, the release client package, load test on the full map. |
| Wed 18 Nov | **Wipe** (section 9), then the launch install (docs/LAUNCH.md section 13). |
| Thu 19 Nov | Staff dress rehearsal on the wiped database: the launch-day checks of docs/LAUNCH.md section 13. |
| **Fri 20 Nov, 15:00** | **Launch.** Launch patch note (`2026-11-20.md`). Season 1 starts (section 5). |

Notes:
- Both beta weekends fall on Blood Moon days (Saturday and Sunday, +50% experience, `Chaos.events`). Leveling speed seen
  in the beta is about 1.5x a weekday. Owner decides: keep it (recommended: it is the real weekend game) or turn the
  event off on the beta server.
- Fixed weekend events to watch: the guild siege (Saturday 20:00), the world boss slots (03:00, 09:00, 15:00, 21:00;
  entry level 300+), the Sunday invasion (17:30), the weekly reset (Monday 06:00, after weekend 1 and weekend 2).

## 2. Who can join

**Owner decides.** Recommendation: an **open beta**. Anyone makes an account on the website and plays with the official
client (the client guard is on, `clientGuardMode = "enforce"`, docs/LAUNCH.md section 3).
- `maxPlayers` 300: run `prod_config.py` with `--max-players 300` on the beta server (decided 2026-10-12; docs/LAUNCH.md
  section 3). The full-map load test (docs/LAUNCH.md section 9, server/README.md "Load test on the full map") filled the
  game loop at 500-600 bots; the beta keeps it under half busy. Launch: 400 (the `prod_config.py` default).
- The normal rules apply: two characters per IP (`multiclient.lua`), the Rules page, reports and bans (docs/GM_HANDBOOK.md).
- The website's register guard, reCAPTCHA keys and SMTP must be live (docs/OWNER_TODO.md "Accounts and services").
- Alternative: a closed beta with invitations. Nothing in the code issues invitations, so it would be a manual list of
  accounts, and the load test would see fewer players. Not recommended.

## 3. What is wiped at launch

**Owner decides.** Recommendation: **characters, items, gold, Chaos Coins and the market are wiped; accounts are kept.**

| Wiped | Kept |
|---|---|
| every character and everything on it: level, skills, items, depot, inbox, storages, spells, deaths | accounts (name, password, e-mail) and the website's account rows |
| houses (owners, items, access lists) | account bans and their history (**Owner decides**; recommendation: keep them) |
| guilds, guild halls, guild banks, guild wars | the admin audit log (`chaos_admin_log`) |
| every `chaos_*` table with game progress: bank stars, stash, market, Orb Exchange, store coins and purchases, the Chaos Pact, cosmetics, transmog, exclusives, class unlocks, achievements, seasons, leaderboards, ratings, reports, ... | the patch notes "seen" state and auto-open setting (`chaos_patchnotes`; the launch note is newer, so it opens anyway) |
| premium time (the Chaos Pact grants premium days, bought with beta coins) | referral codes (`chaos_referral_codes`; codes shared during the beta keep working) |
| the season, community, world buff and leaderboard state rows of `server_config` | the other `server_config` rows (one-time migrations and index builds) |

Why: beta coins and items were free or bought with free coins, and the beta found balance bugs; keeping them would
put beta players ahead at launch. Keeping accounts saves everyone a new sign-up.
- Account-wide unlocks bought with beta coins (class unlocks, cosmetics, depot tabs, Pact extras) are wiped too.
- Accounts made in the beta are older than the referral program's 7-day entry window at launch, so they cannot enter a
  referral code any more (server/README.md "Referral program").
- A thank-you for testers (a title or a cosmetic for accounts that played the beta) is not built. **Owner decides**;
  if wanted, it needs a small script that reads the final beta backup.

## 4. Store and donations in the beta

**Owner decides.** Recommendation: **payments off, test coins from staff.**
- Website `/etc/chaos/payments.env`: `CHAOS_PAY_PIX_PROVIDER=off` and `CHAOS_PAY_PAYPAL_PROVIDER=off`. On the beta server's
  copy of `shop_coins_config.lua`, also `payments.methods.pix.enabled = false` and `paypal.enabled = false`: a method
  switched off there is hidden in the client and on the website. Never the `mock` provider on a public server: it
  approves every donation by itself.
- Test coins: one grant per account at the start of each weekend, announced in the patch note and on Discord, so
  everyone can try the store, the Pact and the coin side of the market. An administrator (group 5+) runs, with the
  server online:
  ```sql
  -- every account up to 5,000 Chaos Coins (never lowers a balance)
  INSERT INTO chaos_shop_coins (account_id, coins) SELECT id, 5000 FROM accounts
    ON DUPLICATE KEY UPDATE coins = GREATEST(coins, 5000);
  ```
  Single corrections: `/coins <character>, <amount>` (group 5+, written to the admin audit log) or the admin panel's
  Store > Give Chaos Coins. The amount (5,000) is **Owner decides**.
- Say it everywhere: beta coins are not real and are wiped at launch.
- Alternative: real donations in the beta. Then the coins of paid orders must survive the wipe (section 9 would keep
  `chaos_shop_coins`, `chaos_coin_orders` and `chaos_coin_payments` for those accounts), the live payment setup must be
  done by 31 Oct (docs/LAUNCH.md "Donations"), and the prices are still placeholders. Not recommended.
- The sandbox run of docs/LAUNCH.md "Donations" step 6 can still be done on the beta server, with sandbox credentials,
  outside the beta hours.

## 5. Season 1 and the PvP seasons

`server/data/scripts/chaos/season_config.lua` has Season 1 (Season of Ash) from 1 Nov 2026 12:00 to 31 Jan 2027: it
would start in the middle of beta weekend 1.

**Owner decides.** Recommendation: Season 1 starts **with the launch, Fri 20 Nov 15:00**, and keeps its 13 weeks (the
season pass is sized for 13 weeks, `seasonpass_config.lua`). Change, before 31 Oct:

```lua
seasons = {
	{
		id = 1,
		name = "Season of Ash",
		tag = "[S1]",
		start = 20261120,  -- was 20261101
		finish = 20270219, -- was 20270131 (13 weeks after the start)
		hour = 15,         -- was 12; server local time (UTC-3)
		...
```

- The dates are read at startup; `/season start [id] | end | status` (god accounts) overrides them in `server_config`
  (`chaos_season_1_start` / `_end`). To test season characters in the beta, start it by hand on weekend 2
  (`/season start 1`); the wipe deletes those rows and every season table, so Season 1 starts clean at launch.
- PvP seasons (arena and battleground, `battleground_config.lua` `season.epoch`) count 8-week seasons from Mon 5 Oct
  2026 06:00, so PvP Season 1 would end on 30 Nov, ten days after launch. **Owner decides**; recommendation:
  `epoch = {year = 2026, month = 11, day = 16, hour = 6}` (the Monday before launch, so PvP Season 1 runs 16 Nov to
  11 Jan). The epoch must not lie after the launch: before the epoch the season number is 0. The wipe deletes
  `chaos_pvp_season_done`, so the new server counts from there.
- Infinity Tower seasons (`Chaos.tower` in `chaos_constants.lua`) are their own 30-day cycle, not the realm Season:
  points, milestones and the ranking reset every 30 days and the top 3 get their chests then, while a realm Season
  lasts 13 weeks, has gaps and can be started or ended by hand. The epoch was 1 Jan 2025 (the launch would have been
  Tower Season 22); it is now the launch, Fri 20 Nov 2026 15:00 server time, so Tower Season 1 runs 20 Nov to 20 Dec.
  Before the epoch everything counts as Season 1 (the beta), and the wipe empties `chaos_tower_players` and deletes
  `chaos_tower_season_done`. **Owner decides** if the launch moves: change `seasonEpoch` with it (only on a wiped
  database). `/towerseason` shows the season, its end and the last season paid out.
- Tests: `server/tests/season_test.lua` uses its own config, so these edits do not break it. Run it anyway.

## 6. Feedback channels

**Owner decides** the Discord layout. Recommendation:
- **In game:** System > Report a Bug (the base client's bug report) and right-click > Report Player / System > Report a
  Player (`chaos_reports`, staff see them at once; server/README.md "Anti-bot and player reports").
  - **Checked (12 Oct):** the base server's `Player:onReportBug` handed the report to its stock callback, which
    returned at once for a normal account (no message, nothing stored) and wrote text files under `data/reports/bugs/`
    for the others. The base client also lost the text: it sent the category digit instead (client base patch 0040
    fixes that). Now `server/tools/patch_base_events.py` step 12 (`install_all.py` step `events`) sends every report to
    `reports.lua`: a `chaos_reports` row (reason "bug") with the text, category, position, time and character, a
    confirmation for the player, `/reports list bugs`, the admin panel, the website staff page and the reports webhook
    (server/README.md "Bug reports"; GM handbook section 3). **Test on the beta server:** one bug report from a normal
    account with a client built with patch 0040. The beta patch note can still name Discord for screenshots.
- **Discord** (the link is still empty: docs/OWNER_TODO.md): `#beta-announcements` (read only), `#bug-reports` (one bug
  per message: what, where, when, character name, a screenshot), `#balance-feedback`, `#group-testing` (to find
  parties for the test list below), `#questions`. Set `CHAOS_REPORTS_WEBHOOK` to a staff-only channel for player
  reports and `CHAOS_ALERT_WEBHOOK` for crash alerts (docs/LAUNCH.md section 5).
- **After each weekend:** a short survey (class played, level reached, what felt bad, would you play at launch).
- Staff triage once a day: each bug gets a severity (crash or dupe, blocks play, wrong, cosmetic) and an owner.

## 7. Test focus per weekend

From ROADMAP.md: the systems not yet run with a real party, the keystones of "Open decisions and loose ends", and load.
Beta characters will not reach the endgame in two weekends, so the endgame tests need **prepared characters**.
**Owner decides.** Recommendation: on weekend 2, staff (group 5+) make level 300 and level 1000 test characters for
volunteers on separate test accounts, with the admin panel (Players > Set level, Set skill) and `/testkit` gear, and
the items the content needs (Rift Keys with `/rift key <tier>`, Ascended Sigils with Create item). Those accounts are
wiped like the rest. Their results are a balance test, not a leveling test.

Weekend 1 (31 Oct to 1 Nov): fresh characters, the real start, and load.

| What | How | ROADMAP |
|---|---|---|
| Load and spawn density | many real players at once on the full map; watch the game loop lag, CPU, RAM and the 300-600 hunting areas | #27 (bots: the game loop fills at 500-600; compare real players with it), #89 |
| New player flow | tutorial island, class kits, gifts at 20 / 50, website sign-up, the official client, the updater | #21, #22, #82 |
| Bounty and bestiary party credit | two or more players in a party on one contract / kill task; kills shared within 30 tiles | #10, #35 |
| Rifts with a real party | low tiers with 2-5 players: party scaling (+100% health and +10% damage per extra player), chest bonus per finisher, shared lives, logout and death in a party | #8 |
| The Ember Descent with friends | parties of 2-4, boons and curses per player, the merchant | #59 |
| Keystones | Overgrowth, arrow Ricochet; both Illusionist keystones in a party; the Bulwark / Thorns / Deadeye visuals | "Open decisions": keystones |
| Invasions and world events | the Sunday 17:30 invasion on the real map areas (proposed from the map file, never walked) | #29 |
| Guild siege | Saturday 20:00 with real guilds | #15 |
| Reports and the anti-bot | real false-positive rates in `chaos_antibot_log` | #56 |
| Instance limits | the warnings and the end of a rift, a trial, a tower run and a base lever boss room; every slot of one type busy (the wait and the "your turn" message); a lever room left empty and unlocked after 2 minutes; `/instances` and `/instances close` during the busy hours; the slow task log on while slots are built for the first time | #108 |

Weekend 2 (7 to 8 Nov): groups and the endgame, with prepared characters where needed.

| What | How | ROADMAP |
|---|---|---|
| The Ashen Sepulchre raid | a real group of 5-15: tank swap, soaks, spread, effigies, the hex; lockouts and saved raids | #61 |
| Ascended Omens and the Cinderheart | party fights (2-5) with health scaling, shared lives, phases; kill times against the model | #57 |
| Battleground 5v5 | Ember Wells with 10+ players: matchmaking by role and rating, respawn waves, AFK and deserter rules | #71 |
| Rifts, high tiers and Omens | tier 10-15 with a full party; Omen arenas; the Rift Atlas keystones | #8, #54 |
| Item sets in a group | Ashen Oath and Mirror Grace in a real group run | #68 |
| World boss | a real world boss with healers and tanks: role scores and rewards | #32 |
| Scorched Marches | two factions contesting the Cinder Shrine | #77 |
| Seasons | `/season start 1` (god): join, Self-Found and Hardcore, the journey, the pass; a Hardcore character at the 06:00 restart | #12, #62, #67 |
| Load again | the same measures with more players, if weekend 1 grew the community | #27 |

Each test: a staff member leads it, writes the result (worked / bug numbers) in the beta log, and ROADMAP.md gets the
status update afterwards.

## 8. Known issues to tell players

From ROADMAP.md and server/README.md; put the short list in the patch note or on Discord.
- The rest of the base world still has old names in places: NPC names and dialogue, quests, houses, raid texts
  (ROADMAP "Open decisions": the rename is in progress).
- The three achievement wings (looks 2140-2142) draw nothing until sprite pair things_custom17 is on `windows-assets`
  (docs/OWNER_TODO.md).
- The outfit window lists no shaders (store ones neither); shaders still work from the store and the wardrobe.
- The Necromancer line has no spell effect skins yet.
- Rift monsters keep the corpse of their pool type.
- Dungeon difficulty changes nothing in the dungeon. (The Infinity Tower season-end top 3 chests are paid since
  12 Oct: server/README.md "Infinity Tower season rewards".)
- Occupied towns do not raise NPC prices yet (invasions).
- Rift Keys cannot be stashed (they do not stack).
- The weapon (auto-attack) numbers are being re-measured; class balance may move between the weekends.
- The Discord link in the client is empty until the server is created (`ChaosTopBar.COMMUNITY_URL`).

## 9. Wipe procedure

**Owner decides** what is kept (section 3). The procedure below follows the recommendation. Run it as root on the game
server, after weekend 2 and before the launch install. Read it to the end first.

**1. Close and stop.** Announce 30, 10 and 1 minutes before (the admin panel's Server > Shutdown has a countdown).

```
sudo systemctl stop chaos-server        # saves every player, ends rifts and other runs cleanly, then stops
```

**2. The final beta backup, kept for good.** `backup.sh` keeps 14 days (`CHAOS_BACKUP_KEEP_DAYS`); this one must outlive
that. The engine is stopped, so no `--save-service`.

```
sudo bash -c 'set -a; . /etc/chaos/chaos.env; set +a; /opt/chaos/repo/server/tools/backup.sh --server-dir /opt/chaos/server'
ls -t /var/backups/chaos/db | head -1                    # the dump just written
sudo install -d -m 0700 /var/backups/chaos-beta-final
sudo cp /var/backups/chaos/db/<that file> /var/backups/chaos/data/<newest archive> /var/backups/chaos-beta-final/
```

Copy it off the machine too: `backup_offsite.sh` sends the newest dump and data archive (docs/LAUNCH.md section 7
"Off-site copy"; it deletes remote copies after `CHAOS_BACKUP_REMOTE_KEEP` days, so keep one more copy outside that
target as well). Restore it into a scratch database once to prove it (docs/LAUNCH.md section 7 "Restore drill"). It
holds the beta's reports, anti-bot log and every character, for later questions and any tester reward.

**3. Review the tables.** The base download may have tables of its own systems. List every table with a character or
account column:

```
set -a; . /etc/chaos/chaos.env; set +a
mysql "$CHAOS_DB_NAME" <<'SQL'
SELECT table_name, GROUP_CONCAT(column_name) AS columns FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND column_name IN ('player_id', 'player_guid', 'guid', 'owner', 'owner_id', 'account_id', 'accountid')
GROUP BY table_name ORDER BY table_name;
SHOW COLUMNS FROM accounts;
SQL
```

Any table in that list that steps 4-6 do not cover and that holds per-character progress is wiped too (add a `DELETE`
for it); per-account settings may stay. Note the premium column name of `accounts` for step 5.

**4. Chaos tables.** Write the list, read it, then run it:

```
mysql -N "$CHAOS_DB_NAME" > /root/chaos-wipe.sql <<'SQL'
SELECT CONCAT('TRUNCATE TABLE `', table_name, '`;') FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_name LIKE 'chaos\_%'
  AND table_name NOT IN ('chaos_admin_log', 'chaos_patchnotes', 'chaos_referral_codes')
ORDER BY table_name;
SQL
less /root/chaos-wipe.sql
(echo 'SET FOREIGN_KEY_CHECKS = 0;'; cat /root/chaos-wipe.sql; echo 'SET FOREIGN_KEY_CHECKS = 1;') | mysql "$CHAOS_DB_NAME"
```

**5. Base tables, the website and `server_config` rows.**

```
mysql "$CHAOS_DB_NAME" <<'SQL'
SET FOREIGN_KEY_CHECKS = 0;
-- characters and what hangs off them (most also go by ON DELETE CASCADE; explicit to be sure)
DELETE FROM player_items;
DELETE FROM player_depotitems;
DELETE FROM player_inboxitems;
DELETE FROM player_storage;
DELETE FROM player_spells;
DELETE FROM player_deaths;
DELETE FROM player_namelocks;
DELETE FROM account_viplist;
DELETE FROM players_online;
DELETE FROM guild_invites;
DELETE FROM guild_membership;
DELETE FROM guild_ranks;
DELETE FROM guildwar_kills;
DELETE FROM guild_wars;
DELETE FROM guilds;
DELETE FROM players;
-- houses: no owner, no bids, no items, no access lists
UPDATE houses SET owner = 0, paid = 0, warnings = 0, bid = 0, bid_end = 0, last_bid = 0, highest_bidder = 0;
DELETE FROM house_lists;
DELETE FROM tile_store;
-- the stock market (off on this server; emptied anyway)
DELETE FROM market_offers;
DELETE FROM market_history;
-- premium time (the column of step 3; TFS 1.4: premium_ends_at; older schemas: premdays and lastday)
UPDATE accounts SET premium_ends_at = 0;
-- the website's character rows (ZnoteX)
DELETE FROM znote_players;
-- state rows of the beta world; the other chaos_* rows (migrations, index builds) stay
DELETE FROM server_config
WHERE config LIKE 'chaos\_season\_%' OR config LIKE 'chaos\_worldbuff\_%'
   OR config IN ('chaos_community_override', 'chaos_leaderboard_reset', 'chaos_pvp_season_done',
                 'chaos_tower_season_done');
SET FOREIGN_KEY_CHECKS = 1;
SQL
```

A statement that fails because its table or column does not exist in this base schema can be skipped; check step 3's list
for the right name. Account bans (`account_bans`, `account_ban_history`, `ip_bans`) stay unless the owner decides
otherwise.

**6. Check.**

```
mysql "$CHAOS_DB_NAME" -e "SELECT COUNT(*) FROM players; SELECT COUNT(*) FROM accounts; SELECT COUNT(*) FROM chaos_shop_coins; SELECT COUNT(*) FROM houses WHERE owner <> 0;"
```

Expect 0, the number of accounts, 0, 0.

**7. Launch install.** Update the repository to the launch commit, set the Season 1 and PvP dates (section 5), put the
launch note into `server/data/patchnotes/`, run `install_all.py` (docs/LAUNCH.md section 4: dry run, real run, a second
run with 0 changes), remove every test-only file (docs/LAUNCH.md section 11, also any beta test characters' accounts),
start the server and read the log. Staff then make their characters on the website and set their group:

```
mysql "$CHAOS_DB_NAME" -e "UPDATE players SET group_id = 4 WHERE name = '<gamemaster character>';"
```

(group 5 or 6 the same way; god accounts also need `accounts.type = 5`, which the wipe kept). Then the dress rehearsal
of docs/LAUNCH.md section 13.

## 10. Staff schedule

**Owner decides** the names and hours. Recommendation: at least one gamemaster online whenever the beta is open, an
administrator reachable, and a developer on call for hotfixes. Roles are those of docs/GM_HANDBOOK.md.

| Slot (UTC-3) | Gamemaster (group 4) in game | Administrator (group 5) | Developer on call | Fixed events |
|---|---|---|---|---|
| Sat 15:00-19:00 | GM 1 | Admin 1 | Dev 1 | opening; world boss 15:00 |
| Sat 19:00-23:00 | GM 2 | Admin 1 | Dev 1 | guild siege 20:00; world boss 21:00 |
| Sat 23:00-03:00 | GM 3 | Admin 2 (reachable) | Dev 2 (reachable) | |
| Sun 03:00-09:00 | none in game; reports by webhook | Admin 2 (reachable) | Dev 2 checks the 06:00 restart log | world boss 03:00, 09:00; server save 06:00 |
| Sun 09:00-15:00 | GM 1 | Admin 1 | Dev 1 | |
| Sun 15:00-19:00 | GM 2 | Admin 1 | Dev 1 | world boss 15:00; invasion 17:30 |
| Sun 19:00-23:00 | GM 3 | Admin 2 | Dev 2 | world boss 21:00; closing at 23:00 |

The same grid for weekend 2. Group tests of section 7 are booked into these slots and announced on Discord a day ahead.
Every shift ends with a handover note: open reports, bugs found, players to watch.
