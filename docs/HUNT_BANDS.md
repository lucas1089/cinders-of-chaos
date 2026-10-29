# Hunt bands (O333)

Tester, 2026-10-29: some hunt teleports send the player to the wrong place. The sign said level 25 and the arrival
held two of the named monster and random monsters of other levels. A stock portal in the same zone led among
monsters of level 300 and 1000. This table is the audit. It is made by `server/tools/audit_hunt_bands.py` from the
base map and spawn file and is not run in CI.

## How to read it

- **Band**: the sign's level range of the hunt (`tools/hall_hunts.csv`). A monster is inside it between lo x 0.8 and hi x 1.2.
- **Monsters**: known monsters on the arrival floor within 20 tiles of the arrival.
- **In band / far**: share of them inside the band, and far outside it (over 2 x the top, or under half the bottom).
- **Own**: how many are the hunt's own monsters (the ones its sign and display name).
- **Flags**: `empty` no known monster, `few` under 8, `spread` under 60% inside the band, `far` 25% or more far outside, `named` under 4 of its own monsters.
- **Gate**: a stock portal reachable on foot from the arrival whose far side has a median level over 1.5 x the band's top and 30 more.

## Totals

37 hunts, 0 flagged, 1 gate portals in reach.

## Hunts

| Hunt (level) | Band | Arrival | Monsters | In band | Far | Median | Own | Flags | Gates |
|---|---|---|---|---|---|---|---|---|---|
| Nomad (7) | 5-15 | 33295,32645,7 | 11 | 82% | 0% | 7 | 11 | ok | 0 |
| Elephant (8) | 5-10 | 32630,31691,9 | 13 | 100% | 0% | 8 | 13 | ok | 0 |
| Cave Rat (9) | 5-15 | 33211,32726,11 | 23 | 96% | 0% | 9 | 7 | ok | 0 |
| Gutworm (10) | 5-10 | 32514,31622,8 | 12 | 100% | 0% | 10 | 5 | ok | 0 |
| Minotaur (11) | 5-15 | 33264,32277,7 | 13 | 92% | 0% | 9 | 11 | ok | 0 |
| Novice of the Cult (16) | 15-20 | 32375,32767,6 | 9 | 100% | 0% | 16 | 8 | ok | 0 |
| Howler Ape (17) | 15-20 | 32770,32504,9 | 19 | 100% | 0% | 16 | 0 | ok | 0 |
| Haunted Treeling (20) | 10-30 | 32962,31499,7 | 54 | 83% | 2% | 28 | 30 | ok | 0 |
| Behemoth (23) | 20-30 | 33261,31646,10 | 16 | 100% | 0% | 23 | 10 | ok | 0 |
| Demon Skeleton (25) | 15-40 | 33026,32417,11 | 49 | 92% | 0% | 25 | 30 | ok | 0 |
| Saltkin Mantassin (32) | 25-55 | 32074,32770,12 | 38 | 100% | 0% | 38 | 0 | ok | 0 |
| Ice Witch (39) | 35-40 | 32881,31052,6 | 12 | 100% | 0% | 39 | 12 | ok | 0 |
| Saltkin Pincher Scout (39) | 30-40 | 31927,32632,10 | 38 | 92% | 0% | 39 | 0 | ok | 1 |
| Fire Elemental (41) | 40-75 | 32599,31346,15 | 14 | 100% | 0% | 57 | 7 | ok | 0 |
| Sandcrawler (42) | 40-45 | 32261,32479,10 | 17 | 82% | 0% | 42 | 14 | ok | 0 |
| Frost Dragon Hatchling (44) | 25-75 | 32045,31044,8 | 38 | 76% | 0% | 44 | 27 | ok | 0 |
| Wyrm (63) | 50-80 | 33620,31627,13 | 38 | 100% | 0% | 67 | 16 | ok | 0 |
| Wyrm (63) | 60-65 | 33066,32395,12 | 14 | 93% | 0% | 63 | 14 | ok | 0 |
| Dawnfire Asura (73) | 70-90 | 32795,32547,11 | 14 | 100% | 0% | 73 | 11 | ok | 0 |
| Frost Dragon (73) | 40-75 | 32189,31429,7 | 13 | 92% | 8% | 44 | 13 | ok | 0 |
| Rustheap Golem (75) | 60-80 | 33635,31690,13 | 15 | 80% | 0% | 75 | 5 | ok | 0 |
| Serpent Spawn (88) | 35-105 | 32880,32636,11 | 23 | 100% | 0% | 88 | 19 | ok | 0 |
| Blightwalker (97) | 95-150 | 33194,31777,12 | 24 | 100% | 0% | 140 | 22 | ok | 0 |
| Ogre rowdy (119) | 100-150 | 33756,31381,7 | 13 | 85% | 15% | 104 | 9 | ok | 0 |
| Freakish Lost Soul (120) | 115-135 | 34149,31340,8 | 10 | 100% | 0% | 125 | 6 | ok | 0 |
| Hellspawn (122) | 95-125 | 33357,31601,14 | 37 | 100% | 0% | 122 | 14 | ok | 0 |
| Demon Outcast (126) | 120-140 | 33592,32434,8 | 29 | 83% | 3% | 126 | 21 | ok | 0 |
| Skeleton Elite Warrior (130) | 130-135 | 33898,31156,9 | 26 | 100% | 0% | 130 | 26 | ok | 0 |
| Usurper Archer (134) | 110-140 | 33646,31468,6 | 43 | 98% | 2% | 132 | 30 | ok | 0 |
| Fleshcarver (150) | 145-155 | 32583,31039,7 | 17 | 71% | 18% | 150 | 13 | ok | 0 |
| Emerald Mage (225) | 180-270 | 31907,32027,5 | 21 | 100% | 0% | 225 | 11 | ok | 0 |
| Blackblade (275) | 150-300 | 32826,31434,7 | 12 | 100% | 0% | 275 | 10 | ok | 0 |
| Aeliana (283) | 280-310 | 33454,31822,4 | 11 | 82% | 0% | 283 | 6 | ok | 0 |
| deathrattle (289) | 230-300 | 32978,30977,7 | 22 | 95% | 5% | 289 | 13 | ok | 0 |
| grothar (304) | 300-335 | 33195,32115,4 | 18 | 100% | 0% | 304 | 18 | ok | 0 |
| Scaledrake (308) | 305-310 | 33016,31932,7 | 14 | 100% | 0% | 308 | 14 | ok | 0 |
| fangclaw (308) | 305-390 | 32413,31488,7 | 14 | 100% | 0% | 312 | 14 | ok | 0 |

## Stock portals in reach of a hunt arrival

| Hunt | Portal | Kind | Lands | Far side band (median) | Monsters | Verdict |
|---|---|---|---|---|---|---|
| Saltkin Pincher Scout | 31928,32631,10 | stairs/down | 31928,32630,11 | 85-105 (88) | Serpent Spawn, Medusa | gate |
| Wyrm | 33065,32399,12 | ramp/up | 33064,32399,11 | 15-45 (25) | Demon Skeleton, Necromancer, White Shade | low |
| Wyrm | 33065,32400,12 | ramp/up | 33064,32400,11 | 15-45 (25) | Demon Skeleton, Necromancer, White Shade | low |

## Limits

- Only the base hunts of the CSV. The planned hunts are generated at their own origins and built to their band.
- Portals with a destination on the map and floor changes. A teleport whose target a movement script sets (an
  action or unique id) has no destination on the map and is not found.
- Levels are the hall's scale (`gen_bounty_pool.py` estimate). Run the audit on the installed server's data
  folder too: the first run is on the base copy.
