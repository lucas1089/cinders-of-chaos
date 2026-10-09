# Chaos unique items

48 unique/legendary items. Each one is a **normal copy of an existing base item** that gets its own name, description
and stats as item attributes when it drops or is given (`ChaosMakeUnique`). `items.xml` is not touched.

Why not override `items.xml`: a first run of the server showed that 28 of the 48 base items are found **by their stock name**
by stock monsters, NPC shops and scripts ("alicorn headguard", "makeshift boots", "ghost chestplate"...). Renaming those ids
made 15 boss loot tables fail to load. With per-copy attributes the stock items keep working and only the dropped copies
are unique.

| file | purpose |
| --- | --- |
| `data/items/chaos_items.xml` | source data for the 48 uniques (base id, name, description, stats); not installed into items.xml |
| `data/lib/chaos_unique_specs.lua` | generated from the XML by `tools/gen_unique_specs.py`: what `ChaosMakeUnique` applies |
| `data/lib/chaos_unique_items.lua` | `ChaosUniqueItems` (drop table for `loot.lua`), `ChaosMakeUnique`, `ChaosGiveUnique`, documented `ChaosSets` |
| `data/items/chaos_items_sheet.jpg` | contact sheet: sprite, name, slot, level, id, tier |

How the stats are applied: attack, defense, extra defense, armor, hit chance and range as item attributes; skills, magic
level, critical hit, leech and absorbs as the custom attributes the stock rarity scripts already apply on equip. Max health,
max mana, speed, regeneration, element damage and attack speed cannot be stored per item in this engine, so they were
dropped (listed as `skipped` in `chaos_unique_specs.lua`).

## Install

1. Copy `data/lib/chaos_unique_items.lua` and `data/lib/chaos_unique_specs.lua` into the server's `data/lib/` and add
   `dofile('data/lib/chaos_unique_items.lua')` at the end of `data/lib/lib.lua`.
2. After editing `chaos_items.xml`, regenerate the specs: `python3 -I tools/gen_unique_specs.py`.
3. Test: `ChaosGiveUnique(player, "Soulreaper")` from a talkaction, or check drops with `print(ChaosLootReport("Demon", "legendary", 10000))`.

## Items

Columns: server id / client id, the stock item that was overridden, required level (see caveats), drop tier (`minTier`), key stats.

| name | slot | id (server/client) | stock item | level | tier | key stats |
| --- | --- | --- | --- | --- | --- | --- |
| Widowmaker | sword | 22690 / 20341 | light rapier | 40 | magic | Atk 24, Def 12, criticalHitChance 3, criticalHitAmount 15 |
| Nightfang Katana | sword | 2412 / 3300 | katana | 60 | magic | Atk 32, Def 16, skillSword 2, criticalHitChance 4, criticalHitAmount 20 |
| Gorecleaver | sword | 11426 / 6101 | the Ron the Ripper's sabre | 70 | rare | Atk 36, Def 18, lifeLeechChance 5, lifeLeechAmount 5 |
| Bloodmoon Edge | sword | 11395 / 860 | crimson sword | 90 | rare | Atk 44, Def 22, skillSword 3, criticalHitChance 5, criticalHitAmount 25 |
| Soulreaper | sword | 8209 / 7385 | crimson sword | 120 | legendary | Atk 52, Def 28, skillSword 4, lifeLeechChance 10, lifeLeechAmount 8 |
| Executioner's Reckoning | axe | 2440 / 3328 | daramian waraxe | 80 | rare | Atk 50, Def 18, skillAxe 3, criticalHitChance 7, criticalHitAmount 30 |
| Harvester of Sorrows | axe | 10301 / 9384 | scythe of the reaper | 100 | legendary | Atk 50, Def 14, elementDeath 22, skillAxe 4, manaLeechChance 7, manaLeechAmount 6 |
| Cinderbrand Axe | axe | 8925 / 8097 | solar axe | 130 | boss | Atk 58, Def 30, elementFire 24, skillAxe 5, absorbPercentFire 10 |
| Lichfang Staff | club | 3961 / 3343 | lich staff | 70 | magic | Atk 36, Def 30, elementDeath 14, magicPoints 2, skillClub 2 |
| Bonegrinder | club | 7379 / 7379 | brutetamer's staff | 90 | rare | Atk 58, Def 18, skillClub 5, criticalHitChance 5, criticalHitAmount 25 |
| Gorehammer | club | 23590 / 21219 | one hit wonder | 100 | rare | Atk 66, Def 20, criticalHitChance 8, criticalHitAmount 30 |
| Mawmaker | club | 25418 / 22762 | maimer | 110 | legendary | Atk 62, Def 30, skillClub 4, lifeLeechChance 7, lifeLeechAmount 6 |
| Hellspear of the Damned | distance | 19390 / 17110 | mean paladin spear | 50 | magic | Atk 28, MaxHit% 84, skillDist 2 |
| Gallowsbolt Crossbow | distance | 8849 / 8021 | modified crossbow | 60 | magic | Hit% 4, skillDist 3 |
| Hellspite Arbalest | distance | 16111 / 14768 | thorn spitter | 100 | rare | Atk 14, Hit% 6, skillDist 4, criticalHitChance 4, criticalHitAmount 20 |
| Doomtide Longbow | distance | 27230 / 24574 | bow of cataclysm | 110 | legendary | Atk 10, Hit% 6, skillDist 6, absorbPercentDeath 6 |
| Riftcaller | wand | 13760 / 12603 | wand of dimensions | 80 | rare | magicPoints 3, manaLeechChance 5, manaLeechAmount 5 |
| Soulshackle Scepter | wand | 29571 / 26915 | Soulbinder Wand | 120 | legendary | magicPoints 5, criticalHitChance 7, criticalHitAmount 12, manaLeechChance 7, manaLeechAmount 8, absorbPercentDeath 8 |
| Duskweaver Wand | wand | 29866 / 27210 | Myst Regalia Wand | 140 | boss | magicPoints 6, criticalHitChance 8, criticalHitAmount 15, manaLeechChance 8, manaLeechAmount 10, absorbPercentPhysical 8 |
| Bonelord's Gaze | head | 3972 / 3408 | bonelord helmet | 60 | magic | Arm 10, magicPoints 2, maxManaPoints 150, absorbPercentDeath 6 |
| Hornsworn Helm | head | 2496 / 3390 | horned helmet | 70 | rare (set) | Arm 14, absorbPercentFire 8, maxHitPoints 120, skillSword 2, skillAxe 2, skillClub 2 |
| Crown of Cinders | head | 7462 / 7462 | ragnir helmet | 100 | legendary | Arm 14, absorbPercentFire 8, maxHitPoints 150, skillAxe 2 |
| Mortis Cowl | head | 27231 / 24575 | galea mortis | 100 | rare | Arm 11, absorbPercentDeath 10, magicPoints 3, absorbPercentHoly -5 |
| Visage of the Pale King | head | 27675 / 25019 | alicorn headguard | 120 | boss | Arm 15, absorbPercentDeath 8, absorbPercentPhysical 6, magicPoints 2, skillDist 3 |
| Carrion Scarab Amulet | necklace | 11374 / 10457 | beetle necklace | 50 | magic | speed 10, absorbPercentPoison 10, maxHitPoints 100 |
| Heart of Cinders | necklace | 10218 / 9301 | bonfire amulet | 80 | rare | absorbPercentFire 18, absorbPercentPhysical 6, maxHitPoints 200 |
| Heartbleed Pendant | necklace | 10221 / 9304 | shockwave amulet | 90 | rare | lifeLeechChance 5, lifeLeechAmount 6, criticalHitChance 4, criticalHitAmount 20 |
| Tear of the Void | necklace | 24851 / 22195 | onyx pendant | 100 | legendary | Arm 2, absorbPercentDeath 10, absorbPercentPhysical 5, maxManaPoints 200, magicPoints 2 |
| Fangs of the Ninth Circle | necklace | 24790 / 22134 | enchanted werewolf amulet | 120 | boss | Arm 2, magicPoints 3, absorbPercentDeath 8, absorbPercentHoly -6, maxManaPoints 250 |
| Pall of Skulls | body | 10296 / 9379 | heavy metal t-shirt | 60 | magic | Arm 14, absorbPercentDeath 8, absorbPercentPhysical 4, maxHitPoints 100 |
| Cindermail Coat | body | 8892 / 8064 | ethno coat | 80 | rare (set) | Arm 16, absorbPercentFire 12, absorbPercentPhysical 4, magicPoints 2 |
| Shroud of the Hollow Wood | body | 27228 / 24572 | embrace of nature | 90 | rare | Arm 18, absorbPercentIce 14, absorbPercentEnergy -3, skillDist 4 |
| Wraithplate | body | 27295 / 24639 | ghost chestplate | 100 | rare | Arm 24, absorbPercentPhysical 8, absorbPercentDeath 6, maxHitPoints 250 |
| Mortis Shroud | body | 27232 / 24576 | toga mortis | 110 | legendary | Arm 20, magicPoints 5, absorbPercentDeath 12, maxManaPoints 300 |
| Emberwarden | shield | 3975 / 3445 | salamander shield | 90 | rare (set) | Def 34, skillShield 3, absorbPercentFire 15 |
| Tome of Whispers | shield | 22474 / 20140 | eerie song book | 100 | rare | Def 14, magicPoints 4, absorbPercentDeath 8, maxManaPoints 200 |
| Obsidian Aegis | shield | 10318 / 9401 | shield Nevermourn | 110 | legendary | Def 38, skillShield 4, absorbPercentPhysical 8, absorbPercentDeath 5 |
| Emberveil Greaves | legs | 27692 / 25036 | dawnfire pantaloons | 80 | rare (set) | Arm 13, absorbPercentFire 10, absorbPercentPhysical 4, magicPoints 2 |
| Nightshade Leggings | legs | 27693 / 25037 | midnight sarong | 90 | rare | Arm 12, magicPoints 3, absorbPercentIce 8, absorbPercentDeath 6 |
| Voidscale Legguards | legs | 28020 / 25364 | Astro Legs | 130 | legendary | Arm 18, skillSword 4, skillAxe 4, skillClub 4, absorbPercentPhysical 6, manaLeechChance 4, manaLeechAmount 6 |
| Maw Treads | feet | 27288 / 24632 | pair of nightmare boots | 70 | rare | Arm 3, magicPoints 2, absorbPercentDeath 5, speed 15 |
| Bloodstep Boots | feet | 27647 / 24991 | makeshift boots | 80 | rare (set) | Arm 4, absorbPercentFire 8, magicPoints 1, speed 20 |
| Voidwalker Boots | feet | 26133 / 23477 | void boots | 100 | legendary | Arm 4, speed 30, absorbPercentDeath 6 |
| Hornbinder Ring | ring | 21693 / 19359 | horn | 60 | magic | Arm 2, skillClub 3, maxHitPoints 120 |
| Ring of the Last Ember | ring | 2206 / 3090 | time ring | 70 | rare | speed 20, healthGain 4, healthTicks 4000, manaGain 6, manaTicks 4000 |
| Cinderclaw Band | ring | 10314 / 9397 | claw of 'The Noxious Spawn' | 80 | rare (set) | skillSword 3, skillAxe 3, skillClub 3, absorbPercentFire 8, magicPoints 1 |
| Widow's Last Vow | ring | 10510 / 9593 | broken wedding ring | 90 | rare | lifeLeechChance 4, lifeLeechAmount 5, manaLeechChance 4, manaLeechAmount 5, maxHitPoints 100 |
| Veil of the Wraith | ring | 29868 / 27212 | Myst Regalia Ring | 120 | boss | Arm 4, skillShield 5, magicPoints 2, absorbPercentPhysical 5 |

Drop chances (per 10000 per kill before the tier multiplier x1/x2/x4/x6 for magic/rare/legendary/boss; normal tier never drops uniques)
are 4-6 (magic), 4-6 (rare), 7-9 (legendary) and 20 (boss-only items) and are in `chaos_unique_items.lua`. Measured with the
mock harness over 20000 simulated kills of a Demon: normal 0, magic 20, rare 276, legendary 871 uniques; Ghazbaran (boss tier): 1132.

### Embers of Aranoth set (6 pieces)
Hornsworn Helm, Cindermail Coat, Emberveil Greaves, Bloodstep Boots, Emberwarden, Cinderclaw Band. The set bonuses are
documented in `ChaosSets` but **not implemented** (see below).

## How the XML was made
For every id the stock entry was copied for structural attributes (`weight`, `weaponType`, `slotType`, `ammoType`, `shootType`,
`range`, `attackSpeed`, hit chances); attack/defense/armor and bonuses were then set, and transform/decay/duration/charges
attributes of the stock item (boots of haste style timers, equip transforms) were deliberately dropped so the items are permanent.


## Honest caveats
* **Nothing was run on a server.** Verified only: XML well-formed, every id present in our items.otb, every attribute key known to the parser,
  no duplicate ids or names, `luac5.3 -p` on the Lua, a mock-harness run of `loot.lua` accepting all 48 unique entries, and the merge tool on a
  copy of the stock items.xml (idempotent).
* **Level requirements are text only.** `items.xml` has no minimum-level attribute in this engine; stock items enforce levels with
  movement/weapon Lua scripts. The level is written into each description ("Requires level N.") and in `ChaosUniqueItems[].level`.
  Nothing stops a low-level player from equipping them until you add a MoveEvent/`onEquip` check.
* **Client display:** the 10.98 client shows item names and descriptions from the server (look/inspect text), but the item
  *sprite* and the client-side name in some windows (e.g. trade lists, market, container titles built from `.dat` names) can stay those of the
  stock item. Sprites are always those of the original item.
* **Overrides are global:** every use of these ids (NPC shops, stock monster loot, quests, `data/` scripts that mention them) now yields the
  new item. They were chosen because none appear in stock monster loot XML; some appear in a few Lua files (e.g. profession/upgrade scripts) - grep your data first.
* **Balance is untested.** Numbers are Tibia-like guesses scaled by level; tune freely. Elemental/leech/crit attributes depend on this
  engine version's parsing: leech/crit use percent chances; `elementFire`/`elementDeath` add elemental damage to melee attack.
* **Wands:** in this base server fork wands/rods have no weapon script; their damage handling is whatever the engine does for
  `weaponType wand`; only magic level and bonuses were changed (shoot type and range kept).
* **Set bonuses are not implemented**, `ChaosSets` is documentation. Drop monster lists use names that exist in our monster data (checked against stock + chaos monster XML).
* Items with several identical-looking stock twins (e.g. two "crimson sword" ids) were chosen on purpose to avoid collisions with the stock loot tables.
