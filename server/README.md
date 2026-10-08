# Chaos server scripts (TFS 1.4.2, the base server style)

Server side for the client modules in `client/overlay/modules/`. One revscript per module,
each registering a `login` CreatureEvent plus an `extendedopcode` CreatureEvent (same pattern as
`scripts/customs/stats_inspect/inspect.lua` in base server).

**Nothing here has been run on a TFS server.** There was no TFS, no MySQL and no OTClient in the
build environment. What was done: every file passes `luac5.3 -p`, and the Lua logic of all modules
was exercised against a hand-written mock of the TFS API (fake `Player`, `db`, `Game`, the
reference server's own `json.lua`) in a scratch directory that is not part of this tree. That
checks protocol shapes and branching, not engine behaviour. `sql/chaos.sql` was not run against a
database. Treat every engine-API call (listed under "Assumed API") as unverified.

## Layout

```
server/
  README.md
  sql/chaos.sql                       CREATE TABLE IF NOT EXISTS for 10 tables
  tools/gen_passivetree_data.lua      regenerates passivetree_data.lua from the client tree
  data/scripts/chaos/
    chaos_constants.lua               ALL opcodes, storage keys, table names, tunables, shared helpers
    bank.lua  autoloot.lua  daily.lua  notifications.lua  passivetree.lua  passivetree_data.lua
    dungeons.lua  infinitytower.lua  stash.lua  spell_guard.lua (Iron Will damage reduction of the Warcry spell)
```

## Install

1. Copy `server/data/scripts/chaos/` to `<server>/data/scripts/chaos/`.
2. Run `server/sql/chaos.sql` against the game database (`mysql -u USER -p DB < chaos.sql`).
   Foreign keys assume `players.id` is `int(11) NOT NULL` (stock TFS schema).
3. Restart the server (or `/reload scripts`). Check the console for Lua errors.
4. Autoloot only: if `data/talkactions/talkactions.xml` registers `!autoloot` (the legacy
   `talkactions/scripts/autoloot.lua`), TFS 1.4.2 keeps the XML one and silently ignores
   `autoloot.lua`'s `!autoloot`. Remove that XML line for live window refresh. See "Stubbed or assumed".
5. Client: apply the client-side gaps listed below, otherwise bank, autoloot, daily and stash
   cannot talk to the server at all.

`data/scripts/chaos/admin/` and `sql/chaos_admin.sql` are a separate admin-panel module written by another
task; they are not covered here. They use extended opcode 120, which does not collide with any opcode below.

Every script starts with `if not Chaos then dofile("data/scripts/chaos/chaos_constants.lua") end`,
so load order inside `data/scripts` does not matter (the `dofile` path is relative to the server's
working directory, as with the rest of the base server libs).

## Module status

| Module | File | Opcode(s) | Status |
|---|---|---|---|
| game_bank | `bank.lua` | 60 | Gold deposit/withdraw/transfer on the native bank balance, star currency in `chaos_bank`. `!bank` opens the window. Written to the client contract; mock-tested only. |
| game_autoloot | `autoloot.lua` | 216 | Window protocol and `!autoloot` / `!autolootclient` talkactions; list lives in the same storages (base 80000) as the base server onDropLoot callback, which does the actual looting. XML talkaction conflict possible (see below). |
| game_daily | `daily.lua` | 207 | 7-day streak with claim, midnight rollover, `!daily`, optional open on login. Rewards: platinum coins, Chaos and Divine Orbs and a crystal coin, plus a week bonus on day 7 (all or nothing); edit `Chaos.daily` in `chaos_constants.lua`. |
| game_notifications | `notifications.lua` | 79 out, 151/152 in | `/gmnotify`, accept/decline of a standard TFS party invite, `ChaosNotify.*` sender API. Catacomb start / leave-queue are hooks only; nothing triggers party/catacomb/task/battle pass toasts automatically. |
| game_passivetree | `passivetree.lua`, `passivetree_data.lua` | 65 | Points, save with full validation (known ids, connected to root, point cap), preset storage, reset for level x 250 gold. Bonuses are computed (`ChaosPassiveTree.getBonuses`) but **not applied to anything**. |
| game_dungeons | `dungeons.lua` | 109 | Reads the base server `DUNGEON_SYSTEM` table. Queue, group formation, teleport in, timer, monster-count progress, boss kill, difficulty unlock, speed/flawless challenges, solo/group rankings, teleport out. Difficulty does not change monsters; loot panel is display only. |
| game_infinitytower | `infinitytower.lua` | 214 | Seasons, points, best floor/time, ranking, milestone claim, `!tower`, `/towerrun` staff test helper. **The tower gameplay does not exist**; a future script reports results with `ChaosTower.recordRun`. Season-end top 3 chests not implemented. |
| game_stash | `stash.lua` | **110** (new), `!stash` | Deposit by drag, redeem, categories, block list, `!stash all`, DB persistence. Client must be ported first (see below). |

Extended opcodes 60, 65, 79, 109, 110, 151, 152, 207, 214, 216 are all registered in the global
`ChaosOpcodes` table in `chaos_constants.lua`.

### Opcode collision check
Searched the reference server for every `onExtendedOpcode`, `sendExtendedOpcode(` and opcode
constant. Opcodes in use there: 1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202. (The
`ServerOpcodes` 125/126 in `global.lua` are game-protocol opcodes, a different number space.)
None of the Chaos opcodes collide; no adjustment was needed. 110 was chosen for the stash because
the client has no fixed value and 110 is free. Storage keys `7100000-7100999` and DB tables
`chaos_*` are new; the one deliberate overlap is autoloot's storage base 80000 (shared on purpose).

## Client-side gaps found while reading the client (not changed, `client/` is out of scope)

1. **`sendAction(opcode, action, data)` does not exist in the overlay.** `game_bank`, `game_autoloot`
   and `game_daily` call a global `sendAction(op, action, data)`; the only `sendAction` in the tree
   is passivetree's own two-argument one. It must send `json.encode({action = action, data = data})`
   on that extended opcode (the server expects exactly that envelope). Without it those three
   modules send nothing.
2. **game_stash** uses the donor client's `modules.client_manager`, which is not in the overlay. The
   server speaks `{"action":"Stash","data":{"make":...}}` both ways on opcode 110. Minimal port:
   set `Stash.Opcode = 110`, replace `modules.client_manager.Manage.NewModule(...)` with
   `ProtocolGame.registerExtendedOpcode(110, function(_, _, buf) local j = json.decode(buf); if j and j.action == "Stash" then Stash.DataManager(nil, 110, j.data) end end)`
   and drop/replace `modules.game_extramenu`, `Keybind`, `modules.game_windowfocus` if absent.
   The envelope is an **assumption** about what client_manager does; only the client's outbound
   JSON proves it for the client-to-server direction.
3. `game_dungeons` loads banners from `/images/dungeons/<title>`; no such images are in the
   overlay (titles: Bones Dungeon, Master of the Elements, Forbidden Chevalier, Rootkraken).
4. `game_passivetree` sends via `protocolGame.sendExtendedJSONOpcode`, an OTClient call. Stock OTClient
   10.98 may lack it.
5. (fixed) the JSON error branches of the bank, autoloot and daily client modules used an undefined variable.

## Stubbed or assumed (read this before relying on anything)

General
- Engine API assumed to match TFS 1.4.2: `Player:getBankBalance/setBankBalance/getMoney/addMoney/removeMoney`,
  `Game.getPlayerByGUID`, `Game.getSpectators(pos, multifloor, onlyPlayers, minX, maxX, minY, maxY)`,
  `Tile:getThing(stackpos)`, `Container:getItems(true)`, `Item:remove(count)`, `Item:hasAttribute`,
  `ItemType:isRune/isStackable/isPickupable/getWeaponType/getClientId`, `Party:getInvitees/addMember/removeInvite`,
  `MonsterType:getOutfit`, CreatureEvent types `kill` and `death`, `os.mtime` (falls back to `os.time`),
  `result.getNumber`. None verified against a real server.
- `json` global is the base server `lib/core/json.lua` (rxi). Empty tables encode as `[]`.
- Packets stay far below the ~24 KB network message limit (stash is chunked at 40 items).
- All client input is validated (integers, ranges, ownership), but there is no flood control.

bank
- Star item id 35572 is **assumed** to be both the client id the client hard-codes and a valid server
  item id. If `ItemType(35572)` is invalid on your server the star tab is disabled (all zeros).
- Offline transfers update `players.balance` directly; transfers have no fee, limit or log.

autoloot
- Client numeric ids sent via `!autolootclient` are treated as **client** ids and mapped to server ids
  through a one-time scan of item ids 100..100000.
- Looting itself is not done here; it needs the base server `scripts/creaturescripts/autoloot.lua` callback.
- If the XML `!autoloot` talkaction exists, add/remove still work (it writes the same storages) but
  the open window does not refresh until reopened.

daily
- Reward table is a placeholder. The shipped client adds 2 to `Day` and maps claims through
  `{6,7,1,2,3,4,5}`; the server compensates (documented in the file). Day 7 of that client logic is
  otherwise unreachable, so do not "simplify" the offset.
- "Midnight" is server local time; the client's countdown uses client local time minus 1 hour.

notifications
- No catacomb system exists in the reference server: `start_catacomb` and `leave_queue` only call the
  overridable `ChaosNotify.onStartCatacomb` / `onLeaveQueue` (the latter also leaves the dungeon queue).
- No `Party:onInvite` hook exists in the reference server, so `partyInvite` toasts are never sent
  automatically (call `ChaosNotify.partyInvite`). Its text says "catacomb"; for plain parties it reads oddly.
- Task / battle pass toasts need one call added to the reference `tasks.lua` / battle pass code.
- `/gmnotify` is allowed for any group with `Group:getAccess()`.

passivetree
- Tree shape comes from the client's `nodes.lua` (618 nodes; the file records 932 stat entries).
  Regenerate `passivetree_data.lua` with `tools/gen_passivetree_data.lua` whenever the client tree changes.
- Points formula is invented: `(level - 8) * 1` plus storage `7100020`. Change `Chaos.passive`.
- Only one preset slot exists in the client UI; presets 0 and 1 are the same slot. `refund` is just a resync.
- Stat keys such as `strength`, `incrementFire`, `absorbIce`, `criticalHitChance`, `lifeLeechChance`
  are **not applied**. base server' `CHARSTAT_*` values are stored by its own system and would conflict.
  Use `ChaosPassiveTree.getBonuses(player)` or `ChaosPassiveTree.appliers[statName] = function(player, value)`.
- The client's "exclude" (two big nodes of one path) rule is not enforced: no node in the data uses it.

dungeons
- Entry is by queue, not by the base server modal/PZ/party rules: no PZ requirement, no real party needed,
  players are matched individually (same difficulty, group size = `AmountParty` when `NeedParty`, else 1).
- Bosses are assumed to exist inside the dungeon box (map spawns or `SpawnMonsters`). Boss names per
  dungeon id are in `Chaos.dungeons.extra` (guessed from the base server boss scripts) and must match the monster
  names on your server. Progress % = monsters that disappeared from the box / monsters at start (summons
  ignored); the boss counts as dead when `onKill` credits it, or when it was seen and is gone.
- One run per dungeon at a time (they share a single map area). All monsters in the box are removed when a
  run ends.
- Difficulty (1..6) is stored and unlocked (finish on your top difficulty to unlock the next) but changes nothing in-game.
- Loot panel and challenge list are configured in `Chaos.dungeons.extra`; real loot comes from the boss XML.
- The base server `DUNGEON_SYSTEM` is used for level, group size, positions, time and cooldown. Its modal script reads
  `Storages.TimerCooldown` while the table defines `timerCooldown` (existing bug); this module accepts both.
  `DUNGEON_SYSTEM.Dungeons[3]` has `DungeonPos` z=0 but `FromPos/ToPos` z=7; the box is widened to include
  DungeonPos so players are not treated as "outside".
- Cooldown (`DUNGEON_SYSTEM.CooldownTime`, 1 h) is also applied after a win (`cooldownOnSuccess`) and when a
  member leaves/dies.
- Ranking: solo = best time per player (party size 1), group = best runs with 2+ players. Times in ms.

infinitytower
- No tower gameplay. Milestone item ids are the ids the client displays and are assumed to be valid server ids.
- Season = 30 days counted from 2025-01-01 UTC (`Chaos.tower`). `nextTry` cooldown disabled by default.

stash
- Opcode 110 is chosen here. Remote access is on for everybody by default (`Chaos.stash.remoteForEveryone`);
  otherwise storage `7100010 > 0` grants it. A depot/locker proximity requirement is not implemented.
- Only stackable, pickupable, attribute-free items are accepted; categories are heuristic (rune, ammo,
  potion/valuable by name, other).
- The `tooltip` field is a plain string; the client's `buildTooltip` is an engine extension whose expected
  type was not verified.
- `UpdateList` always echoes a fresh list, even on rejection, because the client depends on it.

## Tunables
Everything adjustable is in `chaos_constants.lua`: rewards, limits, boss names, season length, storages, table names.

## Monster tiers and monster bar

`data/scripts/chaos/monster_tiers.lua` (opcode 125, client `game_monsterbar`): magic, rare and legendary monsters (health, speed, damage and experience multipliers in `ChaosTiers`), a roll on every spawn (`spawnChance`), and an ambush: when a player kills a monster a magic, rare or legendary copy may appear next to the corpse (`ambush`, `ambushTier`, `maxChain`). All numbers are at the top of the file. Not run on a server; it assumes the base server `onSpawn` and `onGainExperience` event callbacks, `Creature:setMaxHealth`/`changeSpeed` and `Game.createMonster(name, pos, extended, force)`. Tier state is kept in memory only and is lost on reload. No name prefix is set in the world (there is no `Monster:setName`); the client prefixes the tier on the bar only. Tier and boss multipliers also do not change loot.

### Modifiers and shaders (monster_tiers.lua)
Every magic, rare, legendary and boss monster rolls modifiers: magic 1-2, rare 2-3, legendary 3-4, boss 4-5 (`modCount`). Thirteen modifiers in `ChaosMods`: Blazing, Chilling, Venomous and Shocking (on-hit conditions), Vampiric (heals from damage dealt), Berserker (more damage below half health), Brutal (+40% damage), Stoneskin (-30% damage taken), Reflective (reflects 15%), Regenerating (2% health every 2.5 s), Swift (+40 speed), Explosive (fire blast on death), Juggernaut (+60% health). The monster is drawn with the outfit shader of its strongest modifier, from the 17 shaders already in `data/XML/shaders.xml` (animated, glowing), and a rotating magic effect plays one modifier's icon at a time, so the look follows the modifiers. Only one shader fits one monster, so a monster with five modifiers shows the colour of the strongest one. Bosses get modifiers too (`bossMods`), without stat scaling. The names are listed under the bar. The client must register those shader names (base server does it in `game_shaders`; the base client base needs the same list, see below). Shader ids 5 ("blue Dortmond", name differs from the client's "blue_Dortmond") is not used.

The server also pushes `info` for tiered monsters to players within about 10 tiles every 15 s (from the monster's own 2.5 s tick), so the client can label them in the world without a query.

## Custom spells and spell effects
36 spells (`data/spells/chaos/`, installer `tools/register_spells.py`, table in `data/spells/README.md`) and 43 extra magic effects plus 10 projectiles (`data/lib/chaos_fx.lua`, catalog `data/spells/effects_catalog.csv`, merge commands in `data/spells/README_FX.md`). The spells load `chaos_fx.lua` themselves and fall back to standard effects if it is missing, so they work before the merged dat/spr is in use; the custom effects show only with that merged pair on the client. Effect ids above 255 work because the base server sends them as 16 bits and the client profile enables `GameMagicEffectU16`. Not run on a server. The client spell list and action bar need entries and icons for the new spells (see `data/spells/README.md`).

## Passive tree effects (`passivetree_effects.lua`)
The tree now has an effect: after every save, reset and login the summed node stats are applied.
- **Character stats** (strength, intelligence, dexterity, vitality, spirit, wisdom): added on top of the stat window, capped per stat (`charStatCap`) because the engine formulas are percentages (a dexterity above 100 would make the player take no damage). One node in the data carries 239 strength; the cap contains it. A 5 s check re-adds the bonus if the stat window rewrites the value.
- **Skills, magic level, critical hit, leech:** a permanent attribute condition (sub ids 7200 to 7219).
- **Absorbs:** the second absorb storage per damage type (977562 to 977575) that the stock absorb event already reads; `absorbAllElements` adds to the nine elements; capped at 80% from the tree.
- **Damage dealt:** `incrementX` for the type, `multiIncrement` for all elements, `incrementHealth` for healing; the event is registered on the target when a tree player attacks it.
- **Experience, loot, speed:** experience multiplier, the item-find storage that `loot.lua` reads (loot plus rarity loot), and `changeSpeed` by the difference (capped at 80).
- The conversion factors from node value to game value are in `cfg` at the top of the file (for example 1 point of experience = 0.1%), and the client tooltip shows the same numbers.
- `server/tests/passivetree_effects_test.lua` checks the maths and the apply/remove logic against a mocked engine API and runs in CI. It does not prove the real API calls (`Condition`, `setCharacterStat`, `changeSpeed`, `onTargetCombat`) behave as assumed: that needs a server run. Speed bonuses are not restored after a death or a speed-resetting spell until the next save or login.

## Infinity Tower gameplay (`infinitytower_run.lua`)
The tower exists now. `!tower start` (or the new Enter Tower button of the client window, action `enter`) takes you, or your party (leader only, members within 12 tiles, up to 4), into an arena that is built at runtime with `Game.createTile` in an empty part of the map (x from 2000, y 2000, z 7; sixteen arenas side by side), so no map editing is needed. Floors are waves: kill everything to open the next one (6 s pause, half of the missing health and mana restored, `floorGold` x floor gold); every 10th floor is a boss floor with its helpers. Pools get harder every 8 floors, and the chance of magic, rare and legendary monsters (with their modifiers and shaders) rises with the floor. A floor has a 300 s limit. Dying, leaving (`!tower leave`), logging out or running out of time ends your part of the run and records the cleared floors with `ChaosTower.recordRun` (points, best floor, ranking, milestones). Logging in inside an arena sends you to the temple. Milestone rewards now use item ids that exist (gold, Chaos and Divine Orbs, Soulreaper). Everything is configured at the top of the file (`ChaosTowerRunConfig`).
- `server/tests/infinitytower_run_test.lua` covers the floor planner, entering, clearing floors, dying, leaving, the time limit, logout and login with a mocked engine; CI runs it with LuaJIT and Lua 5.3. The real `Game.createTile`, `Tile:addItem`, `Game.createMonster` and teleport calls are assumed from the engine sources, not run.
- Not done: the season-end top 3 chests, a visible ladder of floors in the client window, and per-floor loot beyond what the monsters drop. Check that x 2000..2700, y 2000..2020, z 7 is really empty in your map (it is in the map analysed: the content starts at x 18992).

## Event calendar, boosted creature/boss and the login screen (`events_schedule.lua`, `clientservices.lua`)
- **Events** (`Chaos.events` in `chaos_constants.lua`): recurring server days with real bonuses. Blood Moon (Saturday and Sunday, +50% experience), Chaos Rift (Wednesday, magic/rare/legendary spawns x2 and ambushes x1.5), Loot Frenzy (Friday, +50% Chaos loot and one extra loot roll on every monster) and Tower Ascension (days 1-3 and 15-17 of the month, double Infinity Tower points). Days are given as `weekdays` (1 = Sunday) or `monthdays`. Active events are announced on login and with `!events`. The bonuses are read by `ChaosEvents.bonus(kind)` in the experience callback, `loot_config.lua` (`rateMult`), `loot.lua`, `monster_tiers.lua` and `infinitytower.lua`.
- **Boosted creature and boss:** the base server already picks them at startup (its lists and global storages). `clientservices.lua` reads that pick and falls back to `Chaos.boosted` when it is missing or names a monster that does not exist.
- **Login screen:** the client asks an HTTP endpoint for `boostedcreature`, `eventschedule` and `cacheinfo` (players online). The game server has no HTTP listener, so `clientservices.lua` writes the three answers to `data/chaos_clientservices.json` at startup and every 5 minutes, and `server/tools/clientservices.py` (standard library only) serves that file:
  ```
  python3 server/tools/clientservices.py <server>/data/chaos_clientservices.json --port 8090
  ```
  The client's `init.lua` (base patch 0001) points `clientServicesLink` and `Services.status` at `http://127.0.0.1:8090/clientservices`; change the host for a public server. A GET on the same URL returns everything, handy to check it from a browser.
- `server/tests/events_schedule_test.lua` checks the weekday/month-day rules, the bonus product, the calendar ranges sent to the client and the experience callback.

## Test kit (`admin/testkit.lua`)
`/testkit [mage|knight|paladin][, player]` (admins only) equips a strong set for the vocation (uniques where they fit), a backpack of supplies (potions, runes, crystal coins, Chaos and Divine Orbs), raises the level to 500 and the main skills (magic level 110 for mages, 120 melee or 125 distance), and resets health and mana to the vocation's values. Relog afterwards so the stock rarity script applies the item bonuses.

## Store (`shop.lua`, `shop_config.lua`)
The client's Store (menu Economy -> Store, module `game_shop`) talks JSON on extended opcode 218 (`ChaosOpcodes.shop`; the base server's own store script uses 201 and is left alone). Prices are in Chaos Coins, kept per account in `chaos_shop_coins`; purchases go to `chaos_shop_history` (both in `sql/chaos.sql`). Staff give coins with `/coins <player>, <amount>` (negative takes them away). Categories and offers are in `shop_config.lua`: Chaos and Divine Orbs, supplies, wings, auras and outfit shaders (names and previews read from `data/XML/wings.xml`, `auras.xml`, `shaders.xml`), outfits, mounts and premium time. Wings, auras and shaders are bought once (storages 7100600+); outfits and mounts check whether the player already has them; a delivery that fails refunds the coins. Tested in game: buying an item and wings, refusing a second purchase of the same wings, coins and history in the database.
