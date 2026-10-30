# Hunt bands (O333)

Tester, 2026-10-29: some hunt teleports send the player to the wrong place. The sign said level 25 and the arrival
held two of the named monster and random monsters of other levels. A stock portal in the same zone led among
monsters of level 300 and 1000. This table is the audit. It is made by `server/tools/audit_hunt_bands.py` from the
base map and spawn file of an installed server and is not run in CI.

## How to read it

- **Band**: the sign's level range of the hunt (`tools/hall_hunts.csv`). A monster is inside it between lo x 0.8 and hi x 1.2.
- **Monsters**: known monsters on the arrival floor within 20 tiles of the arrival.
- **In band / far**: share of them inside the band, and far outside it (over 2 x the top, or under half the bottom).
- **Own**: how many are the hunt's own monsters (the ones its sign and display name).
- **Flags**: `empty` no known monster, `few` under 8, `spread` under 60% inside the band, `far` 25% or more far outside, `named` under 4 of its own monsters.
- **Gate**: a stock portal reachable on foot from the arrival whose far side has a median level over 1.5 x the band's top and 30 more.

## Totals

37 hunts, 0 flagged, 0 gate portals in reach.

## Hunts

| Hunt (level) | Band | Arrival | Monsters | In band | Far | Median | Own | Flags | Gates |
|---|---|---|---|---|---|---|---|---|---|
| Sandcrawler (7) | 5-11 | 33012,32366,7 | 40 | 95% | 0% | 7 | 18 | ok | 0 |
| Wasp (8) | 5-12 | 32936,32773,7 | 47 | 62% | 0% | 8 | 13 | ok | 0 |
| Cave Rat (9) | 5-15 | 33211,32726,11 | 23 | 96% | 0% | 9 | 7 | ok | 0 |
| Gutworm (10) | 10-15 | 32124,32371,9 | 37 | 100% | 0% | 10 | 25 | ok | 0 |
| Minotaur (11) | 10-15 | 32738,31326,7 | 36 | 97% | 0% | 11 | 30 | ok | 0 |
| Nomad (12) | 8-15 | 32681,31294,7 | 40 | 95% | 0% | 12 | 13 | ok | 0 |
| Novice of the Cult (16) | 10-20 | 32070,31078,9 | 21 | 100% | 0% | 16 | 12 | ok | 0 |
| Howler Ape (17) | 15-20 | 32770,32504,9 | 22 | 100% | 0% | 17 | 22 | ok | 0 |
| Haunted Treeling (20) | 10-30 | 32962,31499,7 | 70 | 87% | 1% | 20 | 46 | ok | 0 |
| Fire Elemental (24) | 16-36 | 32041,32611,9 | 48 | 100% | 0% | 24 | 18 | ok | 0 |
| Demon Skeleton (25) | 15-40 | 33026,32417,11 | 49 | 92% | 0% | 25 | 30 | ok | 0 |
| Saltkin Mantassin (32) | 25-55 | 32074,32770,12 | 38 | 100% | 0% | 38 | 24 | ok | 0 |
| Ice Witch (39) | 35-40 | 32197,30997,14 | 33 | 100% | 0% | 39 | 33 | ok | 0 |
| Saltkin Pincher Scout (39) | 30-40 | 31927,32632,10 | 38 | 92% | 0% | 39 | 28 | ok | 0 |
| Frost Dragon Hatchling (44) | 25-75 | 32045,31044,8 | 22 | 100% | 0% | 58 | 22 | ok | 0 |
| Wyrm (63) | 50-80 | 33620,31627,13 | 69 | 100% | 0% | 63 | 37 | ok | 0 |
| Wyrm (63) | 60-65 | 33066,32395,12 | 14 | 93% | 0% | 63 | 14 | ok | 0 |
| Frost Dragon (73) | 40-75 | 32189,31429,7 | 37 | 89% | 11% | 73 | 37 | ok | 0 |
| Hydra (73) | 70-90 | 32795,32547,11 | 38 | 100% | 0% | 73 | 32 | ok | 0 |
| Rustheap Golem (75) | 60-80 | 33635,31690,13 | 25 | 76% | 0% | 75 | 25 | ok | 0 |
| Behemoth (80) | 60-80 | 33590,31648,15 | 64 | 100% | 0% | 80 | 19 | ok | 0 |
| Hellspawn (81) | 80-122 | 32010,31056,9 | 53 | 100% | 0% | 81 | 23 | ok | 0 |
| Serpent Spawn (88) | 35-105 | 32880,32636,11 | 38 | 100% | 0% | 88 | 31 | ok | 0 |
| Blightwalker (97) | 95-150 | 33194,31777,12 | 33 | 100% | 0% | 148 | 31 | ok | 0 |
| Ogre rowdy (119) | 100-150 | 33756,31381,7 | 19 | 89% | 11% | 104 | 15 | ok | 0 |
| Freakish Lost Soul (120) | 115-135 | 34149,31340,8 | 25 | 100% | 0% | 134 | 18 | ok | 0 |
| Demon Outcast (126) | 120-140 | 33592,32434,8 | 32 | 84% | 3% | 126 | 24 | ok | 0 |
| Skeleton Elite Warrior (130) | 130-135 | 33898,31156,9 | 10 | 100% | 0% | 130 | 10 | ok | 0 |
| Usurper Archer (134) | 110-140 | 33646,31468,6 | 69 | 87% | 13% | 132 | 30 | ok | 0 |
| Fleshcarver (154) | 145-231 | 32540,31045,6 | 26 | 100% | 0% | 154 | 13 | ok | 0 |
| Emerald Mage (225) | 180-270 | 31907,32027,5 | 37 | 100% | 0% | 225 | 27 | ok | 0 |
| Blackblade (275) | 150-300 | 32826,31434,7 | 12 | 100% | 0% | 275 | 10 | ok | 0 |
| Aeliana (283) | 280-310 | 33454,31822,4 | 21 | 90% | 0% | 283 | 13 | ok | 0 |
| deathrattle (289) | 230-300 | 32978,30977,7 | 22 | 95% | 5% | 289 | 13 | ok | 0 |
| Scaledrake (308) | 305-310 | 33016,31932,7 | 14 | 100% | 0% | 308 | 14 | ok | 0 |
| fangclaw (308) | 305-390 | 32413,31488,7 | 14 | 100% | 0% | 312 | 14 | ok | 0 |
| grothar (331) | 300-335 | 33227,32115,9 | 32 | 100% | 0% | 331 | 22 | ok | 0 |

## Stock portals in reach of a hunt arrival

| Hunt | Portal | Kind | Lands | Far side band (median) | Monsters | Verdict |
|---|---|---|---|---|---|---|
| Wyrm | 33065,32399,12 | ramp/up | 33064,32399,11 | 15-45 (25) | Demon Skeleton, Necromancer, White Shade | low |
| Wyrm | 33065,32400,12 | ramp/up | 33064,32400,11 | 15-45 (25) | Demon Skeleton, Necromancer, White Shade | low |

## Limits

- Only the base hunts of the CSV. The planned hunts are generated at their own origins and built to their band.
- Portals with a destination on the map and floor changes. A teleport whose target a movement script sets (an
  action or unique id) has no destination on the map and is not found.
- Levels are the hall's scale (`gen_bounty_pool.py` estimate). Run the audit on the installed server's data
  folder too: the first run is on the base copy.
