# Project Chaos roadmap

Priority order agreed with the project owner. Update the status here when something is started or done.
Status: `todo`, `in progress`, `done`.

## Now (in progress)

| # | Item | Status | Notes |
|---|---|---|---|
| 1 | Store additions: stamina refill, temple teleport, bottomless loot pouch, auto seller, training weapons, world buffs, name change, vocation change, extras (double exp potion, blessings, frag/skull removal, sex change, respec) | done | `server/data/scripts/chaos/shop*.lua` |
| 2 | Passive tree keystones per vocation (knight Cleaving Arc, paladin Ricochet, sorcerer Arcane Echo, druid Overgrowth, illusionist support) | done | measured on the test dummies so the role order holds |
| 3 | Combat visuals: elemental weapon damage as its own coloured number + element sprite; crit, dodge and reflect sprites | done | server module `ChaosCombatFx` |

## Next: fix the late game (players hit a wall after level ~500)

Estimated before items 4 and 5: ~155 h to level 1000 for a sorcerer, ~285 h for a knight or paladin, and 80% of it is spent between 700 and 1000.

| # | Item | Status | Notes |
|---|---|---|---|
| 4 | Spawn the level-scaled Chaos monsters on the map that is actually loaded | done | 17 of them (levels 650-1000, retuned health/speed/damage/exp, weak to physical and holy) replace 268 of the weaker spawns in four level 500+ areas (Darklight Core, Jaded Roots, Gloom Pillars, Putrefactory): `server/tools/late_game.py` + `late_game_spawns.csv`, README "Late game" |
| 5 | Smooth the experience stage curve after level 700 | done | x15 to 800, x14 to 900, x13 after (was 12/9/6/3; the last stage had no maxlevel, which this engine reads as 0, so 851+ really got rateExp x5). Model: sorcerer ~96 h, knight ~154 h, paladin ~140 h to 1000 (was ~138/257/252 h with the x5 bug, ~154/286/281 h as written) |
| 6 | Fix the waystone "Experience" character upgrade (and its siblings Loot and Rarity) | done | all three only wrote a storage nothing read; now applied (`waystone_bonuses.lua`, `tools/patch_base_events.py`) |
| 7 | Monster level bonus roll bug | done (kept as is) | `src/monster.cpp:52` uses `\|\|`, so only the first branch runs: a plain uniform roll between min and max level. The other branches would skew 80% of monsters to the top of their range and compute negative ranges for narrow level spans, so the current uniform behaviour is kept on purpose |

## Then: class rework (design agreed, see `docs/CLASSES.md`)

| # | Item | Status | Notes |
|---|---|---|---|
| C1 | Vocations: 4 base classes (Warrior, Ranger, Mystic, Thief), each with 2 ascended choices; scripted ascension | done | phase 1: framework (`!ascend`, `server/tools/add_vocations.py`, client ids, store change) with the Thief line; phase 2a: Warrior / Ranger / Mystic and their ascended classes (ids in `docs/CLASSES.md`), one-time migration of existing characters with a free switch to Berserker / Beastmaster (`class_migration.lua`), client names (base patch 0016) |
| C2 | Thief, Ninja and Samurai: kit, shurikens, stealth, scripted dual wield, counters | in progress | kit done: 9 spells, measured at levels 300 / 1000 (`server/data/spells/README.md`); passive tree, healing and gear open (`docs/CLASSES.md`) |
| C3 | Rework the existing kits into Juggernaut/Berserker, Deadeye/Beastmaster, Elementalist/Illusionist (support) | in progress | phase 2a done: kits reassigned (Chaos and stock spells, weapons, equipment, potions), Berserker Rage + Skyfall Cleave + Bloodrage, Beastmaster companion + Wild Bond + Feral Command, sanity-measured at level 1000 (`server/data/spells/README.md`, "Classes"); phase 2b: full rebalance with passive trees, starting kits and outfits |
| C4 | Passive trees, spell icons, effects and outfits per class; balance at levels 300 and 1000 | todo | |
| C5 | Necromancer as a fifth class (summoner) | in progress | ascensions Lich (curses, damage over time, corpse explosion) and Bone Lord (the army); built in new files, joined to the class framework after C1-C3 phase 2 lands |
| C6 | Monk as a sixth class: fists, chi / combo points; ascensions Shadowfist (single-target burst) and Iron Sage (bruiser, party chi shield) | in progress | built in new files like C5, joined to the class framework after phase 2 lands |
| C7 | Templar as a seventh class: holy melee with a party defence aura; ascensions Inquisitor (holy area damage) and Sentinel (tank-support, party aura, Lay on Hands) | in progress | built in new files like C5/C6 |
| C8 | Lock the Necromancer, Monk and Templar behind a store unlock (account-wide) | in progress | `class_unlocks.lua`; 750 coins each as a placeholder; the unlock method is pluggable: the owner will decide the final way to unlock them |

## Then: endgame loops

| # | Item | Status | Notes |
|---|---|---|---|
| 8 | Rifts / map devices: consumable keys open a timed instance with random modifiers; higher tiers drop better keys | done | `chaos/rift*.lua`, client `game_rift`: Rift Keys (tier 1-15, 1-3 of 8 modifiers), instances built at runtime in a 16-slot grid, bounty-pool packs with monster tiers, a guardian at 75%, 10 minutes, reward chest, next-tier keys, an experience cap at the leveling model's rate, crash refund; see server/README.md "Rifts". A real party not tested |
| 9 | Paragon track for leftover passive points ("option 2") | done | `chaos/paragon.lua`, client `game_passivetree/paragon*`: 1 point per level above 1000, four categories of small capped stats added on top of the tree's bonuses; reset level x 250 gold or the store reset; see server/README.md "Paragon" |
| 10 | Bounty board: daily rotating "kill X in Y" contracts paying orbs | done | `chaos/bounty*.lua`, client `game_bounty`, pool from `server/tools/gen_bounty_pool.py` (rerun after spawn changes); see server/README.md "Bounty board". Party credit not tested with two real players |
| 11 | Crafting orbs: add-a-modifier and remove-a-modifier orbs next to Chaos/Divine, plus a crafting bench | done | `data/lib/chaos_crafting.lua` (Exalted, Annulment, Scouring, Transmutation, Alchemy; Chaos/Divine on the bench), bench `chaos/crafting.lua` + client `game_crafting` (`!craft`, Chaos -> Crafting Bench), installer `tools/install_crafting.py`; see server/README.md "Crafting". No Vaal-style orb. Weekly bounty chest extras not tested in game |
| 12 | Seasons / ladders: fresh-start season characters, season uniques, per-vocation highscores, cosmetic carry-over | in progress | per-vocation highscores done: the all-time Class Ladder of the leaderboards (item 13); seasons being built (season characters, isolation, season ladder, season uniques, reward track, end-of-season migration) |
| 24 | Treasure goblins: a very rare cowardly monster that flees, blinks and escapes, and drops a hoard when killed in time | done | `chaos/treasure_goblin*.lua`, `monsters/chaos/treasure_goblin.xml`: replaces 1 in 3000 natural respawns (no bosses, instances, protection zones; per-area cooldown), scaled to the area level; gold, Chaos/Divine Orbs, 2-4 rarity-rolled items and a raised unique chance through the Chaos loot layer; guarded hooks for loot rays and a "goblin" leaderboard; see server/README.md "Treasure goblins" |

## Then: social and replay

| # | Item | Status | Notes |
|---|---|---|---|
| 13 | Weekly world-boss damage leaderboard with titles | done | `chaos/leaderboard*.lua`, client `game_leaderboard` (`!leaderboard`, Chaos -> Leaderboards): weekly World Boss, Bounty Hunter and Rifts boards (Monday 06:00 reset; top 3 get a title in the look text and orbs to the inbox), all-time Class Ladder; rift scripts report with `ChaosLeaderboard.record("rift", player, tier)`; see server/README.md "Leaderboards" |
| 14 | Arena 1v1 / 2v2 with ratings | done | `arena.lua` / `arena_core.lua` / `arena_config.lua`, client `game_arena`: queue by rating window and level band (lowest level >= 80% of the highest), runtime instances, no death / skull / frag inside, Elo per mode in `chaos_arena_ratings`, history, orbs for wins and the daily first win (server/README.md "Arena"). 1v1 tested in game with two clients; 2v2 and parallel slots on the mocked engine. Seasonal resets later |
| 15 | Scheduled guild wars / guild-hall siege | done | Weekly Guild Siege (`siege.lua`, client `game_siege`): sign-ups by leader/vice (`!siege join`), runtime arena with the Chaos Obelisk and a base per guild (up to 4 per arena, 3 arenas), no real deaths (downed, back to base), kills + obelisk points, rewards, "Siege Champions" title and +5% exp for a week; tested in game with two clients. The base server's guild wars have no in-game declare/accept (website only, read at login); out of scope |

## Then: quality of life

| # | Item | Status | Notes |
|---|---|---|---|
| 16 | Loot filter: hide or highlight items by rarity (autoloot and corpses); loot channel with clickable item icons (greyed out once looted); rarity autoloot as a store unlock; loot rays for uniques and Legendary+ | done | `chaos/lootfilter*.lua`, client `game_lootfilter` (`!lootfilter`, Hunt -> Loot Filter, opcode 238): glow / dim by rarity and category in corpses (dimmed, never hidden), presets, settings per character; the Loot tab shows a row of item icons per kill (click to loot, Shift = one; greyed when autolooted, looted or decayed); coloured rare-drop lines; Rarity Autoloot (store, 400 coins); loot rays 424..428 for uniques and Legendary+; tested in game; see server/README.md "Loot filter". Party members do not get rows or rays |
| 17 | In-client hunt tracker: exp/h and profit/h | in progress | |
| 18 | Build sharing: export/import a passive tree code | done | `buildshare.lua`, `buildshare_core.lua`: versioned checksummed code (`CB1-...`, stable node ids), Build Code panel with tree preview, `!build`; short on points = first N nodes in path order; taking points back costs the full reset price. Tested in game |
| 19 | Respec cost that scales with level | done | `respec.lua`, `respec_config.lua`: full reset ~37.5 min of hunting gold (225k at 100, 3.95M at 600, 5.95M at 1000), right-click single-node refund ~1.5 min, free below 50 and once after a class change; income measured with `tools/respec_income.py` (README "Respec") |

## Then: polish and retention

| # | Item | Status | Notes |
|---|---|---|---|
| 20 | Login streaks tied to the daily reward | in progress | `chaos/daily.lua`; with the hunt tracker (item 17): streak counter, milestones, grace days, account-wide claims |
| 21 | New-player kit per vocation | done | `chaos/newplayer*.lua`: kit per class (Warrior / Ranger / Mystic / Thief ids), welcome window + toast, gifts at 20/50/100/200, `/newplayerkit`; tested in game |
| 22 | Tutorial island: passive tree, orbs, keystones | done | `chaos/newplayer_tutorial.lua`: island built at runtime (no map work), 5 stations, skip, resume; tested in game |
| 23 | Weekly patch-notes window in the client | in progress | |

## Open decisions and loose ends

- Fixed: opening the passive tree window with a large build no longer gets players kicked. The window rebuilt
  ~1,400 widgets four times (a 2-4 s freeze); now built once and in slices. Remaining cause, not fixed: the base
  client's healing helper (`mods/game_helper/helper.lua`) replays every missed 50 ms cycle after any client stall
  and can still flood spell casts (packet-limit kick) after other long frames; needs a base patch.
- Notification toasts (`game_chaosnotify`) have no background: the code loads `images/background`, the file is
  `Background.png`. The Daily Reward window also opens over other windows at login.
- Re-measure the weapon (auto-attack) numbers in `server/data/spells/README.md`: the balance harness sets the
  target with `setTarget`, which skips `onTargetCombat`, so the passive tree and weapon-style damage events were
  never put on the dummies in those runs (two-handed x1.6, dexterity, keystones). Spell numbers are not affected.
- Keystones not verified in game yet: Overgrowth, both Illusionist keystones (need a party), arrow Ricochet, and
  the visuals of Bulwark/Thorns/Deadeye (`ChaosCombatFx`).
- Bug (existing): the rarity element script (`data/scripts/customs/rarity/rarity_onCombat_elementdamage.lua`,
  base server) returns nothing when a player wears two different rarity elements, which zeroes the damage.
- Bug (existing): `/testkit` (`admin/testkit.lua`) calls `addHealth(n)`, which does nothing on this engine
  (it takes a damage type first), so health is not refilled.
- Note: the engine only runs `onTargetCombat` for weapon hits after the player clicks to attack; targets set
  from Lua skip it, and with it the rarity, passive tree and combat feedback damage events.
- The Windows server binary has no `server/src-patches/` applied: no "CRIT!" visual there until it is rebuilt.
- Illusionist: decided, a support class (party attack buffs and some healing), the Mystic's second ascension.
- Community (Discord) invite link: `ChaosTopBar.COMMUNITY_URL` in `client/overlay/modules/client_chaos_topbar/chaos_topbar.lua` is empty until there is one.
- Optional: swap the client's xBRZ for version 1.8 (fixes artifacts on transparent sprite edges; same GPL-3 license; needs testing).
- The base server also has its own world-boss timer (`data/scripts/customs/worldbosses/`), separate from the Chaos world bosses; decide whether to keep both.
