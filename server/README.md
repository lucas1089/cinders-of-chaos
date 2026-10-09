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
    classes.lua  ascension.lua                     the classes (docs/CLASSES.md): class rules, the Ascendant Oracle
    class_migration.lua                            one-time move of the old vocations (startup SQL + login message)
    thief_combat.lua                               the Thief line: stealth / evasion / poison blades / dual wield / counter / bushido
    berserker_combat.lua  beastmaster.lua          Berserker Rage and Bloodrage; the Beastmaster's companion
    necro_config.lua  necro_core.lua  necro_lib.lua  necro_minions.lua  necromancer_combat.lua
                                                   the Necromancer line: numbers, rules, minions, curses, the bone shield
    monk_chi_core.lua  monk_combat.lua             the Monk line: ids, numbers, chi; unarmed combat, evasion, focus, stun
    templar_aura_core.lua  templar_combat.lua      the Templar line: ids, numbers, rules; the aura, Radiant Strikes
    class_unlocks_core.lua  class_unlocks.lua      the class lock (store unlock per account; sql/chaos_class_unlocks.sql)
    ascension_quest.lua  ascension_quest_core.lua  ascension_quest_config.lua
                                                   the ascension quest (the Oracle's stages, the Trial, ChaosAscension.ascend)
  data/npc/Ascendant Oracle.xml, data/npc/scripts/ascendant_oracle.lua   the quest's NPC (tools/install_class_ascension.py)
  data/monster/monsters/chaos/ascension/          the Trial's guardian and its adds
  tools/patch_promotion.py            turns the stock promotion off (NPCs, npc lib, premium login); run by install_class_ascension.py
  data/XML/chaos_vocations.xml        the class entries (ids 1, 3, 4, 5, 7, 8, 10-15), installed by tools/add_vocations.py
  data/XML/chaos_vocations_monk.xml, chaos_vocations_necro.xml, chaos_vocations_templar.xml
                                      the Monk (17-19), Necromancer (20-22) and Templar (23-25) lines, installed with them
  tools/add_vocations.py              writes them into data/XML/vocations.xml (2, 6, 9 retired) and converts the vocation lists
                                      of spells.xml / weapons.xml / movements.xml (+ potions.lua, lib/core/player.lua)
    paragon.lua (Paragon track past the passive tree, see "Paragon")
    buildshare.lua  buildshare_core.lua (passive tree build codes, see "Build sharing")
    respec.lua  respec_core.lua  respec_config.lua (respec prices, single-node refund, see "Respec")
  tools/respec_income.py              gold per hour of hunting per level, the basis of the respec prices
  src-patches/0001-critical-hit-to-lua.patch   engine: onHealthChange gets `critical` (combat_fx.lua)
  src-patches/0002-dual-wield-and-vocation-attack-speed.patch   engine: a Ninja may hold a sword in the shield hand;
                                      weapon attack speed scaled by the vocation's (thief_combat.lua)
  src-patches/0003-item-custom-attributes.patch   engine: item custom attributes in every item packet for our client
                                      (rarity, item level, lock, unique, sockets, per-item id, version); item:sendUpdate(),
                                      item:getClientAttributes() (see "Item attributes in packets and rich tooltips")
  src-patches/0004-uniform-chance-rolls.patch   engine: critical hit, life / mana leech and spawn-set chances rolled
                                      uniformly (were a bell curve); rarity crit / leech chance = 2/3 of the roll
                                      (see "Critical and leech chances")
  src-patches/0005-passable-pets.patch   engine: monster flag `passable`: players, monsters and NPCs walk and path through
                                      the creature (the pets, see "Pets")
  src-patches/0006-decay-manager.patch   engine: decaying items in a timestamp map (one scheduler event, exact remaining
                                      time) instead of four lists walked every 250 ms (see "Engine: decay manager, hardening, spell events")
  src-patches/0007-hardening-fixes.patch   engine: zeroed XTEA key and network buffer; a bad globalevent time no longer aborts
  src-patches/0008-spell-events.patch   engine: Player:onSpellCost / onSpellPreCast / onSpellCast / onSpellCooldown
                                      (off by default; tools/patch_base_events.py --enable-spell-events)
  src-patches/0009-locked-items-never-sold.patch   engine: locked items (`chaos_locked`) are never sold, taken by id,
                                      put on the market or thrown into a trash holder (see "Salvage", "The item lock")
  src-patches/0011-attack-speed-cap.patch   engine: attack interval floor, cap on all attack speed bonuses together,
                                      life / mana leech at most once per 900 ms each (see "Attack speed cap")
    item_tooltip.lua  item_tooltip_core.lua (rich item tooltips with the equipped-item compare, client game_itemtooltip)
    shop.lua  shop_config.lua  shop_services.lua  autosell.lua  sell_prices.lua (store, see "Store services")
    bounty.lua  bounty_core.lua  bounty_config.lua  bounty_pool.lua (bounty board; pool from tools/gen_bounty_pool.py)
    rift.lua  rift_core.lua  rift_config.lua (rifts: keys, runtime-built instances, run HUD; see "Rifts")
    crafting.lua (crafting bench and orbs; rules in data/lib/chaos_crafting.lua, installer tools/install_crafting.py)
    salvage.lua  salvage_core.lua  salvage_config.lua (salvage into rune shards, the item lock; installer tools/install_salvage.py)
    item_mods.lua (Chaos item modifiers on the character; catalogue and rolls in data/lib/chaos_item_mods.lua, see "Item modifiers")
    treasure_goblin.lua  treasure_goblin_core.lua  treasure_goblin_config.lua (treasure goblins, see "Treasure goblins")
    invasion.lua  invasion_core.lua  invasion_config.lua  worldevents.lua (invasions and the small world events, see "Invasions and world events";
                                      the Wandering Merchant NPC is data/npc/Wandering Merchant.xml + npc/scripts/wandering_merchant.lua)
    leaderboard.lua  leaderboard_core.lua  leaderboard_config.lua (weekly boards with titles, class ladder)
    season.lua  season_core.lua  season_config.lua (seasons; sql/chaos_season.sql, tools/patch_season_events.py)
    hunt.lua  hunt_core.lua  hunt_config.lua  hunt_supplies.lua (hunt tracker; supply prices from tools/gen_supply_prices.py)
    daily_core.lua  daily_config.lua (daily reward login streaks, milestones, grace, login window order)
    patchnotes.lua  patchnotes_core.lua (patch notes window; the notes are data/patchnotes/*.md, see "Patch notes")
    nameplate.lua  nameplate_core.lua  titles.lua (name plates over players, title registry, the Achievements window; sql/chaos_nameplate.sql)
    guild.lua  guild_hall.lua  guild_core.lua  guild_config.lua (guild levels, perks, guild bank, guild halls; sql/chaos_guild.sql)
    achievements.lua  achievements_core.lua  achievements_data.lua (achievements, points, titles, rewards; sql/chaos_achievements.sql)
    pets.lua  pets_core.lua  pets_config.lua (pets: companions that level from kills, small abilities; sql/chaos_pets.sql)
    bestiary.lua  bestiary_core.lua  bestiary_config.lua  bestiary_spawns.lua (bestiary, kill tasks, task tracker;
                                      sql/chaos_bestiary.sql; spawn data from tools/gen_bestiary_spawns.py)
  data/monster/monsters/chaos/pets/   the pet monster types (not attackable, no attacks)
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
   It also removes the demotion from the base `creaturescripts/scripts/login.lua`: without premium (`freePremium =
   false`) the stock login set every vocation without a promotion back to `vocation:getDemotion()`, so a free account
   lost its ascended class (Berserker, Ninja, ...) at every login. The premium branch is left as it was; the engine
   itself never demotes. Verified on the test server: a Berserker on a free and on a premium account stays Berserker
   (before: Warrior after the login, saved so in `players.vocation`).
   And the base `scripts/creaturescripts/autoloot.lua` hands each item to `ChaosLoot.finalizeRarity` before moving it,
   so autolooted gear gets its rarity stats (the engine only rolls items still in the corpse; see "Rarity stats are
   rolled once").
4b. Stock promotion off, the ascension quest's base parts: `python3 -I server/tools/install_class_ascension.py <server>/data
   [--dry-run]` (idempotent; `install_all.py` runs it as a class hook). It copies the Ascendant Oracle
   (`server/data/npc/Ascendant Oracle.xml`, `npc/scripts/ascendant_oracle.lua`) into `<server>/data/npc/` and runs
   `server/tools/patch_promotion.py <server>/data`, which makes every stock promotion path refuse: `StdModule.promotePlayer`
   in `npc/lib/npcsystem/modules.lua` (King Tibianus, Queen Eloise, the emperors, Ishebad, The Forgotten King, ...) says a
   short line pointing to the Ascendant Oracle and changes nothing; every NPC script that promotes answers "promotion" with
   that line first (a keyword added right after `NpcSystem.parseParameters`), direct `setVocation(<promotion|demotion>)`
   calls in NPC scripts (the "Promo Bug" NPC) are commented out, and the premium branch of the stock
   `creaturescripts/scripts/login.lua` (promotion storage 30018 -> `setVocation(promotion)`) no longer promotes. The tool
   then lists any other promotion in the data folder for a manual check: none in this base server (no talkaction, action
   or store offer promotes; the Oracle of the starting island only sets the first vocation). Verified on the test server:
   King Tibianus answers "promotion" with the pointer and "yes" does nothing; a premium Warrior with storage 30018 = 1 stays
   a Warrior at login. The guardian monsters (`data/monster/monsters/chaos/ascension/`) come with step 5 / the monsters
   step. See "Ascension quest".
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
   else works). Ascension: the quest of the Ascendant Oracle (see "Ascension quest"; staff and the free switch use Character > Services) at level 100 (Warrior: juggernaut|berserker, Ranger:
   deadeye|beastmaster, Mystic: elementalist|illusionist, Thief: ninja|samurai; final, the store's Vocation Change is the only way
   back, except the one free switch of migrated Elite Knights / Royal Paladins). See docs/CLASSES.md.
   The same run installs the Monk (17-19), Necromancer (20-22) and Templar (23-25) lines from `data/XML/chaos_vocations_*.xml`
   and opens the equipment to them: the Monk line gets two-handed clubs (staves) and what the Ranger may wear, the Templar line
   one-handed swords and clubs and what the Warrior may wear (shields too), the Necromancer line every wand and rod, what the
   casters may wear and the Mystic's stock healing and support instants (no rune conjuring, no stock summon); the potions follow
   (Monk: the Royal Paladin's, Templar: the Elite Knight's and the Royal Paladin's, Necromancer: the Elementalist's).
5c. Classes five to seven: their spells come with step 3 (`spells_chaos.xml`), their scripts with step 1. The Necromancer's minions
   are monsters: copy `data/monster/monsters/chaos/necro_*.xml` with the other Chaos monsters (step 5) and register them with
   `python3 -I server/tools/register_monsters.py <server>/data/monster/monsters.xml <server>/data/monster/monsters/chaos`.
   The class lock: run `server/sql/chaos_class_unlocks.sql` (the server also creates the table at startup). The three classes
   need an account-wide unlock, sold in the store's "Classes" category (750 coins each, a placeholder); see "Class lock".
5d. Dark tile set: `python3 -I server/tools/install_dark_tiles.py <server>/data [--dry-run]` (idempotent; `install_all.py` step
   `darktiles`) adds the 74 items of `data/items/dark_tiles.csv` to `items.otb` / `items.xml`. The client needs the matching
   `Tibia.dat` / `Tibia.spr` (`client/tools/sprites/gen_dark_tiles.py`). See "Dark tile set".
5e. Gems: `python3 -I server/tools/install_gems.py <server>/data [--dry-run]` (idempotent; `install_all.py` step `gems`)
   adds the 35 gems (32001-32035) to `items.otb` / `items.xml` and names the Orb of Sockets (24692). The client needs the
   multi-use flag on the small diamond: `client/tools/sprites/set_multiuse.py`. See "Gems and sockets".
5f. Auras: `python3 -I server/tools/install_auras.py <server>/data [--dry-run]` (idempotent; `install_all.py` step `auras`)
   adds the 19 Chaos auras of `data/XML/chaos_auras.csv` (ids 6..24) to `auras.xml`; the store sells them (category Auras).
   The client needs the pair from `client/tools/sprites/import_vfx.py`. See `data/spells/README_FX.md` "Animated pack effects".
6. Restart the server (or `/reload scripts`). Check the console for Lua errors.
7. Player commands: `python3 -I server/tools/install_commands.py <server>/data` takes the base server's spoken player
   commands out (talkactions.xml lines with "!" words, the "!" words of base revscripts, the "!commands" login lines);
   every one of them is in the client menu (see "Player commands: the menu"). It also covers the stock `!autoloot`.
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
| game_bank | `bank.lua` | 60 | Gold deposit/withdraw/transfer on the native bank balance, star currency in `chaos_bank`. Economy > Bank opens the window. Written to the client contract; mock-tested only. |
| game_autoloot | `autoloot.lua` | 216 | Window protocol (add / remove / clear over the opcode); list lives in the same storages (base 80000) as the base server onDropLoot callback, which does the actual looting. XML talkaction conflict possible (see below). |
| game_daily | `daily.lua`, `daily_core.lua`, `daily_config.lua` | 207 | 7-day reward cycle with claim, midnight rollover, Adventure > Daily Reward, open on login through the login window queue. Rewards: platinum coins, Chaos and Divine Orbs and a crystal coin, plus a week bonus on day 7 (all or nothing); edit `Chaos.daily` in `chaos_constants.lua`. Account-wide login streaks with milestones, titles and grace days (see "Daily reward and login streaks"). |
| game_notifications | `notifications.lua` | 79 out, 151/152 in | `/gmnotify`, accept/decline of a standard TFS party invite, `ChaosNotify.*` sender API. Catacomb start / leave-queue are hooks only; nothing triggers party/catacomb/task/battle pass toasts automatically. |
| game_passivetree | `passivetree.lua`, `passivetree_data.lua`, `passivetree_effects.lua`, `passivetree_keystones.lua`, `paragon.lua` | 65 | Points, save with full validation (known ids, connected to root, point cap), preset storage, priced reset and single-node refund (see "Respec"), build codes (see "Build sharing"); the bonuses are applied (see "Passive tree effects"). Paragon track past level 1000 on the same opcode (see "Paragon"). |
| game_dungeons | `dungeons.lua` | 109 | Reads the base server `DUNGEON_SYSTEM` table. Queue, group formation, teleport in, timer, monster-count progress, boss kill, difficulty unlock, speed/flawless challenges, solo/group rankings, teleport out. Difficulty does not change monsters; loot panel is display only. |
| game_infinitytower | `infinitytower.lua` | 214 | Seasons, points, best floor/time, ranking, milestone claim, Adventure > Infinity Tower, `/towerrun` staff test helper. **The tower gameplay does not exist**; a future script reports results with `ChaosTower.recordRun`. Season-end top 3 chests not implemented. |
| game_stash | `stash.lua` | **110** (new), Economy > Supply Stash | Deposit by drag, redeem, categories, block list, the Stash All button, DB persistence. Client must be ported first (see below). |
| game_spellbook | `spellbook.lua` | 219, Character > Spellbook / `/spells` | Spell list window: every player spell of `data/spells/spells.xml` with its data, a short description and its area of effect (see "Spellbook" below). |
| game_lootfilter | `lootfilter.lua`, `lootfilter_core.lua`, `lootfilter_config.lua` | 238, Hunt > Loot Filter | Loot filter (glow/dim by rarity in corpses), loot channel with click-to-loot icons, rare-drop lines, loot rays, Rarity Autoloot store unlock. Tested in game (see "Loot filter"). |
| game_bounty | `bounty.lua`, `bounty_core.lua`, `bounty_config.lua`, `bounty_pool.lua` | 223, Adventure > Bounty Board | Daily rotating kill contracts per level band, tested in game (see "Bounty board"). |
| game_rift | `rift.lua`, `rift_core.lua`, `rift_config.lua` | 228 (server -> client), Adventure > Rifts / `/rift` | Rift Keys open timed instances with modifiers; run HUD; tested in game (see "Rifts"). |
| game_arena | `arena.lua`, `arena_core.lua`, `arena_config.lua` | 236, Adventure > Arena / `/arena` | Ranked PvP arena, 1v1 and 2v2 with Elo per mode, runtime instances, no death / skull / frag inside, tested in game with two clients (see "Arena"). |
| game_siege | `siege.lua`, `siege_core.lua`, `siege_config.lua` | 233, Adventure > Guild Siege / `/siege` | Weekly guild siege for the Chaos Obelisk: sign-ups, runtime arena, HUD, rewards and the champion title, tested in game (see "Guild siege"). |
| game_leaderboard | `leaderboard.lua`, `leaderboard_core.lua`, `leaderboard_config.lua` | 229, Social > Leaderboards | Weekly World Boss / Bounty Hunter / Rifts / Goblin Slayer / Guild Siege / Arena boards with titles and orbs for the top 3, all-time class ladder, tested in game (see "Leaderboards"). |
| game_crafting | `crafting.lua`, `data/lib/chaos_crafting.lua` | 232, Economy > Crafting Bench | Crafting bench and the crafting orbs (Transmutation, Alchemy, Exalted, Annulment, Scouring, plus Chaos and Divine), tested in game (see "Crafting"). Salvage tab and the item lock: `salvage.lua`, `salvage_core.lua`, `salvage_config.lua`, Economy > Salvage (see "Salvage"). |
| game_hunt | `hunt.lua`, `hunt_core.lua`, `hunt_config.lua`, `hunt_supplies.lua` | 241, Hunt > Hunt Tracker | Hunt tracker: session time with pause/reset, exp/h, time to level, loot and profit/h, supplies, kills, damage/healing, Chaos drops; tested in game (see "Hunt tracker"). |
| game_season | `season.lua`, `season_core.lua`, `season_config.lua` | 246, Adventure > Season / `/season` | Seasons: fresh-start season characters isolated from standard ones, season ladder view, season uniques, account-wide reward track, end-of-season migration; tested in game with two clients (see "Seasons"). |
| game_patchnotes | `patchnotes.lua`, `patchnotes_core.lua`, `data/patchnotes/*.md` | 244, Social > Patch Notes / `/patchnotes` | Weekly patch notes read from Markdown files on the server, opened once per new week at login (after the Daily Reward), per-account "Don't show automatically"; tested in game (see "Patch notes"). |
| game_monkchi | `monk_chi_core.lua`, `monk_combat.lua` | 247 (server -> client) | The Monk's chi HUD: five pips over the map, plain text `chi:<chi>:<max>:<decaySec>`; only the Monk line (17-19) sees it. Built, not tested in game yet (see docs/CLASSES.md "Monk"). |
| game_nameplate | `nameplate.lua`, `nameplate_core.lua`, `titles.lua` | 248, the Achievements window | Name plates over players: active title, `{guild}` and the name on a frame (client base patch 0022); title registry `ChaosTitles.register`; tested in game (see "Name plates and titles"). |
| game_guild | `guild.lua`, `guild_hall.lua`, `guild_core.lua`, `guild_config.lua` | 252, Social > Guild | Guild levels (guild XP from the members, perks), guild bank, guild halls (runtime instance, upgrades, rent, depot), weekly top guilds; tested in game with two members (see "Guild levels and guild halls"). |
| game_achievements | `achievements.lua`, `achievements_core.lua`, `achievements_data.lua` | 250, Character > Achievements | Achievements: 100 in 9 categories with points, titles and rewards, progress fed by the other systems, retroactive at login; tested in game (see "Achievements"). |
| game_pets | `pets.lua`, `pets_core.lua`, `pets_config.lua` | 254, Character > Pets / `/pet` | Pets: one companion out at a time that follows its owner, levels from kills, two small abilities per species; drops, store and achievements; tested in game (see "Pets"). |
| game_bestiary | `bestiary.lua`, `bestiary_core.lua`, `bestiary_config.lua`, `bestiary_spawns.lua` | 253, Hunt > Bestiary, Hunt > Kill Tasks | Bestiary (an entry per monster, four stages by kills, completion bonus, points and ranks), personal kill tasks with daily / weekly limits, task tracker HUD with the bounty contracts; tested in game (see "Bestiary and kill tasks"). |
| game_itemtooltip | `item_tooltip.lua`, `item_tooltip_core.lua` (client also `game_itemrarity`) | 242 | Rich item tooltips on hover (inventory, open containers): rarity, item level, base stats, every modifier with its tier and roll range, sockets and gems, unique and set, requirements; Ctrl compares with the equipped item(s) of the same slot. Rarity frames from the item custom attributes of engine patch 0003; tested in game (see "Item attributes in packets and rich tooltips"). |
| game_invasion | `invasion.lua`, `invasion_core.lua`, `invasion_config.lua`, `worldevents.lua` | 251 (server -> client; `query` / `calendar` back), Adventure > Events, `/invasion` | Invasions (waves at a town or hunting ground, breach meter, boss, contribution rewards, Defender board, Victory buff, occupation) and the world events Chaos Storm, Wandering Merchant and Golden Hour; HUD and upcoming events window; toasts with action `invasion` on 79; tested in game on a test area (see "Invasions and world events"). |

Extended opcodes 60, 65, 79, 109, 110, 151, 152, 207, 214, 216, 218, 219, 223, 228, 229, 232, 233, 236, 241, 242, 244, 246, 247, 248, 250, 251, 252, 253, 254 are all registered in the global
`ChaosOpcodes` table in `chaos_constants.lua`.

### Opcode collision check
Searched the reference server for every `onExtendedOpcode`, `sendExtendedOpcode(` and opcode
constant. Opcodes in use there: 1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202. (The
`ServerOpcodes` 125/126 in `global.lua` are game-protocol opcodes, a different number space.)
None of the Chaos opcodes collide; no adjustment was needed. 110 was chosen for the stash because
the client has no fixed value and 110 is free. Storage keys `7100000-7100999` and DB tables
`chaos_*` are new; the one deliberate overlap is autoloot's storage base 80000 (shared on purpose).

## Player commands: the menu (`commands_ui.lua`, `commands_ui_core.lua`, `tools/install_commands.py`)

Players type no commands. Every player command of the server is in the client's top menu (`client_chaos_topbar`):
a Chaos window where one exists, else a page of the **Info & Services** window (client `game_chaosinfo`, extended
opcode 237, `ChaosOpcodes.info`). The window asks `catalog` (which command ids this server has, the ancestral store
entries, the vocation words) and sends `run {page, ids, params}`; `commands_ui.lua` runs each command's function and
catches what it would have shown (text messages, cancel messages, `popupFYI`, `showTextDialog`) to send it back as
the page text. Chaos scripts register their command with `ChaosCommands.register(id, fn)` (`commands_ui_core.lua`)
instead of a `TalkAction`. Base server commands are loaded on demand: an XML talkaction's script from
`data/talkactions/scripts/` (its line, commented out, still names the script), a revscript in a sandbox that keeps
its other events away from the engine. `tools/install_commands.py <server>/data` takes the spoken forms out of the
base server (idempotent; `--dry-run` lists the changes).

| Command (old) | Now |
| --- | --- |
| `!craft`, `!salvage` | Economy > Crafting Bench (Alt+C), Economy > Salvage |
| `!bank`, `!stash [all]` | Economy > Bank, Economy > Supply Stash (Stash All button) |
| `!autosell ...` | Economy > Auto Seller (Info & Services) |
| `!hunt [pause/resume/reset]` | Hunt > Hunt Tracker (Alt+H, its buttons) |
| `!bestiary [name]`, `!tasks` | Hunt > Bestiary (Alt+B, search box), Hunt > Kill Tasks |
| `!lootfilter [preset]`, `!autoloot`, `!autolootclient` | Hunt > Loot Filter (presets), Hunt > Auto Loot (the window's opcode) |
| `!spells`, `!supports` | Character > Spellbook (Alt+S), Character > Spell Supports |
| `!build export/import/confirm/cancel` | Character > Passive Tree (Alt+P), Build Code panel |
| `!achievements`, `!title [name]` | Character > Achievements (title selector: every title held, over the opcode) |
| `!pet [summon/dismiss/rename]` | Character > Pets |
| `!classes`, `!ascension`, `!exp`, `!pos`, `!resis`, `!kills`, `!deathlist`, `!ancestral`, `!deck` | Character > Character Info |
| `!changename`, `!changevocation`, `!ascend` (free switch), `!skiptutorial`, `!summonfamiliar`, `!familiarlevel`, `!choosefamiliar`, `!shop` (web shop items) | Character > Services |
| `!rift` | Adventure > Rifts |
| `!tower [start/leave]` | Adventure > Infinity Tower (Enter / Leave Tower buttons) |
| `!bounty`, `!daily`, `!season [join [confirm]]`, `!arena [queue/leave]`, `!siege [join/leave]` | Adventure > Bounty Board, Daily Reward, Season (Join + confirm box), Arena, Guild Siege |
| `!events`, `!worldbuffs`, `!worldboss`, `!invasion` | Adventure > Events (and its Event Calendar / Upcoming Invasions buttons) |
| `!guild [deposit/withdraw/scroll/hall/upgrade/rent/take]` | Social > Guild (Alt+G) |
| `!leaderboard`, `!patchnotes` | Social > Leaderboards, Social > Patch Notes |
| `!buyhouse`, `!leavehouse`, `!sellhouse <player>` | Economy > More > House |
| `!ancestralstore <group>, <n>` | Economy > More > Ancestral Store |
| `!online`, `!uptime`, `!serverinfo` | System > Server Info |
| `!commands` | removed (the menu is the list) |
| `!report <text>` | removed: System > Report a Bug |

Kept as typed commands: every staff command (`/` words with an access check: `/rift`, `/season`, `/arena`, `/daily`,
`/leaderboard`, `/patchnotes`, `/spells reload`, `/supports reload`, `/achievements`, `/invasion`, `/worldboss`,
`/siege`, `/guild`, `/pet`, `/classunlock`, `/ascendset`, `/towerrun`, `/goblin`, `/coins`, `/gmnotify`,
`/newplayerkit` and the base server's `/` commands); for a player those words are plain chat. The base server's Help
channel words `!mute` / `!unmute` stay: they are tutor tools inside that channel, not player commands.

## Client-side gaps found while reading the client (not changed, `client/` is out of scope)

1. **`sendAction(opcode, action, data)` does not exist in the overlay.** `game_bank`, `game_autoloot`
   and `game_daily` call a global `sendAction(op, action, data)`; the only `sendAction` in the tree
   is passivetree's own two-argument one. It must send `json.encode({action = action, data = data})`
   on that extended opcode (the server expects exactly that envelope). Without it those three
   modules send nothing.
2. **game_stash** uses the donor client's `modules.client_manager`, which is not in the overlay. The
   server speaks `{"action":"Stash","data":{"make":...}}` both ways on opcode 110. Minimal port:
   set `Stash.Opcode = 110`, replace `modules.client_manager.Manage.NewModule(...)` with
   `ProtocolGame.registerExtendedOpcode(110, function(_, buf) local j = json.decode(buf); if j and j.action == "Stash" then Stash.DataManager(nil, 110, j.data) end end)`
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
- Client numeric ids sent by the Auto Loot window are treated as **client** ids and mapped to server ids
  through a one-time scan of item ids 100..100000.
- Looting itself is not done here; it needs the base server `scripts/creaturescripts/autoloot.lua` callback.
- The window's add / remove / clear go over the opcode (no spoken command is involved).

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

## Critical and leech chances (`src-patches/0004-uniform-chance-rolls.patch`)

The base engine rolled the critical hit chance (single-target hits: melee, distance, runes and single-target spells),
the life and mana leech chances (every hit) with `normal_random(1, 100) <= chance`. `normal_random` is a bell curve
around 50 (sd 25; a draw outside 1..100 lands on 50/51), so a chance fired far less often than written, the more so
the smaller it was (measured in game: a 10% leech gem leeched in ~5% of the hits, a small sample; the exact rate is
3.0%). Area spells already rolled their critical hit uniformly. Patch 0004 rolls every one of them with
`uniform_random`: a chance now means what it says. The old effective rate, exactly (P(normal_random(1, 100) <= c)):

| written chance c | old effective rate | new value of a Chaos source (round(2c/3)) |
|---|---|---|
| 1% | 0.1% | 1% |
| 2% | 0.3% | 1% |
| 3% | 0.6% | 2% |
| 5% | 1.2% | 3% |
| 7% | 1.8% | 5% |
| 10% | 3.0% | 7% |
| 15% | 5.6% | 10% |
| 20% | 9.0% | 13% |
| 25% | 13.3% | 17% |
| 30% | 18.7% | 20% |
| 40% | 32.0% | 27% |
| 50% | 50.0% | 33% |

The engine rolls once against the sum of every source (gear, gems, tree, waystone), and the old curve is not linear,
so no per-source mapping can reproduce it; every chance was scaled by one factor, two thirds (at least 1, 100 stays
100), which gives the old effective rate at a total of ~30% (end-game builds); smaller totals now fire more often
than before (10% -> 7% instead of 3%), totals above ~35% a little less. Leech amounts and critical damage are unchanged.
What changed: gems (amethyst 1/2/3/4/5 -> 1/1/2/3/3%, cap 15 -> 10%; onyx 2/4/6/8/10 -> 1/3/4/5/7%, cap 30 -> 20%),
the passive tree nodes (client `treedata/nodes.lua`, `passivetree_data.lua` regenerated: 2 -> 1, 3 -> 2, 5 -> 3,
7 -> 5), the uniques (`chaos_items.xml`, specs regenerated), the rarity roll (engine patch and Exalted Orb, above), and
on install `tools/patch_base_events.py` scales the stock items' `criticalhitchance` / `lifeleechchance` /
`manaleechchance` in `items.xml` and the waystone "Critical / Life / Mana Chance" upgrades the same way. Uniques and
rarity items that already exist keep the values they were made with. Class crits (Bushido, Shadowfist focus, stealth,
the Keen Edge support) are rolled in Lua with `math.random` and were always uniform: unchanged. The patch also rolls the
chance of a `<monsters>` set in a spawn file uniformly (no spawn file of ours uses sets).

## Attack speed cap (`src-patches/0011-attack-speed-cap.patch`)

Life and mana leech roll on every hit a player deals (melee, distance, single-target spells, every scripted
`doTargetCombat` with the player as attacker; an area spell rolls once per cast; damage over time never), so more hits
per second meant more healing per second. Every source of extra or faster hits, at its maximum:

| Source | Max |
|---|---|
| Vocation attack speed (patch 0002 scales a weapon's own interval by it) | Shadowfist 1300, Ninja 1400, Monk 1500, Thief 1600, Iron Sage 1700, Samurai 1800, others 2000 ms |
| Weapon: Chaos `attackspeed` modifier + topaz gems (`M.syncAttackSpeed`) | -20% of the weapon's own interval (2000 without one) |
| Dexterity of the stat window (engine: interval - dex%) | 20 points = -20% (the passive tree's dexterity is a damage multiplier only) |
| Ninja off-hand strike (`thief_combat.lua`) | +1 hit per melee hit |
| Bloodrage cleave / Cleaving Arc keystone | +4 / +3 hits per melee hit |
| Ricochet / Arcane Echo keystones, support repeats and Reprisal | +2 bounces; one hit per enemy of the echoed spell; one repeat per cast |
| Shadowfist Flurry | 2 + chi hits, one every 200 ms |
| Pets, Beastmaster companion, Necromancer minions (hit as their owner) | one hit per 2 - 2.5 s each, pet auras up to 3 targets |
| Waystones, store, world buffs | no attack speed |

Before: fastest single-target swing 832 ms (Shadowfist, weapon -20%, dexterity 20), a Ninja 896 ms + off-hand = 2.2
hits and 2.2 leech heals per second. Three engine rules (config.lua; 0 turns one off; defaults when not named):

- `minPlayerAttackInterval = 1000`: no player swings faster than once a second. The fastest vocation unbuffed is 1300 ms,
  so 1000 is reached only by the fastest classes with most of the bonuses; everyone else never sees it.
- `maxPlayerAttackSpeedBonus = 25`: all bonuses together (weapon attribute against its type's interval, dexterity) shorten
  the vocation-scaled interval by at most 25% (they used to multiply to -36%). Gear alone (-20%) or dexterity alone
  (-20%) stay under it. A 2000 class bottoms out at 1500 ms, a Ninja at 1050, a Thief at 1200.
- `minPlayerLeechInterval = 900`: life leech heals at most once per 900 ms, mana leech too; a roll inside the window is
  skipped. One rule for every extra-hit source above (off-hands, cleaves, procs, pets, multi-hit spells), so leech is
  about one heal per second however many hits land. 900 rather than 1000 so a swing at the 1000 ms floor that the
  timer fires a few ms early still leeches.

Lua mirror: `ChaosItemMods.effectiveInterval` / `attackCapConfig` (`data/lib/chaos_item_mods.lua`, reads the config
keys through `configManager`); weapon tooltips add "Your Attack Interval" for the viewer's vocation and dexterity,
"(capped)" when the cap raised it. Tests: `tests/attack_speed_cap_test.lua`, `tests/item_tooltip_test.lua`.

Measured on a test server (engine built from the base source + patches 0001-0011 in order, 100% leech chance, a dummy,
30 s each; "before" = the same build with the three keys at 0):

| Build | Hits/s before | after | Life (= mana) leech heals/s before | after |
|---|---|---|---|---|
| Ninja, two swords, main hand -20%, dexterity 20 | 2.20 | 1.93 | 2.20 | 0.93 |
| Shadowfist, sword -20%, dexterity 20 | 1.20 | 0.97 | 1.20 | 0.97 |
| Shadowfist unarmed, dexterity 20 (1040 ms, under the caps) | 0.97 | 0.97 | 0.97 | 0.93 |

## Engine: decay manager, hardening, spell events (`src-patches/0006`, `0007`, `0008`)

**Decay manager (0006).** The base engine kept every decaying item (fields, corpses, rings and amulets with a duration,
summons' remains) in four lists and walked one of them every 250 ms, subtracting the elapsed time from each item's
duration. Now `src/decay.cpp` keeps a `std::map<decay time, items>`; one scheduler event waits for the earliest entry
(at most an hour), so the cost is nothing while nothing is due and one map operation per start / stop. A decaying item
carries the runtime attribute `ITEM_ATTRIBUTE_DURATION_TIMESTAMP`; `Item::getDuration()` returns the time left from it, so
the description ("will expire in ..."), `item:getAttribute(ITEM_ATTRIBUTE_DURATION)`, the player and house saves and
the client see the exact remaining time (the old countdown was off by up to a second). What is unchanged: decayTo chains,
`item:decay()`, `canDecay()`, containers (a corpse's contents decay with their own timers), `transformEquipTo` /
`transformDeEquipTo` with `stopduration` (a time ring keeps its remaining time when taken off), saved durations across
logout and restart, an item in a depot or whose owner logged out stops and keeps its remaining time (a 10 s sweep plus the
checks at every move / remove), clones continue from the original's remaining time. Lua: `setAttribute` /
`removeAttribute` of `ITEM_ATTRIBUTE_DURATION` on a decaying item restart the countdown with the new value; the timestamp
attribute is not exposed. Verified on a test server: fire field and corpse chains with shortened durations, a ring equipped
and taken off, a corpse with a decaying item inside in the backpack and on the ground (also cloned), a transformed
decaying item, an item removed before it expired, logout / login (remaining time frozen while offline, within 1 s),
server restart with an equipped time ring, a backpack corpse and a depot item (all kept).

**Hardening (0007).** `Protocol::key` and the `NetworkMessage` buffer start zeroed. A `globalevent` time that is empty,
not a number or has more than three parts, or an hour / minute / second out of range, is rejected with an error line
(`GlobalEvent::configureEvent` and `globalevent:time()` share `parseGlobalEventTime`); before, an empty or non-numeric time
was an uncaught exception at startup, and a failing `localtime()` a null dereference. Not ported: the debug logging of
closed connections and failed async queries behind a `debugMode` key (it only adds console noise).

**Spell events (0008).** Four optional `Player` events in `data/events/events.xml`, all with `self` = the player and
`(spellName, spellId, spellGroup, aggressive, ...)` (`spellGroup` is `SPELLGROUP_NONE / ATTACK / HEALING / SUPPORT /
SPECIAL`, new Lua constants):

| Event | Extra arguments | Return |
|---|---|---|
| `onSpellCost` | `manaCost` | `manaCost[, healthCost]`: the mana that must be available and is paid (and trains magic level); a health cost is paid on top, never lethal |
| `onSpellPreCast` | `manaCost, healthCost` | `false` cancels the cast (nothing paid, no cooldown) |
| `onSpellCast` | `manaCost, healthCost` | none; runs after the spell, the payment and the cooldowns |
| `onSpellCooldown` | `cooldownType` ("spell", "group", "secondary"), `cooldown` (ms) | the cooldown to set in ms (0 sets none); once per cooldown the cast sets |

`tools/patch_base_events.py DATA` adds the four entries to `events.xml` **disabled** and the four stubs to
`events/scripts/player.lua`; a stub calls `ChaosSpellEvents.<event>` when a script defines that table and otherwise
returns the unchanged value, so enabling them without a script changes nothing. `--enable-spell-events` switches the entries
on (only for an engine with patch 0008: the base engine warns about unknown methods). Verified: a test script got all four
events with the right arguments, raised the mana cost by 7 and added 3 health (paid), halved both cooldowns (the cooldown
condition held 1000 of 2000 ms), and `onSpellPreCast` returning `false` cost nothing.

How the supports and the item modifiers could use them (their Lua is not changed): `ChaosSupportsSpell`
(`data/spells/chaos/_supports.lua`) wraps `onCastSpell` and, one tick after a cast, gives mana back (Thrift) and rewrites the
cooldown condition (Quickening). With the events the same effects become exact and need no wrapper timing: a
`ChaosSpellEvents.onSpellCost(player, name, id, group, aggressive, mana)` returning `mana - floor(mana * thrift / 100)` makes
Thrift a real discount (no refund tick, and the check "enough mana" sees it); `onSpellCooldown(..., cooldown)` returning
`max(cooldownMinMs, cooldown - floor(cooldown * quick / 100))` replaces the condition juggling of Quickening, and the same
function is where "spell cooldown reduction" of the item modifiers (README "Item modifiers": "no engine hook") plugs in, per
`cooldownType` ("spell" for the spell's own cooldown, "group" for the shared one). `onSpellCast` is the place for effects
that follow a cast (Reprisal's remembered spell and time, the cast context storage now written by the wrapper before
the script runs), `onSpellPreCast` for casting restrictions (return `false`), and the second return value of `onSpellCost`
for a future "costs health instead of mana" modifier. Spell id and name come straight from the engine, so `spells.xml` does not have to be parsed
(`spellsByScript`). One `ChaosSpellEvents` table is shared by everything that wants a hook: it holds one function per
event and chains the callers itself.

## Passive tree points

One passive point every `Chaos.passive.levelsPerPoint` (4) levels above level 8, plus `passiveExtraPoints` from quests/GMs:
about 248 points at level 1000 against 618 nodes, so the tree cannot be completed and each build has to choose a path.
On login, a preset holding more nodes than the character's points is emptied for free with a message (this covers
characters made under the old 1-point-per-level rate). Past the tree's budget, the Paragon track (below) gives small capped
bonuses.

### Boss passive points (`bosspoints.lua`, `bosspoints_core.lua`, `bosspoints_config.lua`)

The first kill of each major boss gives the character +1 passive point, once per boss (10 points in all): the five world
bosses (Kaelgor, Skaldra, The Rotmother, Nyxareth, Vharok), the Ascension Trial's Warden (type `Ascension Warden`, whatever
class name it wears) and Ghazbaran, Apocalypse, Ferumbras Mortal Shell and Gaz'haragoth. Bosses are matched on the monster
TYPE name, so renamed spawns count.

- Credit, as the bestiary and the bounty board (`ChaosBounty.credit`): every player in the boss's damage map (summons for
  their master), the last hit and the most damage, plus the party members of each within `partyRange` (30) tiles on the same
  floor. A player who logged out or died before the kill is not credited.
- Storage: one flag per boss, `storageBase + id` (7101400 - 7101419 reserved; +0 = old kills checked). `ChaosBossPoints.count`
  is added to the tree budget by `passivetree.lua totalPoints` with the level points and `passiveExtraPoints`, so resets,
  single-node refunds and build codes keep them. The Paragon track is not changed: its points come from levels above 1000
  only, the boss points are tree points (248 + 10 + 1 is still far below the 618 nodes, so they never overflow).
- Old kills: once per character, at the first login (again if `retroVersion` is raised), the missing points are given from
  the `chaos_bestiary` row of the boss (kills > 0), the world boss stats of `chaos_achievement_stats` (`wb_kaelgor` ...) and
  the Ascension quest stage (3 = Trial won, 4 = ascended). Bestiary rows only exist for the last hit / most damage and their
  party (and only since the bestiary was installed), so a helper who only did some damage before that is not found: those
  characters get the point at their next kill of that boss.
- Client: a toast (`game_chaosnotify` action `bosspoints`) and a message on the first kill; the passive tree window shows
  "Boss points n/10" under the points box, with the list (slain or not) as its tooltip (`game_passivetree/bosspoints.lua`,
  `bossPoints` sent after every `sendPoints`).
- Removing a boss from the list takes its point back at the next login (a tree with more nodes than points is refunded for
  free); never reuse an id.
- `server/tests/bosspoints_test.lua`: the list (the five world bosses of `Chaos.worldBoss`, the Trial guardian type and stage
  storage), counting, damage-map and party credit, first kill only, the Trial Warden, the tree budget, the old kills once.

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
- **Allocations only go up.** Taking points back is a reset, priced like the tree's full reset by `respec.lua` (see "Respec"; it
  was level x 250 gold, still the fallback in `paragon.lua` without `respec.lua`). **Decision:** the store's Passive Tree Reset service resets the tree *and* Paragon for free (one paid
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

## Build sharing (`buildshare.lua`, `buildshare_core.lua`)
A build can be exported as a short text code and imported on another character (or after a reset). The server encodes, decodes,
validates and applies; the client only shows what the server sends.
- **Client:** the **Build Code** button of the passive tree window opens a panel (`game_passivetree/buildshare.lua`,
  `buildshare.otui`): **Export** puts the code in the text box and on the clipboard (`g_window.setClipboardText`), **Paste** /
  **Import** asks the server for a preview. The tree then shows the nodes the import would allocate, and the panel says the
  points needed vs. owned, what changes (new / taken back), the nodes left out and the price. **Apply Build** (with a confirm
  box showing the price) applies it, **Cancel Preview** shows the saved tree again.
- **Chat:** the spoken `!build` commands are gone (everything is in the Build Code panel); a "build link" `[build CB1-...]`
  pasted in chat still opens the panel with that code.
- **Code format, version 1:** `CB1-` + base64url of: class line (1 byte, index into `ChaosBuildShare.CLASS_LINES` = warrior,
  ranger, mystic, thief; 0 = no class; never a vocation id), flags (1 byte, 1 = Paragon part), the optional Paragon part (count,
  then stat index into `PARAGON_KEYS` + points, 1 byte each), a bitset of the allocated node ids (bit `id % 8` of byte `id / 8`,
  trailing zero bytes dropped) and a 3 byte checksum (`h = (h x 257 + byte) mod 16777213` over "CB1" and the bytes). Only the
  canonical base64 form is accepted, so every single-character typo is rejected (test). A 100 node build is ~60 characters, a
  248 node level 1000 build ~110, the whole tree ~120.
- **Stability rule:** the bitset is indexed by the stable node ids of `passivetree_data.lua` (the client's `nodes.lua` ids), not
  by array positions. New nodes are appended with new ids; existing ids are never renumbered or reused, so old codes stay valid
  and mean the same nodes. A retired id makes codes that use it invalid ("node N is not in the passive tree"). Class lines and
  Paragon stat keys are append-only lists. A new format gets a new version number; old versions are rejected with a clear message
  unless `decode` keeps reading them (only version 1 exists).
- **Import rules (server):** same class line as the importer (Juggernaut and Berserker share the Warrior line; keystone variants
  follow the importer's class via `ChaosClasses.keystoneKey`), else "This build is for a Warrior line class; you are a ...";
  every node known and connected to the start through the build's own nodes; a keystone only if the importer's class has a variant
  of it; the saved list passes the tree's own save validation (`validateNodes`) again. **Not enough points (decision): the first N
  nodes in path order are applied** (the nodes the character already has first, then nearest to the start, then lowest id; the
  prefix is always connected) and the preview / result says how many were left out. The Paragon part is applied when the track is
  unlocked, stat by stat in key order up to the points owned.
- **Price:** an import that only adds to the current tree (and Paragon) is free, onto an empty tree too. One that takes nodes or
  Paragon points back costs the full reset price of that part (`respec.lua`: tree, Paragon), with the same free cases (below level
  50, the free reset after a class change). The store's Passive Tree Reset service (a free reset of both) can be used first. The
  client sends back the price the preview showed; a higher price at apply time is refused ("preview again").
- Protocol (opcode 65, through `ChaosPassiveTree.extraActions`, which `passivetree.lua` checks before its own actions):
  `buildExport` -> `buildCode {code, nodes, paragon}`; `buildPreview {code}` -> `buildPreview {code, nodes, current, wanted,
  applied, skipped, added, removed, treeReset, paragon, paragonChange, paragonReset, cost, free, points, notes, change, summary}` or
  `buildError {message}`; `buildApply {code, cost}` -> `sendNodes`, `sendPoints`, `paragonState`, `respecInfo`, `buildApplied
  {message}` or `buildError {message}`. No new opcode.
- `server/tests/buildshare_test.lua`: round trip (40 / 248 nodes, Paragon part), every single-character typo, swapped and truncated
  codes, old / newer version, wrong class, unknown and disconnected nodes, keystones, too many points, reset detection, the Paragon
  part, an old code on a tree with an appended node.
- Tested on the test server (Deadeye, level 599, 147 points): a 100 node tree exported (63 characters, clipboard checked), reset
  (3,945,000 gold), imported (free) and saved identical to before; imported over a 147 node tree (took 47 back, 3,945,000 gold) and
  identical again; a 200 node code applied its first 147 nodes; bad checksum, wrong class and old version gave their messages; the
  Build Code panel flow (export / import / apply) and "You need 3,945,000 gold coins" with too little gold. Screenshots in the
  session's scratchpad. Not tested in game: the Paragon part (the character is below level 1000; unit tests only).

## Respec (`respec.lua`, `respec_core.lua`, `respec_config.lua`, `tools/respec_income.py`)
What taking passive points back costs. Every number is in `respec_config.lua`.
- **Full reset** of the tree (Reset button) and of the Paragon track (its Reset button): a level curve worth about 37.5 minutes of
  hunting gold at the level, linear between the points below (and the last slope past level 1000). Paragon uses the same curve
  (`paragonFactor` 1.0). Rounded down to 1,000 gold. Paid from carried gold, then the bank (`Player.removeTotalMoney`).

| Level | 49 | 50 | 100 | 200 | 300 | 500 | 600 | 1000 | 1200 |
|---|---|---|---|---|---|---|---|---|---|
| Full reset | free | 50,000 | 225,000 | 395,000 | 565,000 | 3,450,000 | 3,950,000 | 5,950,000 | 6,950,000 |
| Single-node refund | free | 2,000 | 9,000 | 15,000 | 22,000 | 138,000 | 158,000 | 238,000 | 278,000 |

- **Single-node refund:** right-click a saved node in the tree, confirm (the dialog shows the price). The server checks that the
  node is allocated and that every other allocated node stays connected to the start without it (a leaf, or a node on a loop),
  then charges 4% of the full reset price (~1.5 minutes of hunting) and frees the point. Not-yet-saved nodes are still taken back
  for free with a left click, as before.
- **Free cases:** everything below level 50; **one free full reset after the vocation changed** (ascension, class migration): the
  vocation id of the last free reset is kept in storage `7100550` (`freeVocationStorage`), recorded at the first login with
  `respec.lua`, and a different vocation means the next full reset (tree, Paragon or a build import that takes points back) is free.
  The store's vocation change keeps resetting the tree for free, and the store's Passive Tree Reset service stays a free reset of
  tree and Paragon; both go through `ChaosPassiveTree.resetAll`, which `respec.lua` wraps so it also uses up a pending free reset
  (no double free reset after a vocation change).
- **Client:** the server sends `respecInfo {level, full, paragon, node, free, freeBelowLevel}` with every `requestPoints` and after
  each reset / refund (`game_passivetree/respec.lua`). The Reset button tooltip and the reset dialog show the tree price and the
  node price, the refund dialog the node price, the Paragon reset dialog the Paragon price (`paragonState.resetCost`).
- Protocol (opcode 65, `ChaosPassiveTree.extraActions`): `respecInfo` -> `respecInfo`; `refundNode {id}` -> `sendNodes`,
  `sendPoints`, `respecInfo`; `resetPreset` and `paragonReset` are handled here (the old handlers in `passivetree.lua` /
  `paragon.lua` remain as the level x 250 fallback when `respec.lua` is not loaded).
- **Measured income** (`python3 -I server/tools/respec_income.py <server>/data`): for each level the best of the hunts that are
  spawned in the map, gold per hour = kills per hour x (expected coins + NPC sell value of the drops from `sell_prices.lua`, i.e.
  what the Auto Seller pays) x 1.11 (the Chaos loot layer's extra rolls at the tier spawn chances). Coin counts use the stock
  level count multiplier; health the engine's level bonus. Kills per hour = 3600 x 0.47 x average 5-target rotation DPS
  (`data/spells/README.md`: 1804 at level 300, 4337 at 1000, linear) / health; the late-game monsters 3 at a time (x0.75). This is
  the leveling model's estimate, not a measured hunt.

| Level | Best hunt (spawned) | Kills / h | Coins / h | Item sale value / h | Total / h | Full reset = minutes | Node refund = minutes |
|---|---|---|---|---|---|---|---|
| 100 | Dragons (Dragon, Dragon Lord, Wyrm, Hydra) | 1,033 | 67,777 | 291,062 | 358,839 | 37.6 | 1.5 |
| 300 | Demons (Demon, Hellspawn, Behemoth, Dark Torturer, Juggernaut) | 355 | 158,430 | 723,436 | 881,866 | 38.4 | 1.5 |
| 500 | Soul War (8 monsters, 905 spawns) | 158 | 1,410,416 | 4,137,915 | 5,548,330 | 37.3 | 1.5 |
| 600 | Soul War | 181 | 1,612,325 | 4,730,281 | 6,342,606 | 37.4 | 1.5 |
| 1000 | Soul War | 272 | 2,419,962 | 7,099,748 | 9,519,711 | 37.5 | 1.5 |

  The late-game tier 3 monsters (Darklight Core, `tools/late_game_spawns.csv`) are an experience hunt, not a gold hunt: about
  162,000 gold per hour at level 1000 (33 kills, little coin loot), so the curve follows Soul War, which a level 1000 character can
  still hunt. The jump at level 500 is where Soul War opens. Vexclaw (in `monsters.xml` as `Vexclaw.xml`, file `vexclaw.xml`) is not
  loaded by the server and left out.
- `server/tests/respec_test.lua`: the curve points, linear parts, monotony, the minutes against the measured income, free cases,
  `canRemove` (leaf, middle, loop, root, unallocated), and the handlers against a mocked engine (refund, paid / free / used-up
  reset, the store wrapper, below 50, Paragon, `requestPoints`).
- Tested on the test server (level 599): Reset tooltip and dialog showed 3,945,000 / 157,000, the reset charged 3,945,000 from the
  bank, a right-click refund of node 4 (on a loop) charged 157,000 and freed the point, a refund of node 11 (others depend on it) was
  refused with its message. Not seen in game: the free reset after a class change (unit test only; the test server was killed by the
  machine's memory limit during that run) and the Paragon reset dialog (character below level 1000).

## Infinity Tower gameplay (`infinitytower_run.lua`)
The tower exists now. The Enter Tower button of the client window (action `enter`) takes you, or your party (leader only, members within 12 tiles, up to 4), into an arena that is built at runtime with `Game.createTile` in an empty part of the map (x from 2000, y 2000, z 7; sixteen arenas side by side), so no map editing is needed. Floors are waves: kill everything to open the next one (6 s pause, half of the missing health and mana restored, `floorGold` x floor gold); every 10th floor is a boss floor with its helpers. Pools get harder every 8 floors, and the chance of magic, rare and legendary monsters (with their modifiers and shaders) rises with the floor. A floor has a 300 s limit. Dying, leaving (the Leave Tower button), logging out or running out of time ends your part of the run and records the cleared floors with `ChaosTower.recordRun` (points, best floor, ranking, milestones). Logging in inside an arena sends you to the temple. Milestone rewards now use item ids that exist (gold, Chaos and Divine Orbs, Soulreaper). Everything is configured at the top of the file (`ChaosTowerRunConfig`).
- `server/tests/infinitytower_run_test.lua` covers the floor planner, entering, clearing floors, dying, leaving, the time limit, logout and login with a mocked engine; CI runs it with LuaJIT and Lua 5.3. The real `Game.createTile`, `Tile:addItem`, `Game.createMonster` and teleport calls are assumed from the engine sources, not run.
- Not done: the season-end top 3 chests, a visible ladder of floors in the client window, and per-floor loot beyond what the monsters drop. Check that x 2000..2700, y 2000..2020, z 7 is really empty in your map (it is in the map analysed: the content starts at x 18992).

## Event calendar, boosted creature/boss and the login screen (`events_schedule.lua`, `clientservices.lua`)
- **Events** (`Chaos.events` in `chaos_constants.lua`): recurring server days with real bonuses. Blood Moon (Saturday and Sunday, +50% experience), Chaos Rift (Wednesday, magic/rare/legendary spawns x2 and ambushes x1.5), Loot Frenzy (Friday, +50% Chaos loot and one extra loot roll on every monster) and Tower Ascension (days 1-3 and 15-17 of the month, double Infinity Tower points). Days are given as `weekdays` (1 = Sunday) or `monthdays`. Active events are announced on login and with Adventure > Events. The bonuses are read by `ChaosEvents.bonus(kind)` in the experience callback, `loot_config.lua` (`rateMult`), `loot.lua`, `monster_tiers.lua` and `infinitytower.lua`.
- **Boosted creature and boss:** the base server already picks them at startup (its lists and global storages). `clientservices.lua` reads that pick and falls back to `Chaos.boosted` when it is missing or names a monster that does not exist.
- **Login screen:** the client asks an HTTP endpoint for `boostedcreature`, `eventschedule` and `cacheinfo` (players online). The game server has no HTTP listener, so `clientservices.lua` writes the three answers to `data/chaos_clientservices.json` at startup and every 5 minutes, and `server/tools/clientservices.py` (standard library only) serves that file:
  ```
  python3 server/tools/clientservices.py <server>/data/chaos_clientservices.json --port 8090
  ```
  The client's `init.lua` (base patch 0001) points `clientServicesLink` and `Services.status` at `http://127.0.0.1:8090/clientservices`; change the host for a public server. A GET on the same URL returns everything, handy to check it from a browser.
- **Runtime events:** `ChaosEvents.dynamic[key] = {id, name, description, bonus, untilTime}` adds an event with an end time to `ChaosEvents.active` (and so to the bonuses, Adventure > Events and the login lines) until `untilTime`: the invasion Victory buff and the world events use it (see "Invasions and world events"). Scheduled invasions are whole-day entries of `Chaos.events.list`.
- `server/tests/events_schedule_test.lua` checks the weekday/month-day rules, the bonus product, the calendar ranges sent to the client and the experience callback.

## Test kit (`admin/testkit.lua`)
`/testkit [mage|knight|paladin][, player]` (admins only) equips a strong set for the vocation (uniques where they fit), a backpack of supplies (potions, runes, crystal coins, Chaos and Divine Orbs), raises the level to 500 and the main skills (magic level 110 for mages, 120 melee or 125 distance), and resets health and mana to the vocation's values. Relog afterwards so the stock rarity script applies the item bonuses.

## Store (`shop.lua`, `shop_config.lua`)
The client's Store (menu Economy > Store, module `game_shop`) talks JSON on extended opcode 218 (`ChaosOpcodes.shop`; the base server's own store script uses 201 and is left alone). Prices are in Chaos Coins, kept per account in `chaos_shop_coins`; purchases go to `chaos_shop_history` (both in `sql/chaos.sql`). Staff give coins with `/coins <player>, <amount>` (negative takes them away). Categories and offers are in `shop_config.lua`: Chaos and Divine Orbs, supplies, wings, auras and outfit shaders (names and previews read from `data/XML/wings.xml`, `auras.xml`, `shaders.xml`), outfits, mounts and premium time, plus boosts, world buffs, services, convenience unlocks and training weapons (see "Store services"). The two outfit offers give female characters the female look type (910, 1238; they gave the male one before). Wings, auras and shaders are bought once (storages 7100600+); outfits and mounts check whether the player already has them; a delivery that fails refunds the coins. Tested in game: buying an item and wings, refusing a second purchase of the same wings, coins and history in the database.

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
| | Double Experience Potion / 5 potions | 50 / 225 | the base server's item 28095: x2 experience for 1 h per potion (storage 6000, Character > Character Info) |
| | All Blessings | 60 | blessings 1-5 (refused when all are owned) |
| World Buffs | World Experience | 300 | +25% monster experience for everybody, 1 h, up to 3 h |
| | World Loot | 300 | +25% Chaos loot (`rateMult`) and one extra loot roll on every monster, like the Loot Frenzy event, 1 h, up to 3 h |
| | World Training | 250 | +25% skill and magic level tries for everybody, 1 h, up to 3 h |
| Services | Name Change | 250 | a token for Character > Services |
| | Vocation Change | 400 | a token for Character > Services |
| | Sex Change | 100 | at once; every owned outfit and addon is copied to the other sex (pairs by name in `data/XML/outfits.xml`) |
| | Frag & Skull Remover | 150 | skull time (the engine's unjustified-kill counter) to 0, red/black skull removed; not in combat |
| | Passive Tree Reset | 60 | empties every preset for free (the in-window reset costs level x 250 gold) |
| Convenience | (the Temple Teleport Scroll is no longer sold) | | see below |
| | Bottomless Loot Pouch | 500 | unlock, see below |
| | Auto Seller | 500 | unlock, see below |
| Training | 21 exercise weapon chests | 25 / 75 / 450 | the base server's chests: sword, axe, club, bow, rod, wand, shield with 500 / 1800 / 14400 charges |

Premium (250 for 30 days) stays where it was.

**Temple Teleport Scroll (retired from the store).** Every character has the free Town Portal now ("Town Portal" below), so the store no longer offers the scroll or the 25-use scroll. Scrolls bought earlier keep working: the handler, `S.teleportBlocked` and the action id stay in `shop_services.lua`, and `shop_config.lua` keeps the `templeScroll` service kind. The old description: an ordinary "scroll" (item 6119, used by no other script) with action id 47301, the name
"temple teleport scroll", a description and the uses left in the custom attribute `chaos_uses`; no new item id. Using it
takes you to your town's temple. Refused with a battle sign or PZ lock, inside a dungeon run (`ChaosDungeonIsInside`), the
Infinity Tower (`ChaosTowerRun.isInside`) and the world boss lobby/arena (`ChaosWorldBoss.inside`). 2 s cooldown. The stash
refuses it (action id), so it stays an item.

**World buffs.** A purchase broadcasts "<buyer> activated the World Experience ..." to everybody (and fireworks); buying
while it runs extends it ("<buyer> extended ..."). A purchase that would leave more than 180 minutes is refused before
coins are taken. The expiry times are global storages 7100921 (xp), 7100922 (loot), 7100923 (skill) and rows
`chaos_worldbuff_xp|loot|skill` of the stock `server_config` table: they survive `/reload` and a **restart** (checked on
the test server). Adventure > Events lists the active ones with the time left; players get the list at login; the end is
broadcast (30 s check). Experience: `EventCallback.onGainExperience` (needs `patch_base_events.py`), monsters only.
Training: `EventCallback.onGainSkillTries`, which the base `player.lua` already dispatches (no patch needed); one try
x1.25 becomes 1 or 2 tries at random, so small gains are not rounded away. Loot: `loot_config.lua` `rateMult` and the
extra-roll rule in `loot.lua`.

**Name change.** Character > Services (needs the token, out of combat, in a protection zone). Rules
(`ChaosShopServices.validateName`, settings `Chaos.shopServices.name`): 3-20 characters, letters and single spaces, at most
3 words of at least 2 letters, each word is capitalised for you ("kael vorn" -> "Kael Vorn"), no letter three times in a
row, no staff word as a word (GM, CM, God, Admin, Tutor, Gamemaster, ...), no forbidden substring, not a monster name, not
taken (`players.name`). Then: the token is used, the character is saved and kicked, and 0.5 s later (retried each second
while it is still online) `players.name` is updated together with the tables that keep names as text: the member list of
`chaos_dungeon_runs` (runs the character took part in), `player_deaths.killed_by` / `mostdamage_by` (player killers) and
`guildwar_kills.killer` / `target`. If the name was taken in between, the token is given back. `chaos_admin_log.player_name`
is an audit log and keeps the old name. All other Chaos tables use the player id.

**Vocation change.** Character > Services (pick the class: warrior, juggernaut, berserker, ranger, deadeye, beastmaster, mystic, elementalist, illusionist, thief, ninja or samurai)
(token, out of combat, in a protection zone; your own vocation is refused). Every base class has two ascended classes
(`Chaos.shopServices.vocations`: warrior 4 -> juggernaut 8 | berserker 14, ranger 3 -> deadeye 7 | beastmaster 15, mystic 1 ->
elementalist 5 | illusionist 10, thief 11 -> ninja 12 | samurai 13): an ascended character names the ascended class it wants (the base
word asks it to choose), an unascended one becomes the base class with any word of the line, and a Juggernaut can become a Berserker
this way (the only way after the Ascendant Oracle). The change also resends the vocation to the client, keeps the Ninja's dual-wield storage in
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
The list is managed in the Info & Services window (Economy > Auto Seller): add / remove an item by name (only items an
NPC buys), on / off, clear, and whether items with a rarity or modifiers are sold too.
Prices: `sell_prices.lua`, generated by `python3 -I server/tools/gen_sell_prices.py <server>/data` from the NPC shops
(`shop_sellable` parameters of `data/npc/*.xml`, `addSellableItem` and `{..., sell = n}` tables of `data/npc/scripts/*.lua`,
highest price any NPC pays; 1377 items with the reference data). Regenerate after NPC changes. The client's autoloot window
was not extended; the list has its own page in the Info & Services window.

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
engine, loot multiplier 1.25; buffs still active after a server restart, listed at login and by Adventure > Events; the auto
seller sold plain items to the bank and kept rarity/unique items (rarity sold after the opt-in, nothing sold while off);
the loot pouch sent a stackable to the stash and gear to the inbox with a full backpack; Character > Services renamed the
character (and its dungeon run entry) and back; a vocation change paladin -> knight -> paladin returned exactly the
original health, mana and capacity.

## Town Portal (`townportal.lua`, `townportal_core.lua`, `townportal_config.lua`, spell `shared/town_portal.lua`, client `game_townportal`)

An ability, not an item: every character has it from creation (the spell "Town Portal", id 254, words `ash domh`, level 1, no mana, every
vocation; `needlearn="0"`, so existing characters have it at the next login after `register_spells.py`). The menu entries Character > Town Portal
(cast) and Character > Portal Style (window) call the same code. Numbers: `townportal_config.lua`.

- **Cast:** `ChaosTownPortal.cast(player)` refuses at once (reason below) or starts a 3 s channel (`castMs`, polled every 250 ms). A step or any
  damage (health change, or a mana hit from an attacker) ends it with nothing spent. At the end the rules are checked again, then the pair opens:
  a portal on the first free tile around the caster (`fieldOffsets`, action id 47810) leading to the temple of the character's town, and a return
  portal on the first free tile in rings 1..4 around the temple (action id 47811) leading to the exact tile of the cast (a creature standing there
  moves the arrival to the nearest free tile). Tiles must be walkable, no house, floor change, teleport, field or creature; two pairs never share a tile.
- **Cooldown:** 60 s from the moment the portal opens (storage `7101601` = os.time of the next cast, plus the spell cooldown condition so the action
  bar shows it). A refused or interrupted cast costs nothing.
- **Lifetime:** 5 min (`portalMinutes`, checked by a 2 s think), or when the owner steps through the return portal. A new cast closes the old pair first.
  Logging out keeps the pair until it fades.
- **Who:** the owner and the owner's party members (`partyCanUse`, at the moment of the step); others are pushed back with a message. A party
  member who uses the return portal arrives at the owner's spot and leaves the pair open; only the owner's return closes it.
- **Refused to cast:** already channelling, cooldown, tutorial island (`ChaosNewPlayer.onIsland`), arena match, world boss lobby/arena, guild siege
  (`ChaosSiege.locate`), inside a rift or omen arena, a dungeon, the Infinity Tower, pz-lock, white/red/black skull, inside a protection zone.
  The field portal refuses a pz-locked or skulled player at the step as well.
- **Instances (decision):** the portal cannot be opened inside rifts, dungeons or the tower, and so there is no pair that could point into one: the
  return portal always puts the player back on an open-world tile. (A portal opened outside stays usable while a run is going on elsewhere, but its
  target is the open world, so it can never lead into a finished run.) Leaving an instance uses its own exit, as before.
- **Temple Teleport Scroll (decision):** removed from the store (no new sales; old scrolls still work, see Store services). Starter kits that listed a
  scroll are unchanged (it is the same item).

**Portal Style.** `townportal_config.lua` `styles`: id, key, name, route, item (the portal's look: a stock teleport item of the base server), and
open / close / loop / travel effect lists. An effect entry is a `ChaosVfx` name, a `ChaosFx` name or a stock `CONST_ME_*` number, tried in order
(the last one must be a stock number, so a client without the effect art shows something). The selected id is in storage `7101600`; the style
is read at cast time and stored in the pair, so everybody sees the owner's style. A style that is no longer owned falls back to the default.
Exactly one route per style: `default` (Waygate), `store` (6, ids 1..6, `shop_config.lua` category "Portal Styles", offer `unlock = "portal_<key>"`,
owned in storage `7101610 + id`, resolved by `ChaosTownPortal.storeUnlock` from `shop_services.lua`) or `achievement` (6, ids 31..36, owned while
the character has the achievement whose `reward` is `{portal = {key, name}}` in `achievements_data.lua`, so older unlocks count too).
`ChaosTownPortalCore.validate` (run by `tests/townportal_test.lua` and printed at startup) fails a style with no route, with both, a store offer for a
non-store style, an achievement reward for a non-achievement style, or a missing effect name. No drops.

| Style | Route | Price / achievement | Look and effects |
|---|---|---|---|
| Waygate | everyone | | blue force ring; teleport_in / teleport_out |
| Emberforge Gate | store | 250 | molten lava gate; infernal_seal, fire_explosion, inferno_burst |
| Rimeglass Gate | store | 250 | ice-blue crystal gate; frost_glyph, ice_shatter, frost_ripple |
| Verdant Gate | store | 250 | overgrown green gate; grove_glyph, healing_bloom, heal_sparkle |
| Gilded Gate | store | 300 | golden arch; holy_seal, solar_flash, holy_spiral |
| Bloodmoon Gate | store | 300 | red gate; blood_rune, blood_nova, blood_ring |
| Sanctum Gate | store | 300 | white palace door; px586_white, px652_white, arcane_aura |
| Abyssal Maw | achievement | Colossus Hunter (`wb_all`, all five world bosses) | violet maw with demons; void_maw, void_rift, void_eye |
| Riftwalker's Gate | achievement | Keybearer (`rift_25`, seal 25 rifts) | torn rift doorway; px03_arcane, teleport_out, summon_portal |
| Hellmouth Gate | achievement | Herald of Omens (`omen_10`, 10 omen guardians) | demon jaw; infernal_seal, dome_blast_fire, shadow_flame |
| Hoarder's Gate | achievement | Hoardbreaker (`goblin_50`, 50 Treasure Goblins) | royal gold gate; aura_burst_gold, loot_ray_legendary, arcane_burst |
| Warbanner Gate | achievement | Siege Champion (`siege_win`, win a guild siege) | old stone siege gate; stone_rise, earth_spikes, stone_ward |
| Gravecall Gate | achievement | Death Is a Teacher (`deaths_50`, hidden) | dark crypt door; necro_seal, px633_indigo, shadow_cloud |

Store prices are in the range of the auras (200..300). All visuals come from items and effects already in the client pair (`things_custom7`,
`vfx_catalog.csv`); no new art. **Follow-up:** the sprite libraries R and S on the sprite-libraries branch have portal and gate effects (swirl,
arch, rune circles) that would give styles their own effect art instead of recoloured shared ones.

Protocol (opcode `ChaosOpcodes.townPortal` = 239, JSON): client -> server `open | get | select {id} | cast`; server -> client `state {open,
selected, cooldown, cooldownTotal, styles}`, `cast {ms}`, `castEnd {result}`. The client cast bar is in `game_townportal`.

Install: `register_spells.py` (already in `install_all.py`, step `spells`) installs the spell; no other installer. Client: regenerate
`gen_spell_data.py` and the spell icon sheets (`gen_all_spell_icons.py`, cell 280 is the Town Portal icon). Tests: `tests/townportal_test.lua`.
Not verified: a real party of two clients using the return portal while the owner is away; very crowded temples (80 return spots).

## Spellbook (`spellbook.lua`)
Character > Spellbook in the client menu opens the client window `game_spellbook` on extended opcode 219 (`ChaosOpcodes.spellbook`). The list is read from the running server's own files, so renamed stock spells, the Chaos spells and anything added later show up without a client update:
- `data/spells/spells.xml`: every `<instant>`, `<rune>` and `<conjure>` (name, words, level, magic level, mana, soul, cooldown, group, premium, range, vocations, rune item id). Monster spells (words starting with `#`) and house spells (`house/` scripts) are skipped.
- `data/spells/scripts/<script>` is read as text, never run: element (`COMBAT_PARAM_TYPE`, `doAreaCombat`/`doTargetCombat`/`damageTarget` arguments), kind (damage, heal, buff, summon, conjure, utility), area (the largest `createCombatArea(...)`: an `AREA_*` table of the spell library, an inline table literal, which is loaded only when it holds nothing but digits, commas and braces, or a local table of the same script), scaling (magic level, skill x weapon attack, distance skill x weapon attack). Chaos spells use the first comment line of their script (`-- <Name>: <description>`); stock spells get a generated one ("Single-target fire damage.", "Fire damage in front of you (wave).", "Heals you and cures paralysis.", "Conjures 4 x 'searing orb rune'.").
- Parsed once at startup when the `AREA_*` tables already exist, otherwise on the first Character > Spellbook; `/spells reload` (staff) parses again after a spell change. A player can open it once every 2 seconds.
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
arena built at runtime, and everyone who took real part (damage, healing other players, tanking) is rewarded, not only the
corpse owner; the top 3 damage dealers, healers and tanks get extra rewards and a title. Settings: `Chaos.worldBoss` in
`chaos_constants.lua`. `tests/worldboss_test.lua` covers the layout, schedule, rotation, phases, role accounting, shares,
rewards and the whole event flow against a mocked engine (LuaJIT and Lua 5.3); the roles were tested in game (below).

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
- Adventure > Events (everyone): next start and boss, or the running fight (health %, minutes left). `/worldboss arena` (staff):
  builds the arena if needed and takes you to the lobby, to look at it without an event.

### Rewards

- The corpse works as for any monster: the engine's loot goes to the top damage dealer (corpse owner), plus the Chaos loot
  layer with the `boss` tier (extra rolls, gear rarity floor 6, currency, and the boss-only uniques of
  `chaos_unique_items.lua`, which now list the five world bosses).
- **Participation reward** for every player whose contribution score (see "Roles") reached `minScorePercent` (0.25%) of
  the boss max health (~40-60k, about 1.5 minutes of a level 300 hitting it, or as much healing, or twice as much tanking;
  the anti-AFK rule). share = own score / score of all eligible players. Each gets: 500k gold + share x 10M gold into the
  bank, 3 Chaos Orbs + 1 Divine Orb + share x (60 Chaos Orbs, 25 Divine Orbs), a 15% + share x 30% chance of one piece of
  the boss's set (rarity 6-9 via `Game.createItemWithRarity`) and a 0.5% + share x 3% chance of one of the boss-only
  uniques. Items that do not fit go to the inbox. Players offline at the kill get it at their next login (kept in memory
  until a restart).
- **Top 3 of each category** (`reward.podium`: damage, healing, tanking; eligible players only, one player can place in
  several): 1st 5 Divine Orbs + 50 crystal coins, 2nd 3 + 30, 3rd 2 + 20 (the old top-3 damage bonus, now per category),
  an extra unique roll of 3% / 2% / 1% (one unique at most per player) and the category's title for 7 days on the name
  plate: **Bossbreaker** (damage), **Lifewarden** (healing), **Bulwark** (tanking). "Bossbane" stays the weekly World
  Boss board title, so the damage role got its own name. Ties: who reached the value first places higher, then the lower
  id; a value under `placeMinPercent` (0.1% of the boss max health) does not place. The titles are a `ChaosTitles`
  source "worldboss" (titles.lua; registered when the registry is loaded); the expiry is a player storage
  (7100930-7100932, `roles.titleStorage`), so it survives logout and restarts. The victory broadcast lists the three
  top 3 lists ("Top damage: A 1.2M, B 800k, C 50k. Top healing: ... Top tanking: ..."); the client toast has room for
  two lines, so each category gets its own toast ("World boss slain! Top healing: ...").
- **Multi-client:** characters with another character online from their IP may enter and fight (they already cannot attack
  players, and blocking entry would split friends sharing a connection), but get no participation reward (`mcReward = false`)
  and are told so at entry and at the end. A character counts if it was multi-clienting at entry or at any 3-second check
  while inside. Corpse loot is not affected (it follows the engine's damage rules).

### Roles: damage, healing, tanking (`Chaos.worldBoss.roles`)

Tracked per character (GUID) while the boss is alive (`state.stats`); a death keeps what was earned.
- **Damage:** as before, a healthchange event on the boss (summons count for their master, healing does not, overkill is
  clamped to the health left).
- **Healing:** a healthchange event registered on every player inside the arena (at the arena forcefield and every 3 s
  check). For healing the engine runs it before the heal with the healer as `attacker`, so the credit is the effective
  part: capped at the target's missing health, and at the boss damage the target took and was not healed for yet (the
  "debt": every heal from anyone, self-heals included, pays it off), so only healing of boss damage counts and nobody
  farms by healing damage from elsewhere. Healer and target must both be in the arena. **Self-healing does not count**
  (`selfHealWeight = 0`): what a tank survives is already its tanking credit. Attributed (engine source; the spells also in
  game): instant spells on others (Kindred Mend `saen kin`, Circle of Mending `saen gal vas kal`, the Chaos class heals
  that use `doTargetCombat`/combat objects such as the Templar and keystone heal pulses), healing runes used on someone
  (Grand Mending Rune) and potions used on someone (`potions.lua` calls `doTargetCombat(player, target, ...)`). Not
  attributed: `Chaos.heal` / `Creature:addHealth` (no origin and no attacker: the engine skips the healthchange event),
  health regeneration and food, life leech (no origin), and heals cast by summons only count when the summon has a player
  master. Mana restored is not healing.
- **Tanking:** damage from the boss or one of its adds (by creature id, conditions included: the engine passes the
  condition's owner) that the player survived: a hit that kills counts nothing, each hit is capped at `tankHitCap` (8000,
  the biggest designed boss hit), a hit from a boss or add that was not targeting the player (area splash) counts
  `offTargetWeight` (half), and it only counts while the player is active: attacked the boss or an add (EventCallback
  onTargetCombat) or healed someone within `activeSeconds` (30). So an AFK character parked in the boss's area earns
  nothing. Damage taken into a mana shield is not counted (only health).
- **Contribution score** = damage + healing x `healWeight` (1.0) + tanking x `tankWeight` (0.5; tanking overlaps with the
  healing that undoes it). Sizing: a level 1000 tank in front of the boss survives ~2-3k damage per second (~1.5M in a
  10-minute kill, score ~0.75M plus its own damage), a dedicated healer heals ~1-2k per second (~0.6-1.2M), a damage
  dealer does ~1.2M: the three roles end up in the same range of shares.
- **Leaderboards:** the World Boss board still records damage (and now counts a kill for every rewarded player, healers
  included; rows with 0 damage are not ranked). Two weekly boards were added to `leaderboard_config.lua` (one board = one
  value in this model, so a separate board per role fits it better than extending World Boss): **Boss Healer** (healing
  credit, title Lifebinder) and **Boss Tank** (tanking credit, title Ironwall), keys in `roles.boards`. Staff characters
  are left out of every board as before.
- **Achievements** (`achievements_data.lua`, fed from `distribute` via `ChaosAchievements.progress`, guarded): Lifeline
  (most healing at a kill, title), Immovable (most tanking at a kill, title), Pillar of the Raid (top 3 healing or tanking
  at 5 kills, 5 Chaos + 2 Divine Orbs). `achievements.lua` still wraps `computeRewards` with the same signature; a share's
  `rank` is still the damage place, so "Lion's Share" (wb_top) keeps meaning the most damage.

**Tested in game** (test server with a cropped map, Kaelgor at 150k health and 1/8 damage in a test copy, gather 20 s,
`mcReward = true` because both clients share 127.0.0.1): a level 574 Deadeye tanked and attacked, a gamemaster healed him
with Kindred Mend and Circle of Mending (the driver also used a Grand Mending Rune and a health potion on him; their
share of the credit was not isolated), and both hit the boss. Live
stats during the fight (`state.stats`) grew for tanking and healing; the tank died twice (deaths counted, credit kept,
nothing earned while away) and came back. Result: "Top damage: Tester 15k, Duelist 12k. Top healing: Duelist 12k. Top
tanking: Tester 50k." in the broadcast; the reward message (61.6% of the contribution, 1st in damage and tanking, the
item counts match the formula), "You earned the title Bossbreaker / Bulwark for 7 days", both titles in the Achievements window and on
the name plate, the gamemaster's Lifewarden; World Boss and Boss Tank board rows (the gamemaster's healing is left out
of Boss Healer as staff, as for every board); a second kill showed the three per-category toasts.

### Not verified
`Game.getTowns()` temple spots on the real map (the test map is cropped: no portal spot, players were moved onto the
arena forcefield), the inbox path of the reward, and the actual fight balance at full health and damage. Monster damage
may be scaled by the server's own monster level system.

## Bounty board (`bounty.lua`, `bounty_core.lua`, `bounty_config.lua`, `bounty_pool.lua`, `tools/gen_bounty_pool.py`)

Daily rotating "kill X" contracts that pay gold and orbs (roadmap item 10). Client: `client/overlay/modules/game_bounty`
(Adventure > Bounty Board in the top menu), extended opcode 223, storage `7100300` (range 7100300-7100309),
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

Verified on the test server (level 1000 knight): open from the menu (Adventure > Bounty Board); accept; 50 hunt kills -> 2M gold
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
- **Treasure Goblin Chance** (item modifier `goblinchance`, helmets and amulets / rings, "Treasure Goblin Chance +N%":
  tiers 10-15, 14-20, 18-27, 22-33, 28-40, weight 5, cap +100% per character). A respawn's roll becomes 1 in
  `oneIn / (1 + bonus)`: +100% = 1 in 1500. The bonus is the **highest** total among the players within `spoor.radius`
  (24) tiles on the same floor of the spawn point (they do not add up, so a group gains nothing from stacking). Natural
  respawns happen out of sight but within that radius, so the player hunting there counts. The roll is done in two
  stages (`G.rollWithSpoor`: a first roll with the maximum bonus, players looked up only on its hit, then kept with the
  exact share), so the common miss costs nothing. `maxAlive` 3 and the per-cell cooldown are unchanged. Event bonus
  multiplies on top. Staff: `/goblin dry <monster>, <n>` measures the odds, `/goblin roll <monster>, <n>` rolls for real.
- **Variants** (`cfg.variants`, weights 70 / 20 / 10, one monster XML each, stock look types, distinct outfit shader):
  Treasure Goblin (Hoarder, look 297, shader 12, the hoard below), **Gem Goblin** (look 296, shader 9), **Shard Goblin**
  (look 61, shader 10). Same behaviour, experience, leaderboard (all variants count for Goblin Slayer and the goblin
  achievements) and loot rays. The announce, escape and kill texts use the variant's name. `/goblin [hoarder|gem|shard]
  [level]` spawns one. Variant loot overrides parts of the shared table (`variants[i].loot`):
  - Gem Goblin: half the gold, no Chaos / Divine Orbs, 2-3 gems (+1 per 250 levels, max 5; type random, tier by
    `ChaosGems.levelWeights(level)`, 25% one tier better), 1 Orb of Sockets (+25% for a second), 1 gear item, unique
    roll x1, no hoard roll.
  - Shard Goblin: half the gold, 1-2 Chaos Orbs (+1 per 300 levels, max 4), (10 + level / 10) x 80-120% Rune Shards
    (item 32051, max 60), 1 random crafting orb (salvage orb weights), 1 gear item, unique roll x1.
  - Expected per goblin (level 100 / 300): Gem Goblin 2.5 / 3.5 gems and 1.25 Orbs of Sockets; Shard Goblin 20 / 40
    shards. Over all goblins (70/20/10): about 0.5 gems and 2 / 4 shards per goblin. 25 shards make a Chaos Orb at the
    bench, so a Shard Goblin is worth about a Hoarder's orbs without its gear; goblins stay rare (1 in 3000, at most 1 in
    1500 with the cap), so the effect on the economy is small.
  Not done: **Goblin's Purse** (one-use vault item). The rift room builder is bound to a rift run (key, slot, lives,
  rewards); a clean standalone vault would need its own slot builder, which is not small.
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

## Invasions and world events (`invasion.lua`, `invasion_core.lua`, `invasion_config.lua`, `worldevents.lua`)

Server-wide events in the open world. Client: `game_invasion` (HUD and the upcoming events window, extended opcode
251), toasts through `game_chaosnotify` (action `invasion` on opcode 79). Every number is in `invasion_config.lua`
(loaded as `Chaos.invasionConfig`; plain data, so the merchant NPC reads it too). The pure logic (schedule, waves,
scaling, breach meter, shares, rewards, occupation, world event rotation, HUD message) is in `invasion_core.lua` and
tested by `tests/invasion_test.lua`. No database table, no storage: the state is in memory (a restart ends a running
invasion, the Victory buff and the world event; offline rewards wait in memory like the world boss's).

**Install.** The scripts load with the rest of `data/scripts/chaos/`. Copy `data/npc/Wandering Merchant.xml` and
`data/npc/scripts/wandering_merchant.lua` into the server's `data/npc/` (the ascension quest's installer step, which
`install_all.py` runs, copies every file of `server/data/npc/`). Without them the merchant event refuses to start
("the merchant NPC could not be placed") and the rotation picks another event next time.

### When

- **Schedule** (`schedule`): Wednesday 19:30 and Sunday 17:30, area and faction `"random"`. A random pick depends only
  on the start time, so the warnings, the calendar and the start name the same area and faction.
- **Random invasion** (`random`): on 35% of the days, at a random minute between 12:00 and 23:00, at least 90 minutes
  from a scheduled one and outside the world boss hours 15 and 21. It is decided by the date alone (a restart does not
  roll again) and kept secret until its first warning.
- **Warnings** 30, 10 and 1 minutes before (broadcast + toast). The login-screen calendar and Adventure > Events get one
  whole-day "Invasion" entry per scheduled weekday (added to `Chaos.events.list` at load, as the siege does).
  Adventure > Events shows the running invasion and the upcoming events (scheduled invasions, the running or next world
  event, the Victory buff) and opens the client window.
- A GlobalEvent checks every 15 s. A start while another invasion (or an occupation) runs is skipped and logged.

### The fight

- **Areas** (`areas`): a rectangle on one floor, a level, a target point and its name, optional `edges` the waves come
  from, `exclude` rectangles, a faction list, `kind` (town / hunt), `invasion = false` / `worldEvents = false`.
- **Factions** (`factions`): existing monster types with their hunting level (the `bounty_pool.lua` estimates) and a
  boss. Orc Warband (Orc .. Orc Warlord, boss "Warchief Grashnak" = Orc Warlord renamed), Undead Legion (Skeleton ..
  Blightwalker; Dracola as "Dracola the Unburied", The Pale Count from area level 200), Infernal Host (Fire Devil ..
  Juggernaut; Orshabaal, Ghazbaran from 300), Minotaur Horde (Minotaur .. Moohtant; Bullwark as "Bullwark the Gorer").
  The renaming runs in an `onSpawn` callback, before the monster is placed, so clients see the new name.
- **Waves**: 5. Wave i has (10 + 4 (i - 1)) x player factor monsters (1 + 0.15 per extra player within 30 tiles of
  the area, at most x3): 10, 14, 18, 22, 26 for one player. Monsters come from the faction's roster within [0.35, 1.25] x
  the area level (at least 3 types), wave 1 from its lower part, the last wave from its upper part. Packs of 3-5 appear
  together at one point of the outer 3 rows of the area border. A spawn tile must have ground and be walkable, and
  must not be a protection zone, a house, a depot, a teleport or a floor change, an `exclude` rectangle or within 6
  tiles of a temple (`templeRadius`). Tiers per invader: magic 10% + 4% per wave, rare 2% + 2%, legendary 0% + 1%
  (`ChaosApplyTier`). The next wave comes when 25% of the current one is left or after 150 s.
- **Scaling** to the area level: ratio = area level / monster level; health x ratio, damage x ratio^0.4, experience x
  ratio^0.8, each clamped to [0.5, 10 / 2.5 / 6]. The damage multiplier is applied on the players' `healthchange`
  (like the tier multipliers), experience in an `onGainExperience` callback.
- **The push**: every 0.4 s each invader without a target takes a step to the target point (at its own speed). It
  uses `Creature:getPathTo` and falls back to greedy steps. The step is made with `Creature:move(tile, 0)`, so the
  engine's own rules apply: no monster enters a protection zone, a house or a blocked tile (`move(direction)` would
  ignore all of that). An invader with a player target fights (engine AI) and walks on afterwards.
- **Breach meter**: every second, + 0.25% per invader within 2 tiles of the target (the boss counts 4), at most
  1.5% per second; - 0.25% per second while none is there. 5 invaders at the gate take 80 s to break it. HUD
  broadcasts at 50% and 80%.
- **Boss**: in the last wave, the faction boss with the highest level not above the area level, legendary
  (modifiers and shader), health 2500 x area level x player factor (at least 40,000), damage scaled from its level
  (exponent 0.6, [0.3, 2.5]), experience x3.
- **HUD** (every 2 s to every player online from level 30): area and faction, the target, wave N of M, invaders left,
  the time left, "Horde slain" (killed of all planned), the breach meter (amber, orange from 50%, red from 80%), the
  boss's health, the top 3 contributors with their share, your rank, share and kills. Click it to fold it. It sits
  under the character plate (the rift HUD's spot) and moves right of the rift HUD while a rift runs.

### Win

All waves and the boss slain within 20 minutes. Contribution = damage dealt to invaders + 0.6 x healing done to other
players inside the area (+10 tiles, effective healing only) + kills x 0.25 x the average invader health. A player needs
0.2% of the total invader health in contribution to be rewarded. Multi-client characters fight but get nothing
(`mcReward`). Rewards per player, by share of the total:
- gold to the bank: area level x (200 + 8000 x share), e.g. area 100 alone 820,000; ten equal defenders 100,000 each;
- 1 Chaos Orb + share x 20 Chaos Orbs and 6 Divine Orbs; top 3 extra Divine Orbs (3 / 2 / 1), the first an Exalted Orb;
- a unique at (100 + share x 600) / 10000: the Chaos loot layer's own roll for the boss as a boss-tier kill (x20 item
  find), else any non boss-only unique up to the area level + 20 (season uniques respect the season);
- the weekly **Defender** board (`leaderboard_config.lua`, title "Defender of the Realm"): 10 points per invasion + the
  share in percent (`ChaosLeaderboard.record("defender", ...)`, so the season and guild wrappers count it too);
- achievements, guarded: `ChaosAchievements.progress` with `invasion_defended`, `invasion_top` (rank 1),
  `invasion_boss` (did damage to the boss), `invasion_kills` (kills), `invasion_fought` (a lost one),
  `invasion_liberated`. No entries in `achievements_data.lua` use them yet.
- **Victory buff**: +10% experience for 60 minutes. With `scope = "server"` it is an entry of `ChaosEvents.dynamic`, so
  `events_schedule.lua` applies it and Adventure > Events lists it; with `scope = "area"` the invasion's own experience callback
  applies it inside the area only.

### Loss and occupation

The breach meter at 100% or the time up: the area is **occupied** for 30 minutes. The survivors stop pushing and get
x1.5 health, and a garrison of 6 rare (70%) / legendary (30%) invaders appears around the target. The HUD shows
"<area> is occupied", the occupiers left and the time. All slain: the area is **liberated**, and everyone who fought
them gets 25% of the gold and orbs (no unique, no board). Time up: they withdraw (removed). **NPC shop prices are not
changed**: the trade code is the base server's NPC library (`npc/lib/npcsystem`), and a price penalty per town would
mean editing it; skipped on purpose. `ChaosInvasion.isOccupied(areaKey)` is there for a later hook.

### World events (`worldevents.lua`)

One at a time, the first 20-60 minutes after a start, then every 2-4 hours. It is never in the area of a running
invasion, never during one, and never within 45 minutes of an invasion start. The kind is picked by weight (storm 40,
merchant 30, golden 30), never the same twice in a row. A broadcast + toast at the start and the end, and an entry in
Adventure > Events while it runs (`ChaosEvents.dynamic.worldEvent`).
- **Chaos Storm** (15 min): magic, rare and legendary spawn chances x3 in the area. `monster_tiers.lua` multiplies its
  spawn roll by `ChaosWorldEvents.tierMult(position)`. Lightning and clouds around the players inside every 2 s.
- **Wandering Merchant** (20 min, town areas only): the NPC "Wandering Merchant" at a random free tile of the area (or
  one of `merchantSpots`). Only the area is announced. Goods: Chaos Orb 40k, Divine Orb 120k, Exalted Orb 200k, Orb of
  Alchemy 60k, Orb of Annulment 80k, Double Experience Potion 350k, supreme health potion 900 (no stock limit).
- **Golden Hour** (30 min): +25% Chaos loot in the area. `loot_config.lua` `rateMult` multiplies by
  `ChaosWorldEvents.lootMult(ctx)`, as for the rifts; golden rings around the players inside.

### Commands

Adventure > Events (everyone). Staff (`/invasion`, group with access): `start <area|random> [faction]`, `stop`, `status`,
`schedule <minutes> [area] [faction]` (a one-off start in memory, with the warnings), `check [area]` (is the area usable
on this map: target tile, valid border tiles and why the others are refused), `areas`, `event
<storm|merchant|golden|stop> [area]` (the merchant's spot is in the staff reply), `wave` (the next wave now), `breach <n>`.

### Coordinates for the real map

The areas in `invasion_config.lua` were read from the real map file (town temples from its towns list, tiles of
the rectangles from the map nodes, blocking from `items.otb`). The test server runs a cropped map, so they were not
walked in game.
- `thais` (level 80): x 32324-32414, y 32196-32286, z 7, target 32365,32245 (the first walkable tile outside the temple's
  protection zone; the whole rectangle is one connected walkable area reaching all four borders).
- `carlin` (level 60): x 32315-32405, y 31737-31827, target 32355,31782.
- `thaisfields` (hunting, level 150): x 32290-32400, y 32292-32338, target 32345,32315 (south of Thais).
- `carlinwilds` (hunting, level 100): x 32300-32440, y 31685-31735, target 32370,31710 (north of Carlin).
- `venore` (level 120) is **disabled**. The streets are bridges over water, and the largest connected walkable piece
  around the temple holds only ~370 tiles. Try it with `/invasion check venore` and set `edges` / `target` before enabling it.
On the live server run `/invasion check` once: it lists every area with its problems. Levels are guesses: set them to
the hunting level around each area.

### Test server

`data/scripts/zz_ztest_invasion.lua` (srv2 only, not in the repo) builds a 46 x 41 grass field with a wall and a gate
on the empty cropped map and adds it as area `testtown` (level 300) with `ChaosInvasion.addArea`.

**Verified in game** (srv2, client game_ui, level 1000 character):
- the 30, 10 and 1 minute toasts of a scheduled invasion, and its start; a start skipped while another one ran;
- `/invasion check | schedule | start | status | breach` and Adventure > Events with the upcoming events window;
- packs arriving at the north edge and walking around the wall to the gate; invaders at the gate raising the breach
  meter (50% / 80% broadcasts);
- the HUD updating (waves, left, time, horde slain, breach, top, you) and the boss (Warchief Grashnak) with its health
  in the HUD;
- a win in 3:07: Victory toast, the reward message (7,590,000 gold, 31 Chaos, 13 Divine, 1 Exalted Orb, before the
  gold and orbs were lowered to the current numbers), the Victory buff in Adventure > Events, the Defender board entry (110
  points, 1 invasion) in the leaderboard window;
- two losses (breach) with the occupation: garrison, HUD "occupied", the liberation with its reward (615,000 gold, 5
  Chaos, 1 Divine);
- Chaos Storm: 1000 Dragons created in the area had 175 with a tier shader against 58 without the storm (x3); lightning;
- Wandering Merchant: placed, greeting, trade window with the configured goods;
- Golden Hour: `rateMult` 1.25 inside the area, 1.0 outside.

**Not verified**: healing credit (needs two players), several defenders sharing the rewards, a unique reward (7% roll
not hit), the real map areas, the area-scope Victory buff, a natural world event rotation (started by command), a
withdrawal after 30 minutes. Found on the way, not fixed: `monster_tiers.lua` keys the tier state by the creature id
inside `onSpawn`, which is 0 before the placement, so naturally rolled tiers keep their health and shader but report
"normal" (no tier experience or damage multiplier, no monster bar label). Invasion monsters are not affected
(`ChaosApplyTier` after the creation). Ambush copies of slain invaders are ordinary monsters and stay after an
invasion.

**Edits to shared files**: `chaos_constants.lua` (`ChaosOpcodes.invasion = 251`), `leaderboard_config.lua` (board
`defender`), `loot_config.lua` (`rateMult` x `ChaosWorldEvents.lootMult`), `monster_tiers.lua` (spawn roll x
`ChaosWorldEvents.tierMult`), `events_schedule.lua` (`ChaosEvents.dynamic`: runtime events in `E.active`),
client `game_chaosnotify/notifications.lua` (toast type `INVASION`, action `invasion`).

## Leaderboards (`leaderboard.lua`, `leaderboard_core.lua`, `leaderboard_config.lua`)

Client `game_leaderboard` (opcode 229), opened with Social > Leaderboards in the top menu. Settings:
`leaderboard_config.lua` (loaded as `Chaos.leaderboardConfig`). Tables: `chaos_leaderboard`, `chaos_leaderboard_titles`
(`sql/chaos.sql`); the last processed reset week is the `server_config` row `chaos_leaderboard_reset`.

**Why not the base highscores.** The top menu used to open the base client's `game_highscores`. That window asks for
data with the game packet 0xB1 (the newer protocol's highscores), which this engine does not parse: it stays empty
(checked in game). The base server's own `customs/highscores` script answers extended opcode 73 for a different client
window, and builds its SQL from client input without checks. So the Chaos window is separate, and the menu entry
"Highscores" became "Leaderboards".

- **Boards.** Weekly: **World Boss** (damage dealt to world bosses, kills participated), **Boss Healer** and **Boss Tank**
  (healing and tanking at world bosses, see "World bosses"), **Bounty Hunter** (contracts
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
needs no change. The client needs the multi-use flag on two orbs in its `Tibia.dat`:
`python3 -I client/tools/sprites/set_multiuse.py <client>/data/things/1098/Tibia.dat` (after `gen_effects.py`, which
writes a new dat).

**How an item carries modifiers (base server).** A rarity is the custom attribute `rarity` (1..15: Common, Uncommon,
Rare, Epic, Legendary, Exotic, Mythic, Chaos, Eternal, Divine, Phantasmal, Celestial, Cosmic, Abyssal, Transcendent).
The engine's C++ roll (`Item::applyRarityEffects`) used to make them; new items are now rolled by `ChaosCrafting.forge` (see "Item modifiers"), the same attributes and an item level
(`combatPowerLevel`, shown as "Level: N"), a small attack/defense/armor/hit chance bonus, and per rarity a fixed number
of modifiers, one custom attribute each: absorbs `rarity_<x>Absorb` (%), skills `rarity_<skill>Skill` (magic level is
`rarity_maglevelSkill`), critical / mana leech / life leech as chance + amount pairs, and on weapons without an element
of their own one `rarity_element<x>` (% extra damage). Everything is also written into the description attribute
("Level: 53, Holy +3%, Fishing +1, Critical Chance +1%, Critical Hit +1%"), which is what the look text and the client
tooltip show. With engine patch 0004 a critical / leech chance is (2 x roll + 1) / 3 of the pair's roll (1..6 -> 1, 1,
2, 3, 3, 4; the amount keeps the roll; the Exalted Orb does the same, `ChaosCrafting.specialChance`). `customs/rarity/base_rarity.lua` turns the attributes into conditions and storages when the item is
equipped (and at login); the element and absorb combat scripts read those storages. Uniques (`chaos_unique_items.lua`)
are base items with the custom attribute `chaos_unique` and their stats as the same `rarity_*` attributes, without a
rarity. On top of these, items carry the Chaos modifiers of the next section (`chaos_mod_<key>`).

**Every orb is used directly on the item.** "Use with" on the orb, then click an item or a Rift Key in the backpack
(an `Action` per orb id in `crafting.lua`, `ChaosCraftingUseOrb`). The bench is optional. All seven orbs go through the
same `craft()` as the bench: the orb is owned, the item is in the backpack (equipped items and the ground are still
refused: the copy-making orbs would have to unequip and re-equip, and the equip scripts would have to follow), no
uniques, no stacks, the rules below, a line in `chaos_crafting_log`. Using an orb on nothing, a creature, the floor or
anything that can never carry modifiers only explains how to use it ("Use the Exalted Orb on an item: choose
"Use with" on the orb, then click an item or a Rift Key in your backpack..."); it no longer opens the bench.

**How the two plain-use orbs became use-with (and why that way).** The three rune stones and the Chaos/Divine Orbs
were already use-with; the Orb of Transmutation (29851, client 27195) and the Exalted Orb (29855, client 27199) were
plain items. Use-with needs two flags: the client's multi-use flag in `Tibia.dat` (otherwise the client never starts
the crosshair) and the server's `useable` flag in `items.otb` (`Game::playerUseItemEx` refuses an item without it).
Chosen: set both flags on the existing ids (option a). `install_crafting.py` sets `FLAG_USEABLE` on the two otb nodes
(keeps `items.otb.bak`), `client/tools/sprites/set_multiuse.py` inserts flag byte 7 into the two items of the dat
(keeps `Tibia.dat.bak`; checks that the dat still parses exactly). The ids stay the same, so no migration: every orb
already in a backpack, depot, store offer, loot table, bounty chest and the character-upgrade costs
(`waystone_system/character_upgrades.lua` counts 29851 and 29855) keeps working. Moving the orbs to other multi-use ids
(option b) would have needed a migration of every existing stack and of all those references. With a dat that lacks
the flag the orbs still work on the bench; the engine answers a plain use of a `useable` item with "You cannot use this
object" (it refuses plain use of every use-with item, the rune stones included).

The Chaos and Divine Orbs are registered by `crafting.lua` too (same rules, the log, Rift Keys); `crafting.lua` loads
before `customs/rarity/reroll_rarity_stats.lua` (scripts load in path order), and the installer makes that script skip
its own two registrations when `ChaosCrafting.ownsStockOrbs` is set (otherwise the engine prints a duplicate warning
and keeps the first one, ours). The installer still adds the unique guard to its `isRerollable`.

**The orbs on gear.** A modifier is one line of the description (a leech or critical pair is one modifier, a Chaos
modifier is one). The maximum per rarity is one more than a weapon of that rarity rolls: 3, 4, 4, 5, 5, 6, 6, 6, 7, 7,
7, 7, 7, 9, 9 (`maxMods`), Chaos modifiers included.

| orb | id | on gear |
|---|---|---|
| Orb of Transmutation | 29851 (existing currency item) | normal item (no rarity, no modifiers, no item level) -> Common 65% / Uncommon 35%, engine roll + Chaos modifier roll |
| Orb of Alchemy | 24691 (rune stone, named by the installer) | normal item -> Rare 55% / Epic 30% / Legendary 15%, engine roll + Chaos modifier roll |
| Exalted Orb | 29855 (existing currency item) | item with a rarity and a free slot: one new modifier it does not have yet. Group weights absorb 30, skill 30, leech/critical 25, element 15 (weapons only, one at most), Chaos modifiers 25 (those the item's kind may get); combat skills weigh 4, profession skills 1; value from the rarity's range (item.cpp tables, `chaos_item_mods.lua` tiers) |
| Orb of Annulment | 24697 (rune stone) | item with a rarity: one random modifier goes, Chaos ones included (rarity and level stay) |
| Orb of Scouring | 24688 (rune stone) | item with a rarity: a plain copy of the base item (no Chaos modifiers either) |
| Chaos Orb | 29856 | item with a rarity: a new copy of the same rarity (new level, engine modifiers and Chaos modifier roll) |
| Divine Orb | 29857 | a new copy with a new random rarity, none 85% of the time (the stock roll), plus the Chaos modifier roll |

Transmutation, Alchemy, Scouring, Chaos and Divine make a new copy (like the stock orbs), so upgrade levels on the item
are lost; Exalted and Annulment change the item in place and rewrite only the rarity part of the description (text in
front of "Level:" and `[...]` upgrade slots behind it are kept). Never touched: uniques (also an old unique without the
marker, recognised by its spec name), stacks, containers, non-gear, the boat items, equipped items, items outside the
backpack. No Vaal-style orb. The eighth orb on the bench, the Orb of Sockets, changes the number of sockets: see "Gems
and sockets".

**The orbs on Rift Keys** (the map way; `C.keyCheck` / `C.keyApply`). The rift's own modifier pool, value ranges and
reward bonuses (`rift_config.lua` `mods`, `rift_core.lua`); the tier never changes; the key's `rift_mods` attribute,
name and description (modifiers, reward bonuses, level) are written again through `ChaosRift.applyKey`. Rarity, unique
and slot rules do not apply; the backpack rule and the log do.

| orb | on a Rift Key |
|---|---|
| Transmutation | a key without modifiers gets 1 |
| Alchemy | a key without modifiers gets 2 (60%) or 3 (40%) (`key.alchemyCount`) |
| Exalted | one more modifier the key does not have, up to `key.maxMods` (3) |
| Annulment | one random modifier goes |
| Scouring | every modifier goes |
| Chaos | new modifiers, the count rolled with the drop weights (1: 50, 2: 35, 3: 15) |
| Divine | the same modifiers, new values inside their ranges (whole steps) |

`key.maxMods` also caps the decoded key (`R.decodeMods`); above 3 the crash refund marker would need more storages.

**Bench.** Economy > Crafting Bench in the top menu (the orbs no longer open it). Drag an item or
a Rift Key from an open backpack onto the slot, or click one in the grid (bags inside the backpack included, 64 at
most; keys have a violet frame). The bench shows rarity and item level (a key: tier, level and reward bonuses),
modifiers / maximum and every orb with your count and, when it fits, a preview of what it would do ("2 -> 3 of 5
modifiers", "Rare 55%, Epic 30%, Legendary 15%", "same modifiers, new values"; `C.preview`); a button is enabled only
when the server says the orb fits. The server checks again on every click: the item is found by its path from the
backpack plus its id and a signature of its modifiers (moved or changed -> "put it on the bench again"), the orb is
owned, the rules above, 250 ms between orbs. The last 8 crafts come from `chaos_crafting_log` (rows older than 60 days
go at startup); use-with crafts are logged too.

**Drops and rewards.** Chaos loot layer (`loot_config.lua` currency, per 10000 kills, normal / magic / rare / legendary /
boss): Transmutation 30/200/700/2500/3500 (1-2), Alchemy and Annulment 10/80/300/1200/2000, Scouring
15/100/400/1500/2500, Exalted 4/30/120/600/1000; weights for the guaranteed legendary/boss draw 20/10/10/10/5 (Chaos 70,
Divine 30). Simulated 10000 legendary kills: Chaos 8513, Divine 4380, Transmutation 7607, Alchemy 1862, Annulment 1864,
Scouring 2110, Exalted 945. Store (Chaos Currency): Transmutation 5, Scouring 12, Alchemy 15, Annulment 20, Exalted 40
coins. Weekly bounty chest: + 3 Orbs of Transmutation and 1 Orb of Annulment (`weeklyExtra` in `bounty_config.lua`).

**Tested in game** (test server, cropped map, client with the patched dat): use-with of all seven orbs on items with no
bench open (the Orb of Transmutation and the Exalted Orb with the mouse: right click, then click the item; the others
by `g_game.useWith`, the same packet), the hint for an orb used on oneself and on the floor, the bench (select an item
and a key, previews, Exalted from the bench), every orb on a Rift Key by use-with and on the bench, then a rift opened
with the crafted key (Brutality 15, Withering, Swarm 2: damage x1.15, no regeneration, packs of 5-6), the log rows of
every path; earlier: refusals (unique, full item, no orb, equipped item), drag and drop onto the slot, the store
purchase and the loot simulation. `tests/crafting_test.lua` covers eligibility, each orb on a mocked item, slot limits,
the description, unique protection, the Chaos modifiers through the orbs, the previews and every orb on a Rift Key.
Not tested: the weekly bounty chest with the extra orbs (needs seven finished contracts), a hotkey set to plain "use".

## Dark tile set (`data/lib/chaos_dark_tiles.lua`, `data/lib/chaos_dark_paint.lua`, `tools/install_dark_tiles.py`)

Our own dark environment tiles, drawn in code by `client/tools/sprites/gen_dark_tiles.py` (client/MANIFEST.md "Dark tile
set"): 9 grounds (cracked obsidian, magma-veined obsidian, ash soil, bone-strewn earth, wet black rock, mossy black rock,
dark moss, ruined dark stone floor, an animated cursed pool), 48 border pieces (edges, outer and inner corners for
obsidian, ash soil, wet rock and dark moss), 3 walls and 14 objects (dead trees, a dead bush, a boulder, a 2x2 rock
outcrop, ruined and broken pillars, an iron brazier and a standing torch that give light, violet and teal glowcaps,
blood crystals, bones, rubble).

- Ids: client ids 27484-27557 (appended after the last stock item), server id = client id + 3000 (30484-30557).
  `data/items/dark_tiles.csv` is the manifest (ids, names, size, ground speed, otb group / flags / top order, light,
  dat flags); `data/lib/chaos_dark_tiles.lua` maps the names to server ids. Both are written by the generator.
- Install: step 5d. `install_dark_tiles.py` appends one otb node per row (keeps `items.otb.bak` the first time, parses the
  file again and checks every node) and writes the `items.xml` names between two marker comments. A second run changes
  nothing; a server id that already belongs to another client id stops it before anything is written.
- Without the items (or with `dark.enabled = false`) every area uses its stock ids: `ChaosDarkTiles.id(name, fallback)`
  returns the fallback while `ItemType(id):getId()` is 0, and `ChaosDarkPaint.ready(style)` is false.
- Where it is used (`ChaosDarkPaint.plan` / `apply`; styles in `chaos_dark_paint.lua`): a main ground with accent
  variants, patches of a second ground with border pieces around them, loose walkable pieces on the floor and solid ones
  only against the walls, never near arrival, portal or spawn tiles.
  - Rifts (`rift_config.lua` `dark`): walls `obsidian_wall`, hub lights `brazier`; themes Abyssal Rift (`abyss`), Obsidian
    Hall (`hall`), Ashen Crypt (`crypt`), Forsaken Sanctum (`sanctum`).
  - World boss arena (`chaos_constants.lua` `worldBoss.dark`): `dark_wall`, `ruined_pillar` as cover, `brazier` lights,
    styles `arena` and `lobby`.
  - Ascension trial room (`ascension_quest_config.lua` `trial.dark`): `ruined_wall`, `brazier`, style `trial` (nothing
    solid on the floor).
  - Guild hall decoration tier 2 "Obsidian" (`guild_config.lua`): `obsidian_floor` and `obsidian_wall`.
- Tests: `tests/dark_paint_test.lua` (border pieces per neighbourhood, a planned room: borders next to patches, nothing
  solid near reserved tiles or away from the walls; the fallback when not installed; the Lua ids against the manifest).
  Checked in game on the test server: a tier 1 rift (Ashen Crypt), `/worldboss arena` (lobby, corners, pillars) and the
  trial room, with the set on and off, at normal size and with the client's HD upscaling (x2).

## Item modifiers (`data/lib/chaos_item_mods.lua`, `chaos_crafting.lua`, `item_mods.lua`)

Every item with a rarity is rolled by `ChaosCrafting.forge` (drops, rift chests, world boss, goblin, tutorial, and the new
copy of every orb): an **item level** from its source, **how many modifiers** from its rarity, the **tier** of each from the
item level, and a **prefix / suffix** split. The engine's own rarity roll (`Item::applyRarityEffects`) is no longer used for
new items. All numbers are in `ChaosItemMods.config`; tests: `tests/item_mods_test.lua` (catalogue, tiers, item level,
counts, every effect against a mocked engine), `tests/crafting_test.lua` (forge, orbs, prefix / suffix rules, orbs v2 API),
`tests/item_tooltip_test.lua`, `tests/salvage_test.lua`, `tests/lootfilter_test.lua`, `tests/supports_test.lua`.

**Item level** (`M.sourceLevel`, `loot.lua L.dropLevel`). Stored as the custom attribute `chaos_ilvl` (1-150) and mirrored
into `combatPowerLevel`, which the client frame and the stock scripts read; items from before have only
`combatPowerLevel`, which counts as the item level. The level of a drop is the dropping monster's level
(`Monster:getMonsterLevel`; a monster without one: its hunting level in `bounty_pool.lua`, else 1.6 x sqrt(experience)
raised by health / 60, the estimate of `tools/gen_bounty_pool.py`) along the curve `itemLevel.curve` (level 1 -> 1, 50 ->
22, 100 -> 36, 200 -> 54, 500 -> 90, 900 -> 118, 1500 -> 136, 6000 -> 145), plus: Magic +2, Rare +4, Legendary +7, boss +10;
inside a rift +1 per rift tier (at most +15), an Omen guardian arena +15 more; capped at 150. World boss drops and rewards
are fixed at 145 (`worldBoss`), the tutorial's gear at 5 (`tutorial`), rift chest and coffer gear use the rift boss's
level (else the top of the tier's window) with the rift bonuses, the treasure goblin its area level as a Legendary.
`store` (60) is the fixed level for Chaos-store gear; the store sells orbs and no gear today, so nothing uses it yet
(`ChaosCrafting.createItem(id, rarity, ChaosItemMods.config.itemLevel.store)` is the call). Plain gear without a rarity
gets `chaos_ilvl` too, so an Orb of Transmutation or Alchemy on it uses the level it dropped with. Orbs keep the item's
level (Scouring and Divine too); an item without any level gets one from the item type's required level.

**Tiers.** Eight per modifier, T1 the lowest, T8 the highest. A tier needs an item level (`tierLevels`): T1 1, T2 15, T3 30,
T4 50, T5 70, T6 95, T7 120, T8 140. A modifier rolls among the best five tiers the item level allows
(`tierWindow`), weighted 100, 90, 80, 65, 50, 35, 22, 12 for T1..T8 (higher tiers are rarer): at item level 150 T8 comes
6.5%, T4 35%; at item level 40 T3 40%, T2 33%, T1 27%. The five ranges the modifiers had before (tier = ceil(rarity / 3))
are T2-T6 now, so old items keep their meaning. The tier is stored next to the value as `ct_<attribute key, lower case>`
(`ct_chaos_mod_dodge`, `ct_rarity_swordskill`); an item without it (every item from before) reads its tier from the value:
the lowest of T2-T6 whose range holds it, above T6 the top. The pair attributes (critical, leech) store one tier for both.

**How many, and the sides.** Rarity decides the count (`config.rarity`):

| rarity | modifiers on a new item | prefixes / suffixes at most (each) |
|---|---|---|
| Common, Uncommon | 2 | 1 |
| Rare, Epic, Legendary | 3 | 2 |
| Exotic | 4 | 2 |
| Mythic, Chaos | 4 | 3 |
| Eternal, Divine, Phantasmal, Celestial | 5 | 3 |
| Cosmic, Abyssal, Transcendent | 6 | 3 |

(`config.rarity.count` / `.sides`.) The Exalted Orb fills up to 2 x the side
limit. Prefixes are damage and defence, suffixes utility, resistances and speed; a new item is rolled until the count or
both sides are full. Old items keep what they have (an old Epic item may carry more of one side than today's limit; the
orbs only add on a side that is open). **The Exalted Orb** picks among the modifiers on an open side that the item does not
have and that suit its kind, **Annulment** removes one at random, **Chaos / Transmutation / Alchemy / Divine** make a new
copy and `forge` it (so the limits hold), **Scouring** makes a plain copy. An item's description lists them:
"Item Level: 57. Prefixes: Sword +2 (T3); Critical Chance +1%, Critical Hit +2% (T2). Suffixes: Fire +3% (T4)".

**The engine's types** (absorbs, skills, critical / leech pairs, weapon elements) have tiers too (`config.engine`), weighed
against the Chaos types in one list (`ChaosCrafting.affixes()`):

| group | side | weight | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 |
|---|---|---|---|---|---|---|---|---|---|---|
| absorb | suffix | 3 | 1 | 1-2 | 1-3 | 2-3 | 2-4 | 3-5 | 4-6 | 5-7 |
| skill | prefix | 3 | 1 | 1-2 | 1-3 | 2-3 | 2-4 | 3-5 | 4-6 | 5-7 |
| profession | suffix | 1 | 1 | 1-2 | 1-3 | 2-3 | 2-4 | 3-5 | 4-6 | 5-7 |
| critical | prefix | 8 | 1 | 1-2 | 1-3 | 2-3 | 2-4 | 3-5 | 4-6 | 5-7 |
| leech | suffix | 6 | 1 | 1-2 | 1-3 | 2-3 | 2-4 | 3-5 | 4-6 | 5-7 |
| element | prefix | 2 | 1-3 | 3-6 | 5-9 | 7-12 | 10-16 | 13-20 | 17-26 | 22-35 |

(skills: combat skills and magic level; profession skills are `profession`; critical is the amount, the chance part is about
two thirds of it, `ChaosCrafting.specialChance`.)

**The Chaos modifiers** (kind = which items may roll it: weapon, shield, helmet, armor, legs, boots, jewel = amulet or ring,
other = gloves, belts and the like; cap = the most a character gets from everything equipped).

| key | text | side | kinds | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 | cap |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bossdamage | Damage to Elites and Bosses +N% | prefix | jewel, weapon | 1-3 | 2-4 | 3-6 | 5-8 | 6-10 | 8-12 | 10-14 | 12-16 | 30 |
| dodge | Dodge +N% | prefix | armor, boots, legs, other, shield | 1 | 1 | 1-2 | 1-2 | 2-3 | 2-4 | 3-4 | 3-5 | 10 |
| reflect | Reflect Damage +N% | prefix | armor, shield | 1 | 1-2 | 2-3 | 2-4 | 3-5 | 4-6 | 5-7 | 6-8 | 15 |
| thorns | Thorns +N | prefix | armor, legs, shield | 1-4 | 3-8 | 8-15 | 15-30 | 25-50 | 40-80 | 60-110 | 90-150 | 250 |
| monsterreduction | Damage Taken from Monsters -N% | prefix | armor, helmet, legs, shield | 1 | 1 | 1-2 | 1-2 | 2-3 | 2-4 | 3-5 | 4-6 | 12 |
| block | Block Chance +N% | prefix | shield | 1-2 | 2-3 | 3-4 | 4-5 | 5-7 | 6-8 | 7-10 | 9-12 | 15 |
| bleedchance | Chance to Bleed +N% | prefix | other, weapon | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-11 | 10-13 | 12-16 | 30 |
| ignitechance | Chance to Ignite +N% | prefix | other, weapon | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-11 | 10-13 | 12-16 | 30 |
| poisonchance | Chance to Poison +N% | prefix | other, weapon | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-11 | 10-13 | 12-16 | 30 |
| chillchance | Chance to Chill +N% | prefix | other, weapon | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-11 | 10-13 | 12-16 | 30 |
| shockchance | Chance to Shock +N% | prefix | other, weapon | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-11 | 10-13 | 12-16 | 30 |
| physpen | Physical Penetration +N% | prefix | jewel, weapon | 1-2 | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-11 | 10-13 | 25 |
| elepen | Elemental Penetration +N% | prefix | jewel, weapon | 1-2 | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-11 | 10-13 | 25 |
| execute | Executes Monsters below N% Health | prefix | weapon | 1 | 1-2 | 2 | 2-3 | 3-4 | 4-5 | 5-6 | 6-8 | 10 |
| dot | Damage over Time +N% | prefix | jewel, other, weapon | 2-4 | 4-6 | 6-9 | 8-12 | 10-15 | 13-19 | 16-23 | 20-28 | 60 |
| attackspeed | Attack Speed +N% | suffix | weapon | 1-2 | 2-3 | 3-5 | 4-6 | 5-8 | 7-10 | 9-12 | 11-14 | 15 |
| movespeed | Movement Speed +N% | suffix | boots | 1-2 | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-10 | 9-11 | 12 |
| lifeonkill | Life on Kill +N | suffix | helmet, jewel, weapon | 2-5 | 5-10 | 10-20 | 20-40 | 35-60 | 50-90 | 75-120 | 100-150 | 300 |
| manaonkill | Mana on Kill +N | suffix | helmet, jewel, weapon | 1-3 | 3-6 | 6-12 | 12-25 | 20-40 | 30-60 | 50-80 | 70-100 | 200 |
| lifeonhit | Health on Hit +N | suffix | jewel, other, weapon | 1-2 | 2-4 | 3-6 | 5-9 | 7-13 | 10-18 | 14-25 | 20-35 | 120 |
| manaonhit | Mana on Hit +N | suffix | jewel, other, weapon | 1 | 1-2 | 2-4 | 3-6 | 5-8 | 7-12 | 10-16 | 14-22 | 80 |
| regen | Health Regeneration +N per Second | suffix | armor, helmet, jewel, legs, shield | 1-2 | 2-4 | 4-7 | 6-10 | 9-15 | 13-21 | 18-28 | 25-40 | 120 |
| experience | Experience +N% | suffix | helmet, jewel | 1 | 1-2 | 1-3 | 2-4 | 3-5 | 4-6 | 5-7 | 6-8 | 15 |
| goldfind | Gold Find +N% | suffix | helmet, jewel, legs, other | 1-3 | 2-4 | 3-6 | 4-8 | 6-10 | 8-14 | 11-17 | 14-20 | 40 |
| itemfind | Item Find +N% | suffix | helmet, jewel | 1 | 1-2 | 2-3 | 2-4 | 3-6 | 4-8 | 6-10 | 8-12 | 25 |
| rarityfind | Rarity Find +N% | suffix | helmet, jewel | 1-3 | 2-4 | 3-6 | 5-8 | 6-10 | 8-14 | 11-17 | 14-20 | 40 |
| healing | Healing Done +N% | suffix | jewel, shield, weapon | 1 | 1-2 | 2-3 | 3-5 | 4-6 | 5-8 | 7-10 | 9-12 | 20 |
| goblinchance | Treasure Goblin Chance +N% | suffix | helmet, jewel | 6-10 | 10-15 | 14-20 | 18-27 | 22-33 | 28-40 | 35-50 | 45-60 | 100 |
| cdr | Cooldown Reduction +N% | suffix | helmet, jewel, other | 1-2 | 2-3 | 3-4 | 4-5 | 5-6 | 6-8 | 7-9 | 8-10 | 20 |
| manacost | Mana Cost Reduction +N% | suffix | armor, helmet, jewel | 1-2 | 2-3 | 3-4 | 4-6 | 5-7 | 6-9 | 8-11 | 10-13 | 25 |

**How the new ones work** (`item_mods.lua`; all through the same totals and caps as the others):
- *Ailments* (bleed physical, ignite fire, poison earth): on every hit of yours on a monster the chance rolls; a hit
  starts a condition owned by you that deals 40% of the hit over 4 ticks of 1 s (`config.ailment`). Chill slows the monster
  by 30% for 3 s, shock makes it take 15% more damage from everyone for 4 s. Condition ticks never start ailments.
- *Penetration*: the monster's resistance (`MonsterType:getElementList`) counts that many points lower for physical /
  every other damage type, with the maths of the Sunder support (`M.penetrate`, never below 0, immune stays immune).
- *Execute*: a hit that leaves a non-boss monster at or below N% of its health kills it (not bosses, world bosses, rift or
  Omen guardians).
- *Damage over time*: +N% on the damage of conditions you own.
- *Health / mana on hit*: flat, on every landed hit on a monster. *Health regeneration*: N per second, healed every 3 s by
  the equipment check.
- *Block*: N% chance that a physical melee or ranged hit does nothing (spells are not blocked); shields only.
- *Cooldown / mana cost reduction*: the spell side. Through `ChaosSpellEvents` (below) the cost is reduced when the spell is
  checked and the spell's own cooldown shortened as it is set; they add to the Thrift and Quickening supports and stay
  under those supports' caps (30%) and the 1 s cooldown floor.

**Spell events.** `data/lib/chaos_spell_events.lua` is the one `ChaosSpellEvents` table the stubs of engine patch 0008 call
(`onSpellCost`, `onSpellPreCast`, `onSpellCast`, `onSpellCooldown`); `ChaosSpellEvents.set(kind, key, fn)` registers a
handler (kinds `cost`, `precast`, `cast`, `cooldown`) and the table chains them. `data/spells/chaos/_supports.lua` registers
the `supports` handlers: Thrift and Mana Cost Reduction become a real discount, Quickening and Cooldown Reduction cut the
spell cooldown (the group cooldown is left alone). `ChaosSpellEvents.live` turns true at the first event the engine sends;
until then the spell wrapper keeps its fallback (mana back and a rewritten cooldown condition a tick after the cast), so an
engine or `events.xml` without the events works as before. **To switch the events on**, run
`patch_base_events.py DATA --enable-spell-events` after building with patch 0008; `install_all.py` should pass that flag
(it is a one-argument change where it calls `patch_base_events.py`).

**Skipped on purpose**: none of the approved stats were dropped. Not done: mana-shield damage (dodge, block, reflect and the
reduction act on health damage only), and a stat that adds the ailment chance to spells that deal no damage to the target
(the chance needs a damaging hit).

**Loot filter, tooltips, bench, salvage.** The loot filter has a rule "glow on a modifier of tier T+" (settings bits 22-25,
`tier`); the rarity data of a corpse item (`x`) is "Item Level 57; Sword +2 (T3); ..." and `t` is its best tier. The rich
tooltip (`item_tooltip_core.lua`) sends `level`, `maxTier`, `sides = {p, s, max}` and per modifier `tr` (tier), `sd` (side)
and `lo` / `hi` (the range of that tier); the client shows "Item Level 57  (up to T4)", then "Prefixes 2/2" / "Suffixes
1/2" with "T3 Sword +2 [1-3]" lines in a colour per tier (`game_itemtooltip`). The bench shows the same per modifier
(prefixes first, "T3  Sword +2  [1-3]") and the preview of each orb names the tiers the item level allows ("T1-T3").
Salvage yields `floor(base x (1 + 0.5 x item level / 150))` shards plus one per modifier of T6 or better
(`salvage_config.lua`). The guild depot copies the new attributes (`ChaosCrafting.attributeKeys`). The achievement
"Perfection" now asks for an item with 6 modifiers.

**Storage and caps on the character** (`item_mods.lua`). Like `base_rarity.lua`, the totals of the equipped items (in a slot
they fit, `M.equippedItems`) are worked out again when an item is put on or taken off (EventCallback onItemMoved, after
base_rarity), at login, on level up (speed) and by a check every 3 s. They live in memory (`ChaosItemModsCache`), capped per
modifier; nothing is written to storages. `ChaosItemMods.playerBonus(player, key)` is the API (loot.lua reads item and rarity
find with it).

**Drops and the engine's pass.** The engine rolls the rarity of corpse items in `Monster::dropLoot` after every Lua
callback, only for items whose `rarity` attribute is a number. The loot layer forges the item first (step 2b) and stores
the rarity as a text for the length of that pass (`ChaosCrafting.shield`); `ChaosItemMods.afterDrop` gives it back as a
number the next tick, and `ChaosCrafting.unshield` does the same for an item that is moved first (`onItemMoved`, autoloot).
Readers go through `tonumber`. Items that leave a corpse before the pass go through `ChaosLoot.finalizeRarity`
(autoloot, Rarity Autoloot, the pouch).

**Orbs v2: what the follow-up needs.** `ChaosCrafting.addOrb{key, id, name, text, check, apply, preview, keyCheck, keyApply}`
adds an orb (use-with action and bench row follow; add it from a lib file before `crafting.lua` loads); building blocks
`candidates`, `rollAffix`, `rollAffixes`, `writeAffix`, `removeMod`, `rerollValues` (values inside the current tiers),
`rerollTiers` (new tiers by the item level), `forge`, `recreate`, `rewriteDescription`. The follow-up still has to do: the
new orbs themselves (item ids and names in `items.otb` / `items.xml` / the client `Tibia.dat`, installer step, drop weights in
`loot_config.lua`, store and salvage recipes, `shop_config.lua`, the bench rows), renaming the existing orbs, legendary
powers (a place on the item for a fixed power, an attribute and tooltip line), a lock / seal marker per modifier that
`removeMod` and `rerollValues` respect, item quality as a multiplier, and a decision on the Divine Orb (still the stock rarity
reroll).

## Gems and sockets (`data/lib/chaos_gems.lua`, `chaos_gems_config.lua`, `gems.lua`, `tools/install_gems.py`)

Install: `python3 -I server/tools/install_gems.py <server>/data` (idempotent, `--dry-run`; `install_all.py` step
`gems`). It adds 35 items.otb nodes and an items.xml block (the gems and the Orb of Sockets). The client needs the
multi-use flag on the small diamond sprite: `client/tools/sprites/set_multiuse.py <client>/data/things/1098/Tibia.dat`
(its default list now holds client 3028 next to the two orbs). All numbers: `chaos_gems_config.lua`; tests:
`tests/gems_test.lua` (ids, effects, socket counts, socketing, totals and caps, description, the Orb of Sockets and the
other orbs, combining, drop and reward rolls, and `gems.lua` against a mocked engine).

**Items.** Seven gem types in five tiers, Chipped, Flawed, Polished, Flawless and Perfect. Each type and tier has its
own server id, 32001..32035 = 32001 + (type - 1) x 5 + (tier - 1): ruby 32001-05, sapphire 32006-10, emerald 32011-15,
amethyst 32016-20, topaz 32021-25, diamond 32026-30, onyx 32031-35. They are new items.otb nodes, each a copy of the
stock node of its sprite (same group and flags, plus "useable" for use-with). So the client needs no new sprite. Chipped
to Polished use the stock small gem (ruby 3030, sapphire 3029, emerald 3032, amethyst 3033, topaz 9057, diamond 3028,
onyx chip 22193); Flawless and Perfect ruby, sapphire, emerald and amethyst use the small enchanted gems (676, 675, 677,
678). Gems stack per tier, NPCs do not buy them as stock gems, and nothing in the stock data knows the ids. The dark
tile set uses 30484..30557 (client id + 3000), so the two id ranges stay apart. The Orb of Sockets is the unused
stackable use-with rune stone 24692 (named by the installer, like the crafting orbs).

**Sockets on an item**: custom attributes `chaos_sockets` (count) and `chaos_gem1..3` (the gem's server id). The most
sockets is the lower of two limits. By kind: one-handed weapon 2, two-handed weapon 3, armour 3, shield, helmet and
legs 2, boots, amulets, rings and other gear 1. By rarity: none, Common-Rare 1; Epic-Exotic, Mythic-Eternal 2;
Divine-Celestial, Cosmic-Transcendent 3. Sockets come from:
- drops: the Chaos loot layer (`loot.lua` step 2b) rolls them on every gear drop with a rarity. Weights for 0/1/2/3 by
  rarity tier: 80/18/2/0, 60/30/9/1, 45/35/16/4, 35/38/20/7, 25/40/25/10, then capped by the item's maximum. The
  text is written once the engine's rarity pass is done (`ChaosItemMods.afterDrop`).
- the **Orb of Sockets** (eighth orb on the bench, use-with like the others): a new count from at least the number of
  socketed gems up to the item's maximum, weights 50/35/15 for 1/2/3. Gems stay and move to the front. It is refused
  when nothing could change. It drops from the loot layer (8/60/250/1000/1500 per 10000 kills, normal to boss), and the
  store sells it for 25 Chaos Currency.

Sockets and gems survive every orb that remakes an item (Transmutation, Alchemy, Scouring, Chaos, Divine: `C.recreate`
copies them) and the loot layer's rolled copy (`ChaosLoot.finalizeRarity`). **Uniques** have one fixed socket
(`uniqueSockets`) without the attribute: gems can be socketed and taken out, no orb changes the count. The socket shows
in the look text from the moment the unique is made (`ChaosMakeUnique` is wrapped by `gems.lua`).

**The effects**: one per gem, by the group of the item it sits in (weapon; jewellery = amulets and rings; armour =
everything else, shields included). The values below are for Chipped / Flawed / Polished / Flawless / Perfect. The cap is the
most a character gets from all gems.

| gem | in a weapon | in armour | in jewellery |
|---|---|---|---|
| ruby | Fire Damage +2/4/6/9/12% | Max Health +20/45/80/130/200 | Fire Resistance +2/3/4/6/8% |
| sapphire | Ice Damage +2/4/6/9/12% | Max Mana +15/35/60/100/150 | Ice Resistance +2/3/4/6/8% |
| emerald | Earth Damage +2/4/6/9/12% | Movement Speed +1/1/2/2/3% | Earth Resistance +2/3/4/6/8% |
| amethyst | Critical Chance +1/1/2/3/3%, Critical Hit +5..25% | Death Resistance +2/3/4/6/8% | Death Damage +2/4/6/9/12% |
| topaz | Attack Speed +1/2/3/4/5% | Energy Resistance +2/3/4/6/8% | Energy Damage +2/4/6/9/12% |
| diamond | Holy Damage +2/4/6/9/12% | Elemental Resistances +1/1/2/3/4% (fire, ice, earth, death, energy, holy) | Holy Resistance +2/3/4/6/8% |
| onyx | Life Leech Chance +1/3/4/5/7%, Amount +1..5% | Physical Resistance +1/1/2/3/4% | Physical Damage +1/2/3/4/6% |

Caps: element damage 40% each, physical damage 12%, element resistances 30% each, physical resistance 10%, max health
2000, max mana 1500, critical 10% chance / 75% damage, life leech 20% / 15%, movement speed 12% (together with the
Movement Speed modifier, whose cap it shares), attack speed 20% on the weapon (modifier and gems together).
An offensive theme (critical, life leech, attack speed) sits in weapons with the gem's element damage in jewellery;
otherwise the element damage sits in weapons and the theme in armour.

**Applied on the same path as the item modifiers** (`item_mods.lua` works out `ChaosGems.totals` of the equipped items
whenever it works out the modifiers: equip / unequip, login, the 3 s check), handed to `ChaosGems.applyTotals`
(`gems.lua`):
- max health, max mana, critical chance and damage, life leech: one `CONDITION_ATTRIBUTES`, sub id 7240, replaced when
  the values change.
- element and physical damage: onHealthChange on the target, registered by onTargetCombat: hits by the player or their
  summons of that combat type, primary and secondary part.
- resistances: onHealthChange on the player.
- movement speed: added to the Chaos modifier in `item_mods.lua`.
- attack speed: the weapon's own attack interval (`ChaosItemMods.syncAttackSpeed`, modifier and topaz together).

Nothing is stored; the totals live in memory (`ChaosGemsCache`).

**Using gems** (all by "Use with" on the gem, `gems.lua`):
- on gear you carry (backpack or equipped): into the first free socket. The description, the weapon's interval and,
  for equipped gear, the totals are updated at once. An item without sockets says that an Orb of Sockets gives some;
  a full item points at the bench.
- on a gem of the same kind and quality: three become one of the next quality (Perfect does not combine). Different
  gems are refused.
- plain use: the gem's three effects and how to use it.

Every action is logged in `chaos_crafting_log` (the bench's "Recent crafts").

**Taking gems out** (crafting bench, Economy > Crafting Bench: the sockets are listed under the modifiers, extended opcode 232 action
`gem`): **Remove** returns the gem for 2000 / 6000 / 20000 / 60000 / 200000 gold by tier (bank first, then the
backpack); **Shatter** is free and destroys it. The 3-to-1 combining, the removal cost and shattering are the gem sinks.

**Description**: one section at the end, "Sockets (1/2): Flawless Ruby (Fire Damage +9%), empty." After the engine's
text it follows a full stop. `C.rewriteDescription` strips it and writes it again last, so it is never doubled. Items
without a rarity keep their own text (the items.xml description) in front. The loot filter's tooltip data (`x`) gets
"Sockets 1/2: ..." after the modifiers. The bench shows each socket: gem, effect, Remove (cost) and Shatter.

**Drops and rewards** (`chaos_gems_config.lua` `drop` / `rewards`):
- monster kills (`loot.lua` step 3b): chance per 10000 kills 25 / 150 / 500 / 1500 / 3000 (normal / magic / rare /
  legendary / boss), times the loot layer's rate and item find. Tier weights by the monster's level (the killer's when
  it has none): up to 49: 85/15/0/0/0, 149: 60/32/8/0/0, 299: 35/40/20/5/0, 599: 15/35/35/13/2, above: 5/25/40/24/6.
  Legendary monsters have a 25% chance, bosses 40%, that the gem is one tier better. Simulated in the engine (100,000
  kills each): normal 0.25%, magic 1.5%, rare 5%, legendary 15%, boss 30%. At level 700, a boss drops
  959/5020/10129/9140/4777 per tier.
- bounty contracts: a gem at 30% (hunt), 50% (elite), 100% (boss); tier weights by the level band (80/20 for band 1
  up to 0/10/40/38/12 for band 6). The weekly chest has 2 gems of the band's weights.
- rift chest: 1 + 0.2 x tier gems (the fraction is the chance of one more). Tier weights by rift tier: up to 3:
  50/40/10, up to 6: 20/45/30/5, up to 10: 5/30/45/17/3, above: 0/15/45/30/10.
- world boss: every rewarded participant gets 2 + 4 x share gems, weights 0/10/45/35/10 (`W.computeRewards`, so
  offline delivery includes them).

**Tested in game** (test server with the cropped map, client with the patched dat):
- socketing by mouse (right click on the gem, then the item: "Perfect Ruby socketed into magic sword (socket 1): Fire
  Damage +12%.") and by `g_game.useWith`; a full item refused.
- the look text of socketed gear and of a gem.
- equipping armour with two Perfect Rubies and a Perfect Diamond: max health 8487 -> 8887, critical from the armour's
  own rarity plus the amethyst; taking it off: back to 8487.
- 200 fire damage from the player on a Behemoth (through `Combat:execute`): 168 -> 188 with a Perfect Ruby in the
  weapon (+12%); 300 fire damage taken: 250 -> 230 with a Perfect Ruby in the amulet (-8%).
- combining three Chipped Rubies; on the bench, Remove (200k from the bank; refused without the gold) and Shatter.
- the Orb of Sockets on the bench (3 -> 1, the gem kept and moved to the front) and by use-with (an axe with no
  sockets got 1). The Chaos Orb on socketed armour: sockets and gem kept.
- a unique: one socket, a gem socketed, the orb refused.
- gem drops with a raised chance, sockets on rarity drops (5 of 8 gear drops of 100 demons had sockets, written after
  the engine's text), the rift chest and world boss rewards with gems.

The damage test used `Combat:execute` (the spell path, which runs onTargetCombat and so registers the event);
`doTargetCombatHealth` skips onTargetCombat (see "Open decisions" in ROADMAP.md) and showed no bonus until the event was
registered by hand. Not tested in game: a bounty payout and the weekly chest (unit tests of the rolls only), melee hits,
life leech and attack speed from gems in a fight.

## Salvage (`salvage.lua`, `salvage_core.lua`, `salvage_config.lua`, `tools/install_salvage.py`, client `game_crafting`)

Rolled gear you do not want becomes crafting currency instead of NPC gold. A **Salvage** tab on the crafting bench
(Economy > Crafting Bench, then the tab; or Economy > Salvage, or use a Rune Shard) breaks an item with a rarity into **Rune Shards**, with a
small chance of a whole orb, and turns shards into the existing orbs. Every number is in `salvage_config.lua`; the pure
rules are `salvage_core.lua` (tests: `tests/salvage_test.lua`, which also drives `salvage.lua` against a mocked engine).

**Install.** `python3 -I server/tools/install_salvage.py <server>/data [--dry-run]` (idempotent; `install_all.py` step
`salvage`, after `gems`). It adds one items.otb node, the **rune shard** (server id **32051**), a copy of the stock node
of the violet crystal shard (18414, client 16120: stackable, so the client needs no change), and its items.xml entry
between marker comments. Without it the bench says salvage is not installed and refuses. It also guards the stock rarity
remover against locked items (see "The item lock"). No SQL: salvage writes to
`chaos_crafting_log`.

**What can be salvaged.** Gear with a rarity, in the backpack or a bag inside it (never equipped, never the ground),
not locked, not unique, no gem in a socket (take gems out first on the bench: Remove for gold or Shatter; empty sockets
are fine and pay a shard each). Normal items, Rift Keys, stacks and containers are refused. **Uniques are never
salvaged** (`allowUniques = false`): they are chase items with their own drop table and no rarity tier to price them,
and a duplicate is still worth keeping for a season or a trade.

**Yield** (deterministic, so the preview is exact):
- shards = floor(base x (1 + 0.5 x position of the item level in its rarity's window)) + 1 per Chaos modifier + 1 per
  empty socket. The engine rolls rarity r with item level 10r-9..10r, so the top of the window gives up to +50%.
- base by rarity (Common .. Transcendent): 1, 1, 2, 2, 3, 3, 4, 5, 6, 7, 8, 10, 12, 14, 18 (a Transcendent at the top
  of its window: 27).
- whole orb on top, per item: 0.5, 0.5, 0.75, 0.75, 1, 1, 1.5, 1.5, 2, 2, 2.5, 3, 3.5, 4, 5%; which orb by weight:
  Transmutation 35, Chaos 25, Scouring 12, Alchemy 10, Annulment 8, Divine 5, Sockets 3, Exalted 2.

**Shards into orbs** (one click makes 1, Ctrl+click up to 10): Transmutation 12, Chaos 25, Scouring 30, Alchemy 40,
Annulment 50, Divine 60, Sockets 60, Exalted 100 shards, about 2.5 shards per Chaos Coin of the store price (5, 10, 12,
15, 20, 25, 25, 40).

**Why these numbers.** With the stock rarity roll (70% of gear drops pass, then each rarity in order with its own chance)
an average rolled drop gives about 2.8 shards before modifiers and sockets (about 3.3 with them) and a 0.9% orb chance:
roughly a tenth of a Chaos Orb. Rolled drops come a few times more often than orbs from the loot layer (a normal monster
drops an orb on about 1.4% of kills), so salvaging everything adds a modest share to a player's orb income instead of
replacing the orb drops, and it competes with selling the item: salvage is a sink for unwanted rarity gear, not a mint.
`tests/salvage_test.lua` checks the average (2.2-3.5 shards, about 1% orbs) and that a Chaos Orb takes at least 8 rolled
items.

**Salvage all.** Choose a container (the backpack or one bag in it, its direct contents) and the highest rarity; the bench
shows how many items it takes, the shards, the summed orb chance and what it skips (locked, unique, with gems, above the
rarity, over the limit) and marks the items in the gear grid. The button asks for a confirmation. At most **50 items per
action** (`batchCap`); the rest is listed as over the limit for the next one. The confirmation carries a signature of the
previewed items (paths and item signatures); when anything changed in between the server refuses ("check the list and
confirm again").

**The item lock.** The bench's Lock / Unlock button (gear and Rift Keys in the backpack) sets the custom attribute
`chaos_locked` = 1. **Locked items cannot be sold nor melted.** A locked item is refused by salvage, skipped by "salvage
all", and never sold by the **Auto Seller**, even with Economy > Auto Seller (`autosell.lua` reads the attribute,
`ChaosShopServices.sellBlocked` returns "locked"; "Auto seller: kept a locked item."). The look text says "It is locked:
it cannot be sold, salvaged or thrown away." (EventCallback onLook, index 120); the gear grid shows locked items dimmed,
the rich tooltips (engine patch 0003, key 3) show "Locked". The lock survives the orbs that make a new copy
(Transmutation, Alchemy, Scouring, Chaos, Divine: `C.recreate` calls `ChaosSalvage.copyLock`). Orbs and gems still work
on a locked item: the lock protects from destruction and selling, not from crafting.

Engine patch `src-patches/0009-locked-items-never-sold.patch` closes the paths the scripts cannot see (an item is
"locked" when `chaos_locked` is non-zero; a container with a locked item anywhere inside counts as locked too, so a bag
is never sold or trashed with a locked item in it):

| Path | With 0009 |
|---|---|
| NPC trade window (every NPC with `module_shop`, Yasir, the Wandering Merchant, NPCs with their own `onSell`) | The sale list does not count locked items (a locked-only item is not offered). A sale only locked copies could fill is refused by the engine before the NPC script runs: "Locked items cannot be sold." With one locked and one unlocked copy, selling 1 takes the unlocked one, selling 2 is refused. |
| `player:removeItem(id, n)` (NPC selling, quest and NPC turn-ins, exchanges, any script removing by id) | Skips locked items. Fifth argument `includeLocked = true` takes them too (only the staff panel's "Remove item" uses it). |
| `player:getItemCount(id)` (turn-in checks) | Does not count locked items; third argument `includeLocked = true` counts them. A turn-in with only locked copies fails as if the player had none. |
| Market (sell offer, accepting a buy offer) | Never takes a locked item (`Item::hasMarketAttributes()`; any custom attribute already kept rolled items off the market). |
| Trash holders (trash cans, lava, ...) | A locked item cannot be moved onto one ("This item cannot be moved there."), and a trash holder never destroys one. |
| The stock "Upgrade and Rarity Remover" (29623, makes a plain copy) | Refused: "This item is locked." (a guard added to `data/scripts/customs/upgrade/upgrade_slot_item.lua` by `tools/install_salvage.py`; Lua, works without the patch). |

Unchanged on purpose: scripts that act on one specific item object (`item:remove()`: using a Rift Key or a scroll,
the guild depot and the stash, which keep the item; salvage itself checks the lock), player-to-player trade and mail
(the item and its lock move to the other character), the season join's inventory wipe (confirmed by the player, "this
cannot be undone") and staff tools. Without the patch the NPC trade window and turn-ins still take locked items. The lock
never stops crafting.

**Protocol** (extended opcode 232, `ChaosOpcodes.crafting`, new actions handed from `crafting.lua` to `salvage.lua`):
client -> server `salvage {path, id, sig}`, `lock {path, id, on}`, `salvageScope {bag, maxRarity, mode}`,
`salvageBatch {bag, maxRarity, sig}`, `combine {key, count}`; the bench state gains `salvage` (shards, recipes, bags,
rarity names, the batch preview while the tab is open, the tab) and `locked` / `salvage` (preview) on the items. Answers
are the bench's `result` (orb `"salvage"`) and `state`.

**Server checks.** The item is found by its backpack path plus id and signature (moved or changed -> "put it on the bench
again"); `inBackpack` again before anything is removed; all rules again on every item of a batch; 300 ms between single
actions and locks, 2 s between batches, 300 ms between combines; shards and orbs go to the backpack, else the inbox (a
message says so), else the floor. **Log**: every salvaged item is one row of `chaos_crafting_log` (orb `Salvage`, item
name, "Rare (level 26): 2 rune shards [+ 1 Chaos Orb]"; a batch writes its rows in one INSERT), combines are `Shards`
rows ("75 rune shards -> 3x Chaos Orb"), lock changes `Lock` rows; the bench's Recent crafts shows them.

**Tested in game** (test server, client with the new tab): a single Common salvaged from the bench (1 shard, log row);
"salvage all" in the backpack up to Uncommon with the cap lowered to 5 (5 taken, 6 over the limit, the socketed and the
higher ones skipped), then a bag up to Legendary (4 Commons and a Rare: 6 shards; the locked Uncommon skipped); the
confirmation box; Transmutation (12 shards) and Ctrl+click Chaos (3 orbs for 75 shards); Lock / Unlock from the bench,
the refusal of a locked item, the look text; a monster kill with a locked and an unlocked rarity fire sword on the auto
sell list with the rarity opt-in: the unlocked one sold (4000 gold to the bank), the locked one kept; a Chaos Orb on a
locked sword (new copy, still locked). Unit tests: yields, orb roll, checks, the lock, batch cap and skips, signature,
combine, the economy average, and `salvage.lua` single / batch / lock / combine / full backpack / look text against
mocks; `tests/shop_services_test.lua`: the auto seller keeps a locked item.

## Item attributes in packets and rich tooltips (`src-patches/0003-item-custom-attributes.patch`, `item_tooltip.lua`, `item_tooltip_core.lua`, client `game_itemrarity`, `game_itemtooltip`)

**Item custom attributes in item packets (engine patch 0003).** Our client already parses per-item custom attributes
when the feature `GameItemCustomAttributes` (126) is on: after each item (after the animation phase byte) it reads a
u16 count, then per entry a u16 key and a u64 value, and stores them on the item (`item:getCustomAttribute(key)`).
The feature is negotiated, not part of the client's 10.98 profile: our client sends, after `OTCv8` and its version in
the login packet, the strings `OTCv8TierByte` and `A`; only for such a connection does the server add feature 126 to
its feature packet (0x43, sent before any item) and write the attributes. Other OTC-family clients keep the plain item
format, and our client against a server without the patch never enables the feature (rarity falls back to the
description tag). The client turns the feature off at every logout (`game_itemrarity`), so a later login to another
server starts without it.

Every item the client reads with its item parser goes through `ProtocolGame::AddItem`: map tiles (also the login map
description), inventory, open containers (and the last item of a removed container slot), trade windows, text windows.
The market sends item ids only. A plain item costs 2 bytes (count 0); an item with any of the attributes below gets
its keys, 10 bytes each (a rolled rare with sockets: 52 bytes). The Lua `NetworkMessage:addItem` is unchanged (no
script uses it; a script that sends items by hand to our client would have to add the count itself).

| key | name | source (custom attribute) | value |
|---|---|---|---|
| 1 | rarity | `rarity` (else the item type's) | 1..15 |
| 2 | level | `combatPowerLevel` | item level |
| 3 | locked | `chaos_locked` | 1 (the item lock of salvage.lua) |
| 4 | unique | `chaos_unique` present | 1 |
| 5 | sockets | `chaos_sockets` | socket count (a unique's fixed socket is not stored, so 0) |
| 6 | id | `chaos_iid` | per-item id |
| 7 | version | (computed) | 32-bit hash, never 0 |

The keys are defined three times with the same numbers: `ChaosItemAttrKey` in the engine's `const.h` (patch 0003),
`Chaos.itemAttr` in `chaos_constants.lua`, `ChaosItemAttr` in the client (`game_itemrarity/itemrarity.lua`);
`tests/item_tooltip_test.lua` reads all three and fails when they differ. Keys 6 and 7 are sent only with at least one
of keys 1-5. Key 6: the engine has no per-item id (the `getRealUID` of the base server is never set), so the first
time an item with any of keys 1-5 is sent it gets the custom attribute `chaos_iid` = (unix time of the block) << 20 |
counter, saved with the item; a new block starts every 2^20 ids and at every start, so ids stay unique across
restarts and below 2^53 (exact as a Lua number). A clone of an item (`Item::clone`) keeps the id; the tooltip request
checks the item at the position anyway. Key 7 hashes the item id, every custom attribute (order-independent), the
attack / defense / extra defense / armour / hit chance / range / attack speed attributes and the name and description:
it changes whenever an orb, a gem or an upgrade changes the item.

The engine sends an item again only when it moves or its id or count changes, so a script that changes attributes
calls the new `item:sendUpdate()` (inventory slot, container page of every player who has it open, or the tile's
spectators; touches nothing on the item, unlike a transform to the same id, which would reset durations).
`ChaosItemMods.sendUpdate(item)` wraps it (no-op without the patch); `ChaosCrafting.rewriteDescription` and
`ChaosGems.writeDescription` call it, and every orb, socket and gem change ends there. `item:getClientAttributes()`
returns `{[key] = value}` as the client gets them (the tooltip uses keys 6 and 7 for its cache key).

Build: apply 0001, 0002 and 0003 in the server source root and rebuild everything (0003 adds members to
`ProtocolGame`, so objects built before it must not be linked with it). Built on the test server with a fresh CMake
build of the base source plus the three patches.

**Rich tooltips (extended opcode 242).** Hovering an item in the inventory or an open container asks the server for
its tooltip; holding Ctrl adds the equipped item(s) worn the same way (both hands for weapons and shields, the same kind
only: a weapon is not compared with a shield) as plates next to it, and the hovered tooltip lists the differences per
number in green (better) or red (worse); a shorter attack interval counts as better.

- client -> server `get {items = [{pos = {x, y, z, s}, iid}]}`, at most 3 items; `iid` is the decimal string of key 6
  (JSON numbers lose digits past 14).
- server -> client `tips {items = [{pos, iid, tip} | {pos, iid, gone = true}]}`.
- Positions: `{0xFFFF, slot, 0}` inventory (slots 1-10), `{0xFFFF, 0x40 + container id, slot}` a container the engine
  has open for this player (`player:getContainerById`, slot on the current page), or a map position with the stack
  position `s` on the player's floor, at most 8 x 6 tiles away and visible (`player:canSee`); the client asks only
  about inventory and containers. Anything else, or an item whose `chaos_iid` differs from `iid`, answers `gone`.
- Budget: a token bucket per player, 12 tokens, 6 per second, one per item; a request over it is dropped (the client
  asks again on the next hover).
- The tooltip (`ChaosItemTooltip.build`, pure, `tests/item_tooltip_test.lua`): name, client id, count, kind and slot,
  rarity name, tier (1-5) and item level, base numbers (attack, defense, extra defense, armour, hit chance, range,
  attack interval, element, and the item type's own skills, protections, max health / mana, magic level, speed),
  every modifier as `ChaosCrafting.readMods` lists it with its text, group and roll range (`absorbRange` /
  `elementRange` of the rarity for the engine's modifiers, `ChaosItemMods.range` for the Chaos modifiers, none for
  uniques), sockets with each gem's effect in this item, unique and set (pieces of `ChaosSets` equipped), requirements
  (level, the unique's level, magic level, vocations), weight, flavour text (a unique's text, else the item type's; a
  rolled item's description is its modifiers and is not repeated), the lock, a flat list of numbers for the compare and
  the compare slots.
- Client cache: by `<id>:<version>` (keys 6 and 7), so an orb that changes an item (new version through
  `sendUpdate`) makes the next hover ask again; items without the keys are cached for 30 s under position, id and count.

**Rarity frames.** `game_itemrarity` reads the rarity from key 1 (unique: key 4) and draws a frame in the rarity colour
(unique orange) on container and inventory slots; without the feature it falls back to the `[NAME]` tag of the
description. The loot filter keeps its glow and dim and leaves the frame to `game_itemrarity` where it drew one.

**Tested in game** (srv16 built from the base source with 0001-0003, client with the overlay): the feature negotiated at
login and every inventory, container and ground item carrying its keys (a rolled Chaos sword: rarity 8, level 73,
sockets 2, id, version); frames from the attribute in the backpack (Chaos red, Divine, unique orange) and on the
equipped unique; tooltips of a rolled rare weapon (modifiers with ranges, Chaos modifiers, a Flawless Ruby), of a
unique (Soulreaper) and of Divine armour with two gems; Ctrl compare of the rare sword against the equipped Soulreaper
with green and red rows; an Orb of Annulment on the sword: the version changed at once and the next hover showed one
modifier less; the budget (12 of 20 requests at once answered), unopened container, slot 11, far map position and a
wrong `iid` all answered `gone`; the same client against the engine without the patch: feature off, no errors from it.
Screenshots: scratchpad `tooltips/`. Not tested: two players watching the same container, trade windows.

## Seasons (`season.lua`, `season_core.lua`, `season_config.lua`, `sql/chaos_season.sql`, `tools/patch_season_events.py`)

Roadmap item 12, phase 1: fresh-start season characters with their own ladder, season-only uniques and an account-wide
cosmetic reward track that is kept after the season. Client `game_season` (Adventure > Season in the top menu),
extended opcode 246 (`ChaosOpcodes.season`). Every rule and number is in `season_config.lua`.

**Install.** Run `sql/chaos_season.sql` (4 tables) and `python3 -I server/tools/patch_season_events.py <server>/data`
(idempotent, `--dry-run`). The tool enables `onTradeRequest` / `onTradeAccept` in `data/events/events.xml` (shipped
disabled, so no script could see a trade) and makes `Player:onMoveItem` (`data/events/scripts/player.lua`) ask
`ChaosSeason.onMoveItem` first: a script callback cannot refuse a move reliably, because the base dispatcher keeps only
the return value of the last `onMoveItem` callback. Without the tool the server logs a warning at startup and only the
party, bank and unique rules apply.

**How a character joins (and why this way).** Characters are created on the website: the base server has no account
manager, no in-game creation and the client has no creation screen (the base ships `ADD_DEPOT_BOXES_NEW_PLAYERS.txt`,
a snippet for the website's `users.php`). A creation option would need website work, so a fresh character opts in in
game: Adventure > Season, Join (or Join in the window), then the Season window's Join button (or the window's confirmation) within 60 s.
Allowed while a season runs for a character of level 7 or lower (`join.maxLevel`; level 8 comes within minutes) that never
joined a season, has an empty depot, inbox and store inbox, is not in a party and owns no house. Joining destroys every
carried item, empties the bank balance, the Chaos bank stars and the supply stash (so nothing a standard character handed
over before the join comes along), then gives the new-player kit again when the character had received it. The flag is a
row in `chaos_season_players`; the look text says "He is a Season of Ash character [S1]." (after the season: "a veteran
of ...").

**Season record.** `seasons = {{id, name, tag, start, finish, hour, modifier}}`: dates as YYYYMMDD (at `hour`, server
time) or unix time. The modifier is shown in the window; `expMult` multiplies the monster experience of that season's
characters (an `onGainExperience` callback, so it needs `patch_base_events.py` like every Chaos experience bonus).
Gods (account type god): `/season start [id]` starts the next season now, `/season end` ends the running one now (both
stored as `server_config` rows `chaos_season_<id>_start|_end`, which win over the config dates), `/season status`.

**Isolation.** While a season runs, a character's realm is its season id (standard characters: 0). Different realms
cannot exchange anything; gamemasters and up (`isolation.exemptGroup`) are never blocked.

| Way | Rule | Hook |
|---|---|---|
| Trade window | refused between realms (also the house trade of `!sellhouse`, which skips the request event) | EventCallback `onTradeRequest` / `onTradeAccept` |
| Items on the ground | an item a player drops is tagged with the dropper's realm (custom attribute `chaos_realm`, pickupable items only); another realm cannot move it or anything inside it. Own items lose the tag when they reach the inventory (they stack again) | `onItemMoved`, `ChaosSeason.onMoveItem` |
| Corpses | a monster corpse gets the realm of its owner (the engine's most-damage player), a player corpse the realm of the dead character: another realm cannot loot it | `onDropLoot`, `onDeath` |
| Mail | a parcel or letter dropped on a mailbox is refused when the receiver (first line of the label / letter) is of another realm | `ChaosSeason.onMoveItem` |
| Houses | taking items from, or putting items into, a house owned by another realm is refused | `ChaosSeason.onMoveItem` |
| Party | **not allowed** between realms (the joining character and the leader are told). Chosen over "allowed without shared loot and experience": the party is also what the bounty board, the dungeons and 2v2 arena use, so one rule covers all of them | EventCallback `onJoin` |
| Chaos bank transfer | refused between realms | `bank.lua` asks `ChaosSeason.transferBlocked` |
| PvP: open world, arena, guild siege | **allowed** between realms. Nothing changes hands: player corpses keep the dead character's realm, arena and siege rewards come from the server, and 2v2 arena teams are parties (same realm). Season characters can be in guilds (a guild shares no items) | - |
| Depot | per character, nothing to share | - |

Not blocked (open): **the market** (the market item's action is the engine's `function="market"`; Lua cannot refuse the
market window or an offer, it needs an engine change or the market switched off), **the NPC bank transfer** of the base
NPC scripts, and the account-wide **store coins** (season characters can buy orbs and supplies in the store). Items on
the ground before a season starts are untagged (free).

**Ladder.** While a season runs the leaderboard window shows a "[S1] only" toggle (`leaderboard.lua` adds
`ChaosSeason.leaderboardMeta` to its meta and passes `season` to `ChaosSeason.sendBoard`): the class ladder then lists
only that season's characters (players joined with `chaos_season_players`, cached 120 s), and the weekly boards (World
Boss, Bounty Hunter, Rifts, ...) only their scores. The normal view still lists everybody, and titles are won on the
normal boards only.

**Season uniques.** A `ChaosUniqueItems` entry with `season = <id>` (`data/lib/chaos_unique_items.lua`) drops for nobody
before that season, only for that season's characters during it, and for everybody after it. `loot.lua` passes the
corpse owner to `rollUniques`; rolls without an owner (rifts, treasure goblins, the goblin hoard) leave season uniques
out while the season runs. Season 1: Widowmaker, Riftcaller, Hellspite Arbalest, Mortis Cowl (existing uniques, no new
art; `chaos_unique_specs.lua` is unchanged).

**Reward track.** Milestones of a season character (`track`): level 100 (title Ashborn), 300 (Death Herald outfit),
600 (its addons), 1000 (Doom Skull mount), 25 bounty contracts (Revenant outfit), 5 world bosses (Darklight Devourer
mount), and a tier 10 rift (title Ashen Riftwalker; listed only when `ChaosRift` exists). Season stats come from a wrapper
around `ChaosLeaderboard.record` (`stats`: bounty and goblin add, rift keeps the best, world boss counts), so the bounty,
rift, world boss and goblin scripts needed no change. A milestone unlocks the reward for the whole account forever
(`chaos_season_rewards`): every online character of the account gets outfits and mounts at once, every other character
(also ones created later) at its next login; titles show in the look text ("He holds the season title Ashborn (Season of
Ash)."). Every look type and mount id exists in the base server's XML.

**End of season.** When the finish has passed (once-a-minute check, and at login) or after `/season end`, every
unmigrated character of that season becomes a standard character: `migrated_at` is set once (`WHERE migrated_at = 0`,
so running it again does nothing) and logged in `chaos_season_log` and the console. Level, skills, items, passive tree
and season uniques stay; the realm rule already treats a character of an ended season as standard, so trade works at
once even before the row is updated.

**Tests.** `tests/season_test.lua` (LuaJIT and Lua 5.3): the date math and overrides, join eligibility, the trade /
move / party / mail decisions, realms and item tags, milestone detection and the track view, the migration decisions,
the season unique rule and the look text.

Verified on the test server with two clients (a season character and a standard one): `/season start` and the
broadcast, the window (time left, modifier, track, Join), the join confirmation and the wipe (backpack, gold, bank
5000 -> 0), trade refused between realms and allowed within the season, a standard drop that the season character could
neither push nor pick up (the standard one could), the season character's drop refused to the standard one and untagged
when picked up again, a standard kill's corpse refused to the season character, a parcel to a standard character refused
and to a season character delivered, party refused between realms and allowed within, level 301 -> two milestones,
the outfit, the look text with the title, 25 bounty records -> Revenant outfit, the reward delivered at login to another
character of the account, the "[S1] only" view of the Bounty Hunter board and the class ladder, the bank transfer and
unique rules (300 boss rolls: 23 season uniques for the season character, 0 for the standard one and without an owner),
`/season end` migrating both characters (online and offline) once, a second `/season end` migrating none, and trade
allowed afterwards. Not verified in game: the experience modifier, the house rules, a player corpse in PvP, the confirm
box closing by itself after a join from the chat, a natural season start / end from the dates.

## Guild siege (`siege.lua`, `siege_core.lua`, `siege_config.lua`, `sql/chaos_siege.sql`)

A weekly scheduled war between guilds for the Chaos Obelisk. Client: `game_siege` (HUD + sign-up window, extended
opcode 233, Adventure > Guild Siege in the top menu). Every number below is in `siege_config.lua`.

**Install.** Run `sql/chaos_siege.sql` (tables `chaos_siege_signups`, `chaos_siege_results`) and
`python3 -I server/tools/patch_base_events.py <server>/data` (its third patch puts the siege rules in front of the
base server's `Creature:onTargetCombat`, see "PvP inside"). The Chaos spells ask the siege through
`ChaosSiege.canAttack` in `data/spells/chaos/_common.lua` (reinstall the spells with `register_spells.py`).

**Schedule.** Saturday 20:00 server time (`weekday`, `hour`, `minute`). Broadcasts 60, 15, 5 and 1 minutes before (the
first and the last also as a toast), with the guilds signed up so far. The login-screen calendar and Adventure > Events show a
"Guild Siege" day: siege.lua adds that entry to `Chaos.events.list` when it loads (no edit of the calendar config).

**Sign-ups.** Adventure > Guild Siege / Adventure > Guild Siege (or the window's buttons) by the guild leader or a vice-leader
(`signupRank` 2); the guild needs `minMembers` (3) members in `guild_membership`. Sign-ups close `signupCloseMinutes`
(5) before the start and while a siege runs. Up to `perBracket` (4) guilds share an arena; more guilds run as parallel
brackets (`maxBrackets` 3, arenas side by side, sizes differ by at most one, never below `minGuilds`); beyond 12 the
latest sign-ups wait (first come). Fewer than `minGuilds` (2) at the start: the siege is cancelled and the sign-ups
dropped. Adventure > Guild Siege shows the status and opens the window (next siege, countdown, sign-ups, your guild, champions, rules).

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

**Commands.** Adventure > Guild Siege (status + window), Adventure > Guild Siege, Adventure > Guild Siege, `Adventure > Guild Siege status`. Staff (`/siege`, group with
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

## Guild levels and guild halls (`guild.lua`, `guild_hall.lua`, `guild_core.lua`, `guild_config.lua`, `sql/chaos_guild.sql`)

Guilds earn guild XP (GXP) from what their members already do, level from 1 to 20, and unlock small perks and a
guild hall: a guild-owned instance built at runtime. Client `game_guild` (Social > Guild in the top menu),
extended opcode 252 (`ChaosOpcodes.guild`). Every number is in `guild_config.lua`; the pure rules (curve, caps, perks,
upgrade prerequisites and costs, rent, slots and layout, depot rules, attribute encoding, the weekly board) are in
`guild_core.lua` and tested by `tests/guild_test.lua`. Guilds themselves (founding, members, ranks) stay the base
server's (`guilds`, `guild_ranks`, `guild_membership`; made on the website); rank level 3 = leader, 2 = vice-leader.

**Install.** Run `sql/chaos_guild.sql` (7 tables; `guild.lua` also creates them at startup when missing). Experience
share and the experience perk need the `patch_base_events.py` experience dispatch, like every Chaos experience bonus.

**Guild XP.**

| Source | GXP | Hook |
|---|---|---|
| Experience from monsters | 1% of it counted in "level units": a full level's worth of experience at the member's level = 10 GXP; at most 60 a member a day | own `onGainExperience` callback, kept in memory and written every minute and at logout |
| Bounty contract | 15 | a wrapper around `ChaosLeaderboard.record` (as seasons does), so no other script changes |
| Rift sealed | 10 + 2 x tier (max 40) | same |
| World boss participation | 40 | same (`worldboss`, one call per rewarded participant) |
| Invasion defended | 20 | same (`defender`, invasion.lua; any later `invasion*` board too) |
| Guild siege, per participant | 10 + 2% of the points (max 40) | same (`siege`) |
| Treasure goblin | 5 | same (`goblin`) |
| Guild siege result | 500 to the bracket winner, 150 to every other guild | new rows of `chaos_siege_results`, once a minute (earlier sieges are skipped on the first run) |

A member gives at most 400 GXP a day from all sources (`dailyCapAll`); siege results are not capped. The wrappers stack
safely with the season wrapper (a guard runs the guild part once per call, and seasons is told its wrapper is still in
place). Curve: level L -> L+1 needs round(300 x L^1.5) GXP: 300, 850, 1,560 ... 24,850; 5,110 to level 5, 33,320 to 10,
201,410 to 20 (a ten-member guild hunting daily reaches level 5 in about a week and 20 in months).

**Perks** (for online members, while they are in the guild; totals capped by `caps`):

| Level | Perk | Level | Perk |
|---|---|---|---|
| 2 | +1% experience | 10 | +1% experience, the guild aura (aura 4, Fireflies) |
| 3 | a guild hall scroll every day (`Social > Guild scroll`) | 12 | respec 5% cheaper |
| 4 | +2% loot | 13 | +20 depot slots |
| 5 | a guild hall can be bought | 14 | +1% experience |
| 6 | +1% experience | 15 | +1% loot |
| 7 | respec 10% cheaper | 17 | respec 5% cheaper |
| 8 | +20 depot slots | 18 | +20 depot slots |
| 9 | +2% loot | 20 | +1% experience |

At 20: +5% experience, +5% loot, respec -20%, +60 depot slots. Experience: monsters only, multiplied after the other
bonuses that ran before it. Loot: wraps `ChaosLootConfig.rateMult` for the corpse owner (the Chaos loot layer's extra
rolls and currency). Respec: wraps `ChaosRespec.fullCost` / `nodeCost` (tree, Paragon and single-node refunds). The
aura is given with `addAura` and taken back when the member leaves the guild (not when it was bought in the store).
A level-up is told to every online member with the new perks, and logged. API: `ChaosGuild.levelOf(guildId)` (for
the name plates' level badge), `ChaosGuild.perksOf(guildId)`, `ChaosGuild.addXp(guildId, playerId, source, amount)`.

**Guild bank.** `Social > Guild deposit <gold>` (or the window): any member, at least 1,000, from carried gold then the bank
balance. `Social > Guild withdraw <gold>`: the leader only, to the leader's bank balance. The hall, its upgrades and its rent
are paid from it. Money safety: every change of the guild bank is one conditional `UPDATE ... WHERE bank >= x` checked
with `ROW_COUNT()` (never read-then-write); a purchase pays first and then writes its row with a conditional statement
(`INSERT IGNORE` on the guild's key, `UPDATE ... WHERE tier = n`, `UPDATE ... WHERE paid_until = old`), and refunds and
logs when that write changed nothing. Money requests are limited to one a second per player (`ChaosRateLimit`), the
window requests that read the database to one per 300 ms. Season characters cannot use the guild bank or depot while
their season runs. Staff log: `chaos_guild_log` (deposit, withdraw, hall, upgrade, rent, put, take, refund, level,
staff) and a console line for every gold movement; `/guild log <guild>` shows the last 20.

**The guild hall.** The leader buys it at guild level 5 for 5,000,000 gold, from the guild bank or with their own gold.
One slot per guild (`chaos_guild_hall.slot`), in a grid of 64 slots (8 columns, 40 tiles apart) from 9216, 9216, 7,
where the real map has no tiles (OTBM scan: no tile area between x/y 3000 and 16000 except two at x 1790; other runtime
areas: tower 2000+, tutorial 4600+, world boss 5000+, siege 5100+, PvP arena 6000+, rifts 8192-8447). A slot is a
21 x 15 floor with walls, built with `Game.createTile` the first time it is needed (a slot with a map tile in its
footprint is skipped). The engine cannot remove tiles, so slots stay built and are reused: the fixtures are placed
again whenever the owner or the active upgrades change. Entry: a forcefield next to every temple (`portalOffsets`, or
`portalPositions`; placed at startup and checked once a minute): members of a guild that owns a hall go to their hall,
everyone else is refused ("Only guild members may enter a guild hall."). The exit forcefield leads to the temple
(`exitPosition` overrides it). Players cannot attack players inside a hall (an `onTargetCombat` callback), a player who
is not a member of the hall's guild (left the guild, logged in inside) is sent to the temple within a minute.

| Upgrade | Guild level | Gold | Needs | What it does |
|---|---|---|---|---|
| Teleport Hub | 6 | 2,000,000 | | 4 forcefields along the north wall to the hunting areas of `hall.hub` (lands on the nearest free walkable tile within 3) |
| Training Room | 7 | 1,500,000 | | 3 exercise dummies of the base server (27751/27752; the store's exercise weapons work on them) and a damage dummy monster (the first of `dummyMonsters` the server knows) |
| Crafting Bench | 8 | 1,000,000 | | an anvil that opens the crafting window (`crafting.lua`) |
| Guild Depot | 9 | 2,500,000 | | a large trunk shared by the members, see below |
| Trophy Room | 10 | 1,000,000 | Teleport Hub | statues whose look text shows siege wins, world bosses, rift record, bounties, invasions, level and top contributors |
| Decoration 1 / 2 / 3 | 12 / 16 / 20 | 1.5M / 3M / 6M | Trophy Room | floor and walls: white marble, obsidian (black marble), gilded stone |

**Rent.** 300,000 gold a week + 100,000 per upgrade tier, paid from the guild bank: at purchase for the first week,
then automatically when due (once a minute check). If the bank is short the hall has 24 hours of grace (members are
reminded once an hour); after that the upgrades lock: their fixtures disappear (hub portals, dummies, bench, trunk,
trophies, decoration) and the depot is closed, nothing is deleted. Paying (Social > Guild, the window's Pay rent, or the
automatic try after a deposit) unlocks everything at once; a locked hall starts a new week from the payment (the locked
weeks are not charged), a hall in its grace time keeps its period.

**Guild depot.** Drop an item on the trunk inside your own hall: it is stored in `chaos_guild_depot` (item id, count and
its attributes as text: description, name, text, charges, attack/defense/armor and the other standard attributes, the
rarity system's custom attributes `rarity`, `combatPowerLevel`, every `rarity_*` modifier key of `ChaosCrafting`, uniques,
rift keys) and removed. Take items back in the Guild window (in the hall). Containers are refused; 30 entries + the
depot perks; members take at most 20 entries a day (leader and vice-leaders without limit). A take deletes the row with
one conditional `DELETE` first and only then creates the item, so double clicks or repeated requests give one item; no
room in the backpack -> the inbox; no room there either -> the row is put back. The window shows the depot's put/take
log. Limitation: a custom attribute that is not in that list is not copied (the engine has no call to list them).

**Weekly top guilds.** The window's Top Guilds tab ranks guilds by the GXP earned in the week (Monday 06:00, like the
leaderboards; `chaos_guild_contrib` rows with the week key), then level; it also names last week's top guild. The
Members tab shows every member's GXP this week and in total.

**Commands.** Social > Guild (window), `Social > Guild deposit|withdraw <gold>` (`5k`, `2.5m` work), `Social > Guild scroll`,
`Social > Guild hall buy [bank|self]`, `Social > Guild upgrade <hub|training|crafting|depot|trophy|decor>`, Social > Guild,
`Social > Guild take <id>`, `Social > Guild info`. Staff (`/guild`, groups with access): `xp <guild>, <n>`, `bank <guild>, <+-n>`,
`info <guild>`, `log <guild>`, `rent <guild>, due|lock|paid` (test helper: moves the paid-until time), `hall <guild>`.

**Client** (`game_guild`, JSON on 252): server -> client `state` {guild, perks, members, hall, depot, log, top},
`none` (not in a guild), `message`, `openModule` (the bench); client -> server `open`, `refresh`, `deposit`,
`withdraw`, `buyHall`, `upgrade`, `payRent`, `take`, `scroll`. Tabs: Overview (perks, scroll, guild bank, log),
Members, Guild Hall (rent and upgrades, buttons for the leader and vice-leaders), Depot, Top Guilds.

**Tested in game** (test server, cropped map, guild Iron Wolves with a leader and a member on two accounts, one client):
guild XP from kills (the experience share, 60 a day cap reached) and from a completed bounty contract (+15 through the
leaderboard hook); a level-up to 10 (staff XP on top) with the broadcast and the aura; the experience perk (a Dragon kill
18,900 -> 19,467 experience at +3%); the loot perk (rateMult x1.04); deposit and withdraw (a triple-clicked withdraw
paid once); buying the hall from the guild bank (a triple click bought it once); entering through the portal and
leaving through the exit; a non-member refused at the portal and sent out when placed inside; the Teleport Hub and the
Guild Depot bought from the window; the hub portal; a stack of Chaos Orbs and a Mythic dragon scale mail put on the trunk
and taken back with every modifier (three take requests in a row gave one item); a member taking an item; the depot
log; rent paid from the window; rent past the grace time with an empty bank locking the upgrades (fixtures gone, depot
closed, window red) and paying it unlocking them; the training room, bench (opens the crafting window), trophies and
decoration tiers 1 and 3 (looked at with the upgrades set in memory); the guild hall scroll (refused in combat, a
second claim the same day refused, used -> the hall); the window and its tabs. Not verified in game: the respec
discount (the test server has no respec.lua), rift / world boss / invasion / siege XP (unit-tested amounts; the hook
is the one the bounty used), the siege result poll (no `chaos_siege_results` table on the test server), the real map's
temples and hunting-area positions (the cropped map has neither: the test server's config pointed the portal, the exit
and one hub destination at its tiles), several guilds' halls at once, a restart with a hall in use (the tiles are gone
after a restart; the first entry builds them again).

## Arena (`arena.lua`, `arena_core.lua`, `arena_config.lua`, client `game_arena`)

Ranked PvP: 1v1 and 2v2, an Elo rating per mode, matches in arena instances built at runtime. Settings are in
`arena_config.lua`, the pure part (ratings, matchmaking, level rule, death catch, timeout) in `arena_core.lua`
(`tests/arena_test.lua`), the runtime in `arena.lua` (`tests/arena_flow_test.lua` runs it on a mocked engine: 2v2,
parallel slots, disconnect, timeout).

**Queue.** `Adventure > Arena queue 1v1`, `Adventure > Arena queue 2v2` (a party of exactly two; either member queues both), Adventure > Arena
(leaves the queue, or forfeits a running match), Adventure > Arena (status and the window). The window (Adventure > Arena in the top
menu, or Adventure > Arena) shows the rating, W-L-D and best per mode, the queue buttons, the queue time and window, the level
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
Adventure > Arena, being moved out of the slot, or another character of the same connection logging in. A leaver is sent
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

## Hunt tracker (`hunt.lua`, `hunt_core.lua`, `hunt_config.lua`, `hunt_supplies.lua`, `tools/gen_supply_prices.py`)

Client `game_hunt` (opcode 241), opened with Hunt > Hunt Tracker in the top menu. `Hunt > Hunt Tracker pause`, `Hunt > Hunt Tracker resume`
and `Hunt > Hunt Tracker reset` work from the chat too. Settings: `hunt_config.lua` (loaded as `Chaos.huntConfig`). No DB tables.

**Why not the base client's analyser.** The base client ships an analyser (`mods/game_analyser`, menu Hunt > Hunt
Analyser). Its loot, supply, damage and kill panes are fed by game-protocol messages (kill tracker, loot stats, supply
tracker, impact tracker) that a 10.98 server never sends, and it prices items with the client's own price list, not
the server's NPC prices. Only its experience pane works here. The Chaos window is fed by the server instead. The base
analyser is left as it is.

**What it shows.** The session time, with Pause / Resume and Reset. Experience gained, exp/h, the time to the next
level (the experience left is in the tooltip) and the kill count. Loot value and loot/h, supplies used and supplies/h,
profit (loot minus supplies) and profit/h, in green or red. Damage dealt and healing, as totals and per second. Four
tabs list kills per monster (count and share), looted items (icon, count, gold), supplies used, and Chaos drops (orbs,
uniques and items with a rarity, in the loot filter's rarity colours). Copy puts a text summary on the clipboard.

**How it counts (server side).** Sessions are kept in memory by character. A session starts at login (`autoStart`).
Its clock only runs while the character is online and the session is not paused. After a logout it is kept for
`keepOfflineMinutes` (30), so a relog continues the same session. A server restart clears it.
- Experience: an `onGainExperience` EventCallback at index 1000, after every bonus, so the number is what the character
  really gets. It reads the value and returns it unchanged.
- Kills: a `kill` CreatureEvent. The engine runs it for the last hit and for the most damage. Summons are not counted.
- Loot: the corpses the character owns, read in `onDropLoot` before (1.9) and after (2.4) the index-2 callbacks. For
  each item the larger count is kept, so items the auto seller sells and coins or keys added at index 2 both count.
  Items are valued at the NPC sell price (`sell_prices.lua`, highest price any NPC pays). Coins count at face value.
  `extraValues` can price items no NPC buys. Orbs count at 0 gold unless priced there.
- Supplies: every `thinkMs` (2 s), the potions, runes, ammunition and thrown weapons in the inventory are counted. If
  there are fewer than at the last count, the difference was used. Nothing is counted in a protection zone, so the
  depot, NPC trades and bank are not "used". The baseline is taken again after a pause or a login. Prices come from
  `hunt_supplies.lua`, generated by `python3 -I server/tools/gen_supply_prices.py <server>/data`: the lowest price an NPC
  asks per item. Runes are stackable in this protocol, so the price is per rune. The staff test NPCs are skipped.
- Damage: a `healthchange` event registered from `onTargetCombat` (index 60) on whatever the character or its summon
  attacks. It is capped at the target's remaining health, so overkill does not count.
- Healing: a `healthchange` event on the character itself, capped at the missing health (healing received).
- The client gets a state when the window opens and then every 2 s while it is open. It ticks the clock in between.

**Protocol** (JSON `{action, data}`): client -> server `open | close | get | pause | resume | reset`. Server -> client
`state {open?, t, p, xp, xph, lvl, left, ttl, lv, lvh, sv, svh, pf, pfh, dmg, dps, heal, hps, kc, k, l, s, x}`.
The lists are arrays to keep the message short (see `hunt_core.lua` `H.state`). Each list is capped (`maxKills`
40, `maxLoot` 60, `maxSupplies` 30, `maxSpecials` 40); the totals always count everything.

**Tested in game** (test server, a level 599 paladin, bow and arrows, Dragons, Dragon Lords, Cyclops, Trolls, Orc
Warriors and a treasure goblin):
- Experience: the tracker showed 652,994, the same as the character's experience minus the saved value at login.
- Supplies: 30 health potions, 30 runes and 43 arrows used, matching the inventory.
- Loot: after a reset, 8 corpses held 306 items worth 7,789 gold, the same as the tracker. The goblin's hoard added
  14 crystal coins, 3 platinum coins and two demon helmets (Rare, Mythic) at 40,000 each, plus 5 Chaos Orbs in the
  Chaos drops tab.
- Damage and healing counted, pause / resume / reset worked, and the session continued after a relog.
- `tests/hunt_test.lua` covers the clock (pause, offline, relog, reset), the counters, the corpse merge, used supplies,
  the level formula against the engine's, the rates and the state. The client's `game_hunt/huntmath_test.lua` covers
  the formatting.

**Limits.**
- Loot is what dropped in the corpses the character owns, not what it picked up. In a party, the corpse owner's
  session gets the loot.
- A supply that leaves the inventory outside a protection zone counts as used: thrown on the floor, traded, or put in
  a container on the ground.
- Damage done by a script hit that skips `onTargetCombat` is not counted. That was seen with a scripted kill of the
  goblin.
- Healing is healing received from any source, not healing done to others. Mana is not tracked.
- The rates include idle time while the session runs: pause it when you stop hunting.

## Loot filter, loot channel and loot rays (`lootfilter.lua`, `lootfilter_core.lua`, `lootfilter_config.lua`, client `game_lootfilter`)

Extended opcode 238 (`ChaosOpcodes.lootfilter`), Hunt > Loot Filter (or Hunt > Loot Filter) opens the window; Hunt > Loot Filter applies a preset.

**How rarity reaches the client.** It does not, natively. The base server stores rarity as the item custom attribute
`rarity` (1..15, Common .. Transcendent, rolled in `eventcallbacks/monster/default_onDropLoot.lua` and by the Chaos loot
layer); uniques carry `chaos_unique`. `NetworkMessage::addItem` sends only the client id, count and fluid, so a container
item in the client has no rarity. `game_itemrarity` reads a `[NAME]` tag out of `item:getTooltip()`, but the server never
fills that tooltip string (the 10.98 packets have no description field; the hover tooltip is a separate 0x9F/0x9E request
used by `game_itemtooltip`), and its table has 6 names that are not the server's 15. So the filter asks the server: on
every container open/change the client sends `peek {cid}` and the server answers the rarity, unique flag, orb flag and
category of each slot of that container (`player:getContainerById`), and the item's Chaos modifiers as one line (`x`,
"Item modifiers"; also in the kill rows, shown in the loot channel tooltip). `game_itemrarity` / `game_itemtooltip` are
not changed.

**Rules** (`lootfilter_core.lua`, mirrored for drawing in the client's `lootfilterlogic.lua`):
- *Glow on gear from* rarity X (0 = off): equipment with rarity >= X gets a glow in its rarity colour. Uniques (orange) and
  orbs (teal) always glow.
- *Dim gear below* rarity Y (0 = off): equipment with a lower rarity (rarity 0 = no rarity) is dimmed. Dimming only, items are
  never hidden (hiding would shift container slot indexes); dimmed items stay lootable.
- *Show* per category (equipment, currency = orbs and coins, supplies = potions/runes/ammo/food, other): a category switched
  off is dimmed (gear at or above the glow line still glows).
- Items with a rarity that do not glow get a thin frame in their colour. Corpses dim; other containers only glow/frame.
- *Rare-drop message*: every glowing item (not orbs) gives a coloured line `Rare drop: [Legendary] Dawnforged Helmet`
  (`Unique drop: [Unique] ...`) in the loot channel and over the map. TFS text messages have no colour, so these go through the opcode.
- *Rarity Autoloot* (store unlock, see below): *leave list gear below* Z keeps autoloot-list equipment of a lower rarity in
  the corpse; *also pick up gear from* W autoloots equipment with rarity >= W, and uniques, even when they are not on the
  autoloot list. Uniques, orbs and coins are never held back.
- Presets: *Show all* (Rare+ glows, nothing dimmed), *Hunter* (Epic+ glows, below Uncommon dimmed, picks up Epic+),
  *Strict* (Legendary+ glows, below Epic dimmed, supplies and other dimmed, leaves list gear below Epic, picks up Legendary+).
  Presets keep the two display options (icons, rare-drop message).
- Settings live in one storage value per character, `Chaos.storage.lootFilter` (7100500), packed by `F.pack`; the client
  mirrors them (pushed after login and asked for with `sync` at game start).

**onDropLoot order** (lower index first): 0 stock loot + "Loot of" text, 1 Chaos loot layer, 2 auto seller,
**2.5 snapshot** (the corpse contents for the loot channel; list items below the Rarity Autoloot minimum are moved into a
bag on the corpse tile for the rest of the chain), 3 base autoloot, **3.5 rarity pickup**, 4 loot pouch,
**4.5 finish** (the held items go back into the corpse, the bag is removed, the loot row, rare-drop lines and rays start).
Every step is in `pcall` and returns nothing, so the chain never stops. `autoloot.lua` and `autosell.lua` are unchanged; the
auto seller still sells first (sold items never show in the row) and the loot pouch still takes the list items the base
autoloot could not carry (checked in game: "Auto seller: sold ...", "Loot pouch: ... sent 1 to your stash").
Treasure goblins add their hoard in their death event, which the engine runs before `dropLoot`, so the snapshot sees it
(rays included; the old `ChaosLootRays.beam` hook in `treasure_goblin.lua` was removed).

### Loot channel (icons, click to loot)
- On each kill the corpse owner gets `kill {k, m, p, items = [{n, id, c, r, u, o, g, nm, left}], drops}`. The client opens
  the console's **Loot** tab and lays a panel with one row per kill (time, monster, item icons with count, rarity glow /
  frame / dim, tooltip with name, rarity and how to loot) over that tab's text while it is selected. Uncheck "Loot tab shows
  item icons" to get the plain text back. The last 50 rows are kept (`historySize`, client `MAX_ROWS`).
- The corpse gets the custom attribute `lf_kill = <kill id>` so it can be found again on its tile (it survives
  container-to-container decay stages). Entries are matched to corpse items by `id:rarity:unique name`
  (`F.signature`, `F.reconcile`); identical items are interchangeable.
- Click = loot all of that entry, Shift+click = one of a stack. `take {k, n, id, one}`: the server checks the kill belongs to
  the player, the corpse still exists and holds a matching item, the player may open it (owner or a party member of the
  owner, the engine's `canOpenCorpse` rule), same floor and within 7x5 squares (`reach`). The item goes into the backpack
  and the bags inside it (capacity checked; never into an equipment slot), else, with the Loot Pouch, to the stash or inbox,
  else it is refused ("You do not have enough capacity or room.", shown over the map; a split stack goes back).
- Greying: `update {k, left}` after autoloot (in the same drop), after a click, after any player move out of the corpse
  (`EventCallback.onItemMoved`, index 11), and from a 1 s timer while rays run / every 5 s otherwise; `decay {k}` when the
  corpse is gone (all icons of the row grey with a check mark). Records are dropped on logout, when nothing is left or the
  corpse decayed.

### Rarity Autoloot (store unlock)
Store -> Convenience -> "Rarity Autoloot", 400 Chaos Coins, `kind = "unlock"`, `unlock = "rarityAutoloot"`, storage
`Chaos.storage.shopRarityAutoloot` (7100106), handled by `S.unlocks` in `shop_services.lua`. Without it the two Rarity
Autoloot selectors are greyed in the window with a store hint and the server ignores them (`F.autoloot` returns nil);
glow, dim, rare-drop lines, rays and the loot channel are free. Checked in game: before buying, an Exotic sword off the list
stayed in the corpse; after buying (Strict) it was picked up and a Common list sword stayed.

### Loot rays
- A beam rises from the corpse tile while a qualifying item is still in it: uniques (`rayUniques = true`, orange beam
  `loot_ray_unique`) and items of base rarity >= `rayMinRarity` (5 = Legendary): Legendary/Exotic gold, Mythic/Chaos/Eternal
  red, Divine/Phantasmal/Celestial white-blue, Cosmic/Abyssal/Transcendent violet (`rayBands`). One beam per corpse: a unique
  wins, else the highest rarity left. Epic and below never get one.
- Resent every `rayIntervalMs` (1000; the effect is 900 ms) for at most `rayDurationS` (60) and stops as soon as the item
  leaves the corpse or the corpse decays (same tracking as the loot channel; checked in game: orange -> red after looting
  the unique, nothing after looting the last one).
- Visible to the looters only (`rayVisibleTo = "looters"`: the corpse owner and their party on the same floor nearby);
  `"all"` shows it to everyone who sees the tile.
- Art: effects 424..428 (`loot_ray_*`), style `lootbeam` in `client/tools/sprites/gen_effects.py` (a 2x2 single effect: a
  thin bright core, a soft halo, a ground flare and rising motes, 91 % of every frame transparent). Rebuild the client pair as
  in `data/spells/README_FX.md`; `data/lib/chaos_fx.lua` and `effects_catalog.csv` are regenerated. Without the new dat the
  ids show nothing (the server does not check).

**Tests:** `server/tests/lootfilter_test.lua` (packing, sanitizing, presets, glow/dim rules, Rarity Autoloot decisions,
ray choice with the real config, reconcile, reach, labels, drop lines) and the client's
`game_lootfilter/lootfilter_test.lua`. Checked in game on the test server: glow / frame / dim in a corpse window and in the
loot channel, presets, the setting surviving a relog, click to loot (all, Shift = one, refused with a full backpack),
autoloot greying icons, decay greying a row, the store purchase, Rarity Autoloot hold-back and pickup, the rays of every band.
**Not verified:** party members looting (rows and rays go to the corpse owner only; party members can click-loot only
corpses of their own kills), corpses moved by a player (the row greys as decayed), many players at once.

## Rifts (`rift.lua`, `rift_core.lua`, `rift_config.lua`, client `game_rift`)

Map devices (roadmap item 8). A consumable Rift Key opens a timed instance with random modifiers for the player and their
party. All numbers are in `rift_config.lua`; the pure logic (key rolls, rewards, key odds, slots and layout, the timer, the
experience cap) is in `rift_core.lua` and tested by `tests/rift_test.lua`. Extended opcode 228 (server -> client HUD),
storages 7100400-7100409, action ids 47401 (key), 47402 (reward chest) and 47403 (Sealed Coffer). No database table.

- **The key.** An existing non-stackable item, the "shadow orb" (10155), with action id 47401, the custom attributes
  `rift_tier` (1-15) and `rift_mods` (`"vitality:40,reflection:10"`), the name "Rift Key (Tier N)" and a description
  that lists the modifiers, the reward bonuses and the level needed, so looking at a key shows everything. One NPC (Black
  Bert) lists the shadow orb in his trade, so a player could sell a key there.
- **Modifiers** (1-3 per key, weights 50/35/15; a next-tier key from a sealed rift rolls 25/45/30). Each has a value
  range and gives reward bonuses per point of value:

  | Modifier | Effect | Reward bonus |
  |---|---|---|
  | Vitality | monsters +20-60% health | quantity 0.5x, experience 0.25x the value |
  | Brutality | monsters +15-40% damage (health and mana damage to players) | rarity 0.75x, experience 0.25x |
  | Haste | monsters +40-120 speed | quantity 0.15x |
  | Elites | +50-200% magic/rare/legendary monsters | rarity 0.15x, quantity 0.1x |
  | Reflection | monsters reflect 5-15% of the damage that lands (not overkill) as physical damage | experience 1.5x, quantity 1x |
  | Warding | monsters resist 10-30% of all non-physical damage | quantity 0.75x, rarity 0.5x |
  | Withering | players get no health regeneration (food regeneration is swapped for one with mana only; restored on leaving) | +15% experience, +15% quantity |
  | Swarm | +1-3 monsters in every pack | quantity 8x, experience 5x |

  Map modifiers (second set). These have a roll weight (the first eight weigh 100) and a lowest key tier; keys below
  that tier never roll them, from drops or from orbs (`R.addMods`). Boons are pure rewards with no bonus of their own,
  shown in gold on the HUD:

  | Modifier | Effect | Weight, tier | Reward bonus |
  |---|---|---|---|
  | Teeming | +20-50% packs | 80, 1+ | quantity 0.5x, experience 0.3x |
  | Gilded Trail (boon) | 30-70% chance that the existing Treasure Goblin (`ChaosTreasureGoblin.spawn`) appears in a random open room after 25-60% of the kills, at the level of the strongest type | 40, 1+ | - |
  | Warbands | 10-30% of packs: every member rare, the first legendary | 60, 2+ | rarity 1x, quantity 0.3x |
  | Sealed Coffer (boon) | 40-100% chance of a coffer (treasure chest 1746, action id 47403) in an open room. Using it wakes 5 (+1 per extra player) magic+ rift monsters, which do not count towards the guardian. Once they are dead it opens with coins worth 4,000 x tier^2, Chaos 1 + 0.25 x tier, Divine 0.1 x tier and 2 + 0.25 x tier item rolls, all x quantity. An unwoken coffer crumbles at the seal | 50, 1+ | - |
  | Twin Guardians | two guardians, each with 55-75% of the guardian health; both must die | 50, 3+ | rarity 0.25x, quantity 0.2x |
  | Echoing Spoils (boon) | 5-15% of kills: every corpse item is copied once (onDropLoot 1.5, before the loot snapshot so rays and autoloot see the copies; Rift Keys are not copied) | 35, 2+ | - |
  | Cinderdeath | 1.5 s after a kill, players within 1 sqm take fire damage: 5-15% of the monster's max health, at most 300 + 150 x tier | 70, 3+ | quantity 1.2x, rarity 0.8x |
  | Blighted Mending | players receive 20-50% less healing (spells, potions, runes) | 70, 2+ | rarity 0.5x, experience 0.3x, quantity 0.2x |
  | Waning Veil | the time limit is 15-30% shorter | 70, 1+ | quantity 1x, experience 0.5x |
  | Dread Guardian | the guardian(s) +50-150% health and damage | 60, 4+ | rarity 0.2x, quantity 0.1x |

  The summed bonuses of a key are capped (`bonusCap`): quantity 80%, rarity 75%, experience 60%. These caps sit above
  every three-modifier sum of the first eight modifiers.

  Quantity multiplies the Chaos loot rate of the rift's kills (`loot_config.lua` rateMult) and the chest's gold, orbs
  and rolls; rarity raises the chest's gear rarity; experience multiplies the kill experience in the rift.
- **Modifier tiers (I-V; higher is better).** Every modifier but Withering has five tiers inside its value range
  (`tiers` = the top value of each, rift_config.lua). Tiers I-III are exactly the old ranges (keys saved before decode
  unchanged, nothing new is stored: the tier follows from the value); IV and V extend them (Vitality 20-90, Brutality
  15-60, Haste 40-180, Elites 50-300, Reflection 5-22, Warding 10-40, Swarm 1-5, Teeming 20-70, Gilded 30-100, Warbands
  10-40, Twin 55-85, Echo 5-25, Cinderdeath 5-25, Blight 20-70, Waning 15-40, Dread 50-250; the Coffer stays at 3 tiers
  because it is a chance). A key rolls tiers by its own tier (`modTiers.window`): keys 1-5 I-III (as before), 6-10
  I-IV, 11-15 II-V; Divine Orbs reroll inside the same window. Names show on keys and HUD ("Vitality IV"). Each tier IV /
  V modifier raises the bonus caps (+8/+8/+6 and +16/+16/+12).
- **Lives.** A run has shared lives: 3, +1 per extra player who entered, minus Fragile (new modifier, key tier 4+,
  1-2 fewer lives, quantity 7x / rarity 7x / experience 5x the value), at least 1. A death inside is the engine's
  normal death (experience / skill / item loss with blessings and the amulet exactly as anywhere, no reduction) and costs
  one life; the next login of that character puts it back at the rift's entrance with 5 s in which rift monsters do
  not hurt it. The death that takes the last life collapses the rift (everyone out, no chest, key spent). Fallen players
  who may still return keep a run open and share the chest. HUD shows "Lives: n / max". The Flawless Seal achievement now needs no deaths.
- **Omens.** Sealed rifts of tier 6+ add Omen Fragments (item 32071, copy of the red crystal fragment) to every finisher's
  chest: 2 + 1 per tier above 6, x quantity; rare / legendary monsters of those rifts carry one 8% / 25%. Using 60
  fragments binds an Omen Key (item 32072, copy of the eye of the storm; attribute omen_kind) of a random kind. The key
  opens a guardian arena: a rift slot with every side room shut, level 800+, 10 minutes, the rift lives, the guardian
  after 5 s, health from its XML (+75% per extra player). Guardians (outfits 591, 12, 842 of the client pair, 500k
  health each, `monsters/chaos/omens/`): Sangrith the Bloodmoon Herald, Morvane the Hollow Crown, Thalcyra the
  Stormbound Seer. Chest per finisher: 5M gold, 12 Chaos, 6 Divine, 8 item rolls (boss tier, x1.5 rarity), gems and
  supports as a tier 15 rift, and 2 unique rolls over every unique at boss tier x2 find. Achievements omen_1 / omen_10
  and one per kind. Install: `tools/install_omens.py DATA_DIR` (items.otb / items.xml) and register the omens monster
  folder. `/rift omen [kind]`, `/rift fragments [n]`, `/rift lives n` for gamemasters.
- **Dungeon difficulty** (`dungeons_difficulty.lua`): the six difficulties now do what the client panel says (the test
  compares both): monster health 100/200/320/500/800/1300%, damage to the players 100/130/190/280/400/600%, experience
  +0/75/100/200/300/400%, gold coins +0/75/100/200/300/400%, extra loot roll +0/0/15/30/45/60% of each entry's chance.
  Applied to every monster in the dungeon box during a run (also respawns). Also fixed: the queue called a missing
  Game.getPlayerByGUID, so queued runs never started.
- **Tiers.** Tier N picks its monsters from the bounty pool (`bounty_pool.lua`, only monsters that spawn on the map, no
  bosses, at least 100 health) in a level window, and needs a level: 1: 80-180 (level 100), 2: 140-240 (150),
  3: 200-320 (200), 4: 280-420 (300), 5: 380-520 (400), 6: 480-640 (500), 7: 580-740 (600), 8: 680-840 (700),
  9: 780-940 (800), 10: 880-1100 (900). Tiers 11-15 keep the tier 10 window and add +15% monster health and damage and
  +10% rewards per tier (level +25 per tier). A window with fewer than three types is widened.
- **Opening.** Use the key in a protection zone, out of combat, not multi-clienting (`Chaos.isMultiClient`), not in a
  dungeon, the tower or the world boss arena, at the tier's level. Party members within 8 sqm on the same floor come
  along (up to 4 players); members who fail a rule stay behind and both are told why.
- **The instance** is built at runtime with `Game.createTile` in a grid of 16 slots (4 x 4, 64 sqm apart) at
  x/y 8192-8447, z 7, where the map has no tiles (checked in the OTBM; other runtime areas: tower 2000+, tutorial island
  4600+, world boss 5000+, siege 5100+, PvP arena 6000+). The first use of a slot checks every tile of its footprint like
  `worldboss.lua` and refuses a slot that has a tile it did not build (the slot is marked unusable, the next one is
  taken). Each slot is a 15 x 15 hub and four 11 x 11 side rooms joined by 3-wide corridors; every run opens 2-4 of them
  (stone walls close the others) and picks a theme for the floor: Abyssal Rift (rift floor), Obsidian Hall (black marble),
  Ashen Crypt (dark sandy / rutted stone) or Forsaken Sanctum (gilded stone), with coal basins for light. The engine has
  no Lua call to remove a tile, so built slots stay for the server's lifetime and are reused: at the end of a run every
  monster and loose item (corpses, drops, fields, the chest) on the floor is removed.
- **The run.** Packs: 6 + tier/3 + 2 per extra player, of 3-4 monsters (+ Swarm), one type per pack; the first pack in
  the north of the hub, the rest in the open rooms. Every monster rolls magic 10% / rare 3% / legendary 0.6%
  (x (1 + 0.05 tier) x the Elites modifier) through `ChaosApplyTier` (monster_tiers.lua; the natural spawn roll and the
  ambush also still apply). After 75% of the monsters died the guardian appears in the hub: the strongest type of the
  rift, legendary, with 3x its base health (+100% per extra player). Time limit 10 minutes. The HUD (top left, under the
  character plate) shows tier, theme, time left, kills / left, the guardian, the modifiers and the bonuses.
- **End.** Guardian killed in time: the rift is sealed, the remaining monsters vanish, a chest (1740, action id 47402)
  appears where it died and every finisher may open it once within 60 s; whoever did not gets it delivered at the exit
  (or at the next login when offline). Time up: "the rift collapses", everyone is sent back to where they used the key,
  the key is lost. Death inside: the normal death rules (temple, losses), the player is out of the run. Logout inside: the
  player is put back at their entry position and is out of the run. A run whose last player left fails.
- **The chest** (per finisher): gold to the bank 10,000 x tier^2, Chaos Orbs 1 + 0.5 x tier, Divine Orbs 0.25 x tier,
  item rolls 2 + 0.5 x tier (each draws one entry of a random rift monster's loot table weighted by its chance; gear gets
  a rarity from `ChaosLoot.upgradeRarity` at magic (tiers 1-3) / rare (4-6) / legendary (7-10) / boss (11+), x the
  rarity bonus), one Chaos currency roll and one unique roll at that tier; gold, orbs and rolls x (1 + quantity bonus).
  Measured: tier 1 10k gold, 2 Chaos, 1 Divine, a few items; tier 7 (+40% quantity) 686k gold, 6 Chaos, 3 Divine,
  an [Exotic] dragon robe, potions, 11 crystal coins; tier 10 1M+ gold. Finishers are recorded on the weekly Rifts
  leaderboard (`ChaosLeaderboard.record("rift", player, tier)`).
- **Keys.** A sealed rift drops one key (to the player who used the key, else a random finisher) with 30% + 10% per
  modifier (max 60%); of those 50% + 10% per modifier are the next tier (with more modifiers), the rest the same tier.
  Rare / legendary monsters inside a rift carry a key of its tier 2% / 6% of the time. Tier-1 keys: normal kills outside
  rifts (EventCallback onDropLoot, after the Chaos loot layer, before autoloot) with 50 in 100,000 per kill x (magic 3,
  rare 8, legendary 20, boss 40) when the monster's pool level is at least max(60, killer level x 0.4) and the killer is
  level 100+; completed bounty contracts give one 25% (hunt) / 50% (elite) / 100% (boss) of the time (`bounty.lua` calls
  `ChaosRift.onBountyPaid`).
- **Crafting.** Every crafting orb works on a key (Transmutation / Alchemy on a key without modifiers, Exalted up to
  `key.maxMods` = 3, Annulment, Scouring, Chaos rerolls them, Divine rerolls their values), by "Use with" or on the
  bench; see "Crafting".
- **Experience** comes only from the kills, with a cap so a dense rift cannot beat open hunting: the base experience of a
  kill (monster experience x the monster-level bonus x the stage x the magic/rare/legendary multiplier) counts against
  an allowance of 1.1 x the leveling model's base rate at the player's level (the sorcerer hours of "The leveling model",
  the fastest vocation) per minute in the run; above it a kill gives 2% of its experience. Stamina, potions, the Chaos
  bonuses and the rift's Experience bonus apply on top, as when hunting. Measured at level 1000, tier 10: 32 monsters
  killed in the first second gave 13.8M experience instead of ~220M (the first minute's allowance is 3.2M base).
- **Crash refund.** Using the key writes a "run in progress" marker (tier and modifiers, storages 7100400-7100404) and
  saves the player before the teleport. It is cleared when the key's owner leaves the run (end, death, logout). If the
  server stops during a run (crash, kill, the daily shutdown), the next login returns the key. A key whose owner just
  lost the connection while the server kept running is not returned.
- **Other systems.** `ChaosRift.isInside(player)`; the temple scroll refuses inside a rift (`shop_services.lua`), a second
  character of the connection cannot log in while one is in a rift (`multiclient.lua`).
- **Commands.** Adventure > Rifts (dialog: the run status and every key carried with its modifiers). Gamemasters: `/rift key <tier>
  [count | mods]`, `/rift status` (runs, built and unusable slots), `/rift fail`.

**Edits to shared files** (one line or block each): `chaos_constants.lua` (`ChaosOpcodes.rift = 228`,
`Chaos.storage.riftRun = 7100400`), `loot_config.lua` (rateMult x `ChaosRift.lootMult(ctx)`), `shop_services.lua`
(`S.teleportBlocked`), `multiclient.lua` (`insideInstance`), `bounty.lua` (`payContract` calls `ChaosRift.onBountyPaid`).

**Verified on the test server** (cropped map, level 1000 test characters): open a rift from a key (and the refusals: no
protection zone, in a fight, multi-client); the build and the four themes; the HUD (start, live updates, the guardian,
sealed, collapsed, left); kills -> guardian at 75% -> sealed -> chest (once per player, the second open refused), the
unopened chest delivered at the exit; the next-tier key drop; timeout fail; death inside; logout inside; the crash
refund after `kill -9` of the server; two runs at once (two characters, slots 0 and 1) and a slot reused while another
run was active; cleanup (no monsters or items left, tiles kept); Vitality x1.40 health, Reflection 10% of the landed
damage, Warding -20% fire, Withering (no regeneration inside, back outside); the tier-1 key from a normal kill and from a
bounty; the temple scroll and the multi-client login refusal; the experience cap. Not verified: a real party (only one
player per run was tested), the protection-zone rule on a real map (the cropped test map has no protection zone, so the
rule was switched off after checking the refusal), balance of tiers 8-15 against geared characters.

## New players (`newplayer.lua`, `newplayer_core.lua`, `newplayer_config.lua`, `newplayer_tutorial.lua`)

Roadmap items 21 and 22. Every number, item and text is in `newplayer_config.lua`; the pure logic (kit lookup, flags,
milestones, island layout, station state machine) in `newplayer_core.lua`, tested by `tests/newplayer_test.lua`. Storages
`Chaos.storage.newPlayer` = 7100250 - 7100269 (kit, welcome, tutorial stage / done mask / kills / orb count / flags,
milestones at +10..+19). Tested in game on the test server (fresh level 1 characters, see "Verified" below).

- **Kit** (one time): a character logging in for the very first time (`lastLoginSaved` 0, kit storage unset) gets the kit of
  its class: weapon and armour equipped (into the backpack when the slot is taken), a backpack with potions, 20 brown
  mushrooms, rope, shovel, the store's Temple Teleport Scroll (3 uses, same item and attributes as `shop_services.lua`) and
  500 gold. Kits by class id (`Chaos.classes.ids`): Warrior / Juggernaut / Berserker 4/8/14 jagged sword + dwarven shield +
  brass set; Ranger / Deadeye / Beastmaster 3/7/15 bow + 100 arrows + chain helmet, ranger's cloak, studded legs; Mystic /
  Elementalist / Illusionist 1/5/10 wand of vortex (the scorcher is equipped below level 7, the wand waits in the backpack) +
  spellbook + magician's robe; Thief / Samurai 11/13 dagger + 30 throwing stars + leather set; Ninja 12 the same plus a second
  dagger. A vocation without a row falls back to its base class (`Chaos.classes.baseOf`, then the engine's demotion), then to
  `default` (short sword, wooden shield). Every kit weighs under ~360 oz (a level 1 character carries 400); what does not fit
  goes to the inbox. Existing characters never get a kit by logging in. Messages read the class name from `Vocation(id)`.
- **The base server's starting items:** `creaturescripts/firstitems.lua` only equips vocation 0, which the kit skips
  (`skipVocations`), so nothing is given twice. The base starter chest (`scripts/customs/actions/first_chest.lua`, action id
  and storage 33735, old vocation ids only) is marked as opened when the kit is given (`baseChestStorage`), so nobody collects
  both. No base file is changed and no patch is needed.
- **Welcome** (one time, after the kit): a server modal window (client `game_modaldialog`) with the next steps (Character > Spellbook, the
  passive tree, Adventure > Bounty Board, the store, the top menu, the milestone gifts) and a toast through `game_chaosnotify` (action
  `newplayer`, type NEW_PLAYER, added to `notifications.lua`). The tutorial island is the starter quest line.
- **Milestone gifts** at levels 20 / 50 / 100 / 200, once per character (a storage each, so a death and the same level-up
  again give nothing), on level-up (`onAdvance`; a jump over several milestones gives each): potions by role (each role gets
  only potions the base `potions.lua` lets it drink; the Thief line the unrestricted ones), 1 / 2 / 3 / 5 Chaos Orbs and 2
  Stamina Extensions (the store item) at 100. Backpack first, inbox when full; a message and a toast.
- **API:** `ChaosNewPlayer.kitFor(vocationId)` returns a copy of a class's kit; `ChaosNewPlayer.setKit(name, def, {ids})`
  adds or changes a kit (a `def` with `base = "warrior"` inherits that kit); docs/CLASSES.md.
- **Staff:** `/newplayerkit <name>` gives the kit again (ignores the flag); `, welcome` shows the welcome; `, milestone <n>`
  gives gift n; `, reset` clears every new-player storage; `, tutorial` sends the character to the island's first station.
  Online characters only; logged to the console.

### Tutorial island (`newplayer_tutorial.lua`)

Built at startup with `Game.createTile` like the world boss arena (nothing is saved to the map): footprint x 4598-4642,
y 4598-4612, z 7 (the map has no tiles within x/y 4500-5600; every tile is checked first and the island is not built over
foreign tiles, then new characters get their kit at the first login instead). Five 7 x 9 grass pens side by side, water
around, stone divider walls with a stone-floor gate each (action id 47504), an angel statue (47502, use: read the lesson
again) and a white marble lesson tile (47501) in every pen, coal basins and flowers, a goblin statue (47503, skip) in the first
pen and a magic forcefield exit (47505) in the last.

A brand-new character (first login, no kit yet, a class with a kit) arrives in the first pen instead of the temple. Each
station opens a lesson (modal window + toast) when entered; its gate opens east only when the task is done:
1. Moving and fighting: kill 3 rats (spawned in the first pen when the lesson is closed, the lesson tile is stepped on, or
   after 20 s; at most 3 alive). Detected with a `kill` CreatureEvent.
2. Spells: open Character > Spellbook (`ChaosSpellbook.sendTo` is wrapped at startup: the command and the client button both pass there)
   and cast the class spell (Warrior Salve of Scars `saen tin brak`, Ranger / Mystic Arcane Stitch `saen tin`), detected by
   the spell group cooldown condition (polled every 300 ms). A level 1 character with too little mana gets its maximum raised
   to the spell's cost once. The Thief line has no spell below level 20: opening the spellbook is enough.
3. Passive tree: one free passive point (`passiveExtraPoints` +1, kept); allocating it and pressing Apply Points completes the
   station (a listener in `ChaosPassiveTree.listeners`).
4. Orbs: a Chaos Orb and a Common (rarity 1) leather armor; the station completes when the orb is used (the character's orb
   count drops: the stock action and the crafting bench both consume it). The lesson mentions Economy > Crafting Bench when `ChaosCrafting`
   is loaded.
5. Keystones, Adventure > Bounty Board, the store and the top menu: information; the forcefield then sends the character to its temple with
   the kit and the welcome.

Character > Services > Leave Tutorial, the goblin statue or the lesson's "Skip tutorial" button leave at once with the kit. Characters that existed
before never enter the island. Safety: no PvP on the island (`EventCallback onTargetCombat`; runtime tiles cannot get the
protection-zone flag); nobody dies there (a hit that would kill leaves 1 health and the character is healed; a death anyway,
e.g. elsewhere, is answered at the next login); logging out and in, or a death, puts the character back in the pen of its
station; monsters cannot leave (water and walls, gates push monsters back); multi-client characters are welcome.

**Verified in game (test server, cropped map with a test-only temple floor):** first login lands on the island with lesson 1;
the death guard and the heal; logout / relog and death mid-tutorial resume at the station; each station's task (kills through
real kill events, Character > Spellbook + `saen tin brak`, a passive node applied in the client, the Chaos Orb used on the armor from the
client); the exit to the temple with the Warrior kit and the welcome; "Skip tutorial" (Ranger) and Character > Services > Leave Tutorial (Mystic:
scorcher equipped, wand in the backpack); relog gives no second kit; milestones 20, then 50 + 100 in one jump, nothing after
losing and regaining level 20; `/newplayerkit` and its options. Not verified: PvP block (needs two clients), the island build
refusal over foreign tiles, the full stations for the Thief line beyond 1-2.

## Patch notes (`patchnotes.lua`, `patchnotes_core.lua`, `data/patchnotes/*.md`, client `game_patchnotes`)

Weekly patch notes for players (roadmap item 23). Client: `client/overlay/modules/game_patchnotes` (Social > Patch Notes
in the top menu, or Social > Patch Notes), extended opcode 244 (`ChaosOpcodes.patchnotes`), table `chaos_patchnotes` (created at
startup if missing; also `sql/chaos_patchnotes.sql`). The notes live on the server, so new notes never need a client update.

- **Files.** One Markdown-ish file per week or version in `data/patchnotes/` (copy `server/data/patchnotes/` there), named
  `<id>.md` (e.g. `2026-10-08.md`; the id is the name without `.md`). Format (parser: `patchnotes_core.lua`):
  `# Title`, an optional `Date: YYYY-MM-DD` line (else the date at the start of the file name), free text before the first
  section (the intro), then `## New`, `## Changes`, `## Fixes`, `## Balance` (other headings are kept and drawn in plain
  colour). Bullets `- ` (or `* `, `+ `), sub-bullets indented by 2+ spaces, indented lines without a dash continue the
  bullet above, `- **Lead.** text` gives the bullet a highlighted lead, `<!-- ... -->` is ignored, `**`/`__`/backticks
  and `[text](link)` markers are removed. `README.md` and drafts (a name starting with `_`) are skipped. Write for
  players, and only about what is live. The folder is listed with `ls` (`dir /b` on Windows; `data/patchnotes/index.txt`,
  one file name per line, when the server cannot run commands) at startup and again at most every 60 s, so a new file
  shows up within a minute; `/patchnotes reload` (staff) reads it at once. Weeks are ordered by date, then id (newest
  first); the list shows up to 52.
- **Window.** Weeks on the left (date, title, NEW for unseen ones), the selected week on the right: title, date, intro,
  section headings in colour (New green, Changes gold, Fixes blue, Balance violet), bullets with a dot in the section
  colour, sub-bullets, bold leads. A long note is sent in parts of about 4 KB of text (`PN.parts`; one 9 KB message never
  arrived in the test client) and joined by the client.
- **Login.** Once per new week per **account** (`seen_key` = date|id of the newest week the account was shown; a week
  counts as seen when the client displayed it, opened by itself or by hand, and an older week never lowers it). "Don't
  show automatically" (`auto_open`, per account) stops the login opening; the menu and Social > Patch Notes still work. The login
  opening never stacks with the Daily Reward window: it is the `patchnotes` entry (order 30, after the daily's 20; set
  `Chaos.dailyStreak.loginOrder.patchnotes` to change it) of daily.lua's login window queue `ChaosLoginWindows`, so the
  server sends it only after the client reports the daily window closed (or when the daily is not due), and the window
  reports `closed` itself so the queue can go on. The client also refuses to show it over a visible Daily Reward window
  (and hides it again if one appears in the first 20 s), and game_daily waits while `patchNotesWindow` is on screen. On
  a server without that queue, the script falls back to its own timer (the daily's `openDelayMs` + 1.5 s) and tells the
  client whether a daily window is expected; the client then waits up to 6 s for it to appear and until it is closed.
- **Staff:** `/patchnotes reload` (read the folder now), `/patchnotes unseen` (forget the own account's last seen week, to
  test the login opening), `/patchnotes` (status).
- **Tests:** `tests/patchnotes_test.lua` (parsing, limits, file list, ids, order, seen key, auto-open, the parts; also
  parses every real file of `data/patchnotes/`) and the client's `patchnotesview_test.lua` (blocks and colours, joining
  parts, the login wait).

Verified on the test server: the window from the menu and with Social > Patch Notes, week list and switching weeks, the
formatted notes (four sections, leads, sub-bullets, scrolling), the login opening with the Daily Reward window first
(old timer path and the login window queue: the notes appear only after the daily window is closed), the opening at once
when the daily is already claimed, no second opening at the next login, "Don't show automatically" (no opening for a new
week, unticked again from the window), the seen key and setting in the database. Not verified: two characters of one
account online at once, the Windows `dir` listing and the `index.txt` fallback, the client stepping aside for a daily window that
appears in the first 20 s (cannot happen with the queue).

## Daily reward and login streaks (`daily.lua`, `daily_core.lua`, `daily_config.lua`)

Client `game_daily` (opcode 207), opened with Adventure > Daily Reward or Adventure > Daily Reward, and by itself at login while today's
reward is unclaimed. The 7 daily rewards and the week bonus stay in `Chaos.daily` (`chaos_constants.lua`). The streak
rules are in `daily_config.lua` (loaded as `Chaos.dailyStreak`). Table: `chaos_daily_account` (`sql/chaos.sql`).

**Account-wide.** One claim a day per account, whichever character claims it. The reward goes to that character. The
row holds the streak (consecutive claim days), the best streak ever, grace charges, the day of the last claim and the
total number of claims. It is cached in memory and written through on every claim.
- Migration: the first login of an account after the update builds its row from the old per-character storages
  (`dailyStreakDay`, `dailyLastClaim`) of all its characters. The most recent claim wins, then the higher slot. The
  old cycle only stored the slot, so that slot becomes the streak.
- The old storages are still written on each claim, but nothing reads them any more.
- If the table is missing, the server prints one warning and keeps streaks in memory until the next restart.

**Streak and the 7-slot cycle.** The window's 7 slots follow the streak: slot = ((streak - 1) mod 7) + 1, so day 8
of a streak is slot 1 again, and the week bonus comes with every slot 7. The window shows `Streak: N days`, the best
streak, the grace charges, the next milestone (days, how many claims away, and the reward), and the account's title.
An older client ignores the new fields.

**Grace day.** Missing one day does not break the streak if the account has a grace charge. One charge is used per
missed day. A charge is earned every 7 claimed days of a streak, 2 stored at most (`graceEvery`, `graceMax`). Two or
more missed days in a row always break the streak (`graceMaxMissed` = 1). The window marks the charges in gold on a
day when a charge will be used.

**Milestones** (all in `daily_config.lua`, paid together with the day's reward, all or nothing):

| Days | Reward |
|---|---|
| 7 | 2 Chaos Orbs, 1 Divine Orb |
| 14 | 3 Chaos Orbs, 2 Divine Orbs |
| 30 | 5 Chaos, 3 Divine, 1 Exalted Orb and the title "the Devoted" |
| 60 | 8 Chaos, 5 Divine, 2 Exalted Orbs |
| 100 | 12 Chaos, 8 Divine, 3 Exalted Orbs, 10 crystal coins and the title "the Relentless" |
| 180 | 20 Chaos, 12 Divine, 5 Exalted Orbs, 25 crystal coins and the title "the Undying" |

- A milestone is paid every time a streak reaches it.
- Titles use the leaderboards' mechanism: a line in the look text of every character of the account ("He holds the
  login streak title the Devoted (30 days in a row).", `onLook` at index 101, after the leaderboard titles). The title
  follows the account's best streak, so it is kept after the streak breaks.
- The first time an account reaches a title milestone, it is broadcast.
- No new art or items: the rewards are the existing orbs and coins.

**Login order (`ChaosLoginWindows` in `daily.lua`, the one place for it).** Windows that open by themselves at login go
through one queue, so they never stack on top of each other:
- Each window registers with `ChaosLoginWindows.register(key, order, wants(player), open(player))`. A lower order opens
  first. The daily window is `daily`, order 20 (`Chaos.dailyStreak.loginOrder`). The patch notes use it with order 30.
- At login, after `Chaos.daily.openDelayMs`, the wanted windows are sent one at a time.
- The next window is sent when the client reports the current one closed (`ChaosLoginWindows.closed(player, key)`;
  game_daily sends `{"action":"closed"}`), or after `loginWindowMaxWaitMs` (90 s) if the client never does.
- On the client, a window opened this way (`"Login":1`) waits while a server modal dialog (the new-player welcome, the
  tutorial) or another login window (`LOGIN_BLOCKERS` in game_daily) is on screen. This fixes the daily window that
  opened over the new-player welcome.
- The walk-away rule of the daily window (more than 3 tiles closes it) now ignores jumps (the placement at login, a
  teleport). Those move its anchor instead.

**Protocol additions** (the shipped protocol and its quirks are unchanged; see the header of `daily.lua`):
- `OpenDailyWindow` also carries `Streak, Best, Grace, GraceMax, GraceUse, Broken, Title, Next {Days, In, Reward,
  Title}` and `Login`.
- The client also sends `closed`.

Staff: `/daily` shows the own account's state, `/daily shift <days>` moves the daily clock (tests),
`/daily set <streak> [grace]` sets the own account's streak as if claimed yesterday (group access required).

**Tests:** `tests/daily_test.lua`.
- Pure part: days over month, year and DST ends, the slot cycle, claims, grace (use, earn, cap, two missed days),
  broken streaks, a clock that went back, milestones, titles and texts, the migration, the login order.
- Mocked `daily.lua`: the slot mapping of the client, the migration at login, an alt of the same account refused, a
  second account, a stale window, day 7 with the week bonus, milestone and grace charge, all or nothing with a
  milestone that does not fit, the look text, and the login queue moving on at "closed".

**Tested in game** (test server, clock moved with `ChaosDaily.offsetDays`):
- The migration from the old storages (slot 2 -> streak 2).
- A claim on the next day (streak 3, row written).
- Day 7 paid 3 Divine Orbs plus the milestone (2 Chaos Orbs, 1 Divine Orb), 2 crystal coins of the week bonus, and a
  grace charge.
- A missed day covered by the charge (charges shown in gold, streak 7 -> 8, charge used).
- Day 30: the title in the window and in the look text.
- The window waited behind a server modal dialog and opened when it closed. Closing it emptied the server queue.
- After a relog the window opened by itself. A teleport kept it open; walking 4 tiles closed it.

**Not verified in game.** The refusal for a second character of the same account. The test client cannot list two
characters of one account (a base client character-list error), so this is covered by the mocked test only.

## Ascension quest (`ascension_quest.lua`, `ascension_quest_core.lua`, `ascension_quest_config.lua`, the Ascendant Oracle)

Players ascend through a quest, not a command (docs/CLASSES.md "Ascension quest"). Install: step 4b (the NPC and the promotion
patch) plus the scripts (step 1) and the guardian monsters (`data/monster/monsters/chaos/ascension/`, registered with the
other Chaos monsters). Settings: `ascension_quest_config.lua` (`Chaos.ascensionQuest`); the level rule and the two ascended classes
of every line are read at run time from `Chaos.classes.ascension`, so a new class line gets the quest without code changes.

- **The Ascendant Oracle** is placed at startup next to the temple of every town in `npc.townIds` (default `{1}`; first free tile
  of `npc.offsets`), unless an NPC of that name already stands there (placed with the map editor); `npc.positions` places it
  exactly. Its script runs in the NPC's own Lua state: it reads the storages and opens modal windows, whose answers
  (`ChaosAscensionModal`) are checked again in the scripts' state. "promotion" is answered with the pointer to the quest.
- **Stages** (storage `7101000`: 0 none, 1 Proof, 2 Trial, 3 Choice, 4 done; `7101001` Proof points, `7101002` Trial cooldown,
  `7101003` attempts, `7101004` Trial won): 1 the Calling (talk at level 100 as a base class: the two paths of the class),
  2 Proof of Strength (10 points: a rare monster 1, a legendary 3, counted when the monster's hunting level, from
  `bounty_pool.lua` or estimated from experience and health as `tools/gen_bounty_pool.py` does, is at least 0.6 x the player's
  level, min 40), 3 the Trial, 4 the Choice (a list of the two classes, then a confirmation; near the Oracle, no PvP lock).
- **The Trial**: "trial" at the Oracle -> a modal -> a runtime-built room (13 x 13, slots at x/y 7000+, `Game.createTile`,
  refused when the footprint is not empty; 8 slots) with the class's guardian: `Ascension Warden` renamed and dressed per line
  (Warden of Iron, of the Hunt, of the Veil, of Shadows, of the Still Fist, of Bones, of Dawn; a default for new lines), health
  6000 x level/100 with the level clamped to 100-130, its own hits x the same factor, no experience, no loot, never a monster
  tier. Mechanics per line (`guardians[base].mechanics`): `stillness` (3 s on one tile: a slam of 20% max health, warned at 2 s),
  `adds` (2 shades every 15 s, at most 4), `zones` (5 marked tiles around the player burst 1.5 s later for 25%), `enrage`
  (x1.5 below 30% health). 180 s. A lethal hit is cut to 1 health (no death: no experience, item or blessing loss); death, the
  time limit, leaving the room or logging out fail the attempt: back to where the player stood, healed, retry after 10 min.
  A character saved inside a room (crash) is sent to its temple at login.
- **The ascension** is `ChaosAscension.ascend(player, word[, opts])` in `ascension_quest.lua`: the class lock
  (`ChaosClassUnlocks.canUseVocation`, staff included), then ascension.lua's own vocation change (`ChaosClasses.applyVocation`:
  health / mana / capacity recounted, the vocation resent to the client, dual wield synced, the companion / minions / chi
  HUD), storage `Chaos.classes.storage.ascended`, a toast (game_chaosnotify action `ascension`), a broadcast and the name plate
  title "Ascended <class>" (`ChaosTitles.register("ascension", ...)`, guarded: every ascended character holds it).
- **the Ascendant Oracle**: players get "Ascension is earned, not claimed. Speak with the Ascendant Oracle in the temple." Staff (group 4+)
  keeps the old command, and a migrated character's one free switch (the Ascendant Oracle) still works.
  `command = "open"` in the config restores the command for everyone. The store's Vocation Change is unchanged; a character
  it took back to a base class may choose again at the Oracle without redoing the quest.
- Character > Character Info shows a character's progress. Staff: `/ascendset <player>, <ascended class>` sets an ascended class of the
  character's own line (restores characters demoted by the old login bug; the class lock still applies; no broadcast).
  Characters ascended before the quest keep their class.
- Tests: `server/tests/ascension_quest_test.lua` (the pure rules). Verified on the test server: King Tibianus refuses; a level
  100 Warrior did the Calling, the Proof (a rare Dragon, level 42, did not count; legendary and rare Hydras did), failed the
  Trial twice (lethal hit caught, experience unchanged, cooldown), won it and became a Berserker; a Thief became a Ninja
  (dual-wield storage set); a locked Templar was refused at the confirmation; the Ascendant Oracle and `/ascendset` as documented.
  Not measured: the guardian's balance against geared characters (the numbers are first estimates).

## Class lock (`class_unlocks.lua`, `class_unlocks_core.lua`, `sql/chaos_class_unlocks.sql`)

The Necromancer, the Monk and the Templar (docs/CLASSES.md, classes five to seven) need an account-wide unlock. The method is one
table, `ChaosClassUnlocksCore.config` (`class_unlocks_core.lua`): per class key (`necromancer`, `monk`, `templar`) the vocation ids,
`locked`, and the unlock methods (`store`, `level`, `quest`, `achievement`, or a new kind registered with `registerMethod`). Today
the only method is the store: category "Classes" in `shop_config.lua`, offers `unlockNecromancer`, `unlockMonk`, `unlockTemplar`
at 750 coins each (**placeholder prices**; the offer names and prices must match the config). `shop_services.lua` asks
`ChaosClassUnlocks.storeUnlock` for these offers, so the purchase is written to `chaos_class_unlocks` at once (not the engine's
account storage, which is only saved at server save).

- Gates: the Ascendant Oracle (ascension.lua) and Character > Services (shop_services.lua; the token is kept) refuse a locked class; at login a
  character on a locked vocation goes to its temple, cannot attack and gains no experience or skills until the account unlocks
  the class (the store works in that state). Staff (group 4+, or account type 5+) is never locked.
- Character > Character Info shows the account's state; staff: `/classunlock <character>, <class>[, revoke]`.
- Characters are created on the website (the base server has no in-game character creation): it should offer the three classes
  only to unlocked accounts; the login check holds even if it does not.

## Achievements (`achievements.lua`, `achievements_core.lua`, `achievements_data.lua`, client `game_achievements`)

Long-term goals across every system: 100 achievements in 9 categories (Combat & Leveling, Monsters, World Bosses, Rifts,
Bounties, Items & Crafting, PvP, Exploration & Social, Secrets), 2290 points in all. Client `game_achievements` (Chaos ->
Achievements in the top menu, or Character > Achievements), extended opcode 250 (`ChaosOpcodes.achievements`), tables
`chaos_achievements` and `chaos_achievement_stats` (`sql/chaos_achievements.sql`; also created at startup).

- **The list** is `achievements_data.lua`, one line each: `id`, `name`, `desc`, `cat`, `points`, `stat` + `target` (or `all =
  {stats}`: each at least once), optional `hidden`, `title` (24 characters at most) and `reward` (`gold`, `items`, `outfit =
  {name, female, male, addons}`, `mount = {name, id}`; outfits and mounts the base server already has). Bad entries are
  printed at startup and left out. Never rename a live `id`: it is what the database stores.
- **Counters** (per character, they only go up): `ChaosAchievements.progress(who, key, amount)` and `.set(who, key, value)`
  (the higher value is kept); `who` is a Player, a guid or `{guid, name}`. Offline characters are written straight to the
  database and checked at their next login. Online counters are saved every 30 s, at logout and at shutdown; unlocks at once.
  An achievement unlocks once per character (`INSERT IGNORE`), with a chat line, a toast (game_chaosnotify action
  `achievement`), its reward and its title; the window refreshes if it is open.
- **Where the counters come from.** Nothing in the other systems was rewritten:
  - level, Paragon level (`level - Chaos.paragon.startLevel`), ascension, tutorial island finished, guild: login, level up
    and a 30 s sweep of the online characters;
  - kills (a `kill` event on every player, the tier from `ChaosTierOf`): magic / rare / legendary, party kills, Treasure
    Goblins, the secrets; ambushes from `ChaosTierDead[id].depth` (one line added to `monster_tiers.lua`);
  - `ChaosLeaderboard.record` is wrapped at runtime, like `season.lua` does: `bounty` (contracts), `rift` (tier, runs; the
    modifiers and "nobody lost" from `ChaosRift.runOf`), `arena1v1` / `arena2v2` (wins and best rating from
    `ChaosArena.ratingOf`), `siege` (played; won when the player's bracket winner is their guild);
  - `ChaosWorldBoss.computeRewards` is wrapped: every rewarded player (offline ones too), the boss by name, top damage = rank 1;
  - `ChaosCrafting.apply` is wrapped: orbs used on the bench and by the crafting orbs' use-with, Exalted Orbs, the most
    modifiers on an item. **Not counted:** the base server's own Chaos / Divine Orb use-with (`reroll_rarity_stats.lua`,
    local functions, no hook);
  - `ChaosTreasureGoblin.tick` is wrapped: a goblin removed by its timer after being hit = "escaped" for its attackers;
  - an `onDropLoot` callback at index 2.4 (before the loot filter's snapshot and the base autoloot): uniques found, best
    rarity, modifiers. Only monster corpses count (not rift chests, goblin hoards or world boss rewards);
  - the weekly bounty chest: `Chaos.storage.bountyWeekBonus` holds the week of the last chest; a newer week = one more.
  - the bestiary (`bestiary.lua`, guarded calls): `bestiary_known`, `bestiary_completed`, `bestiary_points` (set at a new
    stage and 2 s after login, so they are retroactive) and `bestiary_tasks` (a completed kill task);
  Any other script: `if ChaosAchievements then ChaosAchievements.progress(player, "my_stat", 1) end` and an entry with
  `stat = "my_stat"`.
- **Retroactive** at every login (quietly, one summary toast): level, Paragon, ascension, tutorial, guild, completed contracts
  in `chaos_bounty` (`status = 1`), the last weekly bounty chest, arena wins and best rating in `chaos_arena_ratings`. Kills,
  orbs, rifts and world bosses have no history to read and start at 0.
- **Points.** Character points are the sum of its unlocks. Account points count each achievement once, whichever character
  of the account earned it (alts do not add the same achievement twice). The window shows both.
- **Titles** go to the name plates: `ChaosTitles.register("achievement", ...)` (titles.lua, colour teal), key
  `achievement:<id>`. Players pick one with the Achievements window or the window's title box (it says the Achievements window for them).
  Nothing happens while titles.lua is not loaded.
- **Class unlock method.** achievements.lua replaces the `achievement` kind of `ChaosClassUnlocksCore` with a superset of it:
  `achievement = {points = 500}` (the account has 500 achievement points), `achievement = {name = "rift_t10"}` (any
  character of the account has that achievement), or both (either is enough). It is checked at login and on level up by
  class_unlocks.lua, and after every unlock by achievements.lua. **No class uses it**: every class keeps `store` only. To
  offer it, add it next to the store in `class_unlocks_core.lua`, e.g.
  `unlock = {store = {offer = "unlockMonk", cost = 750}, achievement = {points = 500}}` (any listed method unlocks; the lock
  message lists both).
- **Protocol** (opcode 250, JSON `{action, data}`): client `open` / `get`; server `state` (points, account points, counts,
  categories, recent, titles, active title), then `list` in parts of 30 rows (`{i, n, d, c, p, h, u, v, t, ti, r}`; hidden
  locked rows come as "???" with no progress, title or reward), and `unlock` (the open window asks again).
- **Commands.** Character > Achievements (summary + window). Staff (`/achievements`, on yourself): `grant <id>`, `stat <key> <value>`,
  `add <key> <n>`, `reset`.
- **Tests:** `tests/achievements_test.lua` (the list, thresholds, unlocking once, hidden rows, points and account points, the
  retroactive stats, titles, the class unlock method plugged into class_unlocks_core.lua, SQL) and the client's
  `game_achievements/achievementsview_test.lua`.

**Tested in game** (test server, cropped map): retroactive unlocks at login (level 562: levels 50-500, ascension, with the
level 500 orbs; a level 1000 character: the Doombringer mount, arena 1v1 wins / rating 1200 and bounty contracts read from
the database), a live level up (level 700 + its orbs) with the toast, a legendary ambush copy (Legend Slayer, It Was a
Trap, the hidden Out of the Frying Pan, Legendary Find from its corpse), a rare kill, a Chaos Orb on the crafting bench, a
tier 1 rift sealed with Brutality / Withering / Swarm (6 achievements), a death, a bounty record and the weekly chest
storage, world boss shares for an offline character (unlocked at its next login), the window (categories, progress,
"???", recent), the title box and the title on the name plate, the class unlock method with a test config. Not tested in
game: arena and siege matches, a real world boss fight, a Treasure Goblin escape, party kills (unit-level only or not at
all).

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

## Name plates and titles (`nameplate.lua`, `nameplate_core.lua`, `titles.lua`, client `game_nameplate`, base patch 0022)

Over every player the client draws three lines, like a name plate: the **active title** (coloured by where it comes from),
the **guild** in braces (`{Ashen Covenant}`), and the **name** in gold on a small framed plate. A line that has nothing to
show is left out (no title, no guild). The health bar stays where the client always draws it, right under the name, so
players read it in the same place as on monsters; the plate is lifted 2 px so the frame does not touch the bar. Monsters
and NPCs keep the normal look. Extended opcode 248 (`ChaosOpcodes.nameplate`), `sql/chaos_nameplate.sql` (also created at
startup).

- **Titles** come from a registry: `ChaosTitles.register(source, fn)`, `fn(player)` returns the titles the player holds
  now (`{text, key?, color?, at?, frame?, priority?}`; see the head of `titles.lua`). Registering a source again replaces
  it. Sources today: `staff` (group: Tutor, Senior Tutor, Game Master, Community Manager, Administrator; red, gold
  frame, always listed first), `leaderboard` (weekly top 3, `ChaosLeaderboard.titlesOf`; gold), `champion` (Siege
  Champions while the guild holds it, `ChaosSiege.champions`; orange, crimson frame), `season` (season title rewards,
  `ChaosSeason.titlesOf`; violet), `streak` (login-streak milestone title, `ChaosDaily`; green); achievements register
  `achievement` (teal) from `achievements.lua`; arena titles have a colour (steel blue) waiting. Each source reads the
  other system's tables at call time and returns nothing while that system is not loaded, so `leaderboard.lua` and the
  rest were not edited (the leaderboard's look-text title stays).
- **Active title**: the one picked with the Achievements window (prefix and case do not matter), stored per character in
  `chaos_player_titles`; otherwise staff titles first, then the most recently earned. the Achievements window lists, No title in the Achievements window hides,
  `the Achievements window auto` goes back to the default. A picked title that is gone falls back to the default.
- **Frames**: `default` (blackened iron with ember studs) for everyone, `gold` while a staff title is active, `crimson`
  for Siege Champions, plus `violet` and `frost` unused yet. `ChaosTitles.registerFrame(source, fn)` lets the store or
  seasons hand out a cosmetic frame (`fn(player)` -> frame id), which wins over the title's frame. The images are
  16x15 9-slices from `client/tools/gen_nameplate_art.py`.
- **Traffic**: plain text, one line per player: `cid|title|RRGGBB|guild|frame` (about 40 bytes). Sent to everyone who
  sees the player (`Game.getSpectators`, all floors) at login, and the plates around to the player who logs in; the
  client asks `q|id,id,...` (batched every 250 ms, at most 40 ids) for players that appear without a plate or with one
  older than 60 s, and asks again (3 s, 4 tries) when no answer came. Every 5 s the server rebuilds the plates of the
  online players and sends only the ones that changed (new or lost title, guild joined or left, frame), so systems that
  grant titles need no hook; `ChaosNameplate.refresh(player)` sends at once.
- **Guild**: the name from the engine (`player:getGuild()`); the rank stays in the look text (the engine already says
  "He is Leader of the ..."). The engine's emblems and war colours are untouched; the guild line turns red-orange for a
  war enemy (red emblem).
- **Client**: patch `client/base-patches/0022-chaos-nameplate.patch` adds `Creature:setNameplate(guild, font, guildColor,
  nameColor, frameImage, border)` to `drawInformation` (the title line is the engine's own `setTitle`; 9 textured quads
  and one text more per player, nothing per frame in Lua). A client without the patch shows title and guild as one block
  above the name, without the frame. **The Windows client must be rebuilt with patch 0022.**

**Tests:** `server/tests/nameplate_test.lua` (title order, pick and find, colours and frames, wire format, queries, the
registry with mocked leaderboard / siege / season / login-streak tables) and `game_nameplate/nameplatemath_test.lua`
(parsing, batching, retries). Checked in game on the test server with two clients: all three lines (staff
"Administrator", guild, gold frame), a player without a title, a leaderboard title appearing live within 5 s, the guild
line disappearing live after leaving the guild, the Achievements window list / switch (Bossbane, Siege Champions with the crimson frame)
/ none / auto, the choice kept after a relog, monsters unchanged. Not checked: 30 players on screen (the drawing cost is a
few quads per player), war colours (no guild war on the test server).

## Pets (`pets.lua`, `pets_core.lua`, `pets_config.lua`, `sql/chaos_pets.sql`, client `game_pets`)

A pet is a small companion that cannot fight and cannot be fought. One is out at a time; it follows its owner, levels from
the owner's kills and has two small abilities (the first from pet level 1, the second from level 20). Client `game_pets`
(Character > Pets in the top menu), extended opcode 254 (`ChaosOpcodes.pets`), table `chaos_pets` (one row per
character and species: name, total XP, out or not, source; `sql/chaos_pets.sql`, also created at startup). Every number
is in `pets_config.lua`; the pure rules in `pets_core.lua`.

- **The creature.** The pet is a monster type of `data/monster/monsters/chaos/pets/` (registered by the installer's
  monsters step), created next to the owner and made the owner's summon, so the engine makes it follow. The types are not
  attackable, have no attacks, no loot, 40 health (below the monster tiers' minimum, and `pets.lua` puts them in
  `ChaosTierConfig.skip`), every immunity and speed 600. They are **passable** (`<flag passable="1" />`, engine patch
  `src-patches/0005-passable-pets.patch`): players (the owner and everyone else), monsters and NPCs walk through a pet and
  path through it, so a pet never blocks anyone; the pet itself still moves only to free tiles. Without the patch the
  engine warns "Unknown flag attribute: passable" for the eight types and pets block as ordinary monsters. A renamed pet
  carries its name (`Monster:rename`); its look text says whose pet it is.
- **Following.** Every 500 ms (`thinkMs`): a pet farther than 6 squares from its owner or on another floor is put next to
  it; a pet the engine removed (a long teleport) comes back next to its owner. The pet **rests** (removed with a puff,
  back by itself when the reason ends) while the owner stands in a protection zone, in a banned zone, or has another
  summon that is not a class companion. No anti-block step-aside: pets are passable for players and monsters (patch 0005).
- **Coexistence with class summons.** Beastmaster companions (`Chaos.classes.companion.monsters`) and Necromancer
  minions (`ChaosNecroConfig.minions`) count only their own monster types, so a pet never lowers their caps, and the
  pet stays out next to them. Any other summon (the stock summon spells and Convince Creature, Moonfang Pack, the base
  server's own familiars) makes the pet rest while it is out, so the stock limit of two summons and Moonfang's cap of
  four are never reduced by a pet. The base server's familiar command refuses while any summon is out, so a player
  dismisses the pet before calling a familiar.
- **Levels.** 1 to 50; XP from level L to L+1 = floor(8 x L^1.4): 8 at level 1, 200 at 10, 724 at 25, 1,859 at 49;
  736 in all to level 10, 7,180 to 25, 38,871 to 50. A kill of the owner while the pet is out (monster with experience,
  not a summon) gives 1 XP, plus 1 / 3 / 7 / 10 for a magic / rare / legendary / boss monster. A normal monster only
  counts when its experience is at least 2 x the owner's level (no farming of trivial monsters): a Dragon (700) counts up
  to level 350, a Dragon Lord (2,100) up to 1,050. At about 700 counted kills an hour, level 20 (4,149 XP) takes about 6 hours, level 50
  about 45 hours of hunting.
- **Abilities** (value at pet level 1 -> 50; L = pet level):

  | Ability | Kind | Value | Rule |
  |---|---|---|---|
  | Mend | combat | 4% -> 7.9% of max health (+0.08 per level) | below 50% health; every 30 s at most |
  | Ward | combat | 6% -> 11.9% less damage from monsters (+0.12 per level) | below 60% health, for 6 s; every 45 s at most |
  | Spark Aura | combat | owner level x 0.25 + L x 4, +/-20% (owner 300 / pet 50: about 275; owner 1000: about 450) | every 2 s, up to 3 monsters next to the pet that target the owner or are its target; dealt as the owner in the pet's element (resistances apply) |
  | Gold Sniffer | utility | +2% -> +6.9% gold coins in the corpse (+0.1 per level) | corpses the owner owns (onDropLoot index 2) |
  | Treasure Sense | utility | +1% -> +5.9% item find (+0.1 per level) | added to the item find of the Chaos loot layer (`loot.lua` `L.itemFindMult`) |
  | Fetch | utility | 3 -> 5 squares (+0.05 per level) | coins of a corpse within range of the pet go to the bank (index 2.45, after the hunt tracker's read) |

  Combat abilities pause in PvP combat (`ChaosHealing.inPvp`) and in "utility" zones; the aura never hits players or
  summons.
- **Zones** (`zones`): banned (the pet waits until the owner leaves, cannot be called there): ranked arena, guild siege,
  PvP-zone tiles. Utility only (no Mend, Ward or Aura): rifts, the world boss arena and lobby, Infinity Tower runs,
  dungeons (their own rankings). Seasons: a season character keeps its own pets; achievement pets come only from
  achievements the season character earned itself (store pets are per character anyway).
- **Species** (looks are existing outfits of our dat):

  | Species | Look | Abilities | How |
  |---|---|---|---|
  | Ember Whelp | 272 (red hatchling) | Spark Aura (fire), Ward | 1 in 2,500 kills of dragons, dragon lords and their hatchlings |
  | Frost Whelp | 283 (frost hatchling) | Ward, Spark Aura (ice) | 1 in 2,500 kills of frost dragons, frost dragon hatchlings, ice dragons |
  | Duskwing | 122 (bat) | Fetch, Gold Sniffer | 1 in 20,000 counted kills of any monster (x2 / x4 / x8 / x10 magic / rare / legendary / boss) |
  | Lantern Wisp | 294 (wisp) | Mend, Ward | Store, Pets: 400 Chaos Coins |
  | Hoarder Squirrel | 274 (squirrel) | Gold Sniffer, Treasure Sense | Store, Pets: 400 Chaos Coins |
  | Ash Cat | 276 (cat) | Fetch, Mend | Achievement Hired Blade (`bounty_25`) |
  | Gilded Goblin | 61 (goblin) | Gold Sniffer, Fetch | Achievement Greed Is Good (`goblin_10`) |
  | Riftling | 232 (lost soul) | Treasure Sense, Spark Aura (death) | Achievement Deeper Wounds (`rift_t5`) |

  A drop goes straight to the character (message, fireworks, console line). A second copy of an owned species gives that
  pet 400 XP. Achievement pets are account-wide like achievements: checked at login, when the window opens and every
  60 s. Store offers are `kind = "unlock"` with the keys of `pets_config.lua` `store`; `shop_services.lua` asks
  `ChaosPets.storeUnlock`, and an owned pet cannot be bought again (no coins taken).
- **Rules.** 5 s between summon / dismiss / switching, 30 s between renames (2-16 letters and single spaces, capitalised;
  never the name of a monster type, so a pet cannot pass for a class companion or a boss). The owner's death: the pet
  flees (dismissed) and cannot be called for 60 s (kept over a relog). Logout: XP and name are saved, the pet that was out
  comes back 2 s after the next login. XP is saved on level up, dismiss, logout, death, every 60 s and at shutdown.
- **Commands.** Character > Pets (window), `Character > Pets summon <name or species>`, `Character > Pets dismiss`, Rename (the pet that is
  out), `Character > Pets list`. Staff (`/pet`, access groups): `give <species>[, character]`, `xp <n>`, `level <n>`, `reset`, `species`.
- **Protocol** (JSON `{action, data}`): client -> server `open | get | close | summon {species} | dismiss | rename {species,
  name}`; server -> client `state` (owned pets with level, XP, abilities and their unlock state, the catalogue with how to
  get each species, the active pet, out / resting text, zone rule, cooldowns) and `xp` (after a kill while the window is
  open).
- **Shared-file lines.** `chaos_constants.lua` (`pets = 254`), `loot.lua` (one line in `L.itemFindMult`),
  `shop_services.lua` (`unlockEntry` asks `ChaosPets.storeUnlock`), `shop.lua` (an unlock offer with `look` shows that
  outfit), `shop_config.lua` (category "Pets").
- **Tests:** `tests/pets_test.lua` (config sanity, the curve numbers above, kill XP, ability values and unlocks, zone rules,
  drops with a seeded run, names, cooldowns, gold, rest reasons, the window view, every pet monster file passable and not
  attackable) and
  `game_pets/petsview_test.lua` (list, texts, buttons).
- **Tested in game** (test server with the scripts of this repo, one client): staff give; summon from the window (the pet
  follows); rename (`Character > Pets rename`) shown over the pet; kill XP (Dragon Lords and Heroes count at level 500, Dragons do
  not) with the window's XP bar updating live; Spark Aura hitting Heroes next to the pet (about 100-115 each 2 s at owner
  500 / pet 1; Dragon Lords take nothing from the fire aura, they are immune); Mend (+475 at pet level 21, 8,496 max
  health) and Ward (a fixed 1,000 hit: 860 without, 787 with ward 8.4%); forced drops (a new Frost Whelp from a Frost
  Dragon, a Duskwing from a Hero, a duplicate Ember Whelp -> +400 XP); Fetch (coins to the bank with a message) and Gold
  Sniffer (with the value raised to 102% for the test: 40 coins in the corpse -> 81 fetched); rest while a non-class
  summon is out and back after it; banned zone (arena check forced on): pet sent home and "Pets are not allowed here (the
  arena)"; leash after a teleport; owner death: pet gone, "still recovering from your death: 34 s" after the respawn;
  store purchase (400 coins taken, pet owned, second purchase refused); achievement pet (Ash Cat after `bounty_25`);
  logout and server restart: name, XP and the pet that was out come back. Passable (server built from the base source
  with patches 0001-0005, two clients): the owner steps onto the pet's tile in all 8 directions, and so does a second
  player; right after a teleport and return with the pet on the east tile, 5 of 5 steps east go through; a Fire
  Elemental and a Dragon Lord (pushes creatures) in a 1-wide corridor path through the pet (the path is computed through
  its tile), share its tile for a step and reach the owner at the dead end, the pet untouched; following and the leash
  still work; attacking the pet from either client is refused. **Not tested in game:** the protection-zone
  rest (the test map has no protection-zone tile; same code path as the other rests), PvP
  pause, the rift / tower / world boss / dungeon utility rule. The stock loot message ("Loot of ...") is
  written before Fetch runs, so it still lists the coins the pet carried to the bank.

## Bestiary and kill tasks (`bestiary.lua`, `bestiary_core.lua`, `bestiary_config.lua`, `bestiary_spawns.lua`, client `game_bestiary`)

A bestiary entry for every monster the server knows, unlocked by kills, plus personal kill tasks and a task tracker HUD.
Client `game_bestiary` (Hunt > Bestiary / Kill Tasks / Task Tracker in the top menu, Hunt > Bestiary, Hunt > Kill Tasks),
extended opcode 253 (`ChaosOpcodes.bestiary`), tables `chaos_bestiary` (kills per character and monster) and
`chaos_bestiary_tasks` (accepted and finished tasks) in `sql/chaos_bestiary.sql` (also created at startup), storages
7100870-7100879 (`Chaos.storage.bestiary`: +0 task points, +1 / +2 the day and level of the day's board). Every number
is in `bestiary_config.lua`; the pure rules in `bestiary_core.lua`.

- **The catalogue** is built at startup from every name in `monster/monsters.xml` plus the Lua-registered types
  (`MonsterType(name)` loads each one: this engine loads monster files on first use, so `Game.getMonsterTypes()` alone
  lists only those already spawned). Left out: experience below 1, no outfit, `excludeNames` / `excludePatterns`
  (dummies, spell summons). When two registered names show the same name (the quest copy "Demon (Goblin)" is called
  "Demon"), the type registered under that name wins. On the test server: 1,396 entries. Loading every monster at
  startup also prints the base server's broken `monsters.xml` lines once (missing files such as Charger, Vexclaw).
- **Categories:** Bosses (boss flag), Chaos (defined under `monsters/chaos/`), then by the words of the name from the last
  one (the head noun: "Giant Spider" is vermin, "Frost Dragon" a dragon) against the category word lists (`word*` prefix,
  `*word` suffix), else by race (undead, fire / energy -> Elementals, venom -> Insects & Arachnids), else Other. 18
  categories.
- **Difficulty and stages.** The estimated hunting level is the bounty pool's (`<level min max>` middle, else
  1.6 x sqrt(experience), raised by health), capped at 1500. Kills for stage 1 Discovered / 2 Studied / 3 Mastered /
  4 Completed and the bestiary points of each stage:

  | Difficulty | Level | Kills | Points | Completion bonus |
  |---|---|---|---|---|
  | Harmless | up to 14 | 1 / 10 / 50 / 250 | 1 / 1 / 2 / 4 | +1% damage, +1% experience |
  | Easy | 15-49 | 1 / 25 / 100 / 500 | 1 / 2 / 3 / 6 | +1% / +1% |
  | Medium | 50-149 | 1 / 25 / 250 / 1000 | 2 / 3 / 5 / 10 | +2% / +2% |
  | Hard | 150-399 | 1 / 25 / 200 / 800 | 2 / 4 / 6 / 12 | +2% / +2% |
  | Challenging | 400-799 | 1 / 20 / 150 / 600 | 3 / 5 / 8 / 15 | +3% / +3% |
  | Deadly | 800+ | 1 / 15 / 100 / 400 | 3 / 6 / 10 / 20 | +3% / +3% |
  | Boss | boss flag | 1 / 2 / 3 / 5 | 5 / 5 / 10 / 20 | +3% / +3% |

  Monsters with 1-5 spawn entries on the map (`bestiary_spawns.lua`) need x0.2 of the kills (at least the stage number).
  Stage 1 shows the outfit, level, health and experience; 2 the elements (as damage taken), immunities, where it lives
  (the 3 busiest 160x160 squares of its spawns, named after the nearest temple, with the depth) and the 4 rarest loot
  items; 3 the whole loot (40 at most, with chances) and the Chaos uniques that list the monster (`ChaosLoot.uniqueList`);
  4 activates the bonus. The bonus: damage through a healthchange event on the monster (registered from
  `onTargetCombat`, like `item_mods.lua`), experience through `onGainExperience` (needs the experience dispatch of
  `tools/patch_base_events.py`).
- **Ranks.** Bestiary points (stages + kill tasks) give a rank with experience from every monster: Novice 0, Tracker 100
  (+0.5%), Hunter 300 (+1%), Slayer 750 (+1.5%), Lorekeeper 1500 (+2%), Bestiarch 3000 (+2.5%), Monster Sage 6000 (+3%).
- **Kills.** A death event on every monster without a master (EventCallback `onSpawn`); the last hit and the most damage
  (summons count for their master) and their party members within 30 tiles on the same floor (`ChaosBounty.credit`) each
  get the kill once. Kills are kept in memory and written every 120 s, at a new stage and at logout.
- **Kill tasks.** A hunt task (kill N of one monster) comes from the daily board or from a discovered entry whose level is
  in the character's take window (0.4 x level to 1.5 x level + 20; up to level 30 anything below that). A family task
  (kill N of a category within a level window) only from the board. The board: 3 hunts and 3 families from monsters that
  spawn in the board window (0.6 x level to 1.25 x level + 10), seeded by task day and character, rolled for the level
  of the character's first look that day. Kills needed: harmless 100, easy / medium 150, hard 120, challenging 100,
  deadly 80 (half, rounded to 5, for monsters with fewer than 20 spawn entries); families 1.8 x the hunt count of the
  window's middle level. Limits: 3 at once, 4 completed a day, 20 a week (done + held; the task day starts at 06:00 like
  the bounty board, the week on Monday). No expiry: a task stays until done or abandoned; progress is written every
  10 kills, at the milestones (25/50/75%) and at logout.
- **Rewards** (paid at once; gold to the bank, orbs to the backpack or the inbox): a share of the bounty board's hunt
  reward of the band of min(task level, character level) (`bounty_config.lua` bands): hunt 40% gold, 50% Chaos Orbs, 1.5%
  of a level's experience, 5 x the difficulty's stage-1 points; family 60% gold, 75% Chaos, 50% Divine, 2% experience,
  8 x points. So: level 120, hunt 20k gold, 1 Chaos Orb, 10.7k experience, 10 points; family 30k, 1 Chaos, 14.3k, 16
  points; band 800+: hunt 800k, 3 Chaos; family 1.2M, 4 Chaos, 1 Divine. Four a day pay at most 4.8M gold at 800+,
  against 24M for the twelve bounty contracts of a day. Multi-client: as the bounty board, a task that got a kill while
  multi-clienting pays nothing (`mcReward = false`).
- **Bounty board split.** The bounty board (`bounty.lua`) stays the shared daily board per level band with the big
  rewards and the weekly chest. Kill tasks are personal, longer-lived, smaller and pay bestiary points; a kill counts for
  both. Nothing in `bounty.lua` was changed: `bestiary.lua` wraps `ChaosBounty.sendBoard` (accept, abandon, completion)
  and `ChaosBounty.onKill` at runtime to refresh the tracker, and reads `ChaosBounty.players` for the tracker rows.
- **Task tracker HUD**: kill tasks (T), then the active bounty contracts (B), 8 rows at most, pushed after every change
  (one push per player per 150 ms). Client side it sits at the bottom right of the visible map: left of the right side
  panels, above the chat (the rift / invasion HUDs are top left, siege / arena / monster bar top centre, toasts top right,
  monk chi bottom centre).
- **Achievements** (guarded `ChaosAchievements.set` / `.progress`): `bestiary_known`, `bestiary_completed`,
  `bestiary_points`, `bestiary_tasks`; 4 entries in the Monsters category (Field Notes, Know Thy Enemy, Monster Scholar
  with the title Lorekeeper, Exterminator with its title).
- **Protocol** (opcode 253, JSON `{action, data}`): client `open | summary | list | entry {id} | board | take {id} |
  accept {key} | abandon {key} | query`; server `summary` (totals, categories, rank, limits), `list` (rows `[id, name,
  category, difficulty, level, kills, stage, lookType]` in parts of about 6.5 KB, one per 50 ms), `entry` (what the stage
  reveals, the task offer), `kill` (one entry's kills and stage after each kill), `board`, `tracker`, `show {tab}`.
- **Spawn data:** `bestiary_spawns.lua` is generated by `python3 -I server/tools/gen_bestiary_spawns.py <server>/data` from
  the loaded map's spawn file (871 names from the full map in the repo). Rerun it after spawn changes, with
  `gen_bounty_pool.py`.
- **Shared-file lines.** `chaos_constants.lua` (`bestiary = 253`, `Chaos.storage.bestiary`), `achievements_data.lua` (4
  entries and the stats comment), client `client_chaos_topbar` (3 Hunt entries), `game_chaosnotify` (toast type
  `BESTIARY`, action `bestiary`), `docs/tools/gen_readme_art.py` (the README card).
- **Tests:** `tests/bestiary_test.lua` (config sanity, levels, difficulties, thresholds with few spawns, stages and points,
  ranks, categories, the catalogue and summary, task windows, the seeded board, matching, party credit, milestones, the
  accept limits, rewards against the bounty bands, views, packets, the spawn data) and the client's
  `game_bestiary/bestiaryview_test.lua`.
- **Tested in game** (test server with the scripts of this repo, cropped map, monsters created next to the character,
  one client): discovery and stage messages and toasts, the window (categories, search, pages, an undiscovered, a studied
  and a completed entry with elements, areas and loot icons), the board, accepting hunt and family tasks, progress on the
  tracker with every kill, completion (20,000 gold to the bank, 1 Chaos Orb, 10,711 experience = 1.5% at level 120, 10
  points), the active cap and the daily limit (Accept greyed with the reason; a forced accept refused), progress kept
  over relog and restart, bounty contracts on the tracker and gone when completed, the completion bonus (a dragon: 45,601
  experience with the bonus, 45,150 without, x1.01; 360 holy damage -> 363) and the damage event registered by real melee,
  the achievement counters. **Not tested in game:** party credit with two players (unit-tested), the 06:00 day change and
  the weekly limit (unit-tested), multi-client tasks.

## Pack items and monsters (`tools/install_pack_items.py`, `data/lib/chaos_pack_items.lua`, `scripts/chaos/pack_items.lua`)

Art from the October 2026 art sets, converted to our 32 px format once and kept in `client/tools/sprites/art_import/`
(atlases + `things.csv`); `client/tools/sprites/import_art_things.py` appends it to the client pair (client/MANIFEST.md
"Pack items and monsters") and writes `data/items/art_items.csv` (items) and `data/items/art_outfits.csv` (outfits).

- Ids: client items 33000-33650 (the importer pads the item list up to 32999 with blank entries, so the ids do not move
  when other tools append items first), server id = client id + 3000 (36010-36650); outfits 2000-2038 (padded the same
  way). Clear of the base items (up to 29926), dark tiles (30484-30557), gems (32001-32035) and donor items (40000-40111).
- Install: step `packitems` of `install_all.py` (`python3 -I server/tools/install_pack_items.py DATA_DIR [--dry-run]`):
  items.otb nodes and an items.xml block for the new items, the new looks, and the creature products in Yasir's
  `shop_sellable` list (`data/npc/Yasir.xml`, at the prices of the manifest). Idempotent. After a change of the manifest:
  `install_pack_items.py --lua` rewrites `data/lib/chaos_pack_items.lua`.
- New looks (mode `replace`: only the client id of the existing items.otb node changes, names and scripts stay): Orb of
  Alchemy 24691, Orb of Annulment 24697, Orb of Scouring 24688 (they were plain rune stones), and the seven ore pieces of
  the mining profession 26398-26404 (they were small dots).
- Creature products 36010-36036 (27, stackable, loot of the new monsters, sold to Yasir for 8-120 gold) and food
  36037-36060 (24, eaten like the stock food by `pack_items.lua`: food x 12 s of regeneration, "You are full" at 1200 s).
- Corpses 36061-36099: one per new monster, the creature's last death frame with its colours, a container of 20 that
  disappears after 10 minutes.
- Environment for the map editor: 100 trees and 100 stumps (36100-36299, tree and stump of the same species next to each
  other, blocking, 2x2 or 3x2), 12 grounds each followed by its 12 border pieces (36300-36455; see docs/MAP_GUIDE.md),
  8 animated water grounds (36456-36463; deep, lagoon, murky and mountain lake are not walkable, the four shallows are,
  speed 250), 6 animated shore sets (36464-36577, border pieces that go on the water tile), 49 lake objects (36578-36626,
  reeds and rocks block, pads and plants under water do not) and 24 dock props (36627-36650).
- Monsters (`data/monster/monsters/chaos/goblins/`, `wildwood/`, registered by the `monsters` step): 15 goblins (Goblin
  Grunt to Goblin Chieftain, hunting levels 15-80) and 24 forest creatures (Forest Wolf to Ancient Treant, 10-140), each
  on its own outfit (2000-2038: idle and walking animation, 4 directions, colour mask; small ones 2x2, large ones 3x3 or
  4x4) with palette colours set in the XML. Loot: gold, their creature products and food, potions from hunting level 25,
  stock weapons for goblins. Bosses with summons: Goblin Chieftain (Goblin Grunts), Mushroom King (Shroomlings), Ancient
  Treant (Treant Saplings). They are not in a spawn file yet; they come with the two new invasion factions
  (`invasion_config.lua`): Goblin Tribe (boss Goblin Chieftain) and Wildwood Uprising (bosses Mushroom King, Ancient Treant).
- Cunning Hyaena (late game, wrong art before) uses the Forest Wolf outfit 2015 in sand colours.
- Tested in game (test server, client with the appended pair): every new monster spawned and drawn in all directions,
  kills leave the new corpse with loot (Goblin Chieftain, Goblin Grunt, Mushroom King, Forest Wolf, Owlbear, Myconid
  Shaman), food eaten ("Yum."), the orb and ore looks in the backpack, grounds with borders, waters with shores, lake
  objects, docks, trees and stumps placed on runtime tiles. Not tested: an invasion of the new factions (the cropped test
  map has no valid town area; `tests/invasion_test.lua` passes with them), selling to Yasir (he is not on the test map).
