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

Estimated today: ~155 h to level 1000 for a sorcerer, ~285 h for a knight or paladin, and 80% of it is spent between 700 and 1000.

| # | Item | Status | Notes |
|---|---|---|---|
| 4 | Spawn the level-scaled Chaos monsters on the map that is actually loaded | todo | They are registered in monsters.xml but only spawn in `newcity-spawn.xml`, which belongs to a map that is not loaded. `server/data/monster/CUSTOM_MONSTERS.md` wrongly says they spawn |
| 5 | Smooth the experience stage curve after level 700 | todo | `config.lua` stages: x15 at 700 drops to x3 from 851 |
| 6 | Fix the waystone "Experience" character upgrade (and its siblings Loot and Rarity) | done | all three only wrote a storage nothing read; now applied (`waystone_bonuses.lua`, `tools/patch_base_events.py`) |
| 7 | Monster level bonus roll bug | done (kept as is) | `src/monster.cpp:52` uses `\|\|`, so only the first branch runs: a plain uniform roll between min and max level. The other branches would skew 80% of monsters to the top of their range and compute negative ranges for narrow level spans, so the current uniform behaviour is kept on purpose |

## Then: class rework (design agreed, see `docs/CLASSES.md`)

| # | Item | Status | Notes |
|---|---|---|---|
| C1 | Vocations: 4 base classes (Warrior, Ranger, Mystic, Thief), each with 2 ascended choices; scripted ascension | in progress (Thief first) | migration of existing characters as in `docs/CLASSES.md` |
| C2 | Thief, Ninja and Samurai: kit, shurikens, stealth, scripted dual wield, counters | in progress | the only fully new class |
| C3 | Rework the existing kits into Juggernaut/Berserker, Deadeye/Beastmaster, Elementalist/Illusionist (support) | todo | reuses today's spells and the new keystones |
| C4 | Passive trees, spell icons, effects and outfits per class; balance at levels 300 and 1000 | todo | |
| C5 | Necromancer as a fifth class (summoner) | todo | after the first eight are balanced |

## Then: endgame loops

| # | Item | Status | Notes |
|---|---|---|---|
| 8 | Rifts / map devices: consumable keys open a timed instance with random modifiers; higher tiers drop better keys | todo | reuse the dungeon instance code and the monster tiers |
| 9 | Paragon track for leftover passive points ("option 2") | in progress | small infinite bonuses once the tree budget is spent |
| 10 | Bounty board: daily rotating "kill X in Y" contracts paying orbs | in progress | cheap content that spreads players over the map |
| 11 | Crafting orbs: add-a-modifier and remove-a-modifier orbs next to Chaos/Divine, plus a crafting bench | todo | item modifier code in `server/data/lib` |
| 12 | Seasons / ladders: fresh-start season characters, season uniques, per-vocation highscores, cosmetic carry-over | todo | |

## Then: social and replay

| # | Item | Status | Notes |
|---|---|---|---|
| 13 | Weekly world-boss damage leaderboard with titles | todo | damage share is already tracked in `worldboss.lua` |
| 14 | Arena 1v1 / 2v2 with ratings | todo | PvP rules and multi-client blocks already exist |
| 15 | Scheduled guild wars / guild-hall siege | todo | |

## Then: quality of life

| # | Item | Status | Notes |
|---|---|---|---|
| 16 | Loot filter: hide or highlight items by rarity (autoloot and corpses) | todo | |
| 17 | In-client hunt tracker: exp/h and profit/h | todo | |
| 18 | Build sharing: export/import a passive tree code | todo | |
| 19 | Respec cost that scales with level | todo | decide together with the store's respec token (item 1) |

## Then: polish and retention

| # | Item | Status | Notes |
|---|---|---|---|
| 20 | Login streaks tied to the daily reward | todo | `chaos/daily.lua` |
| 21 | New-player kit per vocation | todo | |
| 22 | Tutorial island: passive tree, orbs, keystones | todo | needs map work |
| 23 | Weekly patch-notes window in the client | todo | |

## Open decisions and loose ends

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
