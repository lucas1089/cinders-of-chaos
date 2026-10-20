# Gamemaster handbook

Status: **decided** (2026-10-12). The owner adopted the recommended staff rules; they are written below as the rules.
The public part (offences and penalties, appeals) is on the website's Rules page and in the Terms of Use
(docs/legal/). The facts about groups and commands come from the code: the admin panel (`server/data/scripts/chaos/admin/`, its
README.md), `Chaos.staffCommand` in `chaos_constants.lua`, and each system's talkaction. When the code changes, this
file follows.

Related: docs/LAUNCH.md section 6 (staff accounts) and section 11 (never ship), docs/BETA.md (the beta), server/README.md
"Anti-bot and player reports" (Staff guide), "Shared security rules".

## 1. Staff groups

A character's group is `players.group_id`; a god account also has `accounts.type = 5`. Staff use a separate staff
account, never their player account. Staff characters are left out of every leaderboard, season ladder, pass and
community ranking (`staffGroup = 4` in the configs) and are never scored by the anti-bot.

| Group | Name | What it can do |
|---|---|---|
| 1 | player | nothing extra |
| 2, 3 | tutor, senior tutor (base server) | base Help channel tools (`!mute` / `!unmute` inside Help); no `/` commands, no admin panel |
| 4 | **gamemaster** | the admin panel (Admin Panel button in the top bar, or Ctrl+Shift+F12; extended opcode 120): Players (info, kick, ban, unban, mute, set level / skill / vocation, remove item, give premium, teleport, summon, heal, set storage), World (spawn monster / NPC, remove items on a tile, teleport to town, start a raid), Tools (invisible, speed, whitelisted talkactions); most `/` commands (section 2); player reports (`/reports`) |
| 5 | **administrator** (base name: community manager) | everything of group 4, plus the admin panel's Server (broadcast, save, online, stats), Economy (gold, bank, stash, market views), Events, Content, Accounts & Security (account lookup, ban lists, IP ban, sessions, admin log) and Store (sales, donations, give Chaos Coins) categories, Give item, Create item, God mode; the economy commands `/coins`, `/charm give`, `/pact` (all but `info`) and every command that hands out value (section 2) |
| 6 | **god** | everything, plus the admin panel's dangerous actions (reload, shutdown / restart, open / close the server, set group, clean map), Ghost mode, Record a donation |
| account type 5 | god account | `/goblin`, `/blessing`, `/season start / end`, `/seasonpass`, `/journey`; never locked out of a class |

Rules the code enforces: a target of the same or a higher group cannot be touched (except yourself); Set group cannot go
above your own group; every admin panel request (ok, denied or failed) and every use of a guarded `/` command goes to
`chaos_admin_log` (Accounts & Security > Admin log viewer).

**Who holds which group (decided):** gamemasters at 4 for day-to-day work, one or two trusted administrators at 5,
the owner and the lead developer at 6 with god accounts. Few people with power means few mistakes and a short audit.

## 2. Commands

Players type no commands: everything is in the top menu (server/README.md "Player commands: the menu"). Staff `/`
commands are typed in the default channel; for a player those words are plain chat. Group 4+ means a group with the
access flag (gamemaster or higher).

| Command | Who | What |
|---|---|---|
| `/reports`, `/reports list closed\|all\|bugs`, `show <id>`, `score <name>`, `log <name>`, `check <name>`, `close <id>, <text>`, `clear <name>` | 4+ | player reports and the anti-bot (section 3) |
| `/botreview`, `/botreview <name>`, `/botreview mark <name>, reviewed\|false_positive\|escalate\|note[, note]` | 4+ (changing an escalated day: **5+**) | the bot review list, one character's score and signals, a mark (section 3a) |
| `/gmnotify <message>` | 4+ | a toast to every online player |
| `/patchnotes reload\|unseen` | 4+ | read the notes folder now; forget your account's last seen week |
| `/rift status`, `/rift fail` | 4+ | the runs and slots, fail your run |
| `/rift key <tier> [count \| mods]`, `/rift omen`, `/rift fragments` | **5+** | Rift Keys, Omen Keys and fragments for staff test characters |
| `/worldboss start [name\|number\|random]`, `stop`, `arena` | 4+ | the world boss event |
| `/invasion start <area\|random> [faction]`, `stop`, `status`, `schedule <minutes> ...` | 4+ | invasions |
| `/siege start\|match\|end\|stop\|portal\|arena [n]\|signup <guild>\|clear` | 4+ | the guild siege |
| `/arena stop\|slots`, `/bg stop\|slots\|min <n>\|off\|on`, `/marches` | 4+ (`/marches embers`: **5+**) | arena, battleground, Scorched Marches |
| `/raid`, `/descent`, `/ascended`, `/guildboss`, `/trial` | 4+ (`/raid marks`, `/descent sigil`, `/trial tokens`: **5+**) | the instanced content: runs, phases |
| `/ascended sigil\|shards\|relic, <kind>` | **5+** | Ascended test items for staff test characters |
| `/instances`, `/instances <type>`, `/instances close <type> <id>`, `/instances line [type]` | 4+ | every running instance (rift, descent, raid, ascended, guildboss, trials, ascension, tower, dungeon, arena, battleground, worldboss, siege, tutorial, bossroom) with its id, time left, players and idle grace; close one by its system's failure rule (nobody gets a reward, nothing is refunded that a time-out would not refund); who waits in line for a free slot (server/README.md "Instance limits") |
| `/community status\|modifier <key>\|modifier auto\|add <points>\|stage <n>` | 4+ (`add`: **5+**) | the community goal and the weekly modifier |
| `/guild info\|log\|rent\|hall <guild>[, value]`, `/guildwar list\|end, <id>\|expire, <id>` | 4+ | guilds and guild wars (`rent <guild>, paid`: 5+) |
| `/guild xp\|bank <guild>, <value>` | **5+** | guild XP and the guild bank |
| `/classunlock <character>, <class>[, revoke]` | **5+** (revoke: 4+) | a class unlock for the whole account |
| `/cosmetic`, `/exclusive`, `/transmog <character>, <key>[, revoke]` | **5+** (revoke, `/cosmetic ..., sync`: 4+) | grant or revoke account cosmetics; `/exclusive ..., roll` is 5+ too |
| `/faction`, `/professions`, `/pet`, `/gamble`, `/mentor`, `/referral`, `/hideout`, `/achievements`, `/atlas` | 4+ | per-system inspection and test tools (`/pet give`, `/achievements grant\|add`, `/atlas grant`: 5+) |
| `/newplayerkit <name>[, welcome\|milestone <n>\|reset\|tutorial]`, `/towerrun <floors>,<seconds>` | 4+ (the kit, `milestone`, `reset`: **5+**) | new-player kit and tutorial; a fake tower run on yourself |
| `/market sweep\|info <id>\|orders`, `/orbx sweep\|info <id>\|escrow` | 4+ | market and Orb Exchange checks |
| `/creatorcodes [run]` | **5+** | creator codes: the settings and each code's paid shares; `run` matches and pays now. Codes are made and switched off on the website (The World > Creator Codes, admin panel account with a group 5 character); the Character Bazaar's staff cancel is on the website too (The World > Character Bazaar > Administration) |
| `/treestats [<class> [band] [n]]`, `/treestats export` | 4+ | passive tree picks per class line and level band (counts only); the CSV goes to the server's `data/` folder (server/README.md "Passive tree pick statistics") |
| `/daily`, `/leaderboard`, `/season status`, `/spells reload`, `/supports reload` | 4+ (`/daily shift\|set`, `/leaderboard shift`: **5+**) | state and test clocks (`shift`: test servers only) |
| `/testkit` | 4+ (admin panel access) | gear kits for balance tests; **removed from the live server** (docs/LAUNCH.md section 11) |
| `/coins <character>, <amount>`, `/charm give ...`, `/pact <player>, days\|end\|extra\|claimreset` | **5+** | economy value |
| `/goblin`, `/blessing`, `/season start\|end`, `/seasonpass`, `/journey` | **god account** | test and season tools |
| base server `/` commands (ban, kick, teleport, create item, ...) | per the base server's groups | the admin panel covers the common ones with logging; prefer it |

The commands that hand out value (`/rift key|omen|fragments`, `/ascended sigil|shards|relic`, `/newplayerkit` kit,
milestone and reset, `/guild xp|bank` and `rent <guild>, paid`, `/classunlock`, `/cosmetic`, `/exclusive` and `/transmog`
grants, `/pet give`, the test clocks `/daily shift|set` and `/leaderboard shift`, `/raid marks`, `/descent sigil`,
`/marches embers`, `/trial tokens`, `/achievements grant|add`, `/atlas grant`, `/community add`) need group 5, like `/coins`, `/charm give`
and `/pact`.
**Rule (decided):** staff never give anything to a player character with any command; these tools are for staff test
characters only. A refund after a confirmed bug goes through an administrator (group 5) with a written reason
(section 6). Why: every gift to a player is economy value nobody earned. Done (2026-10-12): those commands sit behind
`Chaos.staffCommand(..., true)`, so the code enforces the rule; a gamemaster is refused with a message and every use,
refused or not, is in the admin audit log (`tests/staff_permissions_test.lua`).

### 2b. Reload without a restart (updated 2026-10-18)

A **god** account (group 6, `ACCOUNT_TYPE_GOD`) types `/reload <type>` in the default channel, or uses the admin panel (Server >
Reload system; god only, logged). Nothing here touches the engine, `items.xml`/`items.otb`, `vocations.xml`, the map, spawns or
houses: those need a restart. Read the console for `Lua Script Error` after every reload. A reload runs the files again, so
state a system keeps only in memory (timers, runs in progress, caches) can reset: the system's section in server/README.md says so.

`/reload` types: `all`, `scripts` (every revscript under `data/scripts`, that is every Chaos system), `libs` or `global`
(`data/lib` and the global scripts), `config`, `actions`, `creaturescripts`, `movements`, `talkactions`, `globalevents`,
`spells`, `weapons`, `monsters`, `npcs`, `mounts`, `auras`, `wings`, `shaders`, `quests`, `raids`, `events`, `chat`, `items`
(avoid on a live server).

| What you changed | Reload with | Notes |
|---|---|---|
| a Chaos Lua system (`data/scripts/chaos/*.lua`, configs `*_config.lua`: balance numbers, potions, loot, nemesis, effigy ...) | `/reload scripts` | the common case; players online keep their state, in-memory timers restart |
| a shared lib (`data/lib/*.lua`, e.g. `chaos_buffs.lua`, `chaos_orbs_config.lua`, item mods) | `/reload libs`, then `/reload scripts` | scripts cache lib tables: reload both, libs first |
| a spell script or the spell list (`data/spells/**`, `spells_chaos.xml`) | `/reload spells`, then `/spells reload` | players see new spells after a relog; `/spells reload` re-parses the Spellbook texts |
| monster files (`data/monster/**`: health, flags such as `runonhealth`, loot) | `/reload monsters` | monsters already alive keep the old values until they die |
| NPC files (`data/npc/**`) | `/reload npcs` | |
| `config.lua` keys (rates, `potionChannelDelay`, `runeChannelDelay`, `moveItemDelay`, `proxyProtocolTrusted`, ...) | `/reload config` | ports, database, the RSA key file and the map are read only at start |
| talkactions, actions, movements, globalevents, creaturescripts files | `/reload talkactions` / `actions` / `movements` / `globalevents` / `creaturescripts` | `/reload scripts` already covers the revscripts among them |
| Chaos patch notes (`data/patchnotes/*.md`) | `/patchnotes reload` | group 4+ |
| Chaos spell supports catalogue | `/supports reload` | group 4+ |
| website (PHP, wiki, credits) | the site installer (`docs/LAUNCH.md`), no game restart | |
| a new client build | players download it (the signed updater) | not a reload |

Needs a **restart**: engine patches (`server/src-patches/`), `items.xml` / `items.otb`, `vocations.xml`, map and spawns, houses,
any `install_all.py` step but `files`, SQL changes (run the SQL, then restart if a table is read at start).

Typical hotfix, as in docs/LAUNCH.md section "Hotfix without a restart": `install_all.py ... --only files`, `chown`, then in game
`/reload scripts` (and `/reload monsters` / `/reload spells` for those files), then the admin panel's Online list to check nobody was kicked.

## 3. Report handling

From server/README.md "Anti-bot and player reports", Staff guide:
1. **New report:** online staff see `[Report #12] A reported B: botting. /reports show 12`. In game: `/reports`,
   `/reports list closed|all`, `/reports show <id>` (note, position, public chat lines). The same in the admin panel
   (Accounts & Security) and on the website (`page.php?plugin=chaos&p=reports`, admin accounts).
2. **Look before deciding:** `/reports score <name>` shows the score and each signal. One signal alone is never
   evidence; a failed presence check can be someone who stepped away.
3. **Watch** the character, talk to it, `/reports check <name>` for a fresh presence check.
4. **Decide** with the admin panel (kick, mute, ban), then `/reports close <id>, <what you found>`. `/reports clear
   <name>` resets the score and lifts a leaderboard hold after a review that found nothing.

**Bug reports** (System > Report a Bug, every account; server/README.md "Bug reports"):
1. Online staff see `[Bug #15] Name (map) at 1000, 1000, 7. /reports show 15`. `/reports list bugs` lists the open
   ones; `/reports show <id>` has the text (`[category] text`, at most 240 characters), the position (the reported
   tile of a map report, else the character's), the character's position, level and class. The admin panel (Accounts &
   Security > Player reports, filter "Bug reports (open)") and the website (reason "Bug report") show them too; the
   reports webhook (`CHAOS_REPORTS_WEBHOOK`) gets the id, category, name and place, never the text.
2. Go there or reproduce it, then `/reports close <id>, <what you found or fixed>`. Crash, dupe or anything that gives
   items or experience: tell an administrator at once and do not discuss it in public.
3. Limits: one report per character every 5 s and per account every 30 s, 10 a day per account. A player who hits
   them gets a message; ask them to put the rest on Discord.

House rules (decided):
- Answer every report within the shift; close it with what was found, even "nothing found".
- Never tell the reporter what happened to the other account; never name the reporter.
- Harassment, scams and offensive names: read the public chat lines in the report; private messages are never stored.
- Offensive name: ask the player to change it (Character > Services > name change); if refused, an administrator
  locks the name (base `player_namelocks`) or bans per the ladder.

## 3a. Bot review

The server keeps a daily suspicion score per character for signs of unattended play (server/README.md "Bot
detection").
**It never punishes, kicks or moves anyone.** A day with a score of 50 or more lands on the review list; staff decide.

**Official stance** (from the Rules page, section 2.2 and 7.4 / 7.6, and the Terms of Use):
- **Allowed:** the official client and its tools, the helper included (healing rules, spell rules, the auto rotation the
  owner asked for, targeting), the game's own tools named in Rules 2.2 (hunt tracker, loot filter, autoloot, auto
  seller) and the Loot Bag. A helper user is a player, not a botter. Rules 2.2 says so (decided 2026-10-14): "The
  official client's helper (healing, spell rules, auto rotation, targeting) is allowed while you play."
- **Not allowed:** bot programs, macros and modified or third-party clients that play for you (Rules 2.2). Confirmed
  botting follows ladder line 7.4; a third-party client line 7.6 (section 4).
- **Unattended helper** (Rules 2.2 and 7.4, decided 2026-10-14): "Leaving it running for hours with nobody at the
  keyboard counts as botting (7.4)." It gets the normal botting procedure with one step in front: **the first time a
  warning**, then the 7.4 ladder (ban 7 days and the gain removed, ban 30 days, permanent). Count a case only when all
  three hold, and write each one in the note:
  1. the day's unattended signals cover at least an hour of fighting (the score by hour on the review page);
  2. a presence check was failed or left unanswered while the character kept fighting;
  3. you talked to it (private message, or say next to it) and got no answer within 5 minutes while it kept fighting.
  Anything less: mark **reviewed** with what you saw. A short break (food, the door, the phone) is not a case.

**Where:** the website (`page.php?plugin=chaos&p=botreview`, admin panel accounts with a group 4+ character), in
game `/botreview` (4+), and the admin panel's Accounts & Security > Bot review (5+). Online staff see
`[Bot review] Name is on the review list (day score 63). /botreview Name` when a day is flagged.

**Reading a day.** Two families of signals, each 0 (like a person) to 1 (like a program):
- *Automation:* action rhythm, instant heals after hits, heals at one HP threshold, next target right after a kill,
  looting pace. **The helper does all of these.** Automation alone never makes a high score.
- *Unattended:* hours without a break, no chat / looks / turns / item moves / short pauses, the same route hour after
  hour, a presence check missed while still fighting, actions in step with another character of the same connection
  or party. The score needs at least two of these.
The page shows each signal, the explanations in plain words, the score by hour, the last 30 days and the presence checks.

**Steps:**
1. Read the signals. Automation with no unattended sign is a helper user: mark **false positive** with a note.
2. Watch the character for a few minutes, talk to it, and press **Request presence check** (website) or
   `/reports check <name>`. The check is a small picture question; a failure is only one more signal.
3. Someone answered, moves and talks normally: mark **reviewed** (or **false positive**) with what you saw.
4. Nobody answers and it keeps fighting the same route (the three points of "Unattended helper" above), or you find a
   bot program or a modified client: follow section 3 (report procedure) and section 4 (the unattended helper line,
   ladder 7.4 or 7.6). A gamemaster gives the first warning and the 7-day ban; a ban of 30 days or more or a permanent
   ban: **escalate** (only an administrator may change an escalated day; section 7).
5. Every mark, note and check request is logged with your name (`chaos_bot_actions`). Write what you saw.

**Known false positives** (why one look is never enough): very long sessions of a quiet helper user (12 to 15 hours with
breaks under 20 minutes and almost no chat); one person on two clients (the multi-client rules allow two), whose
helpers act at nearly the same moments; a player who walks the same circle in a spawn for hours; a player who stepped
away for a short break while the helper kept fighting (only hours with nobody there is the unattended helper case). A
player who passes a presence check halves the unattended part of the score for 24 hours.

**Retention:** a day row is kept 30 days, an escalated day 90 days, the staff actions 90 days; then deleted
automatically. Only days with a score of 25 or more are stored at all.

## 4. Mutes and bans

The ladder (decided), per account, counted over 90 days. It is published on the Rules page (section 7 of
`website/setup/rules.bbcode`); staff apply the same table, so players can predict the result:

| Offence | 1st | 2nd | 3rd | then |
|---|---|---|---|---|
| spam, flood, insults in public chat | warning | mute 60 min | mute 24 h | ban 7 days |
| harassment, hate speech, threats | mute 24 h | ban 7 days | ban 30 days | permanent |
| scam (proven trade or market fraud) | ban 7 days, the items or gold back where possible | ban 30 days | permanent | |
| botting, macros (confirmed, section 3) | ban 7 days, the botted gain removed | ban 30 days | permanent | |
| the helper left running for hours with nobody at the keyboard (Rules 2.2, section 3a) | warning | ban 7 days, the gain of that session removed | ban 30 days | permanent |
| exploiting a bug for gain, not reporting it | ban 7 days, the gain removed | ban 30 days | permanent | |
| duplicating items or currency, a third-party client, attacks on the server | permanent, the gain removed | | | |
| impersonating staff | ban 7 days | permanent | | |
| real-money trading of characters or items | ban 30 days, the traded goods removed | permanent | | |
| chargeback fraud: disputing your own donation to keep the coins, or someone else's payment method without permission | the coins taken back (automatic), what they bought removed, the account locked until the dispute is settled | permanent, by an administrator | | |

- Tools: admin panel Players > Mute (online player, 1 to 1,440 minutes, default 60; longer than 24 h is a ban; check
  that it blocks speech on this engine, admin README "Untested"), Players > Ban account (1 to 3,650 days, default 7,
  with a reason; kicks; **permanent = 3,650 days**), Unban; Accounts & Security > IP ban (group 5; for ban evasion only,
  never for a shared IP such as a school or a cafe without an administrator).
- The code enforces the ladder's limits (`ChaosAdminLadder` in `admin/actions_players.lua`, `tests/staff_permissions_test.lua`):
  a mute is at most 24 h, and a ban of 30 days or more (permanent included) needs an administrator (group 5), as in
  section 7. A gamemaster who finds a case for a longer ban hands it to an administrator with the evidence.
- **Chargeback fraud** (decided 2026-10-12; Donation Terms section 6, Rules 7.9): the donation system takes the coins back by itself
  when the provider reports a refund or a dispute (`removeCoinsOnReversal` in `shop_coins_config.lua`, up to the balance
  still there). Gamemasters do not act on payments (section 7, level 4): an administrator checks the order
  (`chaos_coin_orders`, `chaos_coin_payments`), removes what the coins bought, and locks the account with Ban account
  for 3,650 days, reason "chargeback, locked until settled, order <id>". When the dispute is settled (withdrawn, or the
  donation paid again) the administrator lifts it with Unban. Fraud again on the same account, or a payment method of
  someone else: permanent, by an administrator. A dispute in good faith (coins that never arrived, a double charge)
  is not fraud: settle it, never punish it.
- A ban always has a reason the player could read, and the evidence (report id, log lines, screenshots) goes in the
  handover note.
- Appeals (decided): on Discord, in the appeals channel, to an administrator who did not issue the ban. One appeal
  per penalty; the administrator's answer is final.
- Self-reported bugs are never punished (decided). A useful report may be rewarded; the owner decides the reward
  case by case, so nobody is promised anything in advance.

## 5. Never ship (and never do)

The test-only files and switches of docs/LAUNCH.md section 11 must not be on the live server. Above all:
- `zz_test_lua.lua` (`/lua` runs any Lua for any player), every `ztest/` and `zz_*` file, `ztest_chaos_dummy.xml`, the
  cropped test map;
- the test switches: `Chaos.arenaConfig.testNoPzStorage` (7100345), `Chaos.multiClient.offStorage` (7100990),
  `/leaderboard shift` and `/daily shift` (test clocks; `shift 0` puts them back);
- `admin/testkit.lua` (`/testkit`) unless the owner accepts staff giving themselves gear;
- the load-test bots (`loadtest.py cleanup`) and `loadtest_probe.lua`;
- the `mock` donation provider in `payments.env`.

Staff never: play their player character with a staff account; give items, gold, coins or unlocks to players outside
section 6; join a guild, a party or a ranked queue with a staff character; share account data (the account lookup
never shows passwords or e-mail; keep it that way); run `/community modifier`, `/season`, `/worldboss` or `/invasion`
outside the event plan without telling the owner.

## 6. Investigating a dupe

A duplicated item or currency is a server bug first and a ban second. Do not tell the suspect.

1. **Freeze the evidence.** An administrator takes a backup at once (`backup.sh --save-service chaos-server`,
   docs/LAUNCH.md section 7) and notes the time.
2. **Build the timeline** from the logs. Every value movement of the Chaos systems is written somewhere:

   | Source | What it records |
   |---|---|
   | `chaos_admin_log` | every admin panel action and guarded staff command (who, target, parameters) |
   | `chaos_market_log`, `chaos_market_deliveries`, `chaos_market_offers`, `chaos_market_orders` | market sales, deliveries to the inbox, open offers and buy orders |
   | `chaos_orbx_log`, `chaos_orbx_trades`, `chaos_orbx_deliveries` | Orb Exchange orders and fills |
   | `chaos_crafting_log` | crafting orbs and salvage |
   | `chaos_shop_purchases`, `chaos_shop_history`, `chaos_shop_gifts`, `chaos_coin_gifts`, `chaos_coin_orders`, `chaos_coin_payments` | store purchases, gifts, donations |
   | `chaos_guild_log` | guild bank and guild depot |
   | `chaos_pact_log`, `chaos_seasonpass_log`, `chaos_referral_log`, `chaos_mentor_log`, `chaos_season_log` | Pact, pass, referral, mentor and season grants |
   | `chaos_stash`, `chaos_bank` | stash contents and bank stars (current state, no history) |
   | `/var/log/chaos/server.log` | the console: script errors, `[Chaos staff]` lines, rift interruptions, save failures |
   | `/var/log/chaos/crashes/` | crash records with the last console lines (docs/LAUNCH.md section 5) |

   The base server's plain bank transfers have no log (server/README.md "Stubbed or assumed", bank).
3. **Look for a crash or a restart** near the gain. Most dupes need a crash between a removal and a save; the Chaos
   systems save the character before a database credit (`Chaos.saveCharacter`, "Shared security rules"), so a gain
   around a crash time points at a path that does not.
4. **Compare with an older backup.** Restore an earlier dump into a scratch database (docs/LAUNCH.md section 7, Restore,
   into another database name) and compare the character's gold, bank, stash, market rows and item counts.
5. **Rolled items carry a per-item id** (`chaos_iid`, server/README.md "Item attributes in packets and rich tooltips").
   Two items with the same id are copies. The id sits inside the serialized item attributes (`player_items`,
   `player_depotitems`, `player_inboxitems`), not in a column of its own: finding copies needs a script that reads
   those blobs (not built; ask a developer).
6. **Escalate** (section 7) with the timeline. The developer reproduces it on a test server, never on live.
7. **Act** after the fix is ready or the path is closed: remove the gain (admin panel Remove item; Remove gold and
   Add to bank balance with a negative number need group 5), ban per the ladder, write it in the admin log reason. Announce only
   once the hole is closed.

## 7. Escalation

The levels (decided). The names and contacts of each level are in the staff contact list, not in this repository:

| Level | Who | When |
|---|---|---|
| 1 | gamemaster on duty | reports, mutes, short bans, stuck characters, questions |
| 2 | administrator | bans of 30 days and more, IP bans, refunds, economy corrections, anything with coins |
| 3 | developer on call | crashes, a hang, dupes, exploits, a system that misbehaves, a hotfix |
| 4 | owner | a server closure, a rollback, a wipe, public statements, legal or payment matters |

- **Crash or hang:** the server restarts itself (docs/LAUNCH.md section 5); the developer reads the crash record. Two
  crashes within an hour: level 4 decides whether to keep the server closed.
- **Dupe or exploit in progress:** close the server to players at once (a god: admin panel Server > Open / close; or
  the developer on the machine: `ufw insert 1 deny 7172/tcp`, docs/LAUNCH.md "Incident runbook"), then level 4.
- **Payments:** any donation question goes to level 4; staff never promise refunds.
- Every escalation gets a line in the handover note: time, who, what, the result.
- The server-side steps for each kind of incident (server down, crash loop, rollback, ...) are in docs/LAUNCH.md
  "Incident runbook".

## 8. Beta notes

During the beta weekends (docs/BETA.md):
- Progress will be wiped before launch; say so whenever asked, never promise anything will be kept.
- Test coins: only the grant of docs/BETA.md section 4, by an administrator. Gamemasters give nothing.
- Prepared test characters for the group tests are made by administrators on separate test accounts, never on a
  player's account.
- Bugs: ask for what, where, when, the character and a screenshot; post it in the bug channel with a severity (crash or
  dupe, blocks play, wrong, cosmetic). An exploit found by a tester is a gift: thank them, close it, never punish it.
- Bans in the beta follow the same ladder; cheating in the beta is a reason to keep the ban at launch (bans survive the
  wipe, docs/BETA.md section 3).
- Write down every manual change you make (level, items, keys) in the handover note, so the test results stay readable.
