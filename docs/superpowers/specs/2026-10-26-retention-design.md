# Retention pass: measure the funnel, reveal systems, early wins, a weekly reason (O258-O261)

Owner, 2026-10-26: "I want to know what else we can do to make the game as fun, engaging and addictive as possible. I want
players to like it and stay." The server is in closed beta. The owner sees all four signs in the testers: they stop
early, they get lost, the endgame runs out, and they play alone. Players level fast, so the measuring has to reach
levels 500, 1000 and above. The owner approved the approach (fix the funnel in order) and told us to go on without asking
again.

Finding: the systems exist (season pass, dailies, achievements, leaderboards, community goals, records, guilds, party
finder, rifts, waystones, Tower, dungeons, world bosses). What fails is that players **see every system at level 1**: the top
menu shows all of them, and most unlock from level 120 to 1000. They also lack a short, visible next step, a reason to come
back each week, and a push towards each other.

Not in scope: new content, new classes, balance numbers, cutting systems (wait until the funnel data says what nobody
uses), and launch marketing.

## O258: funnel metrics (extends O253, `metrics*.lua`, `tools/progress_metrics.py`)

1. **Milestones** `{10, 25, 50, 100, 200, 500, 1000, 1500, 2000}`. The mask in storage 7102830 holds 9 bits. Characters
   that already passed a new milestone are marked silently (`M.maskAtLogin`), as today.
2. **Return.** Store the day of a character's first login in storage 7102831, as the day number from the epoch, in server
   time. At each later login, count `return:d1`, `return:d3` and `return:d7` once each: a login on calendar day first+1,
   first+3, or first+7 and later. Also count the cohort size `cohort:<YYYYMMDD>` at the first login. The report shows the
   share per cohort week.
3. **First use of a system.** Count `first:<system>` with the level band and the played-minutes bucket, once per
   character. Bits live in storage 7102832 and up. Systems: dungeon, rift, waystone, tower, pocketboss, worldboss,
   invasion, party, guild, market, bounty, craft. Each system's existing hook calls `ChaosMetrics.firstUse(player, key)`.
   Wrap the hook where one exists, as `community.lua` does; otherwise call it from the system's success path.
4. **Where they stop.** At the churn computation, for characters gone for `churnDays`, group by level band and by area.
   The area is the nearest hunt to `posx/posy/posz` from `players`, using `M.areaFor`. There is no per-player row.
5. **Report.** `progress_metrics.py` gets sections Milestones, Return, First use and Where they stop. The admin app gets a
   "Funnel" card in the tab that shows the server report; read `android/` for the place.
   Counts below `minShown` stay suppressed. Testers and staff stay out.

## O259: the top menu reveals systems by level (`client_chaos_topbar`, new `unlocks*.lua`)

1. **One table on the server**, `unlocks_config.lua`. Each entry is `{key, level, menu = "<menu id of the topbar>",
   title, why (en + pt-BR, two lines), go = {open = "<module>"} or {mark = poi}}`. Each level comes from the system's own
   config: the level the server already enforces. A test (`tests/unlocks_test.lua`) reads every system's config and
   fails when a level differs. A new extended opcode, 115 (verify that it is free: the weather test's four checks plus
   `ChaosOpcodes`), sends `{unlocked = [...], next = {key, level}}` at login and on level up.
2. **Client:**
   - The topbar hides an entry until it is unlocked. The next one to unlock shows grey, with a lock and "level N".
   - On unlock the client shows:
     - a big screen text "New: <title>!";
     - a "New" badge on the entry until the player opens it;
     - a small two-line window with a "Go" button that opens the module or marks the map.
   - When several systems unlock at once, they come one per 75 s, the first-hour pace.
3. **No one loses anything:**
   - A character above an entry's level at the first login after this ships gets that entry unlocked silently.
   - "Show the whole menu" in System > Options turns the filter off.
   - A hotkey of a locked system says "Unlocks at level N" instead of opening.
4. **Storage:** 7103000-7103009, unlocked and seen bits (`unlocks_config.lua` `storage`). Add the block to README
   "Storage keys".

## O260: an early power spike, pity, a server drop feed, personal records

1. **First unique.** At the character's `firstUnique.kills`-th kill (default 150, about 10-15 minutes), a leveling unique of
   the character's class drops to the character, once per character. It comes with the gold loot beam and the rare-drop
   sound. Skip characters above level 60 and testers. Storage 7103010.
2. **Pity.** Count a hidden kill streak without a rare-or-better drop for the character's band. At
   `pity.threshold` (config, start 400 kills), the next magic-or-better roll steps up one rarity, and the counter resets.
   Storage 7103011. It applies to normal hunting kills only, not rifts or bosses. Their loot tables stay as they are.
3. **Server drop feed.**
   - Legendary, unique and boss-unique drops post one line, "<name> (Lv N) found <item>!", in a "Drops" channel and in
     Default.
   - The item name is an `itemlink`, so hovering shows the tooltip.
   - A client option sets the minimum rarity shown (off / unique / legendary). The same line goes to `discord.lua`.
   - Rate limit: at most one line per character per `feed.perCharSeconds`, and `feed.maxPerMinute` server-wide; more
     lines are dropped silently.
   - The existing local broadcast in `loot.lua` stays.
4. **Personal records.** Reuse `records.lua`: best drop rarity and value, fastest boss kill per boss, highest Tower floor,
   highest rift tier. Show them in Inspect and in a Records tab of the character window. A new personal best shows
   "New record: ...". Keep it to what `records.lua` already can store; add only the missing keys.

## O261: the Weekly Chest, group nudges, a visible party bonus

1. **Weekly Chest** (new `weeklychest*.lua`, client module or a tab of `game_goals`):
   - Six activities count once each per week: dungeon, rift, waystone, a Tower floor, a world boss or invasion share,
     and a bounty contract.
   - The week is the leaderboard week (Monday 06:00, `ChaosBounty.week`).
   - 4 of 6 open the chest; 6 of 6 add a bonus roll.
   - Rewards scale with the level band. They are orbs and gold within the store and roulette models: check with
     `store_model.lua` and `roulette_model.lua` that nothing breaks a limit.
   - Activities the character has not unlocked yet (O259 table) are left out, and the needed count drops with them, with
     at least 2 needed.
   - Storage 7103020-7103029. Extended opcode 117 (verify that it is free).
2. **Group nudge.** Entering a dungeon or rift alone shows one line if the party finder has open groups for that content:
   "2 players look for a group for Rift T5. [Join]". At most once per 10 minutes per player.
3. **Party bonus visible.** The party frame shows the current party XP bonus (`party_xp.lua`), for example "+20% XP".

## How it is built

- Each item is its own core, config and thin engine file, following the repo pattern, with unit tests under LuaJIT and
  Lua 5.3.
- Every player-facing text has a pt-BR string.
- Docs: README sections, ROADMAP rows O258-O261, client/MANIFEST.md, and a patch note bullet each.
- Four work packages, one per O item, run in parallel worktrees. The storages and opcodes above are assigned up front,
  so they do not collide.
- Shared files (ROADMAP, README, patch notes, `pt_br.lua`, `i18n_strings.lua`, `chaos_constants.lua`) get appended
  entries only.
- Nothing is tested on a live server or client by the packages. The owner's beta test follows a client build.
