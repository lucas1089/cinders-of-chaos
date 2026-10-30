# Hunt transitions (O323)

Owner, 2026-10-29: some low-level hunts have a hole or a portal inside them that takes the player to a place
with much stronger monsters and high density. This table is the audit. It is made by
`server/tools/audit_hunt_transitions.py` from the base map and spawn file, and is not run in CI.

## How to read it

- **Source area**: the hunt of `tools/hall_hunts.csv` the entry belongs to (within 60 tiles of its destination, its hall level),
  else `area x,y,z` with the level of the monsters round the entry. The entry has a spawn within 6 tiles.
- **Kind**: `teleport`, or a floor change (`hole/down`, `stairs/up`, `ladder/up`, `grate/down`).
- **Destination band**: level range (low to high, the 20th to 80th percentile of the monsters round the landing)
  and the median level. Same maths as the hall order.
- **Density**: monsters per 100 walkable tiles within 12 tiles. The source density is in brackets.
- **Verdict**: `danger` when the destination level is 2 x the source level or more (and 25 more), or, from 1.5 x
  (and 15 more), when the experience per kill is over 3 x or the density is over 3 x.
  `extreme` is a destination 3 x the source level or more (and 40 more): a candidate for a level gate (none is added).
  A source level under 8 counts as 8 (the level estimate of rats and fish is noise).

## Totals

8357 transitions at a monster area: 8126 ok, 135 danger, 96 extreme.

Hall hunts with a dangerous entry: Demon Skeleton (4), Haunted Treeling (1).

Dangerous entries outside every hall hunt: 226, in 226 areas of their own.

## What was done

- Near each `danger` and `extreme` entry the game flashes a skull-like effect every few seconds for players in view
  and shows a red warning once per player and area (`hunt_warnings.lua`, `hunt_warnings_config.lua`): "Perigo:
  monstros muito mais fortes adiante (nível N+)" or "Danger: much stronger monsters ahead (level N+)".
- After arriving by a floor change or teleport a second red message says the player is in a level N+ area.
- The entries stay. No level gate was added and no one is blocked.

## Dangerous entries (231)

| Source area (level) | Position | Kind | Destination | Destination band (median) | Monsters | Density (source) | Verdict |
|---|---|---|---|---|---|---|---|
| area 33436,31326,14 (2) | 33436,31326,14 | ramp/up | 33437,31326,13 | 20-65 (51) | Drownkin Scout, Drownkin Spellsinger, Drownkin Warrior | 11.2 (3.4) | extreme |
| area 33446,31338,14 (2) | 33446,31338,14 | ramp/up | 33447,31338,13 | 20-55 (51) | Drownkin Scout, Drownkin Spellsinger, Drownkin Warrior | 4.2 (2.9) | extreme |
| area 33446,31339,14 (2) | 33446,31339,14 | ramp/up | 33447,31339,13 | 20-55 (51) | Drownkin Scout, Drownkin Spellsinger, Drownkin Warrior | 4.3 (3.1) | extreme |
| area 33488,31153,14 (2) | 33488,31153,14 | stairs/down | 33488,31153,15 | 1-55 (51) | Fish, Drownkin Spellsinger, Drownkin Warrior | 4.2 (7.5) | extreme |
| area 32387,31075,7 (4) | 32387,31075,7 | hole/down | 32387,31075,8 | 25-30 (27) | Ice Golem | 0.2 (2.9) | danger |
| area 31616,31383,6 (5) | 31616,31383,6 | ladder/up | 31616,31383,5 | 425-465 (426) | Hedgehog, Velomire | 9.5 (2.8) | extreme |
| area 31616,31387,6 (5) | 31616,31387,6 | stairs/down | 31616,31387,7 | 425-465 (436) | Demibeast, Hedgehog, Velomire | 0.6 (2.6) | extreme |
| area 32089,32181,10 (6) | 32089,32181,10 | trapdoor/down | 32089,32181,11 | 5-65 (63) | Wyrm, Poison Spider, Spider | 4.8 (3.6) | extreme |
| area 31570,33043,7 (7) | 31570,33043,7 | ladder/up | 31570,33043,6 | 120-130 (120) | Bone Ruthless, Bone Knight, Bone Mage | 0.0 (4.2) | extreme |
| area 32148,31180,2 (7) | 32148,31180,2 | stairs/down | 32149,31180,3 | 25-30 (27) | Ice Golem, Crystal Spider | 1.4 (2.3) | danger |
| area 32357,31087,7 (7) | 32357,31087,7 | ramp/down | 32358,31087,8 | 25-30 (27) | Ice Golem | 0.5 (2.1) | danger |
| area 33137,31449,7 (7) | 33137,31449,7 | ramp/down | 33137,31449,8 | 10-50 (48) | Killer Caiman, Gnarlhound | 1.7 (2.5) | extreme |
| area 33142,31522,7 (7) | 33142,31522,7 | ramp/up | 33142,31521,6 | 5-30 (28) | Death Blob, Sandcrawler, Gnarlhound | 3.8 (1.2) | danger |
| area 33157,31720,7 (7) | 33157,31720,7 | ramp/down | 33156,31720,8 | 30-35 (34) | Earth Elemental | 5.2 (1.4) | danger |
| area 32022,31572,7 (8) | 32022,31572,7 | ramp/up | 32022,31571,6 | 5-40 (36) | Wyvern, Frost Troll | 3.2 (0.9) | danger |
| area 32023,31572,7 (8) | 32023,31572,7 | ramp/up | 32023,31571,6 | 5-40 (36) | Wyvern, Frost Troll | 3.2 (0.9) | danger |
| area 32070,31158,2 (8) | 32070,31158,2 | ramp/down | 32071,31158,3 | 25-50 (48) | Crystal Spider, Ice Golem | 4.9 (2.5) | extreme |
| area 32085,31089,7 (8) | 32085,31089,7 | ramp/up | 32086,31089,6 | 5-50 (44) | Crystal Spider, Frost Dragon Hatchling, Frost Troll | 0.0 (3.2) | danger |
| area 32085,31090,7 (8) | 32085,31090,7 | ramp/up | 32086,31090,6 | 5-50 (44) | Crystal Spider, Frost Dragon Hatchling, Frost Troll | 0.0 (3.1) | danger |
| area 32089,31090,5 (8) | 32089,31090,5 | stairs/down | 32088,31090,6 | 5-50 (44) | Crystal Spider, Frost Dragon Hatchling, Frost Troll | 0.0 (1.4) | danger |
| area 32089,31091,5 (8) | 32089,31091,5 | stairs/down | 32088,31091,6 | 5-50 (44) | Crystal Spider, Frost Dragon Hatchling, Frost Troll | 0.0 (1.3) | danger |
| area 32092,31189,4 (8) | 32092,31189,4 | ramp/up | 32093,31189,3 | 5-50 (27) | Crystal Spider, Mammoth, Polar Bear | 3.9 (2.3) | danger |
| area 32098,31148,2 (8) | 32098,31148,2 | ramp/up | 32098,31147,1 | 25-50 (27) | Ice Golem, Crystal Spider, Polar Bear | 0.8 (1.2) | danger |
| area 32099,31090,5 (8) | 32099,31090,5 | stairs/down | 32100,31090,6 | 5-50 (44) | Crystal Spider, Frost Dragon Hatchling, Frost Troll | 1.7 (1.1) | danger |
| area 32099,31091,5 (8) | 32099,31091,5 | stairs/down | 32100,31091,6 | 5-50 (44) | Crystal Spider, Frost Dragon Hatchling, Frost Troll | 1.6 (1.1) | danger |
| area 32103,31085,7 (8) | 32103,31085,7 | ramp/up | 32103,31086,6 | 5-50 (44) | Crystal Spider, Frost Dragon Hatchling, Frost Troll | 2.0 (2.7) | danger |
| area 32104,31085,7 (8) | 32104,31085,7 | ramp/up | 32104,31086,6 | 5-50 (44) | Crystal Spider, Frost Dragon Hatchling, Frost Troll | 2.1 (2.8) | danger |
| area 32131,31181,4 (8) | 32131,31181,4 | rope/up | 32131,31181,3 | 25-50 (27) | Ice Golem, Crystal Spider | 1.9 (1.1) | danger |
| area 32664,31431,12 (8) | 32664,31431,12 | ramp/up | 32664,31430,11 | 20-45 (42) | Dragon, Dragon Hatchling, Fire Elemental | 4.9 (4.9) | danger |
| area 32788,32318,13 (8) | 32788,32318,13 | rope/up | 32788,32318,12 | 40-75 (73) | Dragon Lord, Dragon | 4.5 (2.5) | extreme |
| area 32795,32347,14 (8) | 32795,32347,14 | hole/down | 32795,32347,15 | 70-110 (74) | Nightmare, Phantasm, Demon (Goblin) | 3.8 (6.0) | extreme |
| area 32797,32340,14 (8) | 32797,32340,14 | rope/up | 32797,32340,13 | 5-75 (74) | Demon (Goblin), Nightmare, Demon | 4.6 (5.6) | extreme |
| area 32797,32347,14 (8) | 32797,32347,14 | rope/up | 32797,32347,13 | 5-75 (74) | Demon (Goblin), Nightmare, Demon | 4.5 (6.2) | extreme |
| area 32801,32333,14 (8) | 32801,32333,14 | rope/up | 32801,32333,13 | 5-75 (74) | Demon (Goblin), Nightmare, Demon | 4.2 (5.3) | extreme |
| area 32802,32353,14 (8) | 32802,32353,14 | hole/down | 32802,32353,15 | 70-110 (74) | Nightmare, Phantasm, Demon (Goblin) | 4.9 (5.4) | extreme |
| area 32803,32358,14 (8) | 32803,32358,14 | hole/down | 32803,32358,15 | 70-75 (74) | Nightmare, Phantasm, Demon (Goblin) | 4.8 (3.3) | extreme |
| area 32803,32365,14 (8) | 32803,32365,14 | hole/down | 32803,32365,15 | 70-110 (74) | Nightmare, Phantasm, Demon (Goblin) | 3.5 (4.3) | extreme |
| area 32804,32338,14 (8) | 32804,32338,14 | hole/down | 32804,32338,15 | 70-110 (74) | Nightmare, Phantasm, Demon (Goblin) | 5.7 (4.6) | extreme |
| area 32807,32355,14 (8) | 32807,32355,14 | hole/down | 32807,32355,15 | 70-110 (74) | Nightmare, Phantasm, Demon (Goblin) | 5.2 (4.8) | extreme |
| area 32809,32333,14 (8) | 32809,32333,14 | hole/down | 32809,32333,15 | 70-110 (74) | Nightmare, Phantasm, Demon (Goblin) | 6.0 (5.1) | extreme |
| area 32809,32344,14 (8) | 32809,32344,14 | hole/down | 32809,32344,15 | 70-110 (74) | Nightmare, Phantasm, Demon (Goblin) | 5.1 (5.2) | extreme |
| area 32812,32330,14 (8) | 32812,32330,14 | rope/up | 32812,32330,13 | 5-75 (74) | Demon (Goblin), Nightmare, Demon | 6.4 (5.1) | extreme |
| area 32812,32348,14 (8) | 32812,32348,14 | hole/down | 32812,32348,15 | 70-145 (106) | Nightmare, Phantasm, Blightwalker | 6.1 (5.5) | extreme |
| area 32812,32355,14 (8) | 32812,32355,14 | hole/down | 32812,32355,15 | 70-140 (97) | Nightmare, Plaguesmith, Phantasm | 5.3 (4.1) | extreme |
| area 32813,32342,14 (8) | 32813,32342,14 | rope/up | 32813,32342,13 | 5-140 (74) | Demon (Goblin), Nightmare, Demon | 5.2 (4.9) | extreme |
| area 32813,32346,14 (8) | 32813,32346,14 | rope/up | 32813,32346,13 | 5-140 (74) | Demon (Goblin), Nightmare, Demon | 4.7 (4.9) | extreme |
| area 32816,32335,14 (8) | 32816,32335,14 | hole/down | 32816,32335,15 | 70-145 (106) | Nightmare, Phantasm, Blightwalker | 6.6 (6.0) | extreme |
| area 32816,32342,14 (8) | 32816,32342,14 | rope/up | 32816,32342,13 | 5-105 (74) | Demon (Goblin), Nightmare, Demon | 6.1 (5.2) | extreme |
| area 32816,32364,14 (8) | 32816,32364,14 | rope/up | 32816,32364,13 | 5-140 (74) | Demon (Goblin), Nightmare, Demon | 4.7 (5.0) | extreme |
| area 32817,32322,14 (8) | 32817,32322,14 | hole/down | 32817,32322,15 | 70-140 (106) | Nightmare, Phantasm, Blightwalker | 8.1 (4.7) | extreme |
| area 32817,32358,14 (8) | 32817,32358,14 | rope/up | 32817,32358,13 | 5-105 (74) | Demon (Goblin), Nightmare, Demon | 3.6 (2.4) | extreme |
| area 32822,32320,14 (8) | 32822,32320,14 | hole/down | 32822,32320,15 | 70-150 (137) | Blightwalker, Nightmare, Phantasm | 7.7 (3.0) | extreme |
| area 32823,32321,14 (8) | 32823,32321,14 | rope/up | 32823,32321,13 | 70-80 (74) | Nightmare, Destroyer, Demon (Goblin) | 10.0 (2.0) | extreme |
| area 32969,31477,2 (8) | 32969,31477,2 | trapdoor/down | 32969,31477,3 | 25-55 (39) | Vampire Bride, Giant Spider, Nightstalker | 3.2 (10.6) | danger |
| area 32987,32681,7 (8) | 32987,32681,7 | ramp/up | 32988,32681,6 | 70-105 (81) | Hydra, Dawnfire Asura, Hellspawn | 1.0 (2.7) | extreme |
| area 33126,31303,7 (8) | 33126,31303,7 | ramp/up | 33125,31303,6 | 20-45 (42) | Dragon, Dragon Hatchling | 1.8 (1.2) | danger |
| area 33130,31353,7 (8) | 33130,31353,7 | ramp/down | 33130,31353,8 | 20-45 (27) | Lancer Beetle, Thundertusk, Orc Berserker | 1.3 (6.2) | danger |
| area 33149,31639,10 (8) | 33149,31639,10 | trapdoor/down | 33149,31639,11 | 70-105 (95) | Betrayed Wraith, Lost Soul, Giant Spider | 2.0 (7.5) | extreme |
| area 32089,32961,9 (9) | 32089,32961,9 | hole/down | 32089,32961,10 | 25-30 (27) | Zombie, Ghoul | 5.4 (3.7) | danger |
| area 32127,32164,9 (9) | 32127,32164,9 | ladder/up | 32127,32164,8 | 5-40 (39) | Necromancer, Spider, Poison Spider | 4.6 (4.2) | danger |
| area 32586,31361,12 (9) | 32586,31361,12 | stairs/down | 32586,31361,13 | 20-75 (36) | Dragon, Dragon Hatchling, Dragon Lord | 1.2 (4.1) | danger |
| area 32587,31361,12 (9) | 32587,31361,12 | stairs/down | 32587,31361,13 | 20-75 (36) | Dragon, Dragon Hatchling, Dragon Lord | 1.2 (3.8) | danger |
| area 32596,31359,12 (9) | 32596,31359,12 | stairs/down | 32597,31359,13 | 20-45 (36) | Wyvern, Dragon, Dragon Hatchling | 1.0 (4.9) | danger |
| area 32596,31360,12 (9) | 32596,31360,12 | stairs/down | 32597,31360,13 | 20-45 (36) | Wyvern, Dragon, Dragon Hatchling | 1.0 (4.9) | danger |
| area 32602,31366,12 (9) | 32602,31366,12 | stairs/down | 32602,31366,13 | 35-75 (36) | Wyvern, Dragon, Dragon Hatchling | 1.0 (4.2) | danger |
| area 32603,31366,12 (9) | 32603,31366,12 | stairs/down | 32603,31366,13 | 35-75 (36) | Wyvern, Dragon, Dragon Hatchling | 1.0 (3.9) | danger |
| area 32607,31429,12 (9) | 32607,31429,12 | ramp/up | 32607,31430,11 | 10-45 (27) | Dragon, Elder Bonelord, Skeleton Warrior | 1.4 (3.5) | danger |
| area 32608,31429,12 (9) | 32608,31429,12 | ramp/up | 32608,31430,11 | 10-45 (27) | Dragon, Elder Bonelord, Skeleton Warrior | 1.4 (3.4) | danger |
| area 32655,31406,12 (9) | 32655,31406,12 | ramp/up | 32654,31406,11 | 20-45 (42) | Dragon, Dragon Hatchling, Fire Elemental | 2.9 (1.8) | danger |
| area 32658,31224,7 (9) | 32658,31224,7 | stairs/down | 32659,31224,8 | 30-35 (34) | Mutated Rat | 0.8 (4.4) | danger |
| area 32694,31229,7 (9) | 32694,31229,7 | stairs/down | 32694,31229,8 | 30-35 (34) | Mutated Rat | 1.6 (5.7) | danger |
| area 32818,32143,10 (9) | 32818,32143,10 | rope/up | 32818,32143,9 | 10-45 (42) | Dragon, Dragon Lord, Marsh Stalker | 1.0 (2.4) | danger |
| area 32987,32680,7 (9) | 32987,32680,7 | ramp/up | 32988,32680,6 | 70-105 (81) | Hydra, Dawnfire Asura, Hellspawn | 1.0 (2.8) | extreme |
| area 33042,32632,6 (9) | 33042,32632,6 | trapdoor/down | 33042,32632,7 | 40-45 (42) | Dragon | 0.0 (4.2) | danger |
| area 33044,32632,6 (9) | 33044,32632,6 | trapdoor/down | 33044,32632,7 | 40-45 (42) | Dragon | 0.0 (4.2) | danger |
| area 33075,31186,8 (9) | 33075,31186,8 | stairs/up | 33074,31186,7 | 50-65 (61) | Lizard High Guard, Lizard Legionnaire, Dragon Hatchling | 4.5 (2.3) | extreme |
| area 33224,31651,7 (9) | 33224,31651,7 | stairs/down | 33224,31651,8 | 20-40 (39) | Bonebeast, Cyclops, Vicious Squire | 9.0 (1.0) | danger |
| area 33225,31651,7 (9) | 33225,31651,7 | stairs/down | 33225,31651,8 | 20-40 (39) | Bonebeast, Cyclops, Vicious Squire | 8.7 (1.0) | danger |
| area 31929,31655,9 (10) | 31929,31655,9 | hole/down | 31928,31655,10 | 40-45 (41) | Water Elemental | 1.3 (1.2) | danger |
| area 33009,31437,7 (10) | 33009,31437,7 | ramp/up | 33008,31437,6 | 10-70 (70) | Werewolf, War wolf | 0.7 (2.5) | extreme |
| area 33013,32564,7 (10) | 33013,32564,7 | ramp/down | 33014,32564,8 | 80-85 (80) | Behemoth | 1.2 (3.3) | extreme |
| area 32207,32100,12 (11) | 32207,32100,12 | stairs/down | 32207,32100,13 | 25-55 (55) | Hero, Vampire, Vampire Bride | 4.8 (4.1) | extreme |
| area 32598,31395,12 (11) | 32598,31395,12 | stairs/down | 32598,31394,13 | 20-90 (36) | Wyvern, Diabolic Imp, Dragon Hatchling | 0.7 (1.7) | danger |
| area 32598,31400,12 (11) | 32598,31400,12 | stairs/down | 32598,31400,13 | 5-90 (36) | Diabolic Imp, Skeleton, Wyvern | 0.4 (1.7) | danger |
| area 32613,31390,12 (11) | 32613,31390,12 | stairs/down | 32613,31390,13 | 10-65 (36) | Wyrm, Wyvern, Gutworm | 1.4 (2.0) | danger |
| area 32621,31381,12 (11) | 32621,31381,12 | ramp/up | 32622,31381,11 | 20-50 (39) | Bonebeast, Bonelord, Lich | 2.3 (1.2) | danger |
| area 32621,31382,12 (11) | 32621,31382,12 | ramp/up | 32622,31382,11 | 20-50 (39) | Bonebeast, Bonelord, Lich | 1.5 (1.2) | danger |
| area 32846,32165,5 (11) | 32846,32165,5 | stairs/down | 32846,32165,6 | 5-45 (42) | Dragon, Scorpion, Wolf | 0.0 (6.7) | danger |
| area 32847,32165,5 (11) | 32847,32165,5 | stairs/down | 32847,32165,6 | 5-45 (42) | Dragon, Scorpion, Wolf | 0.0 (6.1) | danger |
| area 32978,32635,7 (11) | 32978,32635,7 | ramp/up | 32978,32634,6 | 40-75 (73) | Dragon Lord, Dragon | 0.0 (1.5) | extreme |
| area 32979,32635,7 (11) | 32979,32635,7 | ramp/up | 32979,32634,6 | 40-75 (73) | Dragon Lord, Dragon | 0.0 (2.2) | extreme |
| area 33031,31274,8 (11) | 33031,31274,8 | ramp/up | 33031,31275,7 | 15-95 (91) | Coastal Catcher, Lizard High Guard, Orc Leader | 2.3 (4.7) | extreme |
| area 33035,32632,6 (11) | 33035,32632,6 | stairs/up | 33035,32631,5 | 20-75 (42) | Dragon, Hydra, Gargoyle | 3.1 (4.6) | danger |
| area 32779,31935,10 (13) | 32779,31935,10 | hole/down | 32779,31935,11 | 20-40 (36) | Wyvern, Hunter, Poacher | 5.1 (3.1) | danger |
| area 32041,32909,8 (15) | 32041,32909,8 | hole/down | 32042,32909,9 | 15-40 (36) | Wyvern, Pirate Skeleton, Crystal Spider | 1.4 (1.6) | danger |
| area 32975,31423,5 (15) | 32975,31423,5 | ladder/up | 32975,31423,4 | 15-85 (73) | Ghoul, Hellspawn, Spectre | 1.2 (6.7) | extreme |
| area 32059,31139,6 (16) | 32059,31139,6 | ramp/down | 32059,31139,7 | 25-40 (39) | Ice Golem, Ice Witch, Crystal Spider | 2.9 (2.7) | danger |
| area 32824,31084,7 (16) | 32824,31084,7 | stairs/down | 32824,31084,8 | 25-120 (81) | Acolyte of the Cult, Hellspawn, Plaguesmith | 6.8 (4.5) | extreme |
| area 32857,31283,8 (16) | 32857,31283,8 | stairs/down | 32857,31283,9 | 20-60 (57) | Worker Golem, Fire Elemental, Damaged Worker Golem | 0.8 (1.4) | extreme |
| area 32879,31294,8 (16) | 32879,31294,8 | stairs/down | 32879,31294,9 | 20-60 (44) | Worker Golem, Fire Elemental, Mad Scientist | 3.2 (1.0) | danger |
| area 32900,31285,8 (16) | 32900,31285,8 | stairs/down | 32900,31285,9 | 20-60 (57) | Worker Golem, Fire Elemental, Damaged Worker Golem | 1.9 (1.3) | extreme |
| area 32904,31074,5 (16) | 32904,31074,5 | stairs/up | 32904,31073,4 | 20-40 (39) | Necromancer, Dark Magician, Infernalist | 1.3 (5.3) | danger |
| area 32909,31310,8 (16) | 32909,31310,8 | stairs/down | 32909,31310,9 | 20-60 (57) | Worker Golem, Fire Elemental, Mad Scientist | 1.6 (1.8) | extreme |
| area 32913,31256,8 (16) | 32913,31256,8 | stairs/down | 32913,31256,9 | 55-60 (57) | Worker Golem | 1.1 (3.3) | extreme |
| area 33156,31647,10 (16) | 33156,31647,10 | hole/down | 33156,31647,11 | 70-105 (101) | Lost Soul, Betrayed Wraith, Giant Spider | 3.6 (6.1) | extreme |
| area 32921,32870,7 (17) | 32921,32870,7 | stairs/down | 32921,32870,8 | 70-75 (73) | Hydra | 2.9 (5.0) | extreme |
| area 32922,32870,7 (17) | 32922,32870,7 | stairs/down | 32922,32870,8 | 70-75 (73) | Hydra | 3.0 (5.1) | extreme |
| area 33028,31286,4 (17) | 33028,31286,4 | ladder/up | 33028,31286,3 | 25-45 (41) | Orc Warlord, Orc Leader, Orc Warrior | 10.6 (5.0) | danger |
| area 33028,31286,6 (17) | 33028,31286,6 | stairs/down | 33028,31286,7 | 15-95 (41) | Coastal Catcher, Orc Leader, Orc Shaman | 3.1 (3.7) | danger |
| area 33038,31289,4 (17) | 33038,31289,4 | ladder/up | 33038,31289,3 | 25-45 (41) | Orc Warlord, Orc Leader, Orc Warrior | 11.7 (5.8) | danger |
| area 33045,31292,4 (17) | 33045,31292,4 | ladder/up | 33045,31292,3 | 25-45 (41) | Orc Warlord, Orc Leader, Orc Warrior | 15.6 (6.6) | danger |
| area 32211,31924,14 (18) | 32211,31924,14 | trapdoor/down | 32211,31924,15 | 15-50 (48) | Banshee, Ghost, Dragon Lord | 0.0 (6.0) | danger |
| area 32216,31931,14 (18) | 32216,31931,14 | trapdoor/down | 32216,31931,15 | 15-50 (48) | Banshee, Ghost, Mummy | 0.0 (6.1) | danger |
| area 32219,31948,14 (18) | 32219,31948,14 | trapdoor/down | 32219,31948,15 | 15-50 (48) | Banshee, Ghost, Mummy | 0.9 (4.3) | danger |
| area 32769,31099,2 (18) | 32769,31099,2 | stairs/up | 32769,31098,1 | 45-50 (48) | Giant Spider | 4.0 (5.5) | danger |
| area 32784,31099,2 (18) | 32784,31099,2 | stairs/up | 32784,31098,1 | 45-50 (48) | Giant Spider | 2.9 (4.2) | danger |
| area 32888,32872,9 (18) | 32888,32872,9 | hole/down | 32888,32872,10 | 15-50 (48) | Giant Spider, Tarantula | 5.0 (2.5) | danger |
| area 33355,32612,10 (18) | 33355,32612,10 | ramp/down | 33356,32612,11 | 15-45 (43) | Ancient Scarab, Scarab, Bonebeast | 5.1 (2.6) | danger |
| area 33355,32613,10 (18) | 33355,32613,10 | ramp/down | 33356,32613,11 | 15-45 (43) | Ancient Scarab, Scarab, Bonebeast | 5.2 (3.1) | danger |
| area 33567,31213,14 (18) | 33567,31213,14 | stairs/down | 33567,31212,15 | 20-75 (51) | Drownkin Guard, Drownkin Scout, Drownkin Spellsinger | 3.1 (1.8) | danger |
| Haunted Treeling (20) | 32940,31450,7 | stairs/up | 32940,31449,6 | 25-55 (52) | Vampire Bride, Vampire, Hellspawn | 3.0 (2.2) | danger |
| area 32481,31871,14 (20) | 32481,31871,14 | hole/down | 32481,31871,15 | 55-70 (68) | Lost Thrower, Lost Basher, Lost Husher | 1.2 (1.8) | extreme |
| area 32549,31861,10 (20) | 32549,31861,10 | hole/down | 32549,31861,11 | 10-45 (42) | Dragon, Dwarf Soldier, Dragon Lord | 1.4 (5.9) | danger |
| area 32559,31859,10 (20) | 32559,31859,10 | hole/down | 32559,31859,11 | 20-45 (42) | Dragon, Dragon Lord, Dwarf Soldier | 1.8 (4.7) | danger |
| area 32670,31184,7 (20) | 32670,31184,7 | stairs/down | 32670,31184,8 | 20-60 (59) | Nightmare Scion, Mutated Human, Slime | 6.1 (3.2) | danger |
| area 32681,31178,9 (20) | 32681,31178,9 | stairs/up | 32681,31177,8 | 20-60 (59) | Nightmare Scion, Mutated Human, Slime | 4.8 (3.7) | danger |
| area 32681,31181,7 (20) | 32681,31181,7 | stairs/down | 32681,31181,8 | 20-60 (59) | Nightmare Scion, Mutated Human, Slime | 4.5 (6.2) | danger |
| area 32684,31161,9 (20) | 32684,31161,9 | stairs/down | 32684,31161,10 | 45-140 (138) | Plaguesmith, Bog Raider | 2.7 (2.8) | extreme |
| area 32689,31097,8 (20) | 32689,31097,8 | stairs/up | 32689,31096,7 | 40-45 (45) | Bog Raider, Mutated Tiger, Acid Blob | 2.8 (2.0) | danger |
| area 32781,32268,9 (20) | 32781,32268,9 | ramp/down | 32781,32268,10 | 40-45 (42) | Dragon, Dragon Lord | 2.5 (4.7) | danger |
| area 32872,32833,7 (20) | 32872,32833,7 | stairs/up | 32871,32833,6 | 30-90 (44) | Clay Guardian, Gnawbloom, Serpent Spawn | 7.5 (5.9) | danger |
| area 32872,32834,7 (20) | 32872,32834,7 | stairs/up | 32871,32834,6 | 30-90 (44) | Clay Guardian, Gnawbloom, Serpent Spawn | 7.3 (5.3) | danger |
| area 32942,32677,7 (20) | 32942,32677,7 | pitfall/down | 32942,32677,8 | 45-75 (73) | Hydra, Lich | 5.5 (2.2) | extreme |
| area 32944,32670,7 (20) | 32944,32670,7 | stairs/up | 32943,32670,6 | 80-105 (102) | Dawnfire Asura, Hellspawn, Midnight Asura | 4.1 (2.2) | extreme |
| area 32944,32700,7 (20) | 32944,32700,7 | hole/down | 32945,32700,8 | 45-75 (73) | Hydra, Lich | 0.5 (0.3) | extreme |
| area 32944,32701,7 (20) | 32944,32701,7 | hole/down | 32945,32701,8 | 45-75 (73) | Hydra, Lich | 0.5 (0.3) | extreme |
| area 32988,32523,7 (20) | 32988,32523,7 | hole/down | 32988,32523,8 | 15-80 (73) | Tarantula, Behemoth, Hydra | 0.8 (3.2) | extreme |
| area 33049,32627,8 (20) | 33049,32627,8 | stairs/up | 33049,32626,7 | 40-45 (42) | Dragon | 0.0 (6.0) | danger |
| area 33052,32693,8 (20) | 33052,32693,8 | ramp/up | 33053,32693,7 | 10-45 (42) | Dragon, Nomad, Dragon Lord | 0.0 (3.9) | danger |
| area 33227,31698,12 (20) | 33227,31698,12 | ramp/down | 33227,31698,13 | 60-100 (100) | Hellfire Fighter, Massive Fire Elemental | 3.8 (5.1) | extreme |
| area 33228,31698,12 (20) | 33228,31698,12 | ramp/down | 33228,31698,13 | 60-100 (100) | Hellfire Fighter, Massive Fire Elemental | 3.8 (5.1) | extreme |
| area 33232,31698,12 (20) | 33232,31698,12 | ramp/down | 33232,31698,13 | 60-100 (100) | Hellfire Fighter, Massive Fire Elemental | 3.9 (5.1) | extreme |
| area 33233,31698,12 (20) | 33233,31698,12 | ramp/down | 33233,31698,13 | 60-100 (100) | Hellfire Fighter, Massive Fire Elemental | 3.9 (5.1) | extreme |
| area 33306,31569,7 (20) | 33306,31569,7 | stairs/up | 33306,31568,6 | 20-65 (53) | Lizard Templar, Lizard High Guard, Lizard Legionnaire | 3.5 (1.2) | danger |
| area 33470,31279,13 (20) | 33470,31279,13 | stairs/down | 33469,31279,14 | 15-65 (62) | Drownkin Warrior, Drownkin worker, Drownkin Guard | 1.4 (6.0) | extreme |
| area 33470,31281,13 (20) | 33470,31281,13 | stairs/down | 33469,31281,14 | 15-65 (62) | Drownkin Warrior, Drownkin worker, Drownkin Guard | 1.4 (5.8) | extreme |
| area 32503,31577,15 (21) | 32503,31577,15 | stairs/up | 32503,31576,14 | 20-105 (101) | Warlock, Elf Arcanist | 2.0 (2.2) | extreme |
| area 32504,31577,15 (21) | 32504,31577,15 | stairs/up | 32504,31576,14 | 20-105 (101) | Warlock, Elf Arcanist | 2.0 (2.7) | extreme |
| area 32515,31577,15 (21) | 32515,31577,15 | stairs/up | 32515,31576,14 | 20-105 (101) | Warlock, Elf Arcanist | 2.0 (2.0) | extreme |
| area 32516,31577,15 (21) | 32516,31577,15 | stairs/up | 32516,31576,14 | 20-105 (101) | Warlock, Elf Arcanist | 2.0 (1.4) | extreme |
| area 32625,31851,14 (21) | 32625,31851,14 | hole/down | 32625,31851,15 | 10-70 (68) | Lost Husher, Dwarf Soldier, Lost Basher | 0.0 (3.3) | extreme |
| area 32704,31156,9 (21) | 32704,31156,9 | stairs/down | 32704,31156,10 | 45-140 (74) | Plaguesmith, Bog Raider, Nightmare | 0.8 (1.6) | extreme |
| area 32744,31284,10 (21) | 32744,31284,10 | ramp/down | 32745,31284,11 | 40-45 (42) | Dragon, Serpent Spawn | 0.8 (1.2) | danger |
| area 32755,31279,10 (21) | 32755,31279,10 | ramp/down | 32756,31279,11 | 40-45 (42) | Dragon | 0.5 (0.9) | danger |
| area 32798,31057,7 (21) | 32798,31057,7 | stairs/down | 32799,31057,8 | 30-140 (119) | Grim Reaper, Plaguesmith, Acolyte of the Cult | 1.5 (1.5) | extreme |
| area 32798,31058,7 (21) | 32798,31058,7 | stairs/down | 32799,31058,8 | 25-120 (119) | Grim Reaper, Acolyte of the Cult, Plaguesmith | 1.6 (1.2) | extreme |
| area 32829,31040,7 (21) | 32829,31040,7 | ramp/down | 32830,31040,8 | 80-140 (81) | Hellspawn, Plaguesmith, Grim Reaper | 7.0 (5.9) | extreme |
| area 32839,31034,7 (21) | 32839,31034,7 | ramp/down | 32838,31034,8 | 80-140 (81) | Hellspawn, Plaguesmith | 4.6 (4.2) | extreme |
| area 32058,32602,4 (22) | 32058,32602,4 | hole/down | 32057,32602,5 | 20-90 (73) | Diabolic Imp, Fire Elemental, Dragon Lord Hatchling | 5.0 (6.0) | extreme |
| area 32804,32147,7 (22) | 32804,32147,7 | ramp/up | 32805,32147,6 | 20-45 (42) | Dragon, Dragon Hatchling | 5.7 (0.9) | danger |
| area 32804,32148,7 (22) | 32804,32148,7 | hole/down | 32805,32148,8 | 10-45 (42) | Dragon, Scorpion, Dragon Hatchling | 4.5 (1.0) | danger |
| area 32825,32143,7 (22) | 32825,32143,7 | ramp/up | 32826,32143,6 | 40-45 (42) | Dragon | 7.1 (1.6) | danger |
| area 32838,32156,8 (22) | 32838,32156,8 | stairs/down | 32839,32156,9 | 40-75 (42) | Dragon, Dragon Lord, Dragon Lord Hatchling | 2.1 (2.6) | danger |
| area 33226,31278,6 (22) | 33226,31278,6 | ramp/up | 33227,31278,5 | 70-75 (73) | Dragon Lord, Dragon Lord Hatchling | 6.7 (1.7) | extreme |
| area 33238,31346,6 (22) | 33238,31346,6 | ramp/up | 33238,31347,5 | 40-75 (73) | Dragon Lord, Dragon Lord Hatchling | 2.6 (3.2) | extreme |
| area 33314,31553,6 (22) | 33314,31553,6 | stairs/up | 33314,31552,5 | 60-70 (66) | Lizard Warbound, Lizard High Guard | 3.0 (5.7) | extreme |
| area 33336,31553,6 (22) | 33336,31553,6 | stairs/up | 33336,31552,5 | 60-70 (66) | Lizard Warbound, Lizard High Guard | 3.6 (5.4) | extreme |
| area 33150,31595,12 (23) | 33150,31595,12 | rope/up | 33150,31595,11 | 20-45 (42) | Dragon, Dragon Hatchling, Demon | 2.5 (5.0) | danger |
| area 33265,31669,15 (23) | 33265,31669,15 | ramp/up | 33264,31669,14 | 25-80 (80) | Behemoth, Cyclops Smith | 3.8 (3.8) | extreme |
| area 33285,31700,13 (23) | 33285,31700,13 | stairs/up | 33285,31699,12 | 20-45 (42) | Dragon, Fire Elemental, Dragon Lord | 3.2 (5.9) | danger |
| area 33300,31743,14 (23) | 33300,31743,14 | stairs/down | 33299,31743,15 | 20-80 (80) | Behemoth, Cyclops Drone | 2.8 (4.6) | extreme |
| area 33301,31714,13 (23) | 33301,31714,13 | stairs/up | 33301,31713,12 | 20-45 (42) | Dragon, Fire Elemental, Dragon Lord | 2.2 (2.8) | danger |
| area 33306,31705,11 (23) | 33306,31705,11 | stairs/down | 33306,31705,12 | 20-45 (42) | Dragon, Fire Elemental, Dragon Lord | 1.9 (6.4) | danger |
| area 33313,31583,7 (23) | 33313,31583,7 | stairs/up | 33313,31582,6 | 20-65 (58) | Lizard High Guard, Lizard Dragon Priest, Lizard Templar | 5.7 (1.5) | danger |
| area 33321,31573,7 (23) | 33321,31573,7 | stairs/up | 33321,31572,6 | 20-65 (58) | Lizard Dragon Priest, Lizard High Guard, Lizard Templar | 5.1 (2.1) | danger |
| area 33339,31685,15 (23) | 33339,31685,15 | ramp/up | 33340,31685,14 | 80-85 (80) | Behemoth, Cyclops Drone | 4.5 (3.7) | extreme |
| area 33345,31569,7 (23) | 33345,31569,7 | stairs/up | 33345,31568,6 | 20-65 (58) | Lizard Dragon Priest, Lizard High Guard, Lizard Templar | 3.8 (1.3) | danger |
| area 33238,31603,14 (24) | 33238,31603,14 | ladder/up | 33238,31603,13 | 105-110 (107) | Fury, Fire Elemental | 0.0 (9.9) | extreme |
| area 33244,31603,12 (24) | 33244,31603,12 | trapdoor/down | 33244,31603,13 | 105-110 (107) | Fury, Blightwalker | 0.0 (4.0) | extreme |
| area 33287,31592,14 (24) | 33287,31592,14 | stairs/up | 33287,31591,13 | 20-140 (137) | Demon, Fire Elemental | 2.9 (2.7) | extreme |
| Demon Skeleton (25) | 33012,32457,11 | other/down | 33012,32455,12 (Wyrm) | 30-120 (45) | Grim Reaper, Shadow Pupil, Vampire Viscount | 1.9 (5.6) | danger |
| Demon Skeleton (25) | 33031,32449,11 | stairs/down | 33032,32449,12 (Wyrm) | 45-120 (119) | Grim Reaper, Shadow Pupil, Gravedigger | 4.9 (4.9) | extreme |
| Demon Skeleton (25) | 33031,32450,11 | stairs/down | 33032,32450,12 (Wyrm) | 45-120 (119) | Grim Reaper, Shadow Pupil, Gravedigger | 5.3 (4.5) | extreme |
| Demon Skeleton (25) | 33031,32451,11 | stairs/down | 33032,32451,12 (Wyrm) | 30-120 (119) | Grim Reaper, Shadow Pupil, Gravedigger | 4.6 (3.9) | extreme |
| area 32083,32799,13 (25) | 32083,32799,13 | ladder/up | 32083,32799,12 (Saltkin Mantassin) | 30-55 (45) | Saltkin Hydromancer, Saltkin Mantassin, Saltkin Constrictor | 1.8 (7.1) | danger |
| area 32241,31920,14 (25) | 32241,31920,14 | trapdoor/down | 32241,31920,15 | 45-75 (48) | Banshee, Dragon Lord, Fire Devil | 0.0 (5.5) | danger |
| area 32911,31184,12 (25) | 32911,31184,12 | stairs/down | 32910,31184,13 | 45-55 (55) | Saltkin Pincher, Saltkin Hydromancer, Saltkin Predator | 6.0 (3.0) | danger |
| area 32915,31193,12 (25) | 32915,31193,12 | stairs/down | 32914,31193,13 | 45-65 (55) | Saltkin Pincher, Saltkin Hydromancer, Saltkin Predator | 5.3 (3.8) | danger |
| area 33265,31721,15 (26) | 33265,31721,15 | ramp/up | 33264,31721,14 | 25-80 (80) | Behemoth, Cyclops Smith | 4.1 (4.2) | extreme |
| area 32024,31076,10 (27) | 32024,31076,10 | ramp/up | 32025,31076,9 (Hellspawn) | 5-130 (81) | Hellspawn, Frost Troll, Ghastly Dragon | 5.2 (1.8) | extreme |
| area 32241,31045,10 (27) | 32241,31045,10 | hole/down | 32242,31045,11 | 35-50 (48) | Crystal Spider, Enlightened of the Cult, Nightmare | 3.7 (2.4) | danger |
| area 32766,31045,7 (27) | 32766,31045,7 | stairs/down | 32766,31045,8 | 40-50 (48) | Banshee, Grim Reaper, Mindrot | 1.0 (2.5) | danger |
| area 32798,31030,7 (27) | 32798,31030,7 | stairs/down | 32798,31030,8 | 115-120 (119) | Grim Reaper | 0.6 (1.0) | extreme |
| area 32798,31044,7 (27) | 32798,31044,7 | stairs/down | 32798,31044,8 | 115-120 (119) | Grim Reaper | 1.2 (1.1) | extreme |
| area 32973,32437,12 (28) | 32973,32437,12 | stairs/down | 32973,32437,13 | 45-120 (45) | Vampire Viscount, Grim Reaper, Vampire | 2.4 (4.1) | danger |
| area 32974,32437,12 (28) | 32974,32437,12 | stairs/down | 32974,32437,13 | 45-120 (45) | Vampire Viscount, Grim Reaper, Vampire | 2.5 (3.5) | danger |
| area 32975,32437,12 (28) | 32975,32437,12 | stairs/down | 32975,32437,13 | 45-120 (45) | Vampire Viscount, Grim Reaper, Vampire | 2.2 (3.7) | danger |
| area 32915,31170,12 (32) | 32915,31170,12 | stairs/down | 32914,31170,13 | 45-55 (55) | Saltkin Pincher, Saltkin Hydromancer, Saltkin Predator | 4.8 (2.5) | danger |
| area 32936,31161,12 (32) | 32936,31161,12 | stairs/down | 32935,31161,13 | 45-55 (55) | Saltkin Pincher, Saltkin Hydromancer, Saltkin Mantassin | 4.5 (4.2) | danger |
| area 32936,31204,12 (32) | 32936,31204,12 | stairs/down | 32936,31204,13 | 45-65 (55) | Saltkin Pincher, Saltkin Hydromancer, Saltkin Predator | 7.6 (1.9) | danger |
| area 32954,31152,12 (32) | 32954,31152,12 | stairs/down | 32954,31151,13 | 45-55 (55) | Saltkin Pincher, Saltkin Hydromancer, Saltkin Predator | 4.8 (2.8) | danger |
| area 33001,32432,12 (32) | 33001,32432,12 | stairs/down | 33001,32432,13 | 45-120 (49) | Grim Reaper, Banshee, Vampire Viscount | 1.5 (4.0) | danger |
| area 33002,32432,12 (32) | 33002,32432,12 | stairs/down | 33002,32432,13 | 45-120 (52) | Grim Reaper, Banshee, Gravedigger | 1.7 (3.2) | danger |
| area 32083,31031,5 (36) | 32083,31031,5 | ramp/down | 32083,31031,6 | 35-75 (73) | Frost Dragon, Frost Dragon Hatchling, Frost Giantess | 2.0 (5.7) | danger |
| area 32784,31049,7 (36) | 32784,31049,7 | stairs/down | 32785,31049,8 | 40-120 (119) | Grim Reaper, Mutated Bat, Banshee | 0.7 (1.0) | extreme |
| area 32783,31059,8 (40) | 32783,31059,8 | trapdoor/down | 32783,31059,9 | 115-120 (119) | Grim Reaper | 0.7 (0.8) | danger |
| area 32784,31023,8 (40) | 32784,31023,8 | trapdoor/down | 32784,31023,9 | 115-120 (119) | Grim Reaper | 5.0 (1.0) | danger |
| area 33157,31270,6 (42) | 33157,31270,6 | ramp/up | 33158,31270,5 | 70-75 (73) | Dragon Lord, Dragon Lord Hatchling | 1.6 (1.7) | danger |
| area 33198,31284,6 (42) | 33198,31284,6 | ramp/up | 33199,31284,5 | 40-75 (73) | Dragon Lord, Dragon Lord Hatchling | 7.8 (2.8) | danger |
| area 33249,31316,6 (42) | 33249,31316,6 | ramp/up | 33248,31316,5 | 70-75 (73) | Dragon Lord, Dragon | 2.1 (3.4) | danger |
| area 33255,31293,6 (42) | 33255,31293,6 | ramp/up | 33254,31293,5 | 70-75 (73) | Dragon Lord, Dragon Lord Hatchling, Dragon | 2.3 (1.4) | danger |
| area 33530,31921,9 (42) | 33530,31921,9 | stairs/down | 33530,31921,10 | 40-70 (67) | Sludgebrass Anemone, Sludgebrass Blob, Rot Elemental | 8.1 (1.3) | danger |
| area 33597,31906,8 (42) | 33597,31906,8 | other/down | 33597,31906,9 | 40-70 (67) | Devourer, Rot Elemental, Sludgebrass Anemone | 5.2 (0.4) | danger |
| area 33082,31819,11 (48) | 33082,31819,11 | stairs/down | 33082,31819,12 | 45-110 (106) | Phantasm, Giant Spider, Nightmare | 3.7 (3.1) | danger |
| area 33083,31819,11 (48) | 33083,31819,11 | stairs/down | 33083,31819,12 | 45-110 (106) | Phantasm, Giant Spider, Nightmare | 3.7 (2.4) | danger |
| area 33013,32472,12 (49) | 33013,32472,12 | stairs/down | 33014,32472,13 | 45-120 (119) | Grim Reaper, Banshee, Gravedigger | 2.0 (2.6) | danger |
| area 33013,32473,12 (49) | 33013,32473,12 | stairs/down | 33014,32473,13 | 45-120 (119) | Grim Reaper, Banshee, Gravedigger | 1.8 (2.5) | danger |
| area 33013,32474,12 (49) | 33013,32474,12 | stairs/down | 33014,32474,13 | 45-120 (119) | Grim Reaper, Banshee, Gravedigger | 1.6 (2.5) | danger |
| area 33013,32475,12 (49) | 33013,32475,12 | stairs/down | 33014,32475,13 | 45-120 (119) | Grim Reaper, Banshee, Gravedigger | 1.6 (2.5) | danger |
| area 33013,32476,12 (49) | 33013,32476,12 | stairs/down | 33014,32476,13 | 45-120 (119) | Grim Reaper, Banshee, Gravedigger | 1.6 (2.6) | danger |
| area 32228,32120,13 (52) | 32228,32120,13 | stairs/down | 32228,32120,14 | 135-140 (137) | Demon | 0.8 (2.6) | danger |
| area 31782,33127,9 (58) | 31782,33127,9 | stairs/down | 31783,33127,10 | 85-140 (130) | Ghastly Dragon, Undead Dragon, Demon | 2.6 (3.4) | danger |
| area 31782,33129,9 (58) | 31782,33129,9 | stairs/down | 31783,33129,10 | 85-140 (130) | Ghastly Dragon, Undead Dragon, Demon | 2.6 (1.4) | danger |
| area 32785,31035,7 (59) | 32785,31035,7 | stairs/down | 32785,31035,8 | 40-120 (119) | Grim Reaper, Mutated Bat, Banshee | 0.8 (0.8) | danger |
| area 31648,32253,7 (104) | 31648,32253,7 | stairs/up | 31648,32252,6 | 720-930 (810) | Black Stag, Blazebringer, Blight Bloom | 13.1 (5.8) | extreme |
| area 31720,32921,12 (125) | 31720,32921,12 | hole/down | 31720,32921,13 | 80-285 (284) | Juggernaut, Magma Crawler | 8.6 (13.0) | danger |
| area 31722,32926,15 (142) | 31722,32926,15 | ladder/up | 31722,32926,14 | 160-285 (284) | Juggernaut, Feral Sphinx | 8.9 (5.1) | danger |
| area 30798,31209,7 (225) | 30798,31209,7 | stairs/up | 30799,31209,6 | 225-440 (436) | Frost Hydra, Frost Larva | 5.0 (1.1) | danger |
| area 30875,31252,7 (225) | 30875,31252,7 | stairs/up | 30876,31252,6 | 360-440 (436) | Frost Hydra, Frosted Dragon | 0.8 (2.2) | danger |
| area 34276,31058,14 (346) | 34276,31058,14 | stairs/up | 34276,31057,13 | 340-960 (880) | Azure Dragon, Jungle Beasts, Nightglass Matter | 5.7 (3.4) | danger |
| area 31648,32257,6 (810) | 31648,32257,6 | stairs/up | 31648,32256,5 | 1180-1800 (1280) | Bloodantler Fiend, Bonepicker, Carrion Drake | 13.4 (13.1) | danger |

## Entries that are ok (8126)

Too many to list (mostly the stairs of a cave to its own next floor). By kind: grate/down 19, hole/down 720, ladder/down 5, ladder/up 727, other/down 42, pitfall/down 71, ramp/down 198, ramp/up 1481, rope/up 783, stairs/down 2020, stairs/up 1456, teleport 2, trapdoor/down 602.

## Limits

- Only the base map and its spawn file. The planned content hunts are placed at their own origins and lead only to
  their exit portal. Run the audit on the installed server's data folder too.
- Levels are the hall's scale (`gen_bounty_pool.py` estimate, `baseLevelMult` applied). A level-scaled monster
  uses the middle of its range.
- Teleports whose target a movement script sets (an action or unique id in movements.xml) have no destination on the
  map and are not in the table. Most teleport items of the base map are of that kind. Holes a player digs are not either.
- Walking off a cliff edge onto a lower floor (a tile with no ground) is not a transition item and is not in the table.
