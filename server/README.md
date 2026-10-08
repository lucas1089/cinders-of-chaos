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
  sql/chaos.sql                       CREATE TABLE IF NOT EXISTS for 13 tables
  tools/gen_passivetree_data.lua      regenerates passivetree_data.lua from the client tree
  tools/late_game.py, late_game_spawns.csv   late game stages and spawns (see "Late game")
  data/scripts/chaos/
    chaos_constants.lua               ALL opcodes, storage keys, table names, tunables, shared helpers
    bank.lua  autoloot.lua  daily.lua  notifications.lua  passivetree.lua  passivetree_data.lua
    dungeons.lua  infinitytower.lua  stash.lua  spell_guard.lua (Iron Will damage reduction of the Iron Bellow spell)
    combat_fx.lua (crit / dodge / reflect / elemental weapon hit visuals, ChaosCombatFx)
    classes.lua  ascension.lua                     the classes (docs/CLASSES.md): class rules, !ascend
    class_migration.lua                            one-time move of the old vocations (startup SQL + login message)
    thief_combat.lua                               the Thief line: stealth / evasion / poison blades / dual wield / counter / bushido
    berserker_combat.lua  beastmaster.lua          Berserker Rage and Bloodrage; the Beastmaster's companion
  data/XML/chaos_vocations.xml        the class entries (ids 1, 3, 4, 5, 7, 8, 10-15), installed by tools/add_vocations.py
  tools/add_vocations.py              writes them into data/XML/vocations.xml (2, 6, 9 retired) and converts the vocation lists
                                      of spells.xml / weapons.xml / movements.xml (+ potions.lua, lib/core/player.lua)
    paragon.lua (Paragon track past the passive tree, see "Paragon")
  src-patches/0001-critical-hit-to-lua.patch   engine: onHealthChange gets `critical` (combat_fx.lua)
  src-patches/0002-dual-wield-and-vocation-attack-speed.patch   engine: a Ninja may hold a sword in the shield hand;
                                      weapon attack speed scaled by the vocation's (thief_combat.lua)
    shop.lua  shop_config.lua  shop_services.lua  autosell.lua  sell_prices.lua (store, see "Store services")
    bounty.lua  bounty_core.lua  bounty_config.lua  bounty_pool.lua (bounty board; pool from tools/gen_bounty_pool.py)
    crafting.lua (crafting bench and orbs; rules in data/lib/chaos_crafting.lua, installer tools/install_crafting.py)
    treasure_goblin.lua  treasure_goblin_core.lua  treasure_goblin_config.lua (treasure goblins, see "Treasure goblins")
    leaderboard.lua  leaderboard_core.lua  leaderboard_config.lua (weekly boards with titles, class ladder)
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
   The same tool makes the base loot callback (`data/scripts/eventcallbacks/monster/default_onDropLoot.lua`) apply
   the waystone character upgrades "Loot" (item drop chances x(1 + level/100)) and "Rarity" (+level % to roll a
   rarity, +level/2 % per tier); `data/scripts/chaos/waystone_bonuses.lua` applies the "Experience" upgrade
   (+1% per level, x2.0 at level 100). Before, all three only stored their level and nothing read it.
   Verified on the test server: Experience 50 -> x1.5; Loot and Rarity 100 over 300 Dragon kills: items
   985 -> 1279, items with a rarity 81 -> 212.
5. Late game: copy `server/data/monster/monsters/chaos/*.xml` to `<server>/data/monster/monsters/chaos/` (17 of them
   are tuned for levels 650-1000), then `python3 -I server/tools/late_game.py <server>/data` (idempotent; `--dry-run`
   shows what would change, `--remove` undoes it). It writes the new `experienceStages` into `config.lua` and puts the
   level-scaled monsters of `server/tools/late_game_spawns.csv` into the loaded map's spawn file. See "Late game".
5b. Classes: `python3 -I server/tools/add_vocations.py <server>/data [--dry-run]` (idempotent). It writes the classes of
   `data/XML/chaos_vocations.xml` into `data/XML/vocations.xml` between marker comments (Warrior 4 / Juggernaut 8 / Berserker 14,
   Ranger 3 / Deadeye 7 / Beastmaster 15, Mystic 1 / Elementalist 5 / Illusionist 10, Thief 11 / Ninja 12 / Samurai 13; the base
   entries with those ids are replaced, 2, 6 and 9 removed), converts the stock vocation lists of `spells.xml`, `weapons.xml` and
   `movements.xml` to the classes once (Berserker: two-handed weapons, no shields; Beastmaster: bows and arrows), adds the Berserker /
   Beastmaster to the knight / paladin potions of `actions/scripts/other/potions.lua` and to `Player.isKnight/isPaladin`, and lets the
   Thief line use one-handed swords, throwing weapons and whatever the Ranger may wear. Run it **together with** the scripts of this
   folder: `class_migration.lua` moves the characters of the retired ids 2, 6 and 9 at the next start, before anyone logs in (a
   character still on a retired id cannot log in). See docs/CLASSES.md, "Phase 2a". For the Ninja's dual wield and the line's attack speed with weapons that have their own speed, build the engine
   with `src-patches/0002-dual-wield-and-vocation-attack-speed.patch` (without it the off-hand sword cannot be equipped; everything
   else works). Ascension: `!ascend <class>` at level 100 in a protection zone (Warrior: juggernaut|berserker, Ranger:
   deadeye|beastmaster, Mystic: elementalist|illusionist, Thief: ninja|samurai; final, the store's Vocation Change is the only way
   back, except the one free switch of migrated Elite Knights / Royal Paladins). See docs/CLASSES.md.
6. Restart the server (or `/reload scripts`). Check the console for Lua errors.
7. Autoloot only: if `data/talkactions/talkactions.xml` registers `!autoloot` (the legacy
   `talkactions/scripts/autoloot.lua`), TFS 1.4.2 keeps the XML one and silently ignores
   `autoloot.lua`'s `!autoloot`. Remove that XML line for live window refresh. See "Stubbed or assumed".
8. Client: apply the client-side gaps listed below, otherwise bank, autoloot, daily and stash
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
| game_passivetree | `passivetree.lua`, `passivetree_data.lua`, `passivetree_effects.lua`, `passivetree_keystones.lua`, `paragon.lua` | 65 | Points, save with full validation (known ids, connected to root, point cap), preset storage, reset for level x 250 gold; the bonuses are applied (see "Passive tree effects"). Paragon track past level 1000 on the same opcode (see "Paragon"). |
| game_dungeons | `dungeons.lua` | 109 | Reads the base server `DUNGEON_SYSTEM` table. Queue, group formation, teleport in, timer, monster-count progress, boss kill, difficulty unlock, speed/flawless challenges, solo/group rankings, teleport out. Difficulty does not change monsters; loot panel is display only. |
| game_infinitytower | `infinitytower.lua` | 214 | Seasons, points, best floor/time, ranking, milestone claim, `!tower`, `/towerrun` staff test helper. **The tower gameplay does not exist**; a future script reports results with `ChaosTower.recordRun`. Season-end top 3 chests not implemented. |
| game_stash | `stash.lua` | **110** (new), `!stash` | Deposit by drag, redeem, categories, block list, `!stash all`, DB persistence. Client must be ported first (see below). |
| game_spellbook | `spellbook.lua` | 219, `!spells` / `/spells` | Spell list window: every player spell of `data/spells/spells.xml` with its data, a short description and its area of effect (see "Spellbook" below). |
| game_bounty | `bounty.lua`, `bounty_core.lua`, `bounty_config.lua`, `bounty_pool.lua` | 223, `!bounty` / `/bounty` | Daily rotating kill contracts per level band, tested in game (see "Bounty board"). |
| game_arena | `arena.lua`, `arena_core.lua`, `arena_config.lua` | 236, `!arena` / `/arena` | Ranked PvP arena, 1v1 and 2v2 with Elo per mode, runtime instances, no death / skull / frag inside, tested in game with two clients (see "Arena"). |
| game_siege | `siege.lua`, `siege_core.lua`, `siege_config.lua` | 233, `!siege` / `/siege` | Weekly guild siege for the Chaos Obelisk: sign-ups, runtime arena, HUD, rewards and the champion title, tested in game (see "Guild siege"). |
| game_leaderboard | `leaderboard.lua`, `leaderboard_core.lua`, `leaderboard_config.lua` | 229, `!leaderboard` | Weekly World Boss / Bounty Hunter / Rifts / Goblin Slayer / Guild Siege / Arena boards with titles and orbs for the top 3, all-time class ladder, tested in game (see "Leaderboards"). |
| game_crafting | `crafting.lua`, `data/lib/chaos_crafting.lua` | 232, `!craft` / `/craft` | Crafting bench and the crafting orbs (Transmutation, Alchemy, Exalted, Annulment, Scouring, plus Chaos and Divine), tested in game (see "Crafting"). |

Extended opcodes 60, 65, 79, 109, 110, 151, 152, 207, 214, 216, 218, 219, 223, 229, 232, 233, 236 are all registered in the global
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
- Tree shape comes from the client's `nodes.lua` (624 nodes; the generator records 951 stat entries, per-vocation keystone variants included).
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
characters made under the old 1-point-per-level rate). Past the tree's budget, the Paragon track (below) gives small capped
bonuses.

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
- **Paragon:** the Paragon track's percentages arrive in the same bonus table and are added here (see "Paragon").
- The conversion factors from node value to game value are in `cfg` at the top of the file (for example 1 point of experience = 0.1%), and the client tooltip shows the same numbers.
- `server/tests/passivetree_effects_test.lua` checks the maths and the apply/remove logic against a mocked engine API and runs in CI. It does not prove the real API calls (`Condition`, `setCharacterStat`, `changeSpeed`, `onTargetCombat`) behave as assumed: that needs a server run. Speed bonuses are not restored after a death or a speed-resetting spell until the next save or login.

## Paragon (`paragon.lua`)
The long-term goal past the passive tree: the tree budget ends around level 1000 (about 248 of 624 nodes), and from there
every level gives one Paragon point (`Chaos.paragon.startLevel` = 1000, `pointsPerLevel` = 1, so level 1001 has 1 point).
Points go into eight small stats in four categories; a stat takes at most `maxPoints`, its cap is `perPoint x maxPoints`:

| Category | Stat (key) | Per point | Max points | Cap | Applied as |
|---|---|---|---|---|---|
| Offense | Damage (`damage`) | +0.5% | 40 | +20% | multiplier on damage dealt (every type, not healing), after the tree's own bonuses |
| Offense | Critical Damage (`critDamage`) | +0.3% | 50 | +15% | added to the tree's `criticalHitAmount` (one condition, sub id 7215) |
| Defense | Max Health (`health`) | +0.5% | 40 | +20% | added to vitality in the same max health condition (sub id 7220) |
| Defense | Damage Reduction (`reduction`) | +0.25% | 32 | +8% | added to every absorb storage (977562-977575), with the tree's absorbs, capped at 80% together |
| Utility | Movement Speed (`speed`) | +0.5% | 20 | +10% | percent of the base speed, added to the tree's flat speed (`changeSpeed` by the difference) |
| Utility | Max Mana (`mana`) | +0.5% | 40 | +20% | added to spirit in the same max mana condition (sub id 7221) |
| Fortune | Gold Find (`goldFind`) | +1% | 20 | +20% | extra coins in the kill's corpse (onDropLoot index 2: after the stock loot and the Chaos loot layer, before autoloot) |
| Fortune | Item Find (`itemFind`) | +0.5% | 40 | +20% | added to the Chaos loot layer's item-find storage (`loot_config.lua` `itemFindStorage`) |

All maxed: 282 points (level 1282). Points past that are kept but have nowhere to go.
- **Stacking with the tree:** `ChaosPassiveTree.apply` (passivetree.lua) asks `ChaosParagon.addBonuses` to put the Paragon
  percentages into the tree's summed bonus table (keys `paragonDamage`, `paragonHealth`, ...), and `passivetree_effects.lua` applies
  the sum once. So the health and mana conditions (fixed sub ids 7220/7221), the crit condition, the absorb storages and the
  item-find storage each hold tree + Paragon together and never overwrite each other. The tree's own caps (vitality 50, absorbs 80,
  speed 80) still apply to the tree's share. A health/mana sum with a half percent (Paragon has 0.5% steps) uses the flat parameter
  with the engine's own formula (current maximum x percent / 100), whole percents keep the percent parameter.
- Whole numbers: crit damage, damage reduction and item find are engine integers, so the sum (tree + Paragon) is rounded down
  (8 reduction points = 2%, 1 point = 0.25% = nothing until the 4th). Damage, health, mana, speed and gold find are exact.
- Gold find: `value x percent / 100` of the coins in the corpse, the fraction as a chance of one more gold coin, paid as crystal /
  platinum / gold coins. Only coins on the corpse's top level count (where the stock loot puts them).
- **Allocations only go up.** Taking points back is a reset: level x `Chaos.passive.resetCostPerLevel` (250) gold, the tree's rule
  (carried gold, `removeMoney`). **Decision:** the store's Passive Tree Reset service resets the tree *and* Paragon for free (one paid
  respec for every passive point; its description says so). The vocation change resets only the tree: Paragon stats do not depend on
  the vocation.
- A character whose level fell below the points it spent is refunded for free at login (like the tree). On every level above 1000
  the player is told how many points are unspent, and the speed share follows the new base speed.
- Protocol (opcode 65, documented at the top of `passivetree.lua` and `paragon.lua`): `paragonRequest` -> `paragonState`
  `{unlocked, level, startLevel, total, spent, free, resetCost, categories = [{key, name, stats = [{key, name, desc, perPoint,
  maxPoints, points}]}]}`; `paragonApply {alloc = {statKey = points}}` (the absolute allocation; the server checks: unlocked, known
  keys, whole numbers 0..maxPoints, no stat lower than now, sum <= points owned) -> saved, applied, `paragonState`; `paragonReset` ->
  costs the gold, `paragonState`. Errors use the tree's `sendMessage` box. The client gets the numbers from the server.
- Table `chaos_paragon` (`server/sql/chaos.sql`): one row per player and stat key with points > 0. Run once on an existing database:

```sql
CREATE TABLE IF NOT EXISTS `chaos_paragon` (
  `player_id` int(11) NOT NULL,
  `stat` varchar(32) NOT NULL,
  `points` smallint(5) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`, `stat`),
  CONSTRAINT `chaos_paragon_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
```

- Client: the Paragon button next to Apply Points / Reset in the passive tree window (`game_passivetree/paragon.lua`,
  `paragon.otui`, maths in `paragonmath.lua`). Below level 1000 it shows "Unlocks at level 1000". The "Info & Bonuses" list has a
  Paragon section.
- `server/tests/paragon_test.lua`: points, caps, validation, the handlers against a mocked db, gold find maths, the login refund and
  the stacking with the tree in `passivetree_effects.lua`. `client/.../paragonmath_test.lua`: the panel's +/- maths.
- Measured on the test server (Elite Knight, 120 tree nodes with vitality 22, spirit 12, absorb physical 3, item find 3, crit 5):
  tree only max health 22055 / mana 6787 / speed base+80 / 1000 fire hit on the dummy 1316 / 1000 physical taken 970. With
  damage 10, health 20, reduction 8, speed 10, item find 2 points: health 23862 (18078 x 1.32: one condition, 22% + 10%), speed base +
  80 + 5%, absorb 5, item find 4, fire hit 1382 (x1.05), physical taken 950. Capped damage 40 / crit 50 / reduction 32 + health 21 +
  mana 1: hit 1579 (x1.20), crit 20, absorb 11, health 18078 x 1.325, mana 6060 x 1.125, taken 890. Gold find 20: the callback added
  207 gold to 1035 in 40 dragon corpses (20.0%). Reset (gold), the store reset, the forged requests, relog, restart and the login
  refund were checked too.

## Passive tree keystones (`passivetree_keystones.lua`)
Two new paths at the edge of the tree, each two notables and a keystone (1 point per node, like every node): **Wrath**
(619 Gathering Fury, 620 Edge of Ruin, keystone 621; starts at node 600, north-east) and **Resolve** (622 Iron Resolve,
623 Unbroken Will, keystone 624; starts at node 489, south-west). Both keystones sit about 25 nodes from the start, like the
divine nodes. A keystone node has one variant per vocation (`knight = {...}`, `paladin = {...}` in the client's `nodes.lua`; the
generator writes them to `v` in `passivetree_data.lua`, and `ChaosPassiveTree.getBonuses` takes the variant of the player's
vocation, by the vocation's client id). The server also sends the vocation key with `sendNodes`, so the client shows the same
variant the server applies (the client's own vocation number did not match: an Elite Knight reported 4, "druid").

| Vocation | Wrath (621) | Resolve (624) |
|---|---|---|
| Knight | Cleaving Arc: two-handed melee hits also hit up to 3 other enemies next to you for 40% | Bulwark: with a shield, 15% to block a melee/ranged attack completely; 30% of melee damage taken reflected |
| Paladin | Ricochet: bow/crossbow hits, 30% to bounce to the nearest other enemy within 4 sqm for 65%, then once more for 42%; never the same target twice | Deadeye: crossbow + bolts, 15% for a shot with double damage |
| Sorcerer | Arcane Echo: a spell hitting 2+ enemies, 35% to repeat 0.6 s later on the same spots for 50%; 3 s cooldown | Elemental Overload: a spell hit primes the other elements, the next spell of another element within 8 s deals +20% |
| Druid | Overgrowth: heals on others heal 30% more over 6 s (3 pulses) | Thorns: melee/ranged attackers take 30% of their hit + 2 x magic level as earth damage |
| Illusionist (support) | Shared Phantasm: your hits mark the enemy for 6 s; other party members deal +12% to it | Inspiring Illusion: other party members within 8 sqm deal +8% damage |

- Every extra hit (cleave, ricochet, echo, reflect, thorns, regrowth) is dealt from an `addEvent` with `ChaosKeystones.depth > 0` and
  `ORIGIN_SPELL`: no keystone, no passive bonus (`passivetree_effects.lua` skips it) and no weapon style (two-handed factor, arrow
  splash) applies to it, so nothing chains. Targets: monsters that are not a player's summon; players only where
  `ChaosSpell.canAttack` (the PvP rules) allows it. The illusionist bonuses need a party, never apply to the illusionist and are
  not given or received by multi-client characters (`Chaos.isMultiClient`).
- The event order matters: the keystones' `onTargetCombat` callback registers with index 1, after the passive tree's and the weapon
  style's (index 0), so the cleave/ricochet share is taken of the hit after the passive bonuses and the two-handed factor.
- Visuals: cleave `blood_slash`, ricochet a bolt/arrow missile between the targets, Deadeye `holy_cross`, echo `arcane_burst` on each
  tile, overload `arcane_circle` on the caster, regrowth plants then `heal_sparkle`, thorns an earth missile and plant attack, Bulwark
  the block / shockwave effect, Shared Phantasm `arcane_circle` on a newly marked enemy; plus `ChaosCombatFx.dodge/reflect/crit`
  when that module is loaded. Icons: `client/tools/gen_keystone_icons.py` -> `data/images/passivetree/keystones.png`.
- Measured on the test server (level 1000, 60-120 s of auto attack against the balance dummies, 5 dummies, two next to the knight):
  knight two-handed 456/s on the main dummy, with Cleaving Arc 503/s main + 454/s on the 2 neighbours; paladin crossbow 766/s single,
  Deadeye 833/s (+9% in 90 s, +15% expected), Ricochet 742/s main + 312/s on the others; sorcerer Rime Bloom 5150 per cast on 5 targets,
  every cast echoing 7490 (+45%), with the real 35% chance +16% expected; alternating ice and fire spells +15% with Overload; Thorns
  reflected 569 per 970 melee hit (magic level 157), Bulwark blocked 2 of 20 hits and reflected 329 per hit.
- Not measured in game: Overgrowth and the illusionist party bonuses (they need a second character); the unit test covers them.
- `server/tests/passivetree_keystones_test.lua`: chance maths, cleave and ricochet target choice, echo cooldown, overload priming, party
  bonus, the engine glue against mocked creatures, the recursion guard, the per-vocation data and that the client tooltips state the
  server's numbers.

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

**Vocation change.** `!changevocation <warrior|juggernaut|berserker|ranger|deadeye|beastmaster|mystic|elementalist|illusionist|thief|ninja|samurai>`
(token, out of combat, in a protection zone; your own vocation is refused). Every base class has two ascended classes
(`Chaos.shopServices.vocations`: warrior 4 -> juggernaut 8 | berserker 14, ranger 3 -> deadeye 7 | beastmaster 15, mystic 1 ->
elementalist 5 | illusionist 10, thief 11 -> ninja 12 | samurai 13): an ascended character names the ascended class it wants (the base
word asks it to choose), an unascended one becomes the base class with any word of the line, and a Juggernaut can become a Berserker
this way (the only way after `!ascend`). The change also resends the vocation to the client, keeps the Ninja's dual-wield storage in
line, dismisses a companion when the character is no Beastmaster any more (`ChaosClasses.afterVocationChange`) and spends a pending free
switch of the class migration. Health and mana are recomputed as the engine counts
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

## Bounty board (`bounty.lua`, `bounty_core.lua`, `bounty_config.lua`, `bounty_pool.lua`, `tools/gen_bounty_pool.py`)

Daily rotating "kill X" contracts that pay gold and orbs (roadmap item 10). Client: `client/overlay/modules/game_bounty`
(Chaos -> Bounty Board in the top menu, or `!bounty`), extended opcode 223, storage `7100300` (range 7100300-7100309),
table `chaos_bounty` (`sql/chaos.sql`). It is separate from the base server's task system (`scripts/customs/tasks`,
opcode 92, storages 187613+): no shared storage, opcode or event; its kills count for both.

- **The roll.** Every day at `rollHour` (06:00 server time) the board rolls, the same for everyone. It is seeded from the
  date with its own generator (`ChaosBounty.rng`, Park-Miller), so a restart gives the same board; it changes only when
  the config or the pool changes. Six level bands (8-49, 50-149, 150-299, 300-499, 500-799, 800+), each with 4
  contracts: two **hunts** (kill N of a monster), one **elite** (kill N monsters of a type that are at least magic, or
  at least rare, tier: `monster_tiers.lua`; the tier of a dead monster is read from `ChaosTierDead`/`ChaosTierOf`) and
  one **boss** (one kill of a boss that spawns on the map; a hunt when no boss fits the band). A player sees the band of
  their level and the bands next to it.
- **Monster pool.** `bounty_pool.lua` is generated by `python3 -I server/tools/gen_bounty_pool.py <server>/data` from
  the spawn file of the loaded map (`world/<mapName>-spawn.xml`, mapName from `config.lua`) and the monster
  definitions (`monster/monsters.xml` + XML files, and the Lua monsters under `monster/`). Only monsters that spawn
  are in it: hunts need at least 6 spawn entries (elites 20), bosses (boss/rewardboss flag) any. Each monster gets an
  estimated hunting level: the middle of `<level min max>` for the level-scaled monsters, otherwise 1.6 x sqrt(exp),
  raised by health for monsters much tougher than their experience. A band picks monsters in its `pick` window.
  **Rerun the generator after changing spawns (for example after `tools/late_game.py`) or monster experience/health**;
  it is idempotent and `--csv FILE` lists every spawned monster with the reason it was taken or left out. At the first
  roll the script drops pool monsters this server does not know (logged as `[ChaosBounty] N pool monster(s) ...`).
  The pool in the repo was generated from the test server's map with the late-game spawns: 708 hunt monsters, 30 bosses.
- **Accepting and progress.** Up to 3 contracts at once (`maxActive`); finished ones free the slot but cannot be taken
  again that day; Abandon drops one (progress lost). A kill counts for the players who made it (last hit and most damage,
  a summon's kill for its master) and for their party members within 30 tiles on the same floor (`partyRange`); each
  player once per kill. Progress is saved per kill; messages at 25/50/75% and a toast (game_chaosnotify, action
  `bounty` on opcode 79) at 50% and on completion. Contracts expire at the next roll: unfinished rows of past days are
  deleted at login.
- **Rewards** (paid at once on completion; gold to the bank, orbs to the backpack or the inbox when it is full):

  | Band | Hunt | Elite / Boss (x1.5, Divine rounded up) | Weekly chest |
  |---|---|---|---|
  | 8-49 | 10k gold, 1 Chaos | 15k, 1 Chaos | 5 Chaos, 1 Divine |
  | 50-149 | 50k, 2 Chaos | 75k, 3 Chaos | 6 Chaos, 1 Divine |
  | 150-299 | 150k, 3 Chaos | 225k, 4 Chaos | 8 Chaos, 2 Divine |
  | 300-499 | 400k, 4 Chaos | 600k, 6 Chaos | 10 Chaos, 2 Divine |
  | 500-799 | 1M, 5 Chaos, 1 Divine | 1.5M, 7 Chaos, 2 Divine | 12 Chaos, 3 Divine |
  | 800+ | 2M, 6 Chaos, 2 Divine | 3M, 9 Chaos, 3 Divine | 15 Chaos, 4 Divine |

  Experience: 3% (hunt) or 4% (elite, boss) of the experience from level L to L+1, L = the player's level capped at the
  band's top. At most 12 contracts a day (3 bands x 4), so at most about half a level a day: it does not move the
  ~100 h to level 1000 target. Measured: level 1006, hunt -> 1.52M experience (expected 1.517M).
  **Weekly chest:** 7 completed contracts in one bounty week (Monday 06:00 to Monday 06:00) give a "bounty chest"
  (present box) with the orbs of the player's band, once per week.
- **Multi-client** (`Chaos.isMultiClient`): as at the world boss event, such characters may accept contracts and hunt,
  but a contract that got a kill (or was accepted) while multi-clienting is marked (`mc = 1`) and pays nothing
  (`mcReward = false`); it does not count for the weekly chest. The player is told at accept and at completion.
- **Tests:** `tests/bounty_test.lua` (seeded roll, bands, kill matching, party credit, milestones, rewards, the accept
  rules and expiry).

Verified on the test server (level 1000 knight): open from the menu and with `!bounty`; accept; 50 hunt kills -> 2M gold
in the bank, 6 Chaos + 2 Divine Orbs (to the inbox, backpack full), 1.52M experience; elite: normal kills do not count,
magic/rare/legendary do; boss kill; weekly chest with 15 Chaos + 4 Divine; the 3-contract limit (also an accept sent
straight from the client is refused); the same board (same checksum) after a restart; progress kept across relog and
restart; next-day expiry (simulated by shifting the day function); a multi-client contract pays nothing. Not verified in
game: party credit with two real players (unit-tested only) and the real 06:00 roll (the roll is a once-a-minute check
of the day key).

## Treasure goblins (`treasure_goblin.lua`, `treasure_goblin_core.lua`, `treasure_goblin_config.lua`)

A cowardly, very rare monster (`data/monster/monsters/chaos/treasure_goblin.xml`, lookType 297, the stock goblin
scavenger with its sack, drawn with the golden outfit shader 12). It never attacks. All numbers are in
`treasure_goblin_config.lua`. Install: copy the XML and register it (`register_monsters.py`, see
`data/monster/CUSTOM_MONSTERS.md`); the scripts load with the rest of `data/scripts/chaos/`.

- **Spawn.** Own `EventCallback.onSpawn` (index -10, so it runs before the monster tiers). Only a *natural* map respawn
  (not `startup`, not `artificial`) of an eligible monster rolls: 1 in `spawn.oneIn` (3000). Never for bosses
  (`isboss` or monster_tiers' boss list), summons, non-hostile critters, monsters under 40 max health, names in
  `skipNames`, protection zones and houses, the rectangles of `excludedAreas` (quest rooms), and, guarded, the world
  boss arena, rift and arena slots. Rifts, arenas, the siege, the tower and ambush copies are created by scripts
  (`Game.createMonster` = artificial), so they never roll. At most `maxAlive` (3) goblins on the server and one per
  64x64 cell per floor every 30 minutes. On a hit the replaced spawn is cancelled (its spawn block retries after its
  normal interval) and the goblin appears on that tile. The roll is multiplied by an event bonus `goblin`
  (`ChaosEvents.bonus("goblin")`) if the event calendar ever defines one.
- **Area level and health.** The replaced monster's level (`getMonsterLevel`), else the average level of the players
  within 30 tiles, else its max health / 20. Health = 300 + 40 x level, at least 3x the replaced monster's health.
- **Announce.** Players who come within 10 tiles get "A Treasure Goblin appears!" (once each) plus a toast through
  `ChaosNotify.gmBroadcast` (game_chaosnotify); the goblin says "Ooh, shiny...". Natural respawns happen out of sight
  of players (the engine blocks a spawn with a player in view), so the announcement is made on discovery, not at spawn.
- **Behaviour.** Non-hostile, it idles or keeps ~4 tiles from players. The XML `runonhealth` is 100,000,000 and the
  script keeps the goblin's health above it (shown as 100%) until the first hit, which drops it to the real health:
  from then on the engine's flee logic runs it away from its target. The first hit also gives it the attacker's
  speed x 0.95 (min +80, max 1500), a taunt, and a blink every 2.5-4.5 s (70%): a teleport 3-5 tiles to the free,
  visible tile farthest from the attackers. Taunts on further hits (60%, 2.5 s cooldown). 18 s after the first hit it
  escapes: portal effect, "Ha ha!", a message to players within 10 tiles, removed with no corpse and no loot. Never
  hit for 15 minutes: it vanishes quietly. `/goblin [level]` (god accounts) spawns one in front of you.
- **Loot** (added to the corpse in the death event, so the stock loot message and autoloot see it; owner = most
  damage): gold worth (2000 + 400 x level) x 80-130% in crystal/platinum/gold coins; 2-4 Chaos Orbs + 1 per 150
  levels (max 10); a Divine Orb at 25% x item find; 2-4 gear items from the replaced monster's loot table (fallback:
  a level-banded pool), each rolled as magic (50, rarity at least 2), rare (35, at least 3) or legendary (15, at least
  5) through `ChaosLoot.upgradeRarity` / `stockRarity` and `Game.createItemWithRarity`; uniques via
  `ChaosLoot.rollUniques` as a legendary kill of the replaced monster with 3x item find, and if none, a 3% "hoard" roll
  for any non boss-only unique up to the area level + 20. Experience: the replaced monster's experience x 3 (min 50,
  cap 60 x level), given directly (the XML experience is 0). The goblin has no tier, so the loot layer's own pass adds
  nothing for it.
- **Leaderboard.** Each kill counts on the weekly **Goblin Slayer** board (`ChaosLeaderboard.record("goblin", player,
  1, "add")`, see "Leaderboards").
- **Optional hook** (called guarded, nothing is created): `ChaosLootRays.beam(position, kind, player)` with kind
  "unique" / "legendary" / "rare" / "magic" once the loot rays module exists (rename the call if it lands with another
  name).
- Tests: `tests/treasure_goblin_test.lua` (eligibility and exclusions, the 1-in-N roll, cooldown, health, the escape and
  lifetime timers, blinks, loot scaling). Verified on the test server: render, announcement and toast, flee, blinks,
  taunts, escape, a kill's corpse (level 100: 43,680 gold, 3 Chaos Orbs, Legendary / Rare / Uncommon gear; a Dragon
  next to it: 33 gold, a crossbow, 3 dragon ham), the onSpawn replacement (driven by hand: the cropped test map has no
  natural spawns), experience 2,100 for a goblin that replaced a Dragon. Not verified: a real natural respawn, party
  loot, the loot ray and leaderboard hooks (their modules do not exist yet). Outfit shader 15 drew as stripes in the
  test client, so 12 is used.

## Leaderboards (`leaderboard.lua`, `leaderboard_core.lua`, `leaderboard_config.lua`)

Client `game_leaderboard` (opcode 229), opened with `!leaderboard` or Chaos -> Leaderboards in the top menu. Settings:
`leaderboard_config.lua` (loaded as `Chaos.leaderboardConfig`). Tables: `chaos_leaderboard`, `chaos_leaderboard_titles`
(`sql/chaos.sql`); the last processed reset week is the `server_config` row `chaos_leaderboard_reset`.

**Why not the base highscores.** The top menu used to open the base client's `game_highscores`. That window asks for
data with the game packet 0xB1 (the newer protocol's highscores), which this engine does not parse: it stays empty
(checked in game). The base server's own `customs/highscores` script answers extended opcode 73 for a different client
window, and builds its SQL from client input without checks. So the Chaos window is separate, and the menu entry
"Highscores" became "Leaderboards".

- **Boards.** Weekly: **World Boss** (damage dealt to world bosses, kills participated), **Bounty Hunter** (contracts
  completed), **Rifts** (highest rift tier completed, runs), **Goblin Slayer** (treasure goblins slain), **Guild Siege** (siege points), **Arena 1v1** and **Arena 2v2** (best rating of the week). All time: **Class Ladder** (highest level per class).
  Each board shows the top 20 (`rows`), the player's own rank and value, and the time until the weekly reset.
  Ranks are never shared: on equal values the player who reached the value first ranks higher, then the lower id.
  Staff characters (`group_id >= staffGroup`, 4) are left out of every board, title and reward.
- **Week.** The weekly boards reset on Monday at 06:00 server time (`resetHour`). This is the bounty board's week rule:
  `ChaosLeaderboard.week` calls `ChaosBounty.week`. The week key is the YYYYMMDD of that Monday.
- **Sources.** `worldboss.lua` records every rewarded participant's damage when the boss dies (the shares of
  `computeShares`, so multi-client characters and those below `minDamagePercent` do not count; offline participants
  count too). `bounty.lua` records a contract when it pays (not when multi-clienting). The rift scripts call the API below.
- **Reset.** A once-a-minute check (and one at startup) runs the reset when the week key is later than the last
  processed one. It takes the top 3 (`top`) of every weekly board of the week that ended. They get the board's title
  (`title`: Bossbane, Warden of the Hunt, Riftwalker, Goblin Slayer, Siegebreaker, Duelist, Gladiator) for the week that starts. Their orbs (`rewards`: 1st 5 Divine +
  10 Chaos, 2nd 3 + 6, 3rd 1 + 3) go straight to the inbox. A player offline at the reset gets them at the next login:
  the `rewarded` flag is in the DB, so a restart loses nothing. The reset broadcasts the winners (also as a toast with
  `game_chaosnotify`). Score rows older than `keepWeeks` (8) are deleted. When the server was down over several
  Mondays, only the week just ended is scored.
- **Titles.** They show in the look text ("He holds the title Bossbane (1st)."; an `onLook` EventCallback registered
  at index 100, after the base server's `default_onLook` at index 0, which builds the "You see" text and ignores what came
  before it) and next to the name on every board (that board's title first, "+n" for more).
- **Class Ladder.** It reads the players table (`deletion = 0`, below the staff group), ordered by experience, and
  caches each class for `cacheSeconds` (300). Online characters count with their last saved level. Classes are grouped by base
  class through `ladder.baseOf` (nil = `Chaos.classes.baseOf` of the class rework). A vocation missing from the
  mapping is grouped through `Vocation(id):getDemotion()`. The class list holds the vocation ids of
  `data/XML/vocations.xml` that the engine knows. Names come from the server (`Vocation(id):getName()`), so renamed
  or new classes need no change here.

### API (rifts and any other script)

```lua
-- board: "worldboss" | "bounty" | "rift" | "goblin" | "siege" | "arena1v1" | "arena2v2" (a key of Chaos.leaderboardConfig.boards)
-- who:   a Player, a player guid, or {guid = n, name = s} (offline players are looked up)
-- value: integer >= 0; mode: "add" (sum) or "max" (keep the best); nil = the board's mode (rift: "max")
-- Every call also adds 1 to the board's count column (kills / contracts / runs).
-- Returns the player's entry {value, count, at} of this week, or nil (unknown board or player).
ChaosLeaderboard.record(board, who, value, mode)

-- e.g. at the end of a cleared rift, for every member:
if ChaosLeaderboard then ChaosLeaderboard.record("rift", player, tier) end
```

`ChaosLeaderboard.recordShares(shares)` (world boss shares), `ChaosLeaderboard.titlesOf(guid)` (titles held this week)
and `ChaosLeaderboard.checkReset(force)` are public too. A new weekly board is one more entry in `boards` (key, name,
mode, value/count labels, title, info); the client builds its tabs from the server.

Staff: `/leaderboard reset` runs the reset again for the week that just ended (it does not award twice),
`/leaderboard shift <days>` moves the leaderboard clock for tests (0 = real time), `/leaderboard` alone shows the state.

**Tests:** `tests/leaderboard_test.lua` (week key and reset time, record add/max, ranking and ties, the staff filter,
titles and rewards at the reset, look and broadcast text, class grouping).

Verified on the test server: a world boss killed with spell damage -> 18M damage, 1 kill on the board. A bounty
contract completed -> 1 contract. `record("rift", player, 7)` then `5` -> 7, 2 runs. Fake scores for 9 characters
through the API (guid path), a tie at 18M ranked by who reached it first. The reset (clock shifted 4 days): 9 titles,
the broadcast, 3 Chaos + 1 Divine Orb in the online 3rd place's inbox, the offline winners' rows kept for their login.
Look text "You hold the title Riftwalker (3rd).". Restart: no second reset, titles and the new week's scores loaded
from the DB, the reward of an unrewarded row delivered at login. Tabs, class tabs, own rank, the top menu entry. Not
verified: the look text from another player's view ("He"/"She"; unit-tested), the real Monday 06:00 change (a
once-a-minute check of the week key), the rift source (the rift scripts do not call it yet).

## Crafting (`crafting.lua`, `data/lib/chaos_crafting.lua`, `tools/install_crafting.py`)

Install: `python3 -I server/tools/install_crafting.py <server>/data` (idempotent, `--dry-run`) and the
`chaos_crafting_log` table of `sql/chaos.sql`. `crafting.lua` loads `data/lib/chaos_crafting.lua` itself, so `lib.lua`
needs no change.

**How an item carries modifiers (base server).** A rarity is the custom attribute `rarity` (1..15: Common, Uncommon,
Rare, Epic, Legendary, Exotic, Mythic, Chaos, Eternal, Divine, Phantasmal, Celestial, Cosmic, Abyssal, Transcendent).
The engine rolls it in C++ (`Item::applyRarityEffects`, reached through `Game.createItemWithRarity`): an item level
(`combatPowerLevel`, shown as "Level: N"), a small attack/defense/armor/hit chance bonus, and per rarity a fixed number
of modifiers, one custom attribute each: absorbs `rarity_<x>Absorb` (%), skills `rarity_<skill>Skill` (magic level is
`rarity_maglevelSkill`), critical / mana leech / life leech as chance + amount pairs, and on weapons without an element
of their own one `rarity_element<x>` (% extra damage). Everything is also written into the description attribute
("Level: 53, Holy +3%, Fishing +1, Critical Chance +1%, Critical Hit +1%"), which is what the look text and the client
tooltip show. `customs/rarity/base_rarity.lua` turns the attributes into conditions and storages when the item is
equipped (and at login); the element and absorb combat scripts read those storages. Uniques (`chaos_unique_items.lua`)
are base items with the custom attribute `chaos_unique` and their stats as the same `rarity_*` attributes, without a
rarity. The stock Chaos Orb (29856) keeps the rarity and makes a new copy of the item (new level, modifiers and values);
the stock Divine Orb (29857) makes a new copy with a new random rarity, which is none 85% of the time (the store text
"rerolls the values" does not describe it). Both are the base server's `customs/rarity/reroll_rarity_stats.lua`.

**The orbs.** A modifier is one line of the description (a leech or critical pair is one modifier). The maximum per
rarity is one more than a weapon of that rarity rolls: 3, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 7, 7, 9, 9 (`maxMods`).

| orb | id | rule |
|---|---|---|
| Orb of Transmutation | 29851 (existing currency item) | normal item (no rarity, no modifiers, no item level) -> Common 65% / Uncommon 35%, engine roll |
| Orb of Alchemy | 24691 (rune stone, named by the installer) | normal item -> Rare 55% / Epic 30% / Legendary 15%, engine roll |
| Exalted Orb | 29855 (existing currency item) | item with a rarity and a free slot: one new modifier it does not have yet. Group weights absorb 30, skill 30, leech/critical 25, element 15 (weapons only, one at most); combat skills weigh 4, profession skills 1; value from the rarity's range (item.cpp tables) |
| Orb of Annulment | 24697 (rune stone) | item with a rarity: one random modifier goes (rarity and level stay) |
| Orb of Scouring | 24688 (rune stone) | item with a rarity: a plain copy of the base item |
| Chaos Orb | 29856 | as the stock orb, on the bench only for items with a rarity |
| Divine Orb | 29857 | as the stock orb |

Transmutation, Alchemy, Scouring, Chaos and Divine make a new copy (like the stock orbs), so upgrade levels on the item
are lost; Exalted and Annulment change the item in place and rewrite only the rarity part of the description (text in
front of "Level:" and `[...]` upgrade slots behind it are kept). Never touched: uniques (also an old unique without the
marker, recognised by its spec name), stacks, containers, non-gear, the boat items, equipped items, items outside the
backpack. The installer also makes the stock reroll script refuse uniques (it turned a unique into a plain copy).
No Vaal-style orb: the stock Chaos/Divine use-with could not be made to respect a "corrupted" flag without more
patching of base scripts.

**Bench.** `!craft` / `/craft`, Chaos -> Crafting Bench in the top menu, or using an Orb of Transmutation / Exalted Orb
(they are plain-use items in the dat, the three rune stones are use-with). Drag an item from an open backpack onto the
slot, or click one of the backpack's gear in the grid (bags inside the backpack included, 64 at most). The bench shows
rarity, item level, modifiers / maximum and every orb with your count; a button is enabled only when the server says
the orb fits. The server checks again on every click: the item is found by its path from the backpack plus its id and a
signature of its modifiers (moved or changed -> "put it on the bench again"), the orb is owned, the rules above, 250 ms
between orbs. The last 8 crafts come from `chaos_crafting_log` (rows older than 60 days go at startup); use-with crafts
are logged too. Use-with: the five new orbs work on items in the backpack the normal way (`Action` per id).

**Drops and rewards.** Chaos loot layer (`loot_config.lua` currency, per 10000 kills, normal / magic / rare / legendary /
boss): Transmutation 30/200/700/2500/3500 (1-2), Alchemy and Annulment 10/80/300/1200/2000, Scouring
15/100/400/1500/2500, Exalted 4/30/120/600/1000; weights for the guaranteed legendary/boss draw 20/10/10/10/5 (Chaos 70,
Divine 30). Simulated 10000 legendary kills: Chaos 8513, Divine 4380, Transmutation 7607, Alchemy 1862, Annulment 1864,
Scouring 2110, Exalted 945. Store (Chaos Currency): Transmutation 5, Scouring 12, Alchemy 15, Annulment 20, Exalted 40
coins. Weekly bounty chest: + 3 Orbs of Transmutation and 1 Orb of Annulment (`weeklyExtra` in `bounty_config.lua`).

**Tested in game** (test server, cropped map): every orb from the bench (Exalted twice to a full Exotic armor, then
refused; Annulment; Transmutation -> Common; Scouring -> normal; Alchemy -> Epic with an element; Chaos keeps Epic;
Divine -> normal), use-with of the Orb of Annulment, plain use of the Exalted Orb opening the bench, drag and drop onto
the slot, refusals (unique on the bench and by use-with, full item, no orb, equipped item, stock Chaos Orb on a unique),
the look text after each change, the armor's modifiers applied when equipped (Holy absorb 3, Fishing +1, Herbalism +2,
the annulled Drown absorb gone), the history, the store purchase and the loot simulation. `tests/crafting_test.lua`
covers eligibility, each orb on a mocked item, slot limits, the description and unique protection. Not tested: the
weekly bounty chest with the extra orbs (needs seven finished contracts).

## Guild siege (`siege.lua`, `siege_core.lua`, `siege_config.lua`, `sql/chaos_siege.sql`)

A weekly scheduled war between guilds for the Chaos Obelisk. Client: `game_siege` (HUD + sign-up window, extended
opcode 233, Chaos -> Guild Siege in the top menu). Every number below is in `siege_config.lua`.

**Install.** Run `sql/chaos_siege.sql` (tables `chaos_siege_signups`, `chaos_siege_results`) and
`python3 -I server/tools/patch_base_events.py <server>/data` (its third patch puts the siege rules in front of the
base server's `Creature:onTargetCombat`, see "PvP inside"). The Chaos spells ask the siege through
`ChaosSiege.canAttack` in `data/spells/chaos/_common.lua` (reinstall the spells with `register_spells.py`).

**Schedule.** Saturday 20:00 server time (`weekday`, `hour`, `minute`). Broadcasts 60, 15, 5 and 1 minutes before (the
first and the last also as a toast), with the guilds signed up so far. The login-screen calendar and `!events` show a
"Guild Siege" day: siege.lua adds that entry to `Chaos.events.list` when it loads (no edit of the calendar config).

**Sign-ups.** `!siege join` / `!siege leave` (or the window's buttons) by the guild leader or a vice-leader
(`signupRank` 2); the guild needs `minMembers` (3) members in `guild_membership`. Sign-ups close `signupCloseMinutes`
(5) before the start and while a siege runs. Up to `perBracket` (4) guilds share an arena; more guilds run as parallel
brackets (`maxBrackets` 3, arenas side by side, sizes differ by at most one, never below `minGuilds`); beyond 12 the
latest sign-ups wait (first come). Fewer than `minGuilds` (2) at the start: the siege is cancelled and the sign-ups
dropped. `!siege` shows the status and opens the window (next siege, countdown, sign-ups, your guild, champions, rules).

**The arena (built in code, like the world-boss arena).** At the start one arena per bracket is built with
`Game.createTile` at `arena.origin` (5100,5000,7; bracket b is `stride` tiles further east), refused if any footprint
tile already exists in the map with another ground or a house. Each is a 31 x 31 floor of black marble with a stone
wall, the Chaos Obelisk (item 1560) on the centre tile, the capture area (white marble, 5 x 5 around the obelisk,
`capture.radius` 2), eight stone pillars for cover, coal basins, and four base rooms (7 x 5, stone floor, two flags,
two basins) outside the middle of each side, sharing the arena wall. A base has a gate forcefield next to the wall
(action id 47212) into the arena, and an exit forcefield at the back (47213) to the temple. Nothing connects a base to
the arena by walking, so no enemy can enter it. After the siege the arena is cleaned (monsters, corpses, loose
items); walls, obelisk and decoration stay for the next week (the footprint check accepts our own grounds).

**Event flow.** Start -> entry forcefields (action id 47211) next to every temple (`portalOffsets`, or
`portalPositions`), broadcast + toast -> members (level 100+) step in and arrive in their guild's base; gates are shut
for `gatherSeconds` (180) -> gates open, broadcast + toast, `matchMinutes` (25) of war; with `lateJoin` the portals stay
open -> end: standings, rewards, results in `chaos_siege_results`, broadcast + toast with every arena's ranking, the
HUD shows the final score -> after `exitDelaySeconds` (30) everyone inside goes to their temple (`exitPosition`
overrides it) and the arena is cleaned. A player who logs in inside during the match goes back to the base; inside
after the siege, to the temple.

**PvP inside.** During the match, in the arena of the player's own bracket:
- members of different guilds can always attack each other: skulls, the target's secure mode and party do not matter.
  `ChaosSiege.targetCombat` decides; the base `Creature:onTargetCombat` refuses a target with secure mode on and party
  members before any script callback runs, which is why `patch_base_events.py` inserts the hook before those rules
  (the hook returns nil outside the siege, so nothing changes elsewhere). Your own secure mode still has to be off to
  attack, as anywhere: the engine checks it (`Combat::canTargetCreature`) before Lua is asked.
- guild mates, players in a base, a downed player, players of other brackets and non-participants cannot be attacked;
  nobody attacks during the gathering. Monsters and fields cannot hurt players in a base or downed.
- **no real death**: a `preparedeath` event cancels the lethal hit. The engine never runs the death, so there is no
  frag, no unjustified kill, no skull from the kill, no experience, skill or item loss and no blessing is used. The
  player is "downed" for `downedSeconds` (3): slowed, cannot attack or be attacked, does not count on the point, then
  wakes up in the guild's base with full health and mana, poison/fire/energy/bleeding/paralyze removed.
- skulls: the engine still gives an attacker a white skull on each hit on an unmarked player
  (`Player::onAttackedCreature`, no Lua hook). siege.lua takes it back right after the hit (health-change event on the
  participants) and every second; on leaving, the in-fight condition (pz lock) is removed for players who came in
  without a skull. A red or black skull from outside stays as it was.
- multi-client (`Chaos.isMultiClient`): refused at the portal with "Multi-client: another character from your connection
  is online. Log it out to join the siege."; a participant who becomes one is sent out.

**Scoring.** `points.kill` (20) to the guild (and the killer) for every enemy struck down; `points.holdPerSecond` (1)
per second to the guild holding the obelisk, and 1 per second to each of its members on the point. Holding = the most
members (not downed) within `capture.radius` of the obelisk; a tie contests it (`capture.exclusive = true`: any enemy
contests). Standings: score, then kills, then sign-up order; a full tie for first place, or nobody scoring, has no
winner. 15 minutes of holding (900) outweighs a few kills more for the other side.

**Rewards.** For players with at least `minPresenceSeconds` (300) inside while the match ran: the winning guild's
members 500,000 gold to the bank, 5 Chaos Orbs and 2 Divine Orbs; everyone else 150,000 gold and 2 Chaos Orbs (inbox
when the backpack is full; offline players get it at their next login). The winning guild is "Siege Champions" for
`titleDays` (7): its members' look text gets "He is one of the Siege Champions (guild)." (an onLook callback after the
base text) and +5% experience from monsters (`buff.xp`, onGainExperience callback; needs the
`patch_base_events.py` experience dispatch). Champions are loaded from `chaos_siege_results` at startup.
Leaderboard: every participant's points (kills x 20 + seconds on the held point) go to
`ChaosLeaderboard.record("siege", player, points, "add")`: the weekly Guild Siege board of the leaderboards (title
Siegebreaker).

**HUD.** Sent every second to everyone inside: title (arena number when there are several), time left (or "Gates
open in"), who holds the obelisk in the guild's colour / contested / neutral, a row per guild (colour of its base:
north red, east blue, south green, west gold; members inside, kills, score) sorted by score, and "You: kills, downed,
points". Hidden when the player leaves.

**Commands.** `!siege` (status + window), `!siege join`, `!siege leave`, `!siege status`. Staff (`/siege`, group with
access): `start` (now, with the upcoming siege's sign-ups; they are consumed when it ends), `match` (skip the
gathering), `end` (end now with results), `stop` (cancel, no results), `portal` (entry forcefield two tiles east of
you), `arena [n]` (build arena n and go there), `signup <guild>` (no rule checks), `clear` (drop the upcoming
sign-ups).

**The base server's guild wars.** The stock TFS tables are there (`guild_wars` with status, `guildwar_kills`), and the
base `playerdeath.lua` (twice: `creaturescripts/scripts` and `scripts/customs/znote`) writes a `guildwar_kills` row
when both guilds have an active war (status 1). There is no in-game way to declare or accept a war (no `/war` or
`!war` script): it is meant for the website (Znote AAC), and the engine reads a guild's wars only at login
(`IOLoginData::getWarList`), so a war accepted while members are online counts for them only after a relog; startup
deletes pending (status 0) declarations. The siege does not use these tables. Possible double `guildwar_kills` rows
from the two death scripts were not checked.

**Tested in game** (test server, cropped map, two clients from one IP, guilds Iron Wolves and Blood Ravens):
sign-up refusal with too few members and the sign-up by command and from the window; the window; the forced start and
the arena build; the multi-client refusal at the portal (blocks on) and the toast; entry into the right base; gates
shut during the gathering and refusing another guild's gate; PvP by melee against a target with secure mode on; a lethal
hit (no death row, no experience lost, back in the base after 3 s); holding the obelisk alone (+1 per second, HUD
"Obelisk: Iron Wolves"); the end with results and rewards (winner 500k + orbs, the other guild 150k + 2 Chaos Orbs);
the champion look text and the +5% experience; everyone sent out and the arena cleaned. Not tested: two guilds at once
on the point (contested; covered by the unit test), parallel brackets, the scheduled start at the real time,
`tests/siege_test.lua` covers the schedule, sign-up rules, brackets, the arena geometry, capture control, standings,
rewards and the champion title.

## Arena (`arena.lua`, `arena_core.lua`, `arena_config.lua`, client `game_arena`)

Ranked PvP: 1v1 and 2v2, an Elo rating per mode, matches in arena instances built at runtime. Settings are in
`arena_config.lua`, the pure part (ratings, matchmaking, level rule, death catch, timeout) in `arena_core.lua`
(`tests/arena_test.lua`), the runtime in `arena.lua` (`tests/arena_flow_test.lua` runs it on a mocked engine: 2v2,
parallel slots, disconnect, timeout).

**Queue.** `!arena queue 1v1`, `!arena queue 2v2` (a party of exactly two; either member queues both), `!arena leave`
(leaves the queue, or forfeits a running match), `!arena` (status and the window). The window (Chaos -> Arena in the top
menu, or `!arena`) shows the rating, W-L-D and best per mode, the queue buttons, the queue time and window, the level
range you can face, whether today's first-win bonus is taken and the last 10 matches. To queue (and again when the match
is found) every player must be level 50+, in a protection zone, out of combat (no fight lock), not multi-clienting
(`Chaos.isMultiClient`) and not inside a dungeon, the Infinity Tower, a rift, the world boss rooms or a siege
(`ChaosDungeonIsInside`, `ChaosTowerRun.isInside`, `ChaosRift.isInside`, `ChaosWorldBoss.inside`, `ChaosSiege.isInside`;
each is skipped when it does not exist). A player who fails the check when the match is found is dropped from the queue
with the reason; the other entry stays queued.

**Matchmaking.** Every 2 seconds, oldest entry first, each entry takes the closest rating it may face. Allowed rating
difference: 100, +50 for every 10 s waited, at most 600, measured on the entry that waited longer. 2v2 teams queue with
the average 2v2 rating of the two. Two 1v1 players in the same party, or two entries from the same connection, never
pair. **Level rule** (one rule for both modes, over every player of the match): the lowest level must be at least 80%
of the highest, or within 20 levels of it. 800 fights 1000, 300 never does; there is no stat normalisation.

**The match.** A free slot of a grid of 8 (`grid` in the config: origin 6000,6000,7, 4 columns, 24 tiles apart; the
world boss uses 5000-5048, the tower 2000-2660, rifts 8192-8448) is built once with `Game.createTile`: an 11 x 9 room
of black marble with two pillars and coal basins, and a gallery south of it behind a wall. The build is refused if any
tile of the slot already exists (runtime tiles are gone after a restart, so an existing tile is always the map's); a
refused slot is skipped (`/arena slots` lists them). Everyone is checked again, healed to full health and mana, freed of
damage-over-time conditions and teleported in, the teams 6 tiles apart. 10 seconds of countdown (no damage between
players at all), then 5 minutes of fight. The client module turns secure mode off for the match (the base PvP rules make
a player with secure mode on unattackable) and back on after it; a fighter who still has it on 15 s into the fight is
counted as defeated.

**No death, skull or frag inside.** Fighters get three creature events for the match. `onHealthChange` drops every hit
that is not allowed (countdown, team mate, defeated attacker or target, anyone from outside the match) and cuts a hit
that would kill to leave 1 health: that player is defeated and moved to the gallery, where nothing can hit them and they
cannot hit. `onPrepareDeath` is the safety net (a hit raised by a later script, an `ORIGIN_NONE` hit): it cancels the
death and defeats the player. `onManaChange` drops mana taken by players who may not hit. An EventCallback
`onTargetCombat` refuses attacks before the fight, on team mates and the defeated, and in or out of a match ("The fight
starts in N seconds."). Nobody dies, so there is no frag, unjustified kill, death loss or corpse; the white skull and the
fight lock of the fight are removed at the end (`removeCondition(CONDITION_INFIGHT)` clears both), the target is
cleared, and everyone goes back to where they stood when the match started (the temple for a missing position), healed.

**End.** One side has nobody standing: the other side wins. Time out: the side with the higher share of health left
(sum of health / sum of max health, the defeated count as 0) wins; equal (within 0.1%) is a draw. Leaving counts as a
loss: logging out (only possible in the countdown, the engine refuses a logout in fight), losing the connection for 3 s,
`!arena leave`, being moved out of the slot, or another character of the same connection logging in. A leaver is sent
back at once and scores 0 even when the partner wins the 2v2. `/arena stop` (staff) ends every match unrated.

**Ratings.** Elo per mode, start 1000, floor 100, K 40 for a player's first 10 matches of the mode, then 24. Every player
is rated against the other team's average (1v1: the opponent). Both the window and the result toast show the change
(`Rating 1000 -> 1020 (+20)`); the chat gets the same line. `ChaosLeaderboard.record("arena1v1" / "arena2v2", player,
rating, "max")` is called after every rated match when the leaderboard module is loaded (board keys in
`arena_config.lua` `modes`): the weekly Arena 1v1 and Arena 2v2 boards of the leaderboards (best rating of the week;
titles Duelist and Gladiator). Seasonal resets are not there yet.

**Rewards.** A win: 1 Chaos Orb (at most 10 rewarded wins a day). The first win of the day on top: 1 Divine Orb and 2
Chaos Orbs. A draw or a loss gives nothing. Backpack first, the rest to the inbox. Storages 7100340-7100342 (player:
first-win day, wins day, wins count); 7100340-7100349 are reserved for the arena.

**Database** (`sql/chaos.sql`): `chaos_arena_ratings` (player, mode, rating, wins, losses, draws, best),
`chaos_arena_matches` (one row per rated match: mode, slot, winner, reason, start, end) and
`chaos_arena_match_players` (every player of a rated match: team, result, rating before/after, opponents, partner,
reason; the window's recent matches).

**Client** (`game_arena`, opcode 236 JSON): `state` (window), `start` (HUD on, secure mode off), `hud` every second
(both teams' names and health %, countdown or fight clock, your team on the left), `end` (VICTORY / DEFEAT / DRAW toast
with the rating change and the reward, 8 s; secure mode restored, attack cancelled); client -> server `open`,
`queue {mode}`, `leave`.

**Test switch.** The test map has no protection zone and the engine has no Lua call to give a runtime tile the
protection-zone flag, so the queue's protection-zone rule can be switched off for tests only:
`Game.setStorageValue(Chaos.arenaConfig.testNoPzStorage, 1)` (global storage 7100345, in memory, gone after a restart).
Never set it on a live server.

**Tested in game** (srv6, two clients on one IP, multi-client blocks switched off for the fights): the multi-client and
protection-zone refusals, the level rule (562 vs 1000 stayed queued, 850 vs 1000 paired), queue and match start, the
countdown block (attack refused with the message, scripted damage dropped), the death catch from a real melee hit and
from a scripted 30000 hit (1 health, defeated, gallery, no death row, no skull after), the rating change on both sides
(+20/-20, +18/-18, the underdog +26), the timeout decision (an exact health-share tie gave a draw, -2/+2), a dropped
connection as a loss, `/arena stop` unrated, the footprint refusal over the test map's tiles and all 8 slots built, the
HUD, the result toast, the window and the top-menu entry. 2v2, the gallery in a 2v2 and parallel matches were run on the
mocked engine only (there were two client displays).

**Limits.** No spectators from outside. No stat normalisation between levels inside the 80% band. The engine refuses a
logout during a fight, so a logout mid-fight is a disconnect (counted after 3 s). Players keep their buffs, summons and
items (potions and runes are used up as normal). The world type must allow PvP (`worldType = "pvp"`); on a no-pvp world
the engine blocks the damage before the scripts see it.

## Late game (`tools/late_game.py`, `tools/late_game_spawns.csv`, 17 monsters in `data/monster/monsters/chaos/`)

Goal agreed with the owner: a dedicated sorcerer reaches level 1000 in about 100 hours, knights and paladins in about 150
or less. Before, the model gave ~155 h (sorcerer) and ~285 h (knight, paladin), 80% of it between 700 and 1000.
`python3 -I server/tools/late_game.py <server>/data [--config PATH] [--spawn PATH] [--dry-run] [--remove]` does both parts
below; it is idempotent and `--remove` restores the stock stage table and every replaced spawn.

### Experience stages (`config.lua`)

| Level | 1-650 | 651-700 | 701-750 | 751-800 | 801-850 | 851-900 | 901-950 | 951+ |
|---|---|---|---|---|---|---|---|---|
| before (as written) | unchanged | 15 | 12 | 9 | 6 | 3 | 3 | 3 |
| before (as the engine used it) | unchanged | 15 | 12 | 9 | 6 | **5** | **5** | **5** |
| after | unchanged | 15 | 15 | 15 | 14 | 14 | 13 | 13 |

The stock last stage `{ minlevel = 851, multiplier = 3 }` has no maxlevel. This engine's `loadLuaStages` reads a missing
maxlevel as 0, so the stage never matched and levels 851+ fell back to `rateExp` (5). The new table gives its last stage
`maxlevel = 999999`. Checked on the test server: `Game.getExperienceStage` 700 -> 15, 750 -> 15, 800 -> 15, 801 -> 14,
900 -> 14, 901 -> 13, 1000 -> 13 (before the fix in the tool, 951 and 1000 returned 5).

### The monsters

The imported level-scaled monsters of the 650-1300 band that render in the client (Dawn Strayer draws broken, Cunning
Hyaena's art does not match it, Mercenary and Mercenary Ranger have no sprite; see `data/monster/CUSTOM_MONSTERS.md`).
The engine scales a monster at level L: health x(1 + 0.0074 L), speed x(1 + 0.0085 L), damage x(1 + 0.0015 L),
experience x0.03 L (`data/events/scripts/player.lua`), black skull from 401 and loot x2.7 from 501. At their old levels
(up to 1300) they had 300k-900k health and 3000-7000 speed. Now:
- levels clamped to 650-1000, narrow ranges, three tiers;
- base health, experience and speed rewritten so the values at the level land where they should (speed 380-480 like the
  existing 500+ monsters, 350-450);
- attack damage scaled per monster so that a level 1000 knight in the best level 1000 gear takes about as much per second as
  from the strongest existing late-game monsters (Embermaw Archon and Inferno Juggernaut ~1550/s, Pitlord Incarnate ~1070/s,
  Aegis Sentinel ~780/s); player spells used as monster attacks (Reaver's Spin, Thornlash, an unknown "death wave",
  "arc bolt") became plain combat attacks, `lenght` typos fixed, slows capped at -900, hastes at +300;
- elements: physical and holy -15% (weakness), fire, energy, ice and earth +20%, death +10%. This is the lever that gives
  knights and paladins a hunt where they keep up (see the model);
- the donor events (`auto_loot`, `orb_bonus`, `crusd_chest_bonus`, unknown here, one warning per spawn) were removed, and
  the donor's "one of" loot lines (`id="a;b;c"`, which this engine reads as item 0 and drops) became one line per item with
  the chance split.

Values at the middle of the level range (health, speed and experience per health point as measured in game on fresh
normal-tier spawns; damage per second and the largest 100 ms hit measured with 45 s of a monster attacking a level 1000
two-handed knight in full level 1000 gear):

| Monster | Level | XML health / exp / speed | Health | Speed | Exp per health | Damage/s | Largest hit |
|---|---|---|---|---|---|---|---|
| Orclops Ravager | 650-690 | 13,400 / 4,550 / 60 | 80k | 402 | 1.15 | 1,094 | 1,736 |
| Shaper Matriarch | 650-690 | 12,600 / 4,300 / 57 | 75k | 382 | 1.15 | 923 | 3,296 |
| Grove Keeper | 680-720 | 13,800 / 4,850 / 59 | 85k | 410 | 1.19 | 1,049 | 4,030 |
| Blazebringer | 700-740 | 13,400 / 4,700 / 60 | 85k | 427 | 1.20 | 1,031 | 12,052 |
| Garack | 710-750 | 14,800 / 5,400 / 67 | 95k | 483 | 1.25 | 1,008 | 5,017 |
| Alptramun | 760-800 | 16,200 / 8,200 / 54 | 110k | 412 | 1.75 | 1,088 | 3,214 |
| Swamp Snapper | 760-800 | 16,200 / 8,200 / 55 | 110k | 420 | 1.75 | 1,229 | 8,904 |
| Loricate Orger | 790-830 | 17,200 / 8,900 / 55 | 120k | 434 | 1.80 | 1,238 | 3,238 |
| Frost Maiden | 800-840 | 16,300 / 8,450 / 50 | 115k | 399 | 1.80 | 1,058 | 3,725 |
| Tundra Troll | 810-850 | 18,200 / 9,650 / 52 | 130k | 419 | 1.85 | 1,253 | 4,507 |
| Royal Man | 810-850 | 17,500 / 9,300 / 53 | 125k | 427 | 1.85 | 1,155 | 3,952 |
| Azure Dragon | 860-900 | 20,000 / 12,250 / 52 | 150k | 441 | 2.15 | 1,175 | 6,002 |
| Golden Lord | 880-920 | 20,900 / 12,750 / 51 | 160k | 441 | 2.15 | 1,241 | 2,474 |
| Lacewing Moth | 900-940 | 19,900 / 12,400 / 53 | 155k | 467 | 2.20 | 1,449 | 5,693 |
| Jungle Beasts | 920-960 | 21,400 / 13,300 / 49 | 170k | 441 | 2.20 | 1,412 | 6,414 |
| Lady bug | 940-980 | 20,400 / 12,900 / 52 | 165k | 476 | 2.25 | 1,719 | 7,450 |
| Malofur Mangrinder | 960-1000 | 22,400 / 14,150 / 49 | 185k | 457 | 2.25 | 1,856 | 5,614 |
| *existing, for comparison* | | | | | | | |
| Embermaw Archon | - | 95,000 / 62,000 | 95k | - | 0.65 | 1,543 | 4,145 |
| Inferno Juggernaut | - | 120,000 / 65,000 | 120k | - | 0.54 | 1,563 | 3,745 |
| Pitlord Incarnate | - | 44,000 / 42,500 / 450 | 44k | 450 | 0.97 | 1,069 | 2,666 |
| Aegis Sentinel | - | 40,000 / 58,000 / 350 | 40k | 350 | 1.45 | 783 | 2,231 |
| Darklight Striker (replaced) | - | - | ~30k | 420 | ~0.69 | 110 | 738 |

"Largest hit" is the largest health drop in one 100 ms sample, so attacks that land on the same tick add up: Blazebringer's
12k and Swamp Snapper's 8.9k are such peaks (Blazebringer peaked at 3.4k in an earlier 40 s run with nearly the same
scale); most attacks land at 1-3k. A level 1000 knight standing in Darklight Core without healing went from 18k to 9k in
about 2 s against a pull of 6-8 and died in the next area: these are not monsters to pull in packs of five.

Tier averages of experience per health point: 1.19 (levels 650-750), 1.80 (760-850), 2.20 (860-1000). Today's best
spawned monsters give 1.0-1.45 (Soul War 1.02, Helm Hunter 1.43, Aegis Sentinel 1.45), so the first tier is no faster than
the existing 650-700 hunts. The Chaos monster tiers (magic/rare/legendary) still apply on top, as everywhere.

### Spawns (the loaded map's `<mapName>-spawn.xml`)

268 entries of four level 500+ areas (the Bakragore monster set, Darklights task, level 500) are renamed to the new
monsters. Only weaker monsters were taken (all under 25k experience per kill: the Darklight / pillar / maggot set at
19-23k and were-creatures; no bosses or unique names), spread evenly over each area in packs of three of a kind; the
positions are the existing spawn positions (walkable, checked in game: tile with ground, not protection zone, not
blocking, not a floor change). Each changed line carries `lategame="<old name>"`.

| Area | Box (x, y, z) | Spawns there | Replaced | New monsters |
|---|---|---|---|---|
| Darklight Core | 34185-34306, 30999-31111, 11-14 | 136 | 68 (Darklight Matter, Striker, Construct, Emitter, Source) | tier 3: Azure Dragon, Golden Lord, Lacewing Moth, Jungle Beasts, Lady bug, Malofur Mangrinder |
| Jaded Roots | 34274-34393, 31198-31321, 9-12 | 299 | 119 (Mycobiontic Beetle, Rotten Man-Maggot, Meandering Mushroom, Oozing Corpus, Werecrocodile, ...) | tier 2: Alptramun, Swamp Snapper, Loricate Orger, Frost Maiden, Tundra Troll, Royal Man |
| Gloom Pillars | 34445-34546, 31191-31303, 9-11 | 149 | 59 (Wandering/Walking Pillar, Sopping Carcass/Corpus, Weretiger) | tier 1: Orclops Ravager, Shaper Matriarch, Grove Keeper, Blazebringer, Garack |
| Putrefactory | 33981-34065, 31144-31224, 11-12 | 58 | 22 (Bloated Man-Maggot, Converter, Elder Bloodjaw, ...) | tier 1 |

The full list (spawn centre, offset, old and new monster) is `tools/late_game_spawns.csv`. Editing it and running the tool
again syncs the file: new rows are applied, changed rows updated, removed rows restored.

### The leveling model and the hours

The model of the earlier analysis: rotation DPS from `data/spells/README.md` (5-target values, interpolated 300 -> 1000),
0.47 of it turning into kills, the best hunt per level (generic 1.25 exp/health, Soul War with its task from 500), tasks as
flat experience. Added: the new monsters from the level a player can hunt them (tier 1 from 650, tier 2 from 725, tier 3 from
800) at their exp/health, with fewer targets per pull (3 instead of 5: they are 5-8 times bulkier than the area's old
monsters and hit as hard as the strongest existing ones) and their elements (knights and paladins x1.15, sorcerers x0.80).
"Boosted" = premium stamina x1.5, double experience potion, Soul Pit; "+hooks" also the Chaos callbacks (Blood Moon,
passive tree, store World Experience +25%, waystone upgrade) as in the earlier analysis.

Hours per level band, base (no boosts):

| Vocation | | 1-100 | 100-300 | 300-500 | 500-700 | 700-800 | 800-900 | 900-1000 | total |
|---|---|---|---|---|---|---|---|---|---|
| sorcerer | before (stages as written) | 0.3 | 2.6 | 7.3 | 21.8 | 22.4 | 43.0 | 56.9 | **154** |
| sorcerer | before (as the engine used them) | 0.3 | 2.6 | 7.3 | 21.8 | 22.4 | 38.0 | 45.7 | **138** |
| sorcerer | after | 0.3 | 2.6 | 7.3 | 21.8 | 17.2 | 21.1 | 25.5 | **96** |
| knight | before (stages as written) | 0.8 | 6.3 | 16.0 | 42.5 | 41.5 | 77.7 | 100.7 | **286** |
| knight | before (as the engine used them) | 0.8 | 6.3 | 16.0 | 42.5 | 41.5 | 68.8 | 80.9 | **257** |
| knight | after | 0.8 | 6.3 | 16.0 | 42.5 | 28.4 | 27.3 | 33.0 | **154** |
| paladin | before (stages as written) | 0.7 | 5.5 | 14.7 | 41.0 | 40.8 | 77.2 | 100.8 | **281** |
| paladin | before (as the engine used them) | 0.7 | 5.5 | 14.7 | 41.0 | 40.8 | 68.3 | 80.9 | **252** |
| paladin | after | 0.7 | 5.5 | 14.7 | 41.0 | 25.3 | 23.6 | 28.8 | **140** |

Levels 1-700 are unchanged (no stage changed there, and the first tier is not better than the existing 650-700 hunts). In
the model the sorcerer keeps hunting Soul War with its task (wide pulls), and the knight and the paladin move to the new
monsters from 725. Boosted: sorcerer 61 -> 35 h, knight 112 -> 52 h, paladin 111 -> 47 h; boosted + hooks 46 -> 25,
84 -> 38, 82 -> 34 h.

Checked on the test server: all 268 entries spawn (a monster of the new name within 6 sqm of every row, 268/268 walkable);
experience per kill at a level 900 knight = XML exp x 0.03 x level x stage x 1.5 (premium stamina) x 1.25 (the store's World
Experience buff that was active), i.e. exactly 1.875 x the model for all 17. Not measured: real hunting speed (the 0.47
efficiency and the 3-target assumption), the one-handed knight (~14% less damage than two-handed), druids and
illusionists (earth/ice/death are resisted too).
