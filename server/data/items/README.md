# Chaos unique items

The unique/legendary items (148 with the sets). Each one is a **normal copy of an existing base item** that gets its own name, description
and stats as item attributes when it drops or is given (`ChaosMakeUnique`). `items.xml` is not touched.

Why not override `items.xml`: a first run of the server showed that 28 of the 48 base items are found **by their stock name**
by stock monsters, NPC shops and scripts ("alicorn headguard", "makeshift boots", "ghost chestplate"...). Renaming those ids
made 15 boss loot tables fail to load. With per-copy attributes the stock items keep working and only the dropped copies
are unique.

| file | purpose |
| --- | --- |
| `data/items/chaos_items.xml` | source data for the 48 uniques (base id, name, description, stats); not installed into items.xml |
| `data/lib/chaos_unique_specs.lua` | generated from the XML by `tools/gen_unique_specs.py`: what `ChaosMakeUnique` applies |
| `data/lib/chaos_unique_items.lua` | `ChaosUniqueItems` (drop table for `loot.lua`), `ChaosMakeUnique`, `ChaosGiveUnique`; loads the item sets |
| `data/lib/chaos_item_sets*.lua` | the item sets (server/README.md "Item sets"): a piece is a unique with `<attribute key="set">` in the XML |
| `data/items/chaos_items_sheet.jpg` | contact sheet: sprite, name, slot, level, id, tier |

How the stats are applied: attack, defense, extra defense, armor, hit chance and range as item attributes; skills, magic
level, critical hit, leech and absorbs as the custom attributes the stock rarity scripts already apply on equip. Max health,
max mana, speed, regeneration, element damage and attack speed cannot be stored per item in this engine, so they were
dropped (listed as `skipped` in `chaos_unique_specs.lua`).

Gear coverage uniques (2026-10-23, server/README.md "Gear coverage"): 17 uniques fill the gaps of `tools/gear_coverage.lua`. Eight quivers
of the Ranger line (levels 6 to 1900) with built-in modifiers from the shared catalogue, two spellbooks (12 and 1650), a ring (30),
two amulets (450, 600) and a helmet pair, an armor and legs for every class at 1550 to 1800. Each has its own `equipLevel` on a stock
base, so the stock copy of the base keeps its rule. A wand or rod unique would keep the damage of its base, so none was added; the wand
and rod coverage comes from the class loot rows (`data/lib/chaos_class_loot.lua`).

Built-in Chaos modifiers (2026-10-23): `<attribute key="mods" value="lifeonkill:25,attackspeed:8" />` gives a unique
modifiers of `data/lib/chaos_item_mods.lua` and legendary powers of `data/lib/chaos_powers.lua` (key:value, each key
once; the generator stops on an unknown key). `ChaosMakeUnique` writes them as T8 modifiers; they count like rolled ones
and the per-character caps still hold. No orb touches a unique. The tooltip, the Codex and the wiki show them.

## Install

1. Copy `data/lib/chaos_unique_items.lua` and `data/lib/chaos_unique_specs.lua` into the server's `data/lib/` and add
   `dofile('data/lib/chaos_unique_items.lua')` at the end of `data/lib/lib.lua`.
2. After editing `chaos_items.xml`, regenerate the specs: `python3 -I tools/gen_unique_specs.py`.
3. Test: `ChaosGiveUnique(player, "Soulreaper")` from a talkaction, or check drops with `print(ChaosLootReport("Demon", "legendary", 10000))`.

## Items

The build archetype uniques (2026-10-12, both rounds; docs/BUILDS.md, server/README.md "Build archetypes") carry an `archetype`
attribute: the effect `data/scripts/chaos/archetypes.lua` reads on the worn copy. Their stats are ordinary ones.

| name | slot | id | stock item | level | tier | archetype effect |
| --- | --- | --- | --- | --- | --- | --- |
| Pyreheart Mantle | body | 8881 | fireborn giant armor | 150 | legendary | Pyre Oath aura +20% |
| Vein of the Unsated | necklace | 27652 | exotic amulet | 180 | rare | Sanguine Covenant leech +1%, cap +3% |
| Spitethorn Bulwark | shield | 15413 | ornate shield | 130 | legendary | Thornbound Oath reflect +10% |
| Knuckles of the Unbound | ring | 28023 | Astro Ring | 400 | legendary | Open Hand at 80% without the keystone, +10% with it |
| Rotbloom Phial | necklace | 21691 | shrunken head necklace | 150 | rare | Contagion Rite +1 target, +1 step |
| Splintered Instant | ring | 28049 | Mercurial Ring | 400 | legendary | Cascade Edge +25%, 0.2 s sooner |
| Stormcaller Recurve | distance | 8858 | elemental bow | 70 | rare | one arc of 25% alone; Stormstring +1 arc |
| Shard of the Long Winter | wand | 26756 | frozen wand | 100 | rare | Winter's Lattice +2%, +1 sqm |
| Effigy Carver's Idol | shield | 22423 | umbral spellbook | 120 | rare | Effigy Covenant: a third effigy |
| Brand of the Ashen Choir | head | 18403 | prismatic helmet | 150 | rare | Sigil of Cinders pulses +25% |
| Aetherbound Plate | body | 2466 | golden armor | 120 | rare | Aether Edge 10% of the shield |
| Reliquary Censer | necklace | 27251 | rainbow necklace | 220 | legendary | Reliquary Warden pulses +25% |
| Snarewalker Greaves | feet | 28115 | shadewalker boots | 120 | rare | snares: +1 trap, armed 0.3 s sooner, traps +10% (no keystone needed) |
| Fusewright's Charm | necklace | 7890 | magma amulet | 150 | rare | snares: +2 mines, mines +10%, fuse 4 s longer (no keystone needed) |
| Choirmaster's Circlet | head | 27667 | eldritch cowl | 200 | legendary | vigils reserve 15% less |
| Oathkeeper's Standard | shield | 15453 | warrior's shield | 180 | legendary | vigils reserve 10% less, reach 2 sqm farther |
| Hollowglass Diadem | head | 27668 | eldritch hood | 250 | legendary | energy shield recharge +10% a second, starts 1 s after a hit (no keystone needed) |
| Stillheart Robe | body | 27390 | soulmantle | 300 | legendary | Hollow Vessel: the items' energy shield +40% more |

The six of the second round carry `equipLevel` and `equipLines` (2026-10-13): their copies are worn by that level and
those class lines, not by the base item's movements.xml rule, which stays for stock copies
(`tools/install_unique_equip.py`, `data/lib/chaos_unique_equip.lua`, server/README.md "Unique equip rules").


Columns: server id / client id, the stock item that was overridden, required level (see caveats), drop tier (`minTier`), key stats.

| name | slot | id (server/client) | stock item | level | tier | key stats |
| --- | --- | --- | --- | --- | --- | --- |
| Widowmaker | sword | 22690 / 20341 | light rapier | 40 | magic | Atk 24, Def 12, criticalHitChance 3, criticalHitAmount 15 |
| Nightfang Katana | sword | 2412 / 3300 | katana | 60 | magic | Atk 32, Def 16, skillSword 2, criticalHitChance 4, criticalHitAmount 20 |
| Gorecleaver | sword | 11426 / 6101 | the Mad Hobb the Ripper's sabre | 70 | rare | Atk 36, Def 18, lifeLeechChance 5, lifeLeechAmount 5 |
| Bloodmoon Edge | sword | 11395 / 860 | crimson sword | 90 | rare | Atk 44, Def 22, skillSword 3, criticalHitChance 5, criticalHitAmount 25 |
| Soulreaper | sword | 8209 / 7385 | crimson sword | 120 | legendary | Atk 52, Def 28, skillSword 4, lifeLeechChance 10, lifeLeechAmount 8 |
| Executioner's Reckoning | axe | 2440 / 3328 | scorchveil waraxe | 80 | rare | Atk 50, Def 18, skillAxe 3, criticalHitChance 7, criticalHitAmount 30 |
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
| Heart of Cinders | necklace | 41641 / 9301 | own base (copy of the bonfire amulet 10218) | 80 | rare | absorbPercentFire 18, absorbPercentPhysical 6, maxHitPoints 200 |
| Heartbleed Pendant | necklace | 41642 / 9304 | own base (copy of the shockwave amulet 10221) | 90 | rare | lifeLeechChance 5, lifeLeechAmount 6, criticalHitChance 4, criticalHitAmount 20 |
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
| Ring of the Last Ember | ring | 41640 / 3090 | own base (copy of the worn time ring 2206) | 70 | rare | speed 20, healthGain 4, healthTicks 4000, manaGain 6, manaTicks 4000 |
| Cinderclaw Band | ring | 10314 / 9397 | claw of 'The Bilespawn' | 80 | rare (set) | skillSword 3, skillAxe 3, skillClub 3, absorbPercentFire 8, magicPoints 1 |
| Widow's Last Vow | ring | 10510 / 9593 | broken wedding ring | 90 | rare | lifeLeechChance 4, lifeLeechAmount 5, manaLeechChance 4, manaLeechAmount 5, maxHitPoints 100 |
| Veil of the Wraith | ring | 29868 / 27212 | Myst Regalia Ring | 120 | boss | Arm 4, skillShield 5, magicPoints 2, absorbPercentPhysical 5 |
| Grasp of the Pyre Saint | fist | 36659 / 33659 | our own "pyre saint's grasp" (server/README.md "Fist weapons") | 650 | legendary | Atk 64, Def 24, skillFist 5, criticalHitChance 4, criticalHitAmount 15, absorbPercentFire 6 |
| Vigil-Knot Wraps | fist | 40009 / 28009 | our "vigil-knot wraps" on donor B claw 10 (`fist_claws.csv`) | 14 | magic | Atk 43, Def 8, skillFist 2, mods dodge 4, lifeonkill 22 |
| Chapel-Iron Knuckles | fist | 40010 / 28010 | our "chapel-iron knuckles" on donor B claw 11 | 26 | magic | Atk 44, Def 10, skillFist 2, mods shockchance 12, manaonkill 15 |
| Gravewind Talons | fist | 40011 / 28011 | our "gravewind talons" on donor B claw 12 | 1400 | rare | Atk 68, Def 38, skillFist 4, criticalHitChance 6, criticalHitAmount 25, mods physpen 14, lifeonhit 45, bossdamage 16, bloodrush 5 |
| Dawnless Gauntlets | fist | 40012 / 28012 | our "dawnless gauntlets" on donor B claw 13 | 2000 | rare | Atk 70, Def 42, skillFist 6, criticalHitChance 8, criticalHitAmount 30, absorbPercentPhysical 5, mods bossdamage 20, dot 30, regen 40, lastbreath 35 |

Drop chances (per 10000 per kill before the tier multiplier x1/x2/x4/x6 for magic/rare/legendary/boss; normal tier never drops uniques)
are 4-6 (magic), 4-6 (rare), 7-9 (legendary) and 20 (boss-only items) and are in `chaos_unique_items.lua`. Measured with the
mock harness over 20000 simulated kills of a Demon: normal 0, magic 20, rare 276, legendary 871 uniques; Moloveth (boss tier): 1132.

### Embers of Aranoth set (6 pieces)
Hornsworn Helm, Cindermail Coat, Emberveil Greaves, Bloodstep Boots, Emberwarden, Cinderclaw Band. The set bonuses are
documented in `ChaosSets` but **not implemented** (see below).

### Weapon coverage uniques (2026-10-23)

Server/README.md "Weapon coverage". Added after the audit (`server/tools/weapon_coverage.lua`) found thin bands. The same
rules as the endgame uniques below (`equipLevel`, `equipLines`, built-in modifiers, drops from the waystone bosses and
monsters of the band, chance 6; the Hoarfen Bow from magic monsters and up, chance 25; the Moonlit Gallows Bow from monster
level 800).

| name | slot | id | stock item | level | classes | stats | built-in modifiers |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Hoarfen Bow | distance | 13873 | shimmer bow | 40 | Ranger line | attack 40, hitChance 95, range 6, skillDist 2 | attackspeed:6, chillchance:10, lifeonkill:20 |
| Moonlit Gallows Bow | distance | 26765 | exowing bow | 900 | Ranger line | attack 83, hitChance 99, range 7, skillDist 6, criticalHitChance 5, criticalHitAmount 20 | attackspeed:12, physpen:14, bleedchance:18, echoshot:18 |
| Hollow Throne Claymore | sword | 25880 | slayer of mayhem | 1550 | Warrior, Templar | attack 73, defense 38, skillSword 6, criticalHitChance 6, criticalHitAmount 30 | attackspeed:12, bossdamage:20, physpen:18, bloodrush:4 |
| Gravetide Arbalest | distance | 25886 | crossbow of mayhem | 1800 | Ranger line | attack 92, hitChance 95, range 6, skillDist 7, criticalHitChance 8, criticalHitAmount 30 | attackspeed:12, physpen:18, poisonchance:20, hunterrush:22 |
| Emberhowl Greataxe | axe | 25882 | chopper of mayhem | 1950 | Warrior, Templar | attack 77, defense 36, skillAxe 7, lifeLeechChance 10, lifeLeechAmount 8 | bleedchance:24, dot:42, lifeonhit:50, crimsonburst:20 |
| Wake-Heron Longbow | distance | 25885 | bow of mayhem | 2100 | Ranger line | attack 91, hitChance 98, range 7, skillDist 7, criticalHitChance 8, criticalHitAmount 30 | attackspeed:14, elepen:18, dot:40, echoshot:20 |
| Bellringer of the Last Vigil | club | 25884 | hammer of mayhem | 2200 | Warrior, Templar | attack 78, defense 36, skillClub 7 | shockchance:22, execute:8, monsterreduction:6, arclightning:20 |

### Leveling and endgame uniques (2026-10-23)

Server/README.md "Leveling and endgame uniques". Every one has `equipLevel` (and the class ones `equipLines`), so a
copy traded down cannot be worn early (install step uniqueequip, "Unique equip rules"). The bases have no abilities of
their own and no stock equip script.

Leveling (level 10-35): strong flat bonuses that fade by level 100-150. Magic monsters and up of the level 5-40 hunts,
chance 25 (the other uniques 4-10).

| name | slot | id | stock item | level | classes | stats | built-in modifiers |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ashen Pilgrim's Blade | sword | 10292 | pointed rabbitslayer | 12 | every class | attack 30, defense 14, skillSword 2 | lifeonkill:25, attackspeed:8 |
| Hatchet of the First Winter | axe | 8601 | steel axe | 15 | every class | attack 32, defense 12, skillAxe 2 | chillchance:12, lifeonhit:6 |
| Tallow-Bell Mace | club | 10302 | club of the fury | 15 | every class | attack 31, defense 14, skillClub 2 | shockchance:12, lifeonkill:25 |
| Fenwatch Longbow | distance | 7438 | elvish bow | 12 | every class | attack 36, hitChance 92, range 6, skillDist 2 | attackspeed:8, lifeonkill:20 |
| Cinder-Wick Wand | wand | 23719 | scorcher | 10 | every class | magicPoints 2 | ignitechance:12, manaonkill:15 |
| Hood of the Roaming Pyre | head | 10291 | odd hat | 20 | every class | armor 7 | experience:8, regen:8 |
| Pathfinder's Treads | feet | 25412 | treader of torment | 20 | every class | armor 3 | movespeed:10, dodge:4 |
| Band of the Second Dawn | ring | 10502 | engraved wedding ring | 25 | every class | - | experience:5, lifeonkill:20, goldfind:10 |
| Moth-Lantern Pendant | necklace | 11393 | lucky clover amulet | 30 | every class | armor 2 | manaonkill:15, regen:8, itemfind:8 |
| Gutter-Saint's Mail | body | 21692 | albino plate | 35 | every class | armor 12 | monsterreduction:6, lifeonhit:6, regen:6 |
| Wanderer's Leggings | legs | 2648 | chain legs | 18 | every class | armor 6 | regen:8, lifeonkill:20 |
| Lantern-Ward Buckler | shield | 10294 | shield of the white knight | 25 | every class | defense 26, skillShield 2 | block:6, thorns:30 |

Endgame (level 1200-2400): one legendary power each. The waystone bosses of the band (low 1100-1500: Vorgrun,
Fractalis; mid 1600-2000: Frostreaver, Rhazgor; high 2100-2500: Morgrath, Nyxdrath) and the band's waystone monsters
(rare and up, monster level 1000+), chance 6. The Choirless Pendant drops from the high band bosses and Ysgrath only.

| name | slot | id | stock item | level | classes | stats | built-in modifiers |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ashfall Verdict | sword | 8931 | the epiphany | 1300 | Warrior, Thief, Monk, Templar | attack 72, defense 36, extraDef 3, skillSword 6, criticalHitChance 7, criticalHitAmount 30 | attackspeed:15, bossdamage:20, physpen:20, critecho:22 |
| Wyrmgrave Cleaver | axe | 25881 | axe of mayhem | 1500 | Warrior, Thief, Monk, Templar | attack 74, defense 33, skillAxe 6, lifeLeechChance 10, lifeLeechAmount 8 | bleedchance:25, dot:44, lifeonhit:55, bloodrush:4 |
| Maul of the Sunken Choir | club | 14334 | giant smithhammer | 1800 | Warrior, Thief, Monk, Templar | attack 76, defense 34, skillClub 7 | shockchance:24, execute:8, monsterreduction:6, arclightning:22 |
| Stormherald's Recurve | distance | 22417 | umbral bow | 1600 | Ranger | attack 88, hitChance 97, range 7, skillDist 7, criticalHitChance 8, criticalHitAmount 30 | attackspeed:14, elepen:20, chillchance:20, echoshot:22 |
| Diadem of the Ninth Pyre | head | 24744 | enchanted werewolf helmet | 1400 | Mystic, Necromancer | armor 16, magicPoints 8, absorbPercentFire 8 | cdr:15, manacost:15, ignitechance:20, crimsonburst:20 |
| Vestments of the Hollow Choir | body | 2656 | blue robe | 2000 | Mystic, Necromancer | armor 28, magicPoints 10, absorbPercentDeath 10, absorbPercentPhysical 6 | dot:45, regen:65, manaonhit:45, smolderaura:30 |
| Bastion of the Last Dawn | body | 2472 | magic plate armor | 2200 | Warrior, Templar | armor 33, skillShield 6, absorbPercentPhysical 10, absorbPercentFire 6 | monsterreduction:8, reflect:10, thorns:220, lastbreath:45 |
| Greaves of the Endless Road | feet | 2646 | golden boots | 1200 | every class | armor 6 | movespeed:12, dodge:7, lifeonkill:220, hunterrush:24 |
| Legguards of Unmaking | legs | 2495 | demon legs | 1700 | every class | armor 16, absorbPercentPhysical 6, absorbPercentDeath 6 | regen:60, lifeonhit:50, monsterreduction:5, frostward:24 |
| Band of the Severed Star | ring | 22516 | ring of ending | 1900 | every class | criticalHitChance 6, criticalHitAmount 30, skillSword 4, skillAxe 4, skillClub 4, skillDist 4, skillFist 4, magicPoints 4 | bossdamage:22, execute:8, itemfind:15, deathblast:22 |
| Rampart of Grey Tides | shield | 6391 | nightmare shield | 1500 | Warrior, Templar | defense 58, skillShield 7, absorbPercentIce 8, absorbPercentPhysical 4 | block:15, reflect:12, regen:50, frostward:26 |
| Choirless Pendant | necklace | 22691 | jade amulet | 2400 | every class | armor 6, magicPoints 5, skillSword 5, skillAxe 5, skillClub 5, skillDist 5, skillFist 5, absorbPercentPhysical 6 | experience:10, rarityfind:30, cdr:10, bloodrush:5 |

The level 800 / 1000 uniques (the Ascended four, the world boss drops, the Ashwarden set) got built-in modifiers too, a
legendary power on 11 of the 13, so they stay worth wearing past level 1000.

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
  Nothing stops a low-level player from equipping them until you add a MoveEvent/`onEquip` check. Exception: the
  uniques with `equipLevel` / `equipLines` (above), held to their own rule by the `uniqueequip` install step.
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

## Thief daggers (2026-10-23)

Owner: "adicione também mais daggers pros thiefs". Five uniques on dagger-sprite bases (one unique per base id), so a Thief has
a dagger to find in every band; with the shop dagger (2379), the stock assassin dagger (7404, level 40), the Duskstalker Fang
(level 300) and the gear sets' blades this fills 1-2400+. Attack follows the one-handed melee curve (`install_gear_sets.py`
`CURVES['attack']`), skill +1 to +5 by level steps, built-in modifiers, no NPC price.

| name | id | stock item | level | tier | who | modifiers |
| --- | --- | --- | --- | --- | --- | --- |
| Cutpurse's Sliver | 2403 | knife | 10 | magic, chance 25 | every class | life on kill 20, attack speed 8 |
| Moonlit Shiv | 2402 | silver dagger | 28 | magic, chance 25 | every class | poison chance 12, life on hit 6, attack speed 8 |
| Gravewhisper Stiletto | 2404 | combat knife | 600 | rare, chance 6 | Thief line | attack speed 10, poison chance 16, life on hit 30 |
| Nightbloom Stiletto | 2411 | poison dagger | 1250 | rare, chance 6, waystone kills | Thief line | attack speed 15, poison chance 24, physical penetration 18, Critical Echo 20 |
| Misericorde of the Pale Vow | 27193 | drownkin ceremonial dagger | 1900 | rare, chance 6, waystone kills | Thief line | attack speed 14, life on hit 45, physical penetration 18, Bloodrush 4 |
