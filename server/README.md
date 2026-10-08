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
    dungeons.lua  infinitytower.lua  stash.lua  spell_guard.lua (Iron Will damage reduction of the Iron Bellow spell)
    combat_fx.lua (crit / dodge / reflect / elemental weapon hit visuals, ChaosCombatFx)
  src-patches/0001-critical-hit-to-lua.patch   engine: onHealthChange gets `critical` (combat_fx.lua)
    shop.lua  shop_config.lua  shop_services.lua  autosell.lua  sell_prices.lua (store, see "Store services")
```

## Install

1. Copy `server/data/scripts/chaos/` to `<server>/data/scripts/chaos/`.
2. Run `server/sql/chaos.sql` against the game database (`mysql -u USER -p DB < chaos.sql`).
   Foreign keys assume `players.id` is `int(11) NOT NULL` (stock TFS schema).
3. Spells: `python3 -I server/tools/register_spells.py <server>/data` (Chaos spells) and
   `python3 -I server/tools/rename_spells.py <server>/data --sql rename_spells.sql` (Chaos names for the stock
   spells and runes; apply the SQL once). See `data/spells/README.md`.
4. Experience bonuses: `python3 -I server/tools/patch_base_events.py <server>/data` (once; idempotent). The base
   server's `Player:onGainExperience` (`data/events/scripts/player.lua`) never runs the script callbacks, so
   without it every Chaos experience bonus is silently ignored: Blood Moon, the passive tree's experience nodes,
   monster tier experience, and the store's world buffs. The patch adds the dispatch after the stage, stamina
   and potion multipliers (verified on the test server: +2% passive bonus -> exactly 1.02x the experience).
5. Restart the server (or `/reload scripts`). Check the console for Lua errors.
6. Autoloot only: if `data/talkactions/talkactions.xml` registers `!autoloot` (the legacy
   `talkactions/scripts/autoloot.lua`), TFS 1.4.2 keeps the XML one and silently ignores
   `autoloot.lua`'s `!autoloot`. Remove that XML line for live window refresh. See "Stubbed or assumed".
7. Client: apply the client-side gaps listed below, otherwise bank, autoloot, daily and stash
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
| game_spellbook | `spellbook.lua` | 219, `!spells` / `/spells` | Spell list window: every player spell of `data/spells/spells.xml` with its data, a short description and its area of effect (see "Spellbook" below). |

Extended opcodes 60, 65, 79, 109, 110, 151, 152, 207, 214, 216, 218, 219 are all registered in the global
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
36 spells (`data/spells/chaos/`, installer `tools/register_spells.py`, table in `data/spells/README.md`) and 52 extra magic effects plus 10 projectiles (`data/lib/chaos_fx.lua`, catalog `data/spells/effects_catalog.csv`, build commands in `data/spells/README_FX.md`). All spell effects are our own procedurally drawn art (`client/tools/sprites/gen_effects.py`): it appends the 52 + 10 and also redraws, at the same ids, the 83 stock effects and 25 stock missiles that spells and spell hits use, so stock spell scripts need no change. The spells load `chaos_fx.lua` themselves and fall back to standard effects if it is missing, so they work before the generated dat/spr is in use; the custom art shows only with that pair on the client. Effect ids above 255 work because the base server sends them as 16 bits and the client profile enables `GameMagicEffectU16`. Not run on a server. The client spell list and action bar need entries and icons for the new spells (see `data/spells/README.md`).

## Combat feedback (`combat_fx.lua`, `src-patches/0001-critical-hit-to-lua.patch`)

What the engine already does: a weapon with an element (items.xml `elementFire` etc.) hits with one combat whose
primary is physical and whose secondary is the element; `Game::combatChangeHealth` sends both values in one damage
message with their own colours (physical by race, e.g. red on blood; fire orange, ice sky blue, energy purple, earth
light green, death dark red, holy yellow) plus the stock hit effect of each type, and the client draws two numbers side
by side (verified on the test server: fire sword on a dummy shows an orange and a red number). The rarity modifier
"adds X% <element> damage" (`customs/rarity/rarity_onCombat_elementdamage.lua`) adds its part to the same secondary
damage, so it shows the same way. Nothing had to change for the numbers.

`combat_fx.lua` adds, for any player attack (event registered on the target from `onTargetCombat`, index 50, after the
rarity and passive-tree damage events):
- elemental weapon hit (origin melee, ranged or wand, secondary damage of an element type; water and arcane use the
  ice / energy art): `imbue_<element>` (418..423) on the target. Falls back to the rarity storages when the rarity
  script has not added its part yet.
- critical hit: `crit_burst` (415) and a yellow "CRIT!" (animated text, opcode 0x84, sent to the spectators). Needs the
  engine patch below; without it `critical` is nil, nothing is added and the engine keeps its own
  `CONST_ME_CRITICAL_DAMAGE`.
- `ChaosCombatFx.dodge(creature)`: `dodge_whoosh` (416) + grey "DODGE"; `ChaosCombatFx.reflect(creature)`:
  `reflect_aegis` (417) (label off by default). Neither the engine nor our scripts had a dodge; the only reflect is the
  monster modifier "Reflective" (`monster_tiers.lua`, which now calls `reflect`). Keystones or items that add dodge or
  reflect call these (`if ChaosCombatFx then ChaosCombatFx.dodge(player) end`).
- `ChaosCombatFx.crit(pos[, sourceId])`, `.element(pos, combatType[, amount[, sourceId]])`, `.label(pos, text, color)`.
- `ChaosCombatFx.config`: `enabled`, `crit`, `critLabel`, `dodge`, `dodgeLabel`, `reflect`, `reflectLabel`, `element`,
  label texts and colours, and the throttle: per source and kind at most `perSource` (3) visuals per `windowMs`
  (300 ms), one per tile and kind per `tileMs` (200 ms), one label per source and kind per `labelMs` (600 ms). An area
  spell that crits 20 monsters shows 3 bursts and one "CRIT!".

Engine patch (only where the server is built from source): `patch -p1 < server/src-patches/0001-critical-hit-to-lua.patch`
in the server source root, rebuild. It pushes `damage.critical` as the 8th argument of `onHealthChange` (existing
scripts ignore it) and removes the two `CONST_ME_CRITICAL_DAMAGE` effects in `combat.cpp`. Tested on the test server
(TFS build from this source, objects of `combat.cpp` and `creatureevent.cpp` recompiled and relinked).

## Passive tree points

One passive point every `Chaos.passive.levelsPerPoint` (4) levels above level 8, plus `passiveExtraPoints` from quests/GMs:
about 248 points at level 1000 against 618 nodes, so the tree cannot be completed and each build has to choose a path.
On login, a preset holding more nodes than the character's points is emptied for free with a message (this covers
characters made under the old 1-point-per-level rate). Planned later: a Paragon track that takes the points a character
earns once the tree's budget is reached, for small capped bonuses.

## Passive tree effects (`passivetree_effects.lua`)
The tree now has an effect: after every save, reset and login the summed node stats are applied.
- **Character stats** (strength, intelligence, dexterity, vitality, spirit, wisdom), capped per stat (`charStatCap`), get the
  engine's effect without being written into the character's stats (those are the stat window's points and are saved with the
  player; writing them made the bonus stack on every login and let the stat window refund it as free points): strength /
  intelligence multiply damage dealt by `1 + value/230` (physical / other types, the engine formula), dexterity multiplies weapon
  hits by `1 / (1 - value/100)` (the damage equal of the engine's faster attacks, which a script cannot set), vitality / spirit
  are +value% max health / mana conditions, wisdom has no effect in the engine. Characters whose stats an older version
  inflated are clamped once to the stat window maximum on login (`passiveStatsFixed` storage).
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
The client's Store (menu Economy -> Store, module `game_shop`) talks JSON on extended opcode 218 (`ChaosOpcodes.shop`; the base server's own store script uses 201 and is left alone). Prices are in Chaos Coins, kept per account in `chaos_shop_coins`; purchases go to `chaos_shop_history` (both in `sql/chaos.sql`). Staff give coins with `/coins <player>, <amount>` (negative takes them away). Categories and offers are in `shop_config.lua`: Chaos and Divine Orbs, supplies, wings, auras and outfit shaders (names and previews read from `data/XML/wings.xml`, `auras.xml`, `shaders.xml`), outfits, mounts and premium time, plus boosts, world buffs, services, convenience unlocks and training weapons (see "Store services"). The two outfit offers give female characters the female look type (910, 1238; they gave the male one before). Wings, auras and shaders are bought once (storages 7100600+); outfits and mounts check whether the player already has them; a delivery that fails refunds the coins. Tested in game: buying an item and wings, refusing a second purchase of the same wings, coins and history in the database.

## Store services (`shop_services.lua`, `autosell.lua`, `sell_prices.lua`)

Five store categories sell services, unlocks and boosts besides the cosmetics. `shop_config.lua` has two new offer kinds,
both dispatched by `ChaosShopServices` (`shop_services.lua`):
- `{kind = "service", service = "<handler>", icon = <item id>}`: done for the character at once (`S.services` table).
- `{kind = "unlock", unlock = "lootPouch" | "autoSeller"}`: a permanent per-character flag (storage).

`shop.lua` asks `ChaosShopServices.check(player, offer)` **before** it takes coins: an unlock already owned, full stamina, a
world buff at its cap, an unused token, no skull to remove, an empty passive tree... is refused with a message and costs
nothing. Then the coins are taken and `ChaosShopServices.deliver` runs; a delivery error (no room for a scroll, a script
error, caught with `pcall`) refunds the coins, as for the other offers. Icons and descriptions come from the server; the
client module needed no change.

| Category | Offer | Coins | What it does |
|---|---|---|---|
| Boosts | Stamina Refill | 40 | stamina to 42 h at once (refused when full) |
| | Stamina Extension | 8 | the base server's item 27990 (+2 h when used) |
| | Double Experience Potion / 5 potions | 50 / 225 | the base server's item 28095: x2 experience for 1 h per potion (storage 6000, `!exp`) |
| | All Blessings | 60 | blessings 1-5 (refused when all are owned) |
| World Buffs | World Experience | 300 | +25% monster experience for everybody, 1 h, up to 3 h |
| | World Loot | 300 | +25% Chaos loot (`rateMult`) and one extra loot roll on every monster, like the Loot Frenzy event, 1 h, up to 3 h |
| | World Training | 250 | +25% skill and magic level tries for everybody, 1 h, up to 3 h |
| Services | Name Change | 250 | a token for `!changename` |
| | Vocation Change | 400 | a token for `!changevocation` |
| | Sex Change | 100 | at once; every owned outfit and addon is copied to the other sex (pairs by name in `data/XML/outfits.xml`) |
| | Frag & Skull Remover | 150 | skull time (the engine's unjustified-kill counter) to 0, red/black skull removed; not in combat |
| | Passive Tree Reset | 60 | empties every preset for free (the in-window reset costs level x 250 gold) |
| Convenience | Temple Teleport Scroll / 25 uses | 5 / 80 | see below |
| | Bottomless Loot Pouch | 500 | unlock, see below |
| | Auto Seller | 500 | unlock, see below |
| Training | 21 exercise weapon chests | 25 / 75 / 450 | the base server's chests: sword, axe, club, bow, rod, wand, shield with 500 / 1800 / 14400 charges |

Premium (250 for 30 days) stays where it was.

**Temple Teleport Scroll.** An ordinary "scroll" (item 6119, used by no other script) with action id 47301, the name
"temple teleport scroll", a description and the uses left in the custom attribute `chaos_uses`; no new item id. Using it
takes you to your town's temple. Refused with a battle sign or PZ lock, inside a dungeon run (`ChaosDungeonIsInside`), the
Infinity Tower (`ChaosTowerRun.isInside`) and the world boss lobby/arena (`ChaosWorldBoss.inside`). 2 s cooldown. The stash
refuses it (action id), so it stays an item.

**World buffs.** A purchase broadcasts "<buyer> activated the World Experience ..." to everybody (and fireworks); buying
while it runs extends it ("<buyer> extended ..."). A purchase that would leave more than 180 minutes is refused before
coins are taken. The expiry times are global storages 7100921 (xp), 7100922 (loot), 7100923 (skill) and rows
`chaos_worldbuff_xp|loot|skill` of the stock `server_config` table: they survive `/reload` and a **restart** (checked on
the test server). `!worldbuffs` lists the active ones with the time left; players get the list at login; the end is
broadcast (30 s check). Experience: `EventCallback.onGainExperience` (needs `patch_base_events.py`), monsters only.
Training: `EventCallback.onGainSkillTries`, which the base `player.lua` already dispatches (no patch needed); one try
x1.25 becomes 1 or 2 tries at random, so small gains are not rounded away. Loot: `loot_config.lua` `rateMult` and the
extra-roll rule in `loot.lua`.

**Name change.** `!changename <New Name>` (needs the token, out of combat, in a protection zone). Rules
(`ChaosShopServices.validateName`, settings `Chaos.shopServices.name`): 3-20 characters, letters and single spaces, at most
3 words of at least 2 letters, each word is capitalised for you ("kael vorn" -> "Kael Vorn"), no letter three times in a
row, no staff word as a word (GM, CM, God, Admin, Tutor, Gamemaster, ...), no forbidden substring, not a monster name, not
taken (`players.name`). Then: the token is used, the character is saved and kicked, and 0.5 s later (retried each second
while it is still online) `players.name` is updated together with the tables that keep names as text: the member list of
`chaos_dungeon_runs` (runs the character took part in), `player_deaths.killed_by` / `mostdamage_by` (player killers) and
`guildwar_kills.killer` / `target`. If the name was taken in between, the token is given back. `chaos_admin_log.player_name`
is an audit log and keeps the old name. All other Chaos tables use the player id.

**Vocation change.** `!changevocation <knight|paladin|sorcerer|druid|illusionist>` (token, out of combat, in a
protection zone; your own vocation is refused). A promoted character gets the promoted id (`Chaos.shopServices.vocations`:
sorcerer 1/5, druid 2/6, paladin 3/7, knight 4/8, illusionist 9/10). Health and mana are recomputed as the engine counts
them, 185 / 90 at level 8 plus (level - 8) x the new vocation's gain; capacity keeps whatever the character has outside the
level gains: cap + (level - 8) x (new gain - old gain). Skills and magic level are **kept** as they are (a knight turned
sorcerer keeps its sword skill and its low magic level). The passive tree is reset for free (`ChaosPassiveTree.resetAll`).
Items restricted to the old vocation stay equipped.

**Bottomless Loot Pouch.** An `onDropLoot` callback with index 4, after the base autoloot (3): every item of the autoloot
list still in a corpse you own is tried once more (the base callback stops at the first item that does not fit), then put
into the supply stash when the stash takes it (stackable, no attributes, not on the block list) or else into your inbox
(gear with a rarity keeps its attributes there). "Loot pouch: your backpack is full, loot sent N to your stash and M to
your inbox" at most once a minute. Note that the base autoloot only fails on a full backpack, not on capacity (the
engine's `moveTo` ignores capacity).

**Auto Seller.** `onDropLoot` index 2 (after the Chaos loot layer at 1, before the autoloot at 3): items on your auto-sell
list are taken out of corpses you own and sold at the NPC price; the gold goes into your bank balance and one loot
message per corpse lists what was sold. The list is separate from the autoloot list (no autoloot slot needed), up to 40
items. Items with a rarity, Chaos modifiers or a custom name/description/text (any custom attribute) are kept unless you
opt in; uniques (`chaos_unique`) are never sold. Containers are not sold.
```
!autosell add <item name>      only items an NPC buys
!autosell remove <item name>
!autosell list | clear | on | off
!autosell rarity on|off        opt-in for items with a rarity or modifiers
```
Prices: `sell_prices.lua`, generated by `python3 -I server/tools/gen_sell_prices.py <server>/data` from the NPC shops
(`shop_sellable` parameters of `data/npc/*.xml`, `addSellableItem` and `{..., sell = n}` tables of `data/npc/scripts/*.lua`,
highest price any NPC pays; 1377 items with the reference data). Regenerate after NPC changes. The client's autoloot window
was not extended; the list is managed by chat command.

**Storage keys** (all in `chaos_constants.lua`): 7100100 Loot Pouch, 7100101 Auto Seller, 7100102 auto seller paused,
7100103 rarity opt-in, 7100104 name change tokens, 7100105 vocation change tokens, 7100111-7100150 auto-sell list; global
7100921-7100923 world buffs. Settings: `Chaos.shopServices`.

**Tests.** `server/tests/shop_services_test.lua` (LuaJIT and Lua 5.3): name rules, buff stacking and the cap, buff
effects and the reload from `server_config`, vocation mapping and stat recomputation, sell prices and the keep rules,
unlock/service checks, the auto seller and the loot pouch callbacks against mocked items and corpses.

**Verified in game** (test server, client screenshots): every new category and offer renders with icon and description;
buying stamina, blessings, potions, a training chest, both scrolls, both unlocks, the three world buffs, both tokens, sex
change, skull remover and passive reset; refusals without coin loss (full stamina, unlock owned, buff at the cap, token
unused, nothing to remove/reset); refund when the backpack had no room; the scroll teleports, counts down and is refused
with a battle sign and in the world boss arena; world experience x1.25 on a real kill, skill tries x1.25 through the
engine, loot multiplier 1.25; buffs still active after a server restart, listed at login and by `!worldbuffs`; the auto
seller sold plain items to the bank and kept rarity/unique items (rarity sold after the opt-in, nothing sold while off);
the loot pouch sent a stackable to the stash and gear to the inbox with a full backpack; `!changename` renamed the
character (and its dungeon run entry) and back; `!changevocation` paladin -> knight -> paladin returned exactly the
original health, mana and capacity.

## Spellbook (`spellbook.lua`)
`!spells` (or `/spells`, or Character -> Spellbook in the client menu) opens the client window `game_spellbook` on extended opcode 219 (`ChaosOpcodes.spellbook`). The list is read from the running server's own files, so renamed stock spells, the Chaos spells and anything added later show up without a client update:
- `data/spells/spells.xml`: every `<instant>`, `<rune>` and `<conjure>` (name, words, level, magic level, mana, soul, cooldown, group, premium, range, vocations, rune item id). Monster spells (words starting with `#`) and house spells (`house/` scripts) are skipped.
- `data/spells/scripts/<script>` is read as text, never run: element (`COMBAT_PARAM_TYPE`, `doAreaCombat`/`doTargetCombat`/`damageTarget` arguments), kind (damage, heal, buff, summon, conjure, utility), area (the largest `createCombatArea(...)`: an `AREA_*` table of the spell library, an inline table literal, which is loaded only when it holds nothing but digits, commas and braces, or a local table of the same script), scaling (magic level, skill x weapon attack, distance skill x weapon attack). Chaos spells use the first comment line of their script (`-- <Name>: <description>`); stock spells get a generated one ("Single-target fire damage.", "Fire damage in front of you (wave).", "Heals you and cures paralysis.", "Conjures 4 x 'searing orb rune'.").
- Parsed once at startup when the `AREA_*` tables already exist, otherwise on the first `!spells`; `/spells reload` (staff) parses again after a spell change. A player can open it once every 2 seconds.
- Protocol (JSON `{action, data}`): `open` {vocation, level, magicLevel, total, chunks, vocationNames [{id, name}]}, then `spells` {index, spells [...]} until all are sent (about 6.5 KB of JSON per packet), then `done` {total}. A spell: name, words, level, maglevel, mana, manaPercent, soul, cooldown and groupCooldown (ms), group, type, element, target (`single`/`area`/`self`/`front`), center (`caster`/`target`), area (matrix, 1 = hit, 2 = centre, 3 = centre and hit; `front` spells drawn facing north), range, description, scaling, vocations (ids), premium, rune and runeClientId. The client sends `open` to ask for the same answer.
- With the reference spell set (234 player spells) that is 14 packets, about 76 KB.
- `server/tests/spellbook_test.lua` (fixtures in `tests/fixtures/spellbook/`) covers the XML parsing, named, inline and local areas, refusal of unsafe or malformed inline tables, the classification and descriptions, the chunking and the talkaction/opcode flow. Not run on a server.

## Multi-client (`multiclient.lua`)

At most `Chaos.multiClient.maxPerIp` (2) characters per IP can be online; a further login is refused with a popup
(the base server's own anti-mc script allows 4, the lower limit wins). While a character has another character online
from its IP it cannot queue for dungeons (`dungeons.lua` entry check), start or join the Infinity Tower
(`infinitytower_run.lua`) or attack players (EventCallback onTargetCombat; the Chaos spells that deal damage from
their script repeat the check in `ChaosSpell.canAttack`). A second character cannot log in while the first is inside a
dungeon run or the tower. Gamemasters and up are exempt; `Game.setStorageValue(7100990, 1)` switches the blocks off
(not the login limit). Tested with two live clients on one IP: spells did 0 damage to the other character, the tower
refused entry, a third login was refused.

## Weapon styles (`weapon_styles.lua`, `tools/two_handed.py`)

- Two-handed weapons (swords, axes, clubs, bows, crossbows) attack 1.5x slower and hit 1.6x harder (about +7% damage
  per second over one hand + shield). Run `python3 -I server/tools/two_handed.py <server>/data` once: it raises the
  `attackspeed` of the two-handed weapons in items.xml (2000 -> 3000 ms, 1800 -> 2700 ms; idempotent). The extra damage
  is applied by `weapon_styles.lua` to weapon hits only (spells, runes and wands are not affected).
- Arrows splash: creatures around the target take 50% of the hit (normal PvP / protection zone rules). Bolts hit only
  their target.

## World bosses (`worldboss.lua`, `data/monster/monsters/chaos/world_bosses/`)

A server-wide event: a portal opens next to every temple, players gather in a lobby, one of five world bosses appears in an
arena built at runtime, and everyone who did real damage is rewarded, not only the corpse owner. Settings: `Chaos.worldBoss`
in `chaos_constants.lua`. Not run on a server; `tests/worldboss_test.lua` covers the layout, schedule, rotation, phases,
damage shares, rewards and the whole event flow against a mocked engine (LuaJIT and Lua 5.3).

**Install.** Copy the XMLs to `<server>/data/monster/monsters/chaos/world_bosses/` and register them:
`python3 -I server/tools/register_monsters.py data/monster/monsters.xml data/monster/monsters/chaos/world_bosses`.
The script itself loads with the rest of `data/scripts/chaos/`. Without the XMLs `/worldboss start` refuses with "not loaded".

### The bosses

All five have `<flag isboss="1"/>` (monster_tiers.lua also lists them in `cfg.bosses` as a fallback), so the client gets
the `boss` tier and draws them bigger; worldboss.lua also pushes the tier to players in the arena every 3 s. They are in
monster_tiers' `cfg.skip`: no random modifiers (Regenerating, Juggernaut or Explosive would wreck a tuned fight).

| Boss | Health | Main attacks (per 2 s check) | Phases (script) | Weak / immune | Loot highlights |
|---|---|---|---|---|---|
| Kaelgor the Infernal Warlord (fire warlord, look 842) | 18M | melee 2.5-5.5k, fire wave 3.5-6k, meteor r3 3-5k, warstomp r5 2.5-4.5k, burning DoT 4-7k, slow | 70% 4 Hellfire Fighters, 40% enrage (fire nova r6 2.5-4k / 8 s), 15% 4 Hellspawn | ice -15% / fire 60% resist | Dawnforged set (plate, longsword, chopper, helmet, shield, ring) |
| Skaldra the Rime Queen (frost wyrm queen, look 1472) | 16M | melee 2-4.5k, rime breath (length 9) 3.5-6.5k, hailstorm r3 3-5.5k, shatter r6 2.5-4k, frostbite DoT 6-9k, slow r4 | 70% 3 Frost Dragons, 40% enrage (blizzard r7 2-3.5k / 7 s), 15% 4 Ice Golems | fire -20% / ice immune | Seraphic set (tabard, piercer, greaves, quiver, ring), Myst galoshes |
| The Rotmother (plague abomination, look 238) | 22M | poisoned melee 2-4k, bile wave 3.5-6k, spore burst r4 3-5k, miasma DoT r6 6-10k, lifedrain 2.5-4k; heals 40-60k | 75% 5 Defilers, 50% 4 Plaguesmiths, 25% enrage (miasma r8 1.5-2.5k / 6 s) | fire -25%, holy -10% / earth immune | legs and boots of all three sets, Myst amulet |
| Nyxareth the Void Archon (void caster, look 862, keeps distance 4) | 15M | oblivion bolt r3 3.5-6k, rift beam (length 8) 4.5-8k, mana drain r6 3-5k, curse DoT 5-8k, drunk r5 | 70% 4 Phantasms, 40% enrage (void pulse r7 2.5-4k / 7 s), 15% 4 Lost Souls | holy -25%, physical -10% / death immune | Myst Regalia set (helmet, mantle, spellbook, wand, ring), Seraphic necklace |
| Vharok the Blood Colossus (blood colossus, look 591) | 24M | bleeding melee 3-6.5k, crimson cleave wave 4-7.5k, quake r4 3-5k, blood leech r3 3-5k, hemorrhage DoT 6-9k; heals 60-100k | 75% 4 Blood Beasts, 45% enrage (blood nova r6 2.5-4.5k / 7 s, +5k health per player hit), 20% 3 Juggernauts | holy -20% / physical 40% resist, lifedrain immune | Dawnforged plate, great axe, skull crusher, mace, amulet; Seraphic helmet |

Every boss: 55-75 crystal coins, 12-15 Chaos Orbs, 5-7 Divine Orbs (80-90%), 4-6% per set item; immune to paralyze,
invisibility, outfit and drunk. Adds get the configured health (100k-200k) so they matter at level 1000. Look types are
outfits other monsters already use (1472 needs the merged dat, see `data/monster/CUSTOM_MONSTERS.md`); corpses are stock
containers (slain demon, dead frost dragon, dead defiler, dead juggernaut).

**Why these numbers.** Measured single-target damage per second: level 300 about 400-700, level 1000 with the best gear
about 1300-3200. With ~70% uptime (movement, deaths, healers who do not attack):

| Group | Raw DPS | Effective | Nyxareth 15M | Skaldra 16M | Kaelgor 18M | Rotmother 22M | Vharok 24M |
|---|---|---|---|---|---|---|---|
| 20 x level 1000 | ~45k | ~31k | ~8 min | ~9 min | ~10 min | ~13 min | ~15 min |
| 15 x level ~700 | ~22k | ~16k | ~17 min | ~18 min | ~20 min | ~27 min | ~32 min |
| 10 x level 300 | ~5.5k | ~3.9k | > 60 min: fails the 45-minute limit |

(Self-healing is included: 1.2-3.2k health per second on average from the XML heals, Vharok up to ~3.5k more while
enraged.) Resistances shift this per vocation (Vharok resists 40% physical). The 5-target numbers (2400-6300 at level 1000)
only count against adds. Incoming damage: single hits 2.5-8k (the 8k rift beam and 7.5k cleave are the spikes), DoTs of
4-10k total over ~20-40 s, so a 9k-health level 1000 character survives one big hit and a 27k tank survives several,
with a healer. Level 300 characters (3-5k health) can be one-shot by the spikes; they should stay at range.

### Arena (built in code)

`Game.createTile` + ground/wall items, like the Infinity Tower; nothing is saved to the map. Coordinates (z 7):
- Arena x 5000-5032, y 5000-5032 (31 x 31 inside walls), black marble floor, stone walls, four stone pillars as cover at
  the centre +-7, coal basins in the corners. Boss spawn: centre 5016, 5016. Players arrive at 5016, 5029; the forcefield
  at 5016, 5031 goes back to the lobby.
- Lobby x 5009-5023, y 5040-5048 (13 x 7 inside), seven empty rows south of the arena so the boss can never see or reach it.
  Arrival 5016, 5046; forcefield to the arena at 5016, 5041; forcefields home (own temple) at 5010, 5044 and 5022, 5044.
- Free area: the map file was scanned for tile areas (OTBM tile-area nodes): the nearest content is around x 1024-2047,
  y 3072-4095; nothing exists within x/y 4500-5600. Other runtime areas: Infinity Tower x 2000-2660, y 2000-2020; the
  balance test harness 1490-1510. Before building, every tile of the footprint is checked: a tile that already exists and
  is not ours (other ground or a house) stops the build ("arena not built: tile x,y,z already exists").
- The lobby is protected by script (no combat against players in it); the engine has no Lua call to give a dynamic tile the
  protection-zone flag. PvP is blocked in lobby and arena (`allowPvp = false`). Deaths in the arena are normal deaths.
- Forcefields are item 1387 (magic forcefield, type teleport) **without destination** and with action ids 47201-47204;
  MoveEvents do the moving, so monsters that step on them stay put and the entry rules are checked.

### The event

- **Schedule:** every `intervalHours` (6) at full hours offset by `offsetHours` (3): 03:00, 09:00, 15:00, 21:00 server time,
  with broadcasts 10, 5 and 1 minute before. A GlobalEvent checks every 30 s. `events_schedule.lua` was not reused: it
  handles whole-day bonus events for the calendar, not timed spawns. `enabled = false` turns the schedule off.
- **Start** (`/worldboss start [name|number|random]`, staff only; no argument = the configured mode): the arena is built,
  a portal appears next to every distinct temple of `Game.getTowns()` (first free tile of `portalOffsets`: walkable, not a
  house, no other teleport; or exactly at `portalPositions`), broadcast + toast (game_chaosnotify `gmBroadcast`, no client
  change). Entry: level 300+, at most 40 players inside. The boss appears after 120 s; portals stay 30 minutes.
- **Boss choice:** `mode = "rotation"` (next one each time; the last index is a global storage, in memory) or `"random"`
  (never the same twice in a row).
- **End:** the boss dies (victory, rewards, broadcast with the top 3 and the time), or 45 minutes pass (it withdraws), or
  `/worldboss stop`. Town portals and adds disappear at once; after 90 s (10 s on stop) everybody still inside goes to their
  temple and the arena is cleaned (monsters, corpses, loose items). Logging in inside the arena when no event runs sends you
  to the temple.
- `!worldboss` (everyone): next start and boss, or the running fight (health %, minutes left). `/worldboss arena` (staff):
  builds the arena if needed and takes you to the lobby, to look at it without an event.

### Rewards

- The corpse works as for any monster: the engine's loot goes to the top damage dealer (corpse owner), plus the Chaos loot
  layer with the `boss` tier (extra rolls, gear rarity floor 6, currency, and the boss-only uniques of
  `chaos_unique_items.lua`, which now list the five world bosses).
- **Participation reward** for every player whose damage reached `minDamagePercent` (0.25%) of the boss max health
  (~40-60k damage, about 1.5 minutes of a level 300 hitting it). Damage is counted per character (GUID) by a healthchange
  event on the boss (summons count for their master, healing does not, overkill is clamped to the health left).
  share = own damage / damage of all eligible players. Each gets: 500k gold + share x 10M gold into the bank, 3 Chaos Orbs +
  1 Divine Orb + share x (60 Chaos Orbs, 25 Divine Orbs), the top 3 extra Divine Orbs and crystal coins, a 15% + share x 30%
  chance of one piece of the boss's set (rarity 6-9 via `Game.createItemWithRarity`) and a 0.5% + share x 3% chance of one
  of the boss-only uniques. Items that do not fit go to the inbox. Players offline at the kill get it at their next login
  (kept in memory until a restart).
- **Multi-client:** characters with another character online from their IP may enter and fight (they already cannot attack
  players, and blocking entry would split friends sharing a connection), but get no participation reward (`mcReward = false`)
  and are told so at entry and at the end. A character counts if it was multi-clienting at entry or at any 3-second check
  while inside. Corpse loot is not affected (it follows the engine's damage rules).

### Not verified (needs a server run)
Monster XML loading of the five files (attack names, effect names and flags were checked against the engine source: every
`areaEffect`/`shootEffect` value is in the engine's name tables), dynamic-tile building and the forcefields' step-in with no
destination, `Game.getTowns()` temple spots on the real map, the reward delivery (`addItemEx`/inbox, bank), the client
showing the boss tier, and the actual fight balance. Monster damage may be scaled by the server's own monster level system.
