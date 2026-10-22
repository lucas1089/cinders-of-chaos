# Content coverage

What a player can do at each level, what was thin, and what was added on 2026-10-14. Written for the owner.

The numbers come from tools, so they can be measured again after a map or spawn change:

```
# a scratch copy of the base server, with our names and spawns (never the live folder)
python3 -I server/tools/install_all.py SCRATCH --no-sql --only files,lib,monsternames,lategame,monsters,spawns
python3 -I server/tools/content_audit.py SCRATCH/data --json audit.json
```

`content_audit.py` reads the spawn file that the server really loads. It groups spawn entries into hunts: entries on
one floor at most 12 tiles apart, at least 10 monsters that give experience. Monster levels come from the bounty pool,
the same estimate the bounty board and the area planner use. A hunt counts for a band when at least a fifth of its
entries are monsters of that band. Parties at once is one party per 30 spawn entries of the band, at least one.
The generated areas and the planned areas are listed apart: they are instanced or not placed yet.

## Summary

| Band | World hunts | Spawn entries | Parties at once | Other areas | Our quests with a story | Gap | Severity |
|---|---|---|---|---|---|---|---|
| 1-20 | 502 | 22,102 | 797 | - | tutorial island, base quest lines | first hour: no hint where to hunt or shop | high, fixed |
| 20-50 | 392 | 16,237 | 583 | - | base quest lines | none | - |
| 50-100 | 208 | 11,724 | 395 | - | base quest lines | none | - |
| 100-200 | 157 | 6,696 | 228 | - | Ascension quest, Vocation Trials | none | - |
| 200-300 | 37 | 1,020 | 43 | 2 planned | none before; now The Bone Choir | half the entries are one library isle | medium, plans written |
| 300-500 | 100 | 4,780 | 169 | - | world boss and faction lines only | no story quest | low |
| 500-700 | 16 | 688 | 23 | 3 planned | none before; now The Wyrm Tithe | 14 parties for the whole band | critical, plans written |
| 700-1000 | 10 | 212 | 10 | Hollow Vault, 3 planned | Sepulchre intros; now Requiem for the Ash-Sister | late game rows only, one town | critical, plans written |
| 1000+ | 0 | 0 | 0 | 3 generated, 6 planned | none before; now The Last Ember | no world hunt at all | critical, plans written |

Numbers after the fill of 2026-10-14 (every hunt under 3.25 monsters per 100 walkable tiles raised to 3.4 by
`tools/gen_spawn_density.py`, server/README.md "Spawn density and respawn", Fill); the hunt lists below are from before.
The generated areas were doubled the same day (738 monsters instead of 205; README "Generated areas").

Planned areas count once they are placed on the map. Until then 500-1000+ still rely on the late game rows, the
generated areas and the instanced content below.

## Hunting areas per band

Biggest world hunts per band, by spawn entries of the band, with the nearest temple:

| Band | Biggest hunts |
|---|---|
| 1-20 | Larva, Scarab, Nomad near Dunescar, floor 9, 681. Centipede, Howler Ape, Gorebloom near Fevergate, 527. Sandcrawler, Lizard Legionnaire near Ashstrand, 377 |
| 20-50 | Earth Elemental, Mutated Rat near Saltgrave, floor 12, 410. Rot Elemental, Sludgebrass Blob near Brassgate, 303. Insectoid Worker, Swarmer near Ashstrand, 210 |
| 50-100 | Lost Thrower, Lost Basher, Wyrm near Saltgrave, floor 15, 594. Lizard High Guard near Hollowspire, 423. Tidecrest Serpent, Sea Serpent near Brassgate, 353 |
| 100-200 | Choking Fear, Retching Horror near Nightwrack, 338. Hellspawn, Destroyer, Grim Reaper near Brassgate, 251. Demon Outcast, Dark Torturer near Nightwrack, 199 |
| 200-300 | Animated Feather, Biting Book, Brain Squid near Isle of Oaths, 120 and three more library floors. 414 of 805 entries are on that isle |
| 300-500 | Sorcerer's, Druid's and Paladin's Apparition near Wyrmscar, 368 and 271. Rotten Golem, Mould Phantom near Ashstrand, 131 |
| 500-700 | Snallygaster, Babayaga near Saltgrave, 31. Hellmaw Brute, Mirethorn Hexer near Dunescar, 29. Gloomstinger, Aegis Sentinel near Dunescar, 27. 217 of 280 entries near Dunescar |
| 700-1000 | The late game rows of tools/late_game_spawns.csv: Grindmaw the Mauler, Jungle Beasts near Wyrmscar, 32; Dreamgorger, Loricate Orger, 27. 188 of 212 near Wyrmscar |
| 1000+ | none in the world |

Instanced and timed content per band, for scale: bounty contracts from 8 in six tiers, rifts from 100, the Ember
Descent from 100, the Vocation Trials 100-250, 250-500 and 400-1000, the guild siege from 100, the guild boss from 150,
world bosses from 300, the Ashen Sepulchre from 800, the Ascended Omens from 900 and the Cinderheart from 1000, the
Hollow Vault dungeon at 800, the Emberdeep Hollows, Sunken Ossuary and Cinderfall Wastes at 1000-1300.

Found on the way: 32 level-scaled monsters of 650-1300 spawned nowhere. The planned areas give 29 of them a home.
Mercenary, Mercenary Ranger and Cunning Hyaena stay out: no sprite or a wrong one. Several of the others still wait for
their final art, per `server/data/monster/CUSTOM_MONSTERS.md` and `sprite_report.csv`; check them in the client before
placing an area.

## Planned hunting areas

Sixteen area-planner plans in `server/tools/areaplan/plans/`, schema `chaos-area-plan/1`. Each validates with no warning,
compiles with no QA error, has a camp with a protection zone, a loop and decoration at `dense`. CI validates and
compiles them with the examples. Placement notes: docs/MAP_GUIDE.md "Content plans".

| Plan | Band | Biome | Monsters | Parties | Chest |
|---|---|---|---|---|---|
| bonechoir_catacomb | 200-290 | catacomb | Deathrattle, Skullshade, Bonecleaver, Doombone, Blackblade | 8 | bonechoir_tithe |
| sulphur_gallery | 215-299 | lava | Hellflayer, Demon of the Depths, Alpha Demon, Skullcrusher Demon, Juggernaut | 8-12 | - |
| wyrmspine_hollows | 500-640 | cave | Ashfang, Shadowvein, Stormvein, Viridscale Wrym, Flarevein Wyrm | 12 | wyrmspine_clutch |
| pyrarch_crucible | 520-690 | lava | four Pyrarchs, Embermaw Archon, Pitlord Incarnate, Hellmaw Brute, Inferno Juggernaut, Nightflare Dreadknight | 12 | - |
| widowmere | 480-640 | swamp | Nightfang and Shadowcrystal Widow, Mirethorn Hexer, Gloomstinger, Plague Warbringer | 12 | widowmere_silk |
| corsairs_reach | 780-900 | cave | Captain Bloodbeard, Ironhook Corsair, Scourgejaw, Stormy Seadevil; since 2026-10-22 also Gashrunner, Caged Convict, Chained Runt, Ironmask Taskmaster, Ironmask Brander, Ironmask Bannerman | 12 | corsairs_cache |
| hexwood_thicket | 720-840 | forest | Elite Spider, Cursed Ape, Webbound Crawler, Black Stag, Dark Sorcerer; since 2026-10-22 also Gallows Oak, Rootbound Pilgrim, Thornveil Wraith, Shroud Brood, Ironbound Troll, Blight Hound | 12 | - |
| mirefang_basin | 880-999 | swamp | Nexweaver, Acid Hydra, Mutated Visco, Elite Tidecrest Serpent, Elite Twisted Shaper; since 2026-10-22 also Reedgrave, Leechwing, Bloom Husk, Blight Bloom, Crypt Crab | 12 | - |
| rimecrown_depths | 1000-1120 | ice | Ice Lich, Scaleborn, Spirit of Purity, Twisted Shaper, Celestial Wyrm, Vorkhaz; since 2026-10-22 also Rimecairn, Quicksilver Wraith, Geode Seer | 12 | rimecrown_tribute |
| cinderglass_sanctum | 1120-1300 | sanctum, 2 floors | Jungle Warrior, Black Vixen, Golden Dragon, Spiky Carnivor, Vyrm, Winterstride, Facetis, Thal, Silicron; since 2026-10-22 also Bellhelm Zealot, Masque Dancer, Gildguard Revenant, Wan Sentry | 16 | - |
| slagmourn_foundry | 1000-1150 | lava | Dawn Strayer, Scaleborn, Twisted Shaper, Celestial Wyrm, Vorkhaz, Jungle Warrior; since 2026-10-22 also Slagheart, Slagborer Reaver, Deepforge Fiend, Rustguard | 12 | slagmourn_ingot |
| hollowmass_reliquary | 1150-1300 | crypt, 2 floors | Black Vixen, Golden Dragon, Spiky Carnivor, Vyrm, Winterstride, Silicron, Thal, Facetis; since 2026-10-22 also Reliquary Urn, Wax Penitent, Grave Lantern, Dirge Herald, Nailcrown Regent | 14 | hollowmass_tithe |
| gallowfen_mire | 1300-1450 | swamp | Vyrm, Winterstride, Silicron, Thal, Facetis, Gloamfang Ravager, Rimeshroud Revenant; since 2026-10-22 also Gorebristle, Corpselight Lurker, Pit Delver, Carrion Drake, Pitgnawer, Blightcrown Matron | 13 | gallowfen_noose |
| voidscar_chasm | 1400-1500 | abyss, 2 floors | Vyrm, Winterstride, Silicron, Thal, Facetis, Rimeshroud Revenant, Cinderskull Reaver; since 2026-10-22 also Veiled Crawler, Maw Grub, Limb Hoarder, Ashveil Hierarch | 14 | voidscar_relic |
| gravehorn_deeps | 1500-1750 | crypt, 2 floors | Cinderskull Reaver, Bloodantler Fiend, Cinderhorn Juggernaut, Rimeshroud Revenant, Wraithbone Stalker; since 2026-10-22 also Bonepicker, Hollowhorn, Gnawbone Swarm, Oathbroken Colossus | 16 | gravehorn_antler |
| duskmarrow_crater | 1750-2000 | lava, 2 floors | Wraithbone Stalker, Mirecoil Wyrm, Pyrewing Tyrant, Cinderhorn Juggernaut; since 2026-10-22 also Pyre Stork, Siege Behemoth, Ironmask Warbreaker, Gnarlback | 16 | duskmarrow_ember |

Since 2026-10-14 each is four times the first draft (owner: "Deixe-as 4x maior"; "Todas devem ser grandes e cheias de
monstros"): about 3,900-6,800 walkable tiles and 130-220 monsters each, 3.2-3.5 monsters per 100 walkable tiles.
Placed, they take 500-700 from 14 to about 50 parties, 700-1000 from 10 to about 46 and 1000+ from none to 28.

The last four (owner, 2026-10-14: four more hunts for 1000+) follow the same standard: 184-192 x 156-176 tiles,
5,200-7,150 walkable tiles, 176-236 monsters, 3.3-3.4 per 100. When they were made no hunting monster of ours sat above
1280, so 1300-1500 run on the 1140-1280 set in larger numbers. With them 1000+ goes from none to about 81 parties.

**1300-2000 (2026-10-14, owner approved).** Eight hunting monsters of our own, one every 100 levels from 1300 to 2000,
on the late-game curves carried on from Facetis (server/README.md "Late game", The 1300-2000 set): Gloamfang Ravager
1300, Rimeshroud Revenant 1400, Cinderskull Reaver 1500, Bloodantler Fiend 1600, Cinderhorn Juggernaut 1700,
Wraithbone Stalker 1800, Mirecoil Wyrm 1900, Pyrewing Tyrant 2000. Two plans use them: gravehorn_deeps (1500-1750,
188 x 172, 2 floors, 7,320 walkable tiles, 246 monsters, 3.38 per 100) and duskmarrow_crater (1750-2000, 192 x 176,
2 floors, 6,423 walkable tiles, 210 monsters, 3.29 per 100). Placed, 1000+ goes to about 96 parties, and 1500-2000 gets
hunts made for it instead of more of the 1280 set. gallowfen_mire and voidscar_chasm took the 1300-1500 ones in place of
some of their weakest spawns (same counts and density: Gloamfang Ravager and Rimeshroud Revenant for the fen's Black Vixen and Spiky Carnivor, Rimeshroud
Revenant and Cinderskull Reaver in the chasm).

## Quests per band

| Band | What a player can do | Story or task |
|---|---|---|
| 1-20 | tutorial island, 5 stations; base quest lines; milestone gift at 20; bounty from 8; 3 tales from 8 | tutorial lessons; base lines have a story; tales |
| 20-50 | base quest lines; invasions from 30; bounty; achievements; 4 tales | story in the base lines; tales |
| 50-100 | base quest lines; arena from 50; Seasonal Journey chapter 1; 4 tales | journey chapters are task lists with one line of text; tales |
| 100-200 | Ascension quest at 100; Vocation Trials; rifts; Ember Descent; guild siege; journey chapter 2 at 150; 4 tales | Ascension, Trials and tales have a story |
| 200-300 | journey chapter 3; Trials; rifts; **The Bone Choir** | tasks before; now one tale |
| 300-500 | world bosses; Omens; journey chapters 4-5; faction contracts; 3 tales | tasks; world boss and faction lines; tales |
| 500-700 | journey chapter 6; Trials Merciless; Omens; **The Wyrm Tithe** | tasks before; now one tale |
| 700-1000 | Ashen Sepulchre; Ascended Omens; journey chapters 7-8; **Requiem for the Ash-Sister**, **The Keeper's Key** | boss intros before; now two tales |
| 1000+ | the Cinderheart; generated areas; **The Last Ember** and 4 more tales up to 2000 | nothing before; now five tales |

The base world has 35 quest lines with 310 missions in its quest log, renamed at install by `worldtexts`. They were
written for low and mid levels. Our achievements: 173 in 10 groups, mostly counters. Bestiary kill tasks and bounty
contracts cover every band but are tasks without a story.

## Tales

Short quests with a story, 27 from level 8 to 2000. Archivist Maelis gives them and closes them. She stands next to
the first temple, placed at startup like the Ascendant Oracle, and shows on the map markers. Steps: kill, visit (stand
at a hunting mark, revealed on the map), talk (ask a faction leader about "tales"), deliver and report. A chained tale
opens when the one before it is done. Experience is a share of the next level, measured at most at the top of the
tale's band. "x" below is that share; gold goes to the bank.

| Tale | From level | Steps | Rewards |
|---|---|---|---|
| Teeth in the Cellars | 8 | visit the cellars; kill 25 rats; report | 1.0x, 1,500 gold, 100 Thornbound Circle reputation, the book "The Cellars of Cinderhold" |
| The Lantern Road | 12 | after Teeth in the Cellars; ask Warden Ysolde; kill 30 restless dead; report | 1.0x, 3,000 gold, 150 Ashen Vigil reputation, the book "The Lantern Road" |
| The Troll Toll | 15 | kill 35 trolls; ask Forgemaster Brannoc; report | 1.0x, 4,000 gold, 150 Cinderforge Compact reputation |
| The Deserters of Anvildeep | 20 | visit the dwarven mine; kill 40 dwarves; report | 0.8x, 6,000 gold, 2 Orbs of Awakening, 200 Compact reputation |
| Rime and Ruin | 25 | visit the frost giants; kill 40; ask Elder Bramwyn; report | 0.8x, 7,500 gold, 2 Orbs of Awakening, 200 Circle reputation |
| The Stone Watchers | 30 | after The Lantern Road; visit the gargoyles; kill 40; report | 0.8x, 10,000 gold, 3 Orbs of Awakening, 250 Vigil reputation |
| The Grave Circle | 40 | after The Stone Watchers; visit; kill 40 necromancers and bonebeasts; kill 15 liches and banshees; report | 0.75x, 15,000 gold, 2 Whetstones, 1 Tempering orb, 300 Vigil reputation, the book "The Grave Circle" |
| The Dragon Census | 50 | visit the dragon lair; kill 40 dragons; ask Cantor Velith; report | 0.75x, 22,000 gold, 2 Whetstones, 300 Veiled Choir reputation, the book "The Dragon Census" |
| The Moon-Sick | 65 | kill 40 were-beasts; ask Elder Bramwyn; report | 0.7x, 30,000 gold, 1 Orb of Upheaval, 400 Circle reputation, the book "The Moon-Sick" |
| Lords of the Brood | 70 | after The Dragon Census; kill 30 dragon lords and frost dragons; bring 10 rune shards | 0.7x, 35,000 gold, 2 Tempering orbs, 400 Choir reputation |
| The Hundred Heads | 85 | after The Moon-Sick; visit the hydras; kill 40; report | 0.7x, 40,000 gold, 2 Orbs of Upheaval, 400 Circle reputation |
| Where the Lost Souls Walk | 100 | kill 50 lost souls and wraiths; ask Warden Ysolde; report | 0.6x, 50,000 gold, 2 Orbs of Upheaval, 450 Vigil reputation |
| The Bone Court | 120 | after Where the Lost Souls Walk; kill 50 of the bone court; bring 15 rune shards | 0.6x, 70,000 gold, 3 Orbs of Upheaval, 500 Vigil reputation, the book "The Bone Court" |
| Outcasts of the Pit | 130 | kill 50 demon outcasts, torturers and hellspawn; ask Forgemaster Brannoc; report | 0.6x, 75,000 gold, 2 Orbs of Upheaval, 500 Compact reputation |
| Wings of the Unburied | 160 | after Lords of the Brood; visit; kill 40 undead dragons and hellflayers; kill 15 black dragons; report | 0.6x, 100,000 gold, 3 Orbs of Upheaval, 550 Choir reputation |
| The Mould Gardens | 340 | visit; kill 60 rotten golems, mould phantoms and crawlers; report | 0.5x, 250,000 gold, 2 Orbs of Upheaval, 1 Orb of Fate, 700 Circle reputation |
| Phantoms of the Furnace | 360 | kill 60 infernal demons and phantoms; bring 20 rune shards | 0.5x, 280,000 gold, 1 Orb of Fate, 700 Compact reputation |
| The Ash Widows | 470 | kill 60 widows, hexers and adepts; ask Elder Bramwyn; report | 0.5x, 350,000 gold, 2 Orbs of Fate, 800 Circle reputation |
| The Keeper's Key | 800 | defeat Vault Keeper Ossrim; bring 30 rune shards | 0.4x, 900,000 gold, 1 Orb of Grafting, 1,100 Compact reputation, the book "The Wardens of the Deep" |
| The Gravecage | 1000 | defeat Ossivane the Gravecage; ask Warden Ysolde; report | 0.3x, 2,200,000 gold, 2 Orbs of Grafting, 1,400 Vigil reputation, the book "The Four Deeper Doors" |
| Kharzun's Anvil | 1300 | kill 80 of the crucible's beasts; defeat Forgewarden Kharzun; report | 0.3x, 3,000,000 gold, 2 Orbs of Grafting, 1,600 Compact reputation |
| The Fallen Seraph | 1600 | after Kharzun's Anvil; kill 80 of the sanctum's dead; defeat Vaelith; ask Cantor Velith; report | 0.3x, 4,000,000 gold, 3 Orbs of Grafting, 1,800 Choir reputation |
| The Chained Wyrm | 2000 | after The Fallen Seraph; defeat Azhkarrath the Chained Wyrm; report | 0.25x, 5,000,000 gold, 3 Orbs of Grafting, 2,000 Vigil reputation, the book "The Fall of the Cinders" |
| The Bone Choir | 200 | kill 40 of the drowned chapel's dead; tell her what they sang | half a level of experience, 150,000 gold, 3 Orbs of Upheaval, 600 Ashen Vigil reputation, the book "Ashen Crypt" |
| The Wyrm Tithe | 500 | kill 50 wrym; bring 20 rune shards | half a level, 400,000 gold, 2 Orbs of Fate, 800 Cinderforge Compact reputation, the book "Obsidian Hall" |
| Requiem for the Ash-Sister | 800 | kill 60 of the Sovereign's lost court; defeat Morwen the Ash-Sister in the Sepulchre; return | 0.4 of a level, 1,000,000 gold, 1 Orb of Grafting, 1,200 Ashen Vigil reputation, the book "The Ashen Sepulchre" |
| The Last Ember | 1000 | defeat a warden of the deep places; defeat an Ascended Omen; return | 0.3 of a level, 2,500,000 gold, 2 Orbs of Grafting, 1,500 Veiled Choir reputation, the book "Ysgrath the Cinderheart" |

Every kill target spawns today, so the tales work before any planned area is placed. Party members within 30 tiles
on the same floor share a kill. Every text is in English and Brazilian Portuguese: a player says "portugues" to her,
or the localization work's `Chaos.lang` decides once it exists. Files: `server/data/scripts/chaos/tales*.lua`,
`server/data/npc/Archivist Maelis.xml` and its script, `server/tests/tales_test.lua`.

## First hour

Walked from the tutorial, the welcome and the new-player scripts. Dead ends found:

| Dead end | Severity | Done |
|---|---|---|
| The tutorial and the welcome never say where to hunt. Hunting marks stay hidden until a character walks near one | high | the three nearest hunts of the character's level are put on its map at 1, 8, 20, 35, 50 and 80, and named in a hint |
| No pointer to the next gear after the kit | medium | hint at level 4: town shops, the Loot Buyer, Economy > Item Finder |
| The bounty board opens at 8 without notice | medium | hint at 8 |
| The first passive point at 12 is only told on the island | low | hint at 12 |
| Level 20: a gift, then nothing about where next | low | hint with the Bestiary and new hunts |
| Invasions at 30, the arena at 50, ascension and rifts at 100 are found by chance | low | hints at 30, 50 and 100 |
| No signposts by the start temple | low | owner, below |
| The tutorial and the welcome are English only | medium | the localization work |
| The Thief line's tutorial stations 3-5 were never walked in game | low | owner test |

The hints come once each, as a message and a toast, in English or Brazilian Portuguese. Characters above level 20 when
the module first sees them get every hint marked as given, silently. Files: `server/data/scripts/chaos/firsthour*.lua`,
`server/tests/firsthour_test.lua`.

## Lore

Before: world bosses had a one-line yell, the Sepulchre bosses a short intro, the four factions one line each, item sets
a description and the Trials one story line per class. Rifts, Omens, the Cinderheart, the Sepulchre itself, the
Descent, the generated areas' bosses and the fall of the Cinders had no lore anywhere.

Now: 22 short entries in English and Brazilian Portuguese in `server/data/scripts/chaos/lore_data.lua`. They show in:

- the Codex, a new Lore tab: `server/tools/gen_codex_data.lua`;
- the website wiki, a Lore tab: `server/tools/gen_wiki_data.lua`;
- Archivist Maelis: say a name such as "sangrith", "rifts" or "sepulchre", or "lore" for the list;
- books: each tale gives one entry as a readable book, in the player's language.

| Group | Entries |
|---|---|
| The world | The Fall of the Cinders, The Isle of First Blood, The Archivist's Ledger |
| Rifts | The Rifts, Abyssal Rift, Obsidian Hall, Ashen Crypt, Forsaken Sanctum |
| Omens | The Omens, Sangrith, Morvane, Thalcyra, the Ascended Omens and the Ember Gate, Ysgrath the Cinderheart |
| The Ashen Sepulchre | Varkhul and his court |
| World bosses | Kaelgor, Skaldra, the Rotmother, Nyxareth, Vharok |
| The deep places | The Ember Descent, the Wardens of the Deep |

## For the owner

1. Review the previews of the ten plans, then place the ones you keep with `area_planner.py place` into a copy of the
   world map, add an entrance portal on the live map and test them. Notes: docs/MAP_GUIDE.md "Content plans".
2. Check the art of the dormant monsters in the client before a plan that uses them goes live.
3. Add two or three signposts by the first temple in the map editor, for example "Hunting grounds: see your map" and
   "Shops and the Loot Buyer".
4. Walk the tales once on the test server: the Archivist's placement, the Portuguese switch, a turn-in, a visit
   place of each low tale, a talk step at each faction leader, a chain opening.
5. Walk the Thief line's tutorial stations 3-5.
