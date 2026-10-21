# Map building guide

Rules for building new areas so they match the best maps we have. Every number below was measured with
`tools/map/` on real maps. The per-map and per-area numbers are in `docs/map_guide/stats.json` and
`stats.csv`. The pictures are in `docs/map_guide/`. They are rendered at 32 px per tile with our 10.98
sprites and show one floor only: no roofs from the floor above, no creatures and no light.

Review a new area with `tools/map/score_area.py` (see "Reviewing a new area" at the end).

## What was studied

| map | size | notes |
|---|---|---|
| live base map (the map our server runs) | 18.2 M tiles, 5.5 M open, 16 floors, 20 towns, 1 057 houses, 50 338 spawns / 74 071 monsters | full world, items 3.57 |
| map B (a large custom world) | 13.7 M tiles, 3.1 M open, 16 floors, 2 towns, 122 houses, 48 960 spawns | items 3.20, has some custom ids our sprites lack |
| map C (an older full world, same lineage as the live map) | 5.2 M tiles, 1.0 M open, 16 floors, 12 towns, 150 houses, 13 563 spawns | items 3.62 |
| 162 community maps (a local map pack and the shared-drive map collection) | 134 surveyed (10.x ids, 3 000+ tiles), 125 with natural areas ranked, 41 of them full-size (20 000+ natural open tiles) | quests, islands, hunts, whole worlds |

Not analysed: 8 maps with old item ids (items major 1-2), 4 maps with item ids newer than ours (major 4)
and 16 fragments under 3 000 tiles. One converted map ("community 088", 3.6 M open tiles) uses an id table
that does not match ours: every ground shows up as flat and unknown, so its score of 15 says nothing about its
quality. Eight server archives on the shared drive were listed. Seven of them hold no .otbm. The eighth holds
a few small campaign and test maps, which were not used.

Terms used below (they are defined exactly in `tools/map/analyze.py`):

- **open tile**: terrain a player sees: a ground that is not mountain fill, deep water or a lava pool, and no wall on it.
- **deco**: every item that is not ground, border, wall, door or floor change. It covers nature (grass tufts, stones,
  flowers, bushes), furniture, lights and loose items.
- **transition**: two neighbouring tiles whose grounds belong to different families (grass, earth, sand, ice, swamp,
  lava, water, mountain, street).
- **border coverage**: the share of transitions with a border item on either tile. "border or wall" also counts a
  wall or mountain side as the edge.
- **flat block**: a 16x16 block where one ground id covers 95 % or more of the main ground.
- **ground variants**: the number of distinct ground ids of the main family in one 16x16 block.
- **heavy tile**: an open tile with 3 or more deco items (spam).
- **area type**: each 16x16 block of a floor is classed as town, building, dungeon, cave, forest, grassland, dirt,
  desert, ice, swamp, lava, water or exotic.

## Quality ranking

The score (0-100) is computed by `tools/map/collect.py` over natural areas. It weighs border coverage (35),
detail density (20), ground variation (15), no barren blocks (15) and no spam (15).

Best full-size maps: community 001 (100), 060 (98.5), 139 (98.2), 017 (97.9), 018 (94.5), 007 (93.6),
127 (93.2) and 025 (93.1). Next come 137 (91.1), 040 (90.7) and the **live base map at 90.6** (rank 11 of the 44 full-size maps),
**map C 88.9** and **map B 86.7**. The weakest real maps are community 036 (74.6), 117 (73.3), 138 (70.0)
and 107 (69.6). The four "shape" maps (generated terrain, no detail, no borders) score 44.6.

What separates the best maps from the weak ones (medians of the natural areas):

| sign | best maps | weak maps |
|---|---|---|
| ground transitions bordered (or walled) | 91-100 % (most 99-100 %) | 69-100 %; 138 leaves 31 % open |
| flat 16x16 blocks (one ground id) | 0-24 % | 28-43 % |
| barren share (flat **and** under 0.05 deco per tile) | 0-5 % | 21-35 % |
| nature deco per open tile | 0.15-0.31 | 0.07-0.14 |
| forest ground variants per block | 11 | 7 |
| tiles with 3+ deco items | 0.0-0.3 % | 0.0-0.1 % (spam is rare; it is not what makes maps weak) |

So weak maps are not spammy. They are **empty and flat**: big areas of one grass or sand id with nothing on
them, and edges left unbordered. The live map loses points for the same reason: 24 % of its natural blocks
are flat and 7 % are barren, against 0-5 % in the best maps.

## Numbers per area type

Values are the 10th percentile, median and 90th percentile over the best full-size maps (score 88 or more,
18 maps, the live map included). Build inside the p10-p90 range. Aim for the median.

| area | deco / open tile | empty tiles | ground variants / block | flat blocks | lights / 100 tiles | border coverage |
|---|---|---|---|---|---|---|
| town (streets, plazas) | 0.15 / **0.20** / 0.28 | 76-86 % | 1-2 | 43-71 % | 1.2 / 2.5 / 3.6 | 91-98 % |
| building interiors | 0.11 / **0.18** / 0.27 | 77-90 % | 1-2 | 46-88 % | 2.5 / 3.1 / 5.9 | 80-96 % |
| dungeon | 0.11 / **0.17** / 0.24 | 78-90 % | 1-2 | 43-90 % | 2.6 / 4.5 / 9.5 | walls do the edges (99 % with walls) |
| cave | 0.09 / **0.19** / 0.26 | 77-91 % | 3.5-5 | 3-20 % | 0.6 / 4.2 / 6.1 | 49-96 %, 99.6 % with walls |
| forest | 0.33 / **0.39** / 0.46 | 57-67 % | 7 / **11** / 15 | 0-24 % | ~0.3 | 97.5-99.6 % |
| grassland | 0.13 / **0.15** / 0.21 | 79-88 % | 4 / **9** / 12 | 1-45 % | 0.1-1.6 | 95-99 % |
| dirt / earth | 0.17 / **0.22** / 0.26 | 75-84 % | 5 / **11** / 16 | 9-31 % | 0.7-3.5 | 92-99 % |
| desert | 0.03 / **0.11** / 0.19 | 83-97 % | 1-7 | 38-97 % | 0.1-3.0 | 94-100 % |
| ice / snow | 0.02 / **0.07** / 0.13 | 88-98 % | 12 / **14** / 15 | 0-6 % | 0.1-7.8 | 94-99.6 % |
| swamp | 0.08 / **0.14** / 0.20 | 82-93 % | 1 | 79-99 % | 0.6-4.7 | 88-98 % |
| lava | 0.04 / **0.08** / 0.09 | 92-96 % | 1-3 | 38-78 % | 5 / **11** / 20 | 93-99 % |

How to read it:

- **Forest is the densest area**: about 2 tiles in 5 carry a deco item, and every 16x16 block mixes about 11 grass
  ids. The live map's forest reaches 0.39 deco per tile, 15 ground variants and 98 % borders, the same as the best maps.
- **Open land is quieter**. Grassland, desert and ice have 0.07-0.15 deco per tile. Variation comes from ground
  ids (ice and snow mix 14 ids per block), not from clutter.
- **Interiors** carry 0.02-0.06 furniture per tile and 0.18 deco per tile.
- **Caves and dungeons need lights**: 3-5 per 100 open tiles, and lava areas 5-20 (lava itself glows).
- **Spam** (3+ deco items on one tile) stays under 0.5 % of tiles in every good area. Above 1 % it looks cluttered.

## Rules

### Ground and borders
1. **Border every ground transition.** The best maps border 97.5-99.6 % of natural transitions. The rest are edges
   made by a wall or mountain side. Mountain sides and cave walls count as the edge, so no extra border is needed there.
2. Most transitions are bordered from the "higher" ground over the lower one: grass over dirt, dirt over sand,
   snow over ice and so on. The pairs that are always bordered in good maps are dirt-grass, dirt-sand, sand-earth,
   ice-snow, ice-rock, lava-rock, lava-dirt, mud-dirt and dirt-water (100 % each).
3. Pairs that weak areas forget: sand to shallow water (about 45 % bordered even in good maps; a beach needs the
   water border), flowers-ground to grass (60 %), and two cave floors of the same family (muddy floor next to dirt
   floor, 53-63 %). Use the matching border set every time.
4. **Never leave a block of one ground id.** In forest, grassland, dirt and cave, mix the family's variants:
   7-15 grass ids per 16x16 block in forests, 3-5 floor ids in caves, 12-15 ice/snow ids. Rooms in towns,
   buildings and dungeons may use one floor id; that is normal there.
5. Water: put kelp, bubbles, coral and stones on sea floors that players can see. Shore edges need the water
   border on every tile (93-100 % in good maps).

### Detail (decoration)
6. Nature deco does most of the work. In order of use: grass tufts (ids 6216-6219), small stones (3610-3614,
   3621-3623), dry grass (10738-10740, used in desert and dirt), flowers and mushrooms, and ice spikes and lumps
   (6715-6718, 6939-6942) on ice.
7. Scatter deco **evenly**. Over 16x16 blocks of good forest, the quietest quarter still has 0.28-0.35 deco per tile
   and the busiest quarter 0.38-0.55. Clumps followed by empty stretches look like a weak map.
8. One deco item per tile. Two only where it reads naturally (a stone under a bush). Three or more on under 0.5 % of tiles.
9. Trees and bushes are walls on the map. They frame paths and break up open land. Good forests keep 57-67 %
   of open tiles empty, so players can walk.

### Towns
Measured over the 14 towns of the live map with 10 or more houses, map C and the best community worlds:

| item | value |
|---|---|
| town footprint | about 100-200 x 80-160 tiles (live median 132 x 124) |
| street width | median 3-4 tiles. Main streets 4-6, alleys 2. Plazas 25-140 tiles (squares about 5x5 to 12x12) |
| built share of the footprint | 0.14-0.33 (the rest is streets, plazas, gardens and nature) |
| house size | median 40-60 tiles (p25 25, p75 80-90); footprint 6 x 7 (p25 5 x 6, p75 7 x 9) |
| house floors | 77 % of live-map houses have 1 floor and 10 % have 2. The few big houses and guildhalls have 3-5 |
| doors | 1 door per house (2 for big ones). The door sits in the wall line and faces a street |
| roofs | 97-100 % of house tiles have a roof on the floor above |
| house interior | 0.09 furniture per tile (p25-p75 0.05-0.13), 2 beds, 2 windows, deco 0.16 per tile; no empty houses |
| lockers / depot | 6-25 depot lockers per town, in one depot building near the temple |
| street detail | 0.05-0.30 deco per street tile; 75-97 % of street tiles stay empty |
| floor changes | live-map towns have 43 stairs, ladders or holes per 1 000 open tiles, 10x the wilderness |

Construction: walls are one tile thick, as a wall item on the outline tile. Corners use the corner piece. Frame
walls (framework, stone, white stone, sandstone, brick) follow the town's style. Every building has a roof on z-1
over all its tiles. In the pictures the temple sits on its own square with a main street leading to it. See shots
01, 02, 03 and 17.

### Wilderness
These rules come from the pictures and were not measured.
- Paths: dirt or earth roads 2-4 tiles wide, bordered on both sides, winding (no long straight lines).
- Forest edges: trees thin out over 3-6 tiles into grassland. The ground changes with a border and is never cut
  off straight. See shot 06.
- Farms and fields: fenced plots with crop or soil ground, a 1-2 tile path around them. See shot 07.

### Caves
- Floor: earth or dirt-floor family with 3-5 ids per block (live map: earth 9026, dirt floor 9021-9025).
- Walls: cave walls (5639-5642) or mountain walls (4468-4479) on the rock side of every edge. The rock fill is
  mountain ground (919). In the classic style the wall pieces sit on the north and west sides of the floor and the
  south and east edges use the matching border. See shot 10.
- Detail: 0.19 deco per tile, mostly small stones (3610-3623), plus roots, mushrooms and moss near walls.
- Lights: about 4 per 100 open tiles (torches, glowing mushrooms, crystals, coal basins); mines more (shot 11).
- Shape: irregular edges. A straight wall run longer than 4-5 tiles looks built, not grown (compare shot 23).

### Dungeons, tombs, halls
- Floors may be one id per room, but rooms vary: tiles, marble, slate and sandstone, with carpets and patterns.
  Debris (3653-3656) and stones break the floor up (shots 13, 14).
- Walls 1 tile thick with matching pillars, arches and door frames. Furniture 0.012-0.036 per tile: shelves,
  coffins, altars, statues.
- Lights 2.6-9.5 per 100 tiles (wall lamps, coal basins, torch bearers).
- Do not build a long hall of one floor id with nothing on it (shot 22).

### Hunting areas
Measured around every spawn (13 tiles around each monster) on the live map, with map B and map C in brackets:

| item | value |
|---|---|
| corridor width (narrowest walkable run through a tile) | median 7 (8, 6), p25 4, p75 11. About 4 % of hunt tiles are 1 wide and 7 % are 2 wide |
| rooms vs corridors | 68 % of hunt tiles are in rooms (5+ wide). Room size median 27 tiles, p75 64-71 |
| loops | 13-14 per 1 000 hunt tiles. Every hunt has at least one circuit, so players can run a loop |
| dead ends | 17-25 per 1 000 hunt tiles (short side pockets; good safe spots) |
| monsters per spawn | mean 1.1-1.5 (most spawns hold 1 monster with radius 1; groups of 3-8 for packs) |
| distance between spawn points | median 4-7 tiles (p25 3-4, p75 4-8) |
| density | 4.0-5.0 monsters per 100 walkable hunt tiles since pack combat (server/README.md "Pack combat (pace)": monsters die 2-30x faster, packs of 3-7; before 2.7-4.4). By area: forest/grass 1.2-1.7, desert/ice 1.7-2.0, dirt 2.2, swamp 2.5, cave 2.7-3.2, dungeon 3.3-3.6, lava 1.3-3.9 |
| depth | 64 % of live-map spawns are on floors 7-11 and 21 % on floors 12-15. Above ground (0-6) holds 14 % |
| floor changes | caves have 4 per 1 000 open tiles, dungeons 3.4. On the live map 98 % of ladders have a tile above, 79 % of stairs and 70 % of holes have a tile directly below |

Layout rule: build a loop of rooms (5-10 wide, 25-70 tiles) joined by 3-4 wide corridors. Add 1-2 dead-end pockets
per 50x50 area as safe spots. Put 1 monster per spawn point every 4-7 tiles. Give each room 1-3 lights.

## Pack items in the map editor (palette)

The map editor reads our items.otb / items.xml, so the pack items (server/README.md "Pack items and monsters") are in
its item list by id and name. Each ground is followed by its 12 border pieces in this order: north, south, east and west
edge, north-west, north-east, south-west and south-east corner, then the four inner corners (named after where the higher
ground lies: the "north edge" goes on a tile with the ground to its north). A border piece goes on the
lower neighbour tile, like a stock border, and draws the rim of the higher ground; rules 1-4 above apply.

| ground | id | speed | border pieces |
|---|---|---|---|
| thick lush grass | 36300 | 150 | 36301-36312 |
| dense grass | 36313 | 150 | 36314-36325 |
| dry prairie grass | 36326 | 150 | 36327-36338 |
| meadow grass | 36339 | 150 | 36340-36351 |
| bright grass | 36352 | 150 | 36353-36364 |
| loam | 36365 | 110 | 36366-36377 |
| flagstone floor | 36378 | 100 | 36379-36390 |
| jade tile floor | 36391 | 100 | 36392-36403 |
| violet slate floor | 36404 | 100 | 36405-36416 |
| red clay | 36417 | 110 | 36418-36429 |
| fine sand | 36430 | 120 | 36431-36442 |
| fresh snow | 36443 | 150 | 36444-36455 |

Other pack items: water 36456-36463 (deep lake water, shallows over sand, pebbles and weeds, lagoon, murky, mountain lake,
mountain shallows; animated, the four shallows walkable), shores 36464-36577 (border pieces placed on the water tile next to
land: grass, sand, rock, snow, stone rim, mud; pieces named after the land sides, `in_` pieces for two or more sides,
straight pieces vary along the shore by themselves), lake objects 36578-36626 (reeds, lilies, rocks, logs, buoys: use them
like rule 5), dock props 36627-36650, trees 36100-36298 (even ids) with their stumps one id higher (36101-36299). Monsters:
goblins and forest creatures in the editor's creature list (tools/windows/rme_creatures.py reads monsters/chaos).

## Pictures

Coordinates are the top-left tile. Each shot is 30 x 20 tiles.

| file | what it shows | where |
|---|---|---|
| 01_town_street.jpg | cobbled main street 4 wide, framework houses, lamps and signs at the doors | live 32332,32204,7 |
| 02_town_temple_square.jpg | temple on its square, marble, fountain, street to it | live 32345,31768,7 |
| 03_house_garden.jpg | white stone house with hedge garden, pond, bordered grass | live 32346,32780,7 |
| 04_jungle_village.jpg | wooden huts on jungle grass, mixed ground, tufts everywhere | live 32578,32728,7 |
| 05_swamp_town.jpg | swamp settlement: mud, grass and water, all shores bordered | live 32935,32055,7 |
| 06_forest_river.jpg | river with full shore border, forest edge thinning out, a ruin | live 32602,32222,7 |
| 07_farmland.jpg | fenced fields, bordered paths | live 32202,32830,7 |
| 08_desert.jpg | sand, grey sand and earth mixed and bordered, dry grass, stones | live 33050,31374,7 |
| 09_ice_settlement.jpg | snow and ice mixed, a fenced field, shore borders | live 31994,31358,7 |
| 10_cave_classic.jpg | classic cave: walls on north/west sides, stones scattered | live 33018,31118,13 |
| 11_cave_mine_lit.jpg | grey-stone mine hall with many lights | live 33434,31310,8 |
| 12_cave_jungle.jpg | jungle cave with water pools, roots, plants | live 32666,32846,9 |
| 13_dungeon_tomb.jpg | sandstone tomb: pillars, patterned floors, bookcases, debris | live 32970,32398,10 |
| 14_dungeon_halls.jpg | marble halls with patterned floors | live 32954,32398,13 |
| 15_lava.jpg | basalt with lava streams, every lava edge bordered | live 33626,32638,14 |
| 16_community_forest_coast.jpg | best-ranked community world: coast, rocks, forest | community 127, 1994,1614,7 |
| 17_community_village.jpg | best-ranked community world: village street | community 060, 1050,1070,7 |
| 18_weak_unbordered_draft.jpg | WEAK: grass, stone and water with no borders | community 138, 538,1166,7 |
| 19_weak_barren_grass.jpg | WEAK: one grass id, almost no deco | community 036, 1290,926,7 |
| 20_weak_patch_edges.jpg | WEAK: dark-grass patches framed by hedges, beds on grass | community 036, 1002,830,7 |
| 21_weak_blocky_lava.jpg | WEAK: square lava blobs, blocky shapes | map B, 378,1918,15 |
| 22_weak_flat_hall.jpg | WEAK: one floor id, a row of lamps, nothing else | map B, 1978,782,15 |
| 23_weak_box_cave.jpg | WEAK: box-shaped cave room, plain floor | map C, 32858,31806,8 |

## The live base map: references and weak spots

Good references to copy from (the best-scoring 16x16 blocks of each type in the block survey):

- Forest: 32640,31120,7 and 32624,31232,6 (0.72 deco per tile in the densest blocks, 15 ground variants).
- Grassland: 33200,31456,7. Dirt: 32208,32832,7. Desert: 33056,31376,7 and 33248,31360,7. Ice: 32048,31104,6.
- Caves: 33440,31312,8 (mine) and 32000,32080,12. Dungeons: 32912,32560,9 and 33440,32064,10.
- Towns: the town around temple 32957,32076,7 is the densest (46 % built, 0.32 deco per street tile, street
  width 3). Wider, more open towns are around 32369,32241,7 and 32787,31276,7.

Weak spots (checked with `score_area.py` on 48 x 48 areas):

- 32560-32607, 32752-32799, z7 (next to the town at 32594,32745): flat grassland with 0.02 deco per tile and
  98 % empty tiles.
- 32992-33071, 32848-32927, z7: desert with 0.015 deco per tile.
- 31312-31359, 32800-32847, z10 and 31232-31279, 32880-32927, z12: dungeons with one floor id, 0.07-0.09 deco
  per tile and 0-1.3 lights per 100 tiles.
- 33056-33103, 31056-31103, z14: a cave with too much deco (0.8 per tile, 3.4 % of tiles with 3+ items).
- 32336-32383, 32768-32815, z7: town edge where 5.5 % of transitions are unbordered.

Over the whole live map: 24 % of natural 16x16 blocks are flat and 7 % are barren. These are the areas to touch up
first. Many of its town streets are bare: the median is 0.09 deco per street tile, while the densest town has 0.32.

## Checklist for a new area

1. Every ground transition has a border or a wall. `score_area.py` border_or_wall is 0.97 or more, and the water
   shore is bordered on every tile.
2. No 16x16 block of natural ground uses one ground id. Forest has 6+ variants per block, cave 3+ and ice 10+.
3. Deco per open tile is inside the band for the area type (table above). No empty stretch bigger than about 8x8
   outside streets, plazas and arenas.
4. Fewer than 1 % of tiles have 3+ deco items.
5. Caves and dungeons have 2+ lights per 100 tiles. Lava areas have 5+.
6. Edges are irregular: no straight wall or border run longer than 4-5 tiles in natural areas.
7. Hunting area: a loop exists, corridors are 3-12 wide (median), there is a dead-end pocket or two, monsters
   1.5-5 per 100 walkable tiles, and spawn points 4-7 tiles apart.
8. Floor changes lead somewhere: each ladder has a walkable tile above, and each stair or hole lands on a walkable tile below.
9. Buildings: walls 1 thick, a roof over every tile, 1 door to the street, 2 beds and furniture in each house,
   and stairs inside multi-floor houses.
10. Render the area (`render.py`) and look at it next to the matching shot in `docs/map_guide/`.

## Reviewing a new area

```
# score a rectangle (exit code 1 when a value is out of band)
python3 -I tools/map/score_area.py world.otbm items.otb items.xml X0 Y0 X1 Y1 Z [Z2 ...] \
    --dat Tibia.dat [--type cave] [--spawn world-spawn.xml] [--png out.png --spr Tibia.spr]

# render a crop at 32 px per tile
python3 -I tools/map/render.py world.otbm items.otb items.xml Tibia.dat Tibia.spr X0 Y0 X1 Y1 Z out.png

# survey a whole map, then rank several surveys (writes stats.json / stats.csv)
python3 -I tools/map/survey.py world.otbm items.otb items.xml out.json --dat Tibia.dat \
    --spawn world-spawn.xml --house world-house.xml --blocks out_blocks.npz
python3 -I tools/map/collect.py OUT_DIR a.json b.json ...
```

An area type needs at least 3 blocks of 16x16 in the rectangle to be judged. Use rectangles of 48x48 or more, or
force the type with `--type`. The bands are in `BANDS` at the top of `score_area.py`. They come from the 10-90 %
range of the best maps, widened a little.

## Generated areas

Caves, wastes, rift-like halls and dungeon layouts can be generated from a seed instead of drawn
(server/README.md "Generated areas"). Towns and story areas stay hand-made. The server builds the areas at startup.
The same model can be written as an OTBM piece for the map editor.

### Make or change an area
1. Add or edit an entry in `areas` of `server/data/scripts/chaos/areagen_config.lua`:
   - `kind`: `cave`, `dungeon` or `waste`; `theme`; `seed`;
   - `origin`: top-left of the first floor, inside x/y 14336-15359 (a queue dungeon also 24576-25599, below), not
     overlapping another area;
   - `size`, `floors`, `linksPerFloor`, `layout` (below), `spawns`, `boss`;
   - `entrance` and `back` on the world map, and `minLevel`.
2. Look at it before it goes live:
   ```
   python3 -I server/tools/areagen_export.py summary                  # tiles, monsters, density, problems
   python3 -I server/tools/areagen_export.py preview OUT items.otb items.xml Tibia.dat Tibia.spr --dark --sheet
   python3 -I server/tools/areagen_export.py otbm OUT                 # OUT/<id>.otbm + <id>-spawn.xml
   python3 -I tools/map/score_area.py OUT/<id>.otbm items.otb items.xml X0 Y0 X1 Y1 Z --dat Tibia.dat \
       --type cave --spawn OUT/<id>-spawn.xml                         # the bands of this guide
   ```
3. A new seed gives a new layout. Keep the seed of a layout you like. Change only the numbers you want to change.
   Then run `luajit tests/areagen_test.lua` from `server/` and update the fixed checksum the test prints.
4. Restart the server. `/areagen status`, `/areagen goto <id>`.

### The knobs
| knob | effect | typical |
|---|---|---|
| `layout.fill` (cave, waste) | share of rock at the start: higher = narrower passages | cave 0.45-0.48, waste 0.34-0.38 |
| `layout.steps`, `spread` | smoothing passes; `spread` 1-2 keeps more pillars | 4-5, 1-2 |
| `layout.minRegion` | pockets smaller than this are filled; bigger ones are joined by a tunnel | 40-60 |
| `layout.tunnelRadius` | 1 = 3-wide tunnels, 2 = 5-wide | 1-2 |
| `layout.rooms`, `room`, `corridor`, `loops`, `bossRoom` (dungeon) | room count and size, corridor width, extra circuits | 9-13 rooms of 7-12, corridor 3, loops 2-4 |
| `spawns.density` | monsters per 100 walkable tiles outside the safe radius | hunts 4.5 (band 4.0-5.0, pack combat), queue dungeons 8-8.75 in packs of 6-7 (at least 100 monsters a run) |
| `spawns.roomCap` (dungeon) | most monsters per 100 tiles of one room | 5-5.5 (queue dungeons 16) |
| `spawns.packChance`, `packMin`, `packMax` | the share of points that are packs and their size | hunts 60, 2-4; queue dungeons 100, 6-7 |
| `spawns.minDistance`, `packChance`, `packMax` | spacing of spawn points, packs | 4-5, 15-30 %, 2-3 |
| `spawns.level` | the level the monsters are scaled to | the area's band |
| `theme.decor.share`, `clusters` | single pieces per walkable tile, clusters per 1000 tiles | cave 0.10, dungeon 0.12, waste 0.08 |
| `theme.lights.per100`, `props.per100` | lights and wall furniture per 100 walkable tiles | caves 2.5 (+ lava), dungeons 4.5-5 and 2.5-3 |
| `theme.patches`, `pools` | share and radius of second grounds and lava pools | 0.05-0.10, 0.025-0.03 |

### Palettes
- A theme names ground families (`families`: weighted ground ids and a z order), border sets (`borders`, `pieces`),
  walls, decoration, obstacles, lights and props.
- Use only ids that `areagen_export.py check items.otb items.xml Tibia.dat --dark` passes.
- New border sets come from the live map. `python3 -I tools/map/derive_borders.py MAP items.otb items.xml neighbours IDS`
  shows which grounds real maps put next to a ground. `... edges OVER UNDER --lua` prints the 12 pieces as a table. A
  set whose winning piece is under about 70 % is not a clean set: pick another pair.
- `... walls H V C P` prints the piece per wall pattern.
- The rules of this guide apply to generated areas too: border every transition (the generator does), mix ground ids,
  keep decoration even, 2+ lights per 100 tiles underground, loops and dead ends in hunts, 1.5-5 monsters per 100 tiles.

### What it does not do
- No houses, roofs, towns or quest logic.
- One monster level is shown per type: the native one. The scaling is in health, damage and experience.
- Generated tiles cannot be protection zones. The arrival is a spawn-free radius with the exit portal next to it.

## Area planner

A plan says what an area is; our code turns it into tiles, checks them and draws them for review. The plan is
semantic JSON and never holds an item id. A person writes it by hand, or an AI writes it when the owner sets up an
endpoint on their own machine. `server/tools/area_planner.py` validates, compiles, renders and keeps the approved
plans (server/README.md "Area planner").

### The plan
Schema `chaos-area-plan/1`: `server/tools/areaplan/schema.json`. Examples: `server/tools/areaplan/examples/`
(`swamp_hunt.json`, `crypt_boss.json` with 2 floors and a boss, `lava_cave.json`, `temple_throne.json`: a dense
temple with a nave, chapels and a boss throne room).

| key | what |
|---|---|
| `id`, `name`, `biome`, `size` [w, h] (24-200), `floors` (1-4), `level` [lo, hi] | the area |
| `seed`, `origin`, `decoration` (sparse, normal, dense), `light` (dark, dim, normal, bright) | optional |
| `zones` | `id`, `floor`, `shape` (room, cave, arena), `size` (small, medium, large, huge or [w, h]), `at` or `place` (compass), `role` (hunt, camp, boss, treasure, passage), `pz` |
| `paths` | `from`, `to` (same floor), `width` 1-6, `style` corridor or tunnel |
| `connections` | `stairs`, `ladder` (hole and ladder, both ways), `hole` (one way down), `teleport` (any two zones, `two_way`) |
| `entry`, `exit` | the arrival zone (floor 1); the exit portal's zone and optional world target |
| `spawns`, `boss`, `npcs`, `chests` | monster names from our list with count, pack and respawn; the boss in the boss room; NPCs of our list; quest chests with a quest key and a `reward` (item names, gold, experience); `new` NPCs with `lines`; `chest_action` |

Biomes map to our areagen themes (`python3 -I server/tools/area_planner.py catalogue`): cave (emberdeep), lava and
waste (cinderfall), swamp (emberdeep with wide mud, swamp trees and glowing mushrooms; with the pair 24 switch on, the
pair 24 swamp ground and water and acid pools), crypt (ossuary), vault, catacomb, hall, abyss, sanctum (the rift
themes), forest (16 stock grass ids, dirt patches, the grass border set, stock trees) and ice (27 stock snow ids, ice
sheets and grey rock with the snow and ice border sets, snowy trees). `forest_pack` and `ice_pack` use the pack
grounds and need the packitems step. `harvest` (a farmland at night: autumn grass, tilled soil, corn stubble, mud
road and grave grass of the pair 33 kit with its three border sets, corn, pumpkins, scarecrows, tombstones and
jack-o'-lanterns) and `harvest_crypt` (crypt flagstones and bone dust in crypt brick walls, urns, skull niches, black
candles) use the pair 33 kit and need the pack33items step and the client pair 33 ("Haunted Harvest" below). Every
id comes from our tables: `areagen_config.lua`, `chaos_dark_tiles.lua`, `chaos_pack33_kit.lua`,
`chaos_theme_items.lua`, `data/items/art_items.csv`, `rift_config.lua` (the chest), the stock grounds and borders
listed in `server/tools/areaplan_build.lua`, and the decoration kits in `server/tools/areaplan/decor_kits.json`.

### Rules the validator checks
- The schema: unknown keys are refused, so an item id cannot slip in.
- Every zone is reachable from the entry over paths, stairs, holes (down only) and teleports.
- Monsters exist (close names are suggested), and their level fits the band's tier window (the bounty board's six
  tiers); a band may touch two neighbouring tiers. Wrong picks get a list of monsters of the right level.
- No spawn in a PZ zone. The boss room has exactly one way in; a one-way teleport out does not count.
- Teleport, stairs, chest, NPC and spawn targets exist. Stairs and holes join floors next to each other.
- Zones fit inside the 4-tile rim with 3 tiles between them. Each message ends with a fix an AI can apply.
- Chest rewards name items of our item tables (close names are suggested); two quest keys may not share a storage;
  a `new` NPC may not reuse an existing name.

### What compile does
1. Lays the zones out (fixed `at`, compass `place`, or next to their neighbours) and routes each path around the other
   zones; the boss room is never crossed. Holes go inside the upper zone; the zone below is placed under them.
2. Runs the area generator with a planned layout (`layout.plan`, `links` in `areagen_core.lua`): our grounds, patches,
   pools, auto-borders, walls, decoration, lights, hole and ladder. Same seed, same bytes in LuaJIT and Lua 5.3.
3. Places the stair brush (stairs ground above, stone stairs below), teleports (with their destination), the exit
   portal (action id 47951 or a world target), chests against a wall (with the area's chest action id), NPCs, the
   boss and the spawn points (4 tiles apart, packs on one point), flags PZ tiles, and roofs dungeon floors at z 7 or
   above.
3b. Dresses the area with the biome's decoration kit (below).
4. QA on the written file: OTBM structure and attributes, known tile flags, no id outside the biome's catalogue, every
   ground transition bordered and no walkable edge open, every zone and the boss reached, one way into the boss room,
   no spawn on a PZ or blocked tile, density inside 1-6 per 100 tiles (warning), no walkable tile cut off by the
   decoration and nothing on a protected tile, under 1 % of tiles with 3+ decoration items (warning).
5. Stats: walkable tiles, monsters per 100 walkable tiles and per screen (15 x 11), steps from the entry to the boss
   and to each zone.

### Use
```
python3 -I server/tools/area_planner.py validate my_area.json
python3 -I server/tools/area_planner.py compile my_area.json OUT        # OUT/<id>.otbm, -spawn.xml, .json
python3 -I server/tools/area_planner.py render my_area.json OUT items.otb items.xml Tibia.dat Tibia.spr
python3 -I server/tools/area_planner.py stats my_area.json
python3 -I server/tools/area_planner.py approve my_area.json             # into the knowledge base
python3 -I server/tools/area_planner.py suggest swamp 50 140             # numbers and monsters for a new plan
python3 -I server/tools/area_planner.py similar my_area.json
python3 -I server/tools/area_planner.py plan --from-prompt "a two-floor crypt for 150-280 with a boss" --out my_area.json
python3 -I server/tools/area_planner.py place OUT/my_area.otbm world.otbm copy.otbm --at X Y Z \
    --spawn world-spawn.xml copy-spawn.xml                              # a COPY of the map with the area in it
python3 -I server/tools/area_planner.py install OUT SERVER_DIR          # chest script and new NPCs into data/
python3 -I server/tools/area_planner.py check-kits items.otb items.xml Tibia.dat
```
Open the `.otbm` (or the placed copy) in the map editor, check it with `tools/map/score_area.py`, then use the copy.
The planner never writes the world map. Render only for review: the pair stays out of git.

### Decoration
The generator's scatter alone reads clean but bare, so compile dresses every area with its biome's kit
(`decor_kits.json`: groups of stock items of one look and role, `check-kits` verifies them on the pair):

| rule | what |
|---|---|
| halls (dungeon rooms 11x9 and up, every room at `dense`) | one pillar look in two mirrored rows 2 tiles in from the walls, every 4 tiles; statues in the inner corners |
| boss room | the throne 1-2 tiles north of the boss, a brazier on each side |
| walls | torches and candles (as often as `light` asks), tapestries, banners, carvings on the north and west walls of rooms, one colour per area, every 4 tiles |
| light props | braziers, lava holes, glowing mushrooms, crystals against the walls, about 1 per 100 tiles x `light` |
| corners | cobwebs, stalagmites, bones, reeds in the room corners |
| wall props | coffins, crates, barrels, rubble, rocks, reeds along the walls |
| clusters | an anchor piece 2-3 tiles from a wall and 2-5 small pieces around it, about 2 per 100 tiles |
| path edging | small pieces along the sides of the corridors and tunnels |
| floor detail | 14 % of the tiles next to a wall, 8 % one tile further, 3 % in the middle: dense at the edges, open where the fights are |

Never on a spawn, teleport (or its landing), link, chest, NPC or the boss; nothing blocking inside a planned path or on
the walk from the arrival to every zone and special tile, and a blocking piece only where its neighbours stay joined.
`decoration` scales every rate (sparse x0.55, normal x1, dense x1.5); a kit may raise its own rates (lava). The
result sits above the bands of rule 6 on purpose (owner, 2026-10-13: "more decoration"); `stats` shows decoration per
open tile, lights per 100 tiles and the spam share.

### Proposals for new sprites (not drawn)
- A stair-down ground and a stone stair in the dark stone and rift floor colours (the stock stairs are light grey).
- Wall-hung torches and moss for cave rock and mountain edges (the hung pieces fit only built walls).
- More snow and ice variants with soft drifts, and a frozen water ground with its border, for the ice biome.
- A flat roof and roof edge set matching the dark stone walls.

### What it does not do
- No towns, houses or house roofs (only a flat roof over a dungeon above ground).
- The chest script gives items, gold and experience; quest logic beyond that is hand-written.

### Content plans
`server/tools/areaplan/plans/`: sixteen production plans for the thin level bands (docs/CONTENT.md). CI validates and
compiles them with the examples. Each has its own `origin`, one 200 x 200 cell in the empty block east and south of
the generated areas (rows y 14340, 14540, 14940 and 15140; the plaza at 14800, 14800 sits in the free band between),
so they never overlap each other, the generated areas or the plaza. Since 2026-10-14 each is four times the first
draft (owner: "Deixe-as 4x maior"; "Todas devem ser grandes e cheias de monstros"): twice the side, 12-17 zones in
loops, 3.2-3.5 monsters per 100 walkable tiles; since pack combat (the same day, server/README.md "Pack combat (pace)")
4.1-4.6 in packs of 3 (respawn 45 s for 300-599, 75 s for 600+), no zone above the validator's 8 per 100:

| Plan | Band | Size | Origin x, y, z | Arrival |
|---|---|---|---|---|
| bonechoir_catacomb | 200-290 | 148 x 120 | 14700, 14340, 10 | 14773, 14363, 10 |
| sulphur_gallery | 215-299 | 164 x 124 | 14900, 14340, 10 | 14931, 14401, 10 |
| wyrmspine_hollows | 500-640 | 176 x 136 | 15100, 14340, 9 | 15134, 14366, 9 |
| pyrarch_crucible | 520-690 | 172 x 140 | 14700, 14540, 10 | 14733, 14651, 10 |
| widowmere | 480-640 | 168 x 132 | 14900, 14540, 8 | 14983, 14565, 8 |
| corsairs_reach | 780-900 | 172 x 132 | 15100, 14540, 9 | 15133, 14605, 9 |
| hexwood_thicket | 720-840 | 184 x 144 | 14700, 14940, 7 | 14791, 15054, 7 |
| mirefang_basin | 880-999 | 176 x 140 | 14900, 14940, 8 | 14934, 14967, 8 |
| rimecrown_depths | 1000-1120 | 180 x 140 | 15100, 14940, 7 | 15189, 14967, 7 |
| cinderglass_sanctum | 1120-1300 | 192 x 152, 2 floors | 14700, 15140, 9 | 14795, 15260, 9 |
| slagmourn_foundry | 1000-1150 | 188 x 168 | 14340, 14700, 10 | 14376, 14783, 10 |
| hollowmass_reliquary | 1150-1300 | 184 x 156, 2 floors | 14340, 14920, 9 | 14431, 15043, 9 |
| gallowfen_mire | 1300-1450 | 184 x 176 | 14900, 14700, 8 | 14991, 14734, 8 |
| voidscar_chasm | 1400-1500 | 192 x 176, 2 floors | 15100, 14700, 11 | 15252, 14787, 11 |
| gravehorn_deeps | 1500-1750 | 188 x 172, 2 floors | 14340, 15140, 10 | 14433, 15173, 10 |
| duskmarrow_crater | 1750-2000 | 192 x 176, 2 floors | 15305, 14340, 9 | 15342, 14427, 9 |

The last four sit west of the generated areas' column (x 14340, below y 14686) and in the band between rows 14540
and 14940 east of the plaza (x 14900 and 15100, y 14700), at least 10 tiles from every other plan, the generated
areas, the plaza and the two chronicle cells (14900, 15140 and 15100, 15140).

**The fixed areas of `server/tools/areaplan/chronicle/`** (2026-10-14): the Capital Memorial's plaza at 14800, 14800, 7
(48 x 40), the Cinderscar Breach at **14910**, 15140, 7 (128 x 104; moved 10 east of its cell so it keeps 18 tiles
from cinderglass_sanctum, which ends at x 14891) and the Ossuary Stair at 15100, 15140, 9 (120 x 104; 60 tiles below
mirefang_basin and rimecrown_depths). Every one is 10+ tiles from every plan and generated area in x and y, whatever
the floor; the base map has no tile within 10 of any of them (checked with `tools/map/otbm.py`). Install step
`contentareas` places them at their origins with their spawns, without a teleport: their ways in are runtime portals
in the capital (chronicle_config.lua `areas` gate, memorial_config.lua `plaza.portal`). Dry run and real run on a
copy of the base map (2026-10-14): 19 areas and the room placed, the second run changed nothing.

**The placed rooms of `server/tools/areaplan/rooms/`** (2026-10-15): the Idle Hall (server/README.md "Idle Hall") at
**14600, 14760, 7** (44 x 28), in the free band between slagmourn_foundry (ends x 14527), pyrarch_crucible (ends
y 14679), the generated areas (end y 14675), hollowmass_reliquary and hexwood_thicket (start y 14920 / 14940) and the
plaza (starts x 14800): 70+ tiles from each (`tools/idle_hall_test.py` holds it 10+ from every plan and generated
area). Step `contentareas` places this folder like the chronicle folder: a fixed area at its origin, no teleport; the
way in is idlehall.lua's move, the way out the plan's exit portal.
The two **Halls of Services** (server/README.md "Halls of Services", 2026-10-15): `services_cinderhold` at **14560,
14820, 7** and `services_mirewake` at **14560, 14870, 7** (66 x 34 each, one layout), in the same band west of the Idle
Hall: 33 tiles below it, 37 east of hollowmass_reliquary (ends x 14523), 60+ from hexwood_thicket; the base map has no
tile there on floors 6-8 (checked with `tools/map/otbm.py`), and an install `--dry-run` on the base map places both.
Biome `townhall` (new): the temples' white marble floor (406) and grey stone walls (1049 vertical, 1050 horizontal,
1051 the north-west pole, 1053 the south-east corner, as the live map uses them), no clutter, no floor lights (the
booths' coal basins light the rooms). The booths' counters are placed at runtime by npc_booths.lua, not in the plan, so
the planner's rooms stay plain; `tools/services_halls_test.py` checks every booth tile on the compiled plans.

The two 1500-2000 plans (2026-10-14, on the 1300-2000 hunting monsters, server/README.md "Late game") take the
last free cell, 14340, 15140 (gravehorn_deeps, 64 tiles below hollowmass_reliquary), and a new column at x 15305
(duskmarrow_crater, 13 tiles east of voidscar_chasm's 15292 and 29 east of wyrmspine_hollows). Its origin stays inside
the schema's 14336-15359; the area runs to x 15497, where the map has no tiles (the full map read with
tools/map/otbm.py: no tile in x 15295-15510, y 14330-14545 nor in x 14330-14545, y 15130-15355). The block is now full:
a next plan goes further along that column (x 15305, rows 14540, 14700, 14940) after the same check.
Teleports: 16 plans in the room's 20 slots (4 spare).

**The dungeon block x/y 24576-25599** (2026-10-14, owner approval: the queue dungeons 6-9 of `areagen_config.lua`,
server/README.md "Generated areas"). The 14336-15359 block is full, so the four deep dungeons got a block of their
own outside the world (world x 30700-34600, y 30900-33850). Checked with `tools/map/otbm.py` on the full map
(18,388,336 tiles): no tile and no spawn in x/y 24576-25599, the nearest tile is 5,315 sqm away (30851, 30914, 9);
the rift slots use 20480-21503 and every other runtime area 2000-15359. Cells of 256 sqm, z 9 (z 10 free too):

| Dungeon | Cell origin x, y, z | Size, floors |
|---|---|---|
| The Marrow Crypts (6, level 1000) | 24576, 24576, 9 | 52 x 42, 1 |
| The Iron Crucible (7, level 1300) | 24832, 24576, 9 | 52 x 42, 1 |
| The Fallen Sanctum (8, level 1600) | 24576, 24832, 9 | 52 x 42, 1 |
| The Pyre Throne (9, level 2000) | 24832, 24832, 9 | 52 x 42, 1 |

The block has room for twelve more cells (x 25088 and 25344, every row; rows y 25088 and 25344). `tests/areagen_test.lua`
holds every area to one of the two blocks and apart from the others.

**The way in: the teleport room.** `install_all.py` step `contentareas` (`server/tools/install_content_areas.py`)
places every plan at its own origin, with its spawns and chest script, and grows the teleport room of Cinderhold
(the hub the "Teleports" portals beside Cinderhold's temple lead to; floor 6, "More Teleports", of the
three-floor hall at 31627-31669, 32251-32261) by five alcove modules on each side:
20 new teleports, one per plan in the order of `hunt_teleports_config.lua` (a plan missing there comes after, by band),
room for 14 plans and 6 spare. Each teleport has the plan's name and band on its sign and floating over it, and two
monsters of the plan in the cells beside it, like the room's own. Below the band's floor
it refuses (in the player's language); the camp portal of a placed plan leads back to the middle of the room. Safe to
re-run; it reads the plans at run time (a moved or resized plan that was placed already is refused: restore
`<map>.otbm.bak` and install again). Details: server/README.md "Hunt teleports".
```
python3 -I server/tools/install_content_areas.py SERVER_DIR/data --dry-run      # what it would do
python3 -I server/tools/install_all.py SERVER_DIR --only contentareas            # do it
```
Placing one by hand (a copy of the map, for the map editor):
```
python3 -I server/tools/area_planner.py compile server/tools/areaplan/plans/widowmere.json OUT
python3 -I server/tools/area_planner.py render server/tools/areaplan/plans/widowmere.json OUT items.otb items.xml Tibia.dat Tibia.spr
python3 -I server/tools/area_planner.py place OUT/widowmere.otbm world.otbm copy.otbm --at 14900 14540 8 \
    --spawn world-spawn.xml copy-spawn.xml
python3 -I server/tools/area_planner.py install OUT SERVER_DIR      # the chest script, when the plan has chests
```
- Keep the origin of the table in `--at`: the chest script keys its chests by the origin, and `place` rewrites it
  when the area moves.
- A new plan gets its teleport at the next install; a line in `hunt_teleports_config.lua` `plans` (id and display
  monster) chooses its place and monster. More plans than slots: raise `modules` of a side there.
- The monsters of the 650-1300 plans spawned nowhere before. Check their art in the client first
  (server/data/monster/CUSTOM_MONSTERS.md).
- After placing, rerun `gen_bounty_pool.py`, `gen_bestiary_spawns.py` and `gen_poi.py`, so the bounty board, the
  bestiary and the map markers know the new spawns, and `content_audit.py` to see the bands again.

### Haunted Harvest (event areas of the pair 33 kit)
The seasonal haunted village (server/README.md "Haunted Harvest"; owner 2026-10-21: a Halloween / haunted map) is two
fixed plans in `server/tools/areaplan/events/`, at the column x 15305 below the Hollow Crypt (the base map has no tile
in x 15295-15510, y 14330-15120 on any floor, checked with `tools/map/otbm.py`; `gen_harvest_places_test.py` holds both
10+ tiles from every other plan and generated area):

| Plan | Biome | Band | Size | Origin x, y, z | Arrival |
|---|---|---|---|---|---|
| haunted_harvest | harvest | 450-650 | 156 x 132 | 15305, 14700, 7 | 15382, 14804, 7 |
| harvest_catacombs | harvest_crypt | 500-650 | 112 x 96 | 15305, 14880, 8 | 15326, 14898, 8 |

- **The village** (decoration normal, light dark): the **crossroads** (south, camp, PZ: the arrival from the Harvest
  Portals, Widow Hessa, the exit portal) between the **pumpkin fields** (southwest) and the **hamlet** of the hedge
  witches (southeast: a barn and three huts, candy cauldrons); the **corn maze** in the middle; the **west furrows**,
  the **gibbet hill** (northwest, the cursed bell) and the **dead orchard** (east) around it; the **graveyard**
  (north, behind an iron fence, twelve graves) and the **ruined chapel** (northeast, crypt stone walls, the crypt
  seal) at the far end, about 100 steps from the arrival. Loops: fields - furrows - gibbet hill - graveyard, maze -
  graveyard, hamlet - orchard - chapel - graveyard.
- **The catacombs** (decoration dense, light dark): the **seal stair** (northwest, camp, PZ: the arrival from the seal,
  the exit portal), the **coffin gallery** (upright coffins) and the **candle vault** leading to the **ossuary hall**
  and the **bone pits**, the **ritual chamber** (south: the ritual circle) and the **King's Crypt** (southeast, the
  boss room, four graves), reached only by the circle's portal; its own teleport leads back to the stair.
- The plans hold no item id, like every plan. The kit's art comes in three ways: the biomes' grounds, borders, walls,
  scatter and lights (`server/tools/areaplan_build.lua`, "kit:" rows), the decoration overlay
  `areaplan/decor_pack33_kit.json` (kits `haunted_harvest` and `harvest_crypt`, merged only while
  `ChaosHarvestArt.PAIR33` is on), and the set pieces and mechanics of `data/scripts/chaos/harvest_places.lua`, which
  `server/tools/gen_harvest_places.py` chooses on the compiled tiles and `harvest_event.lua` places at startup (the
  corn maze, the chapel walls, the fence, the huts, haystacks, scarecrows, trees, gibbets, pumpkin patches, graves,
  coffins, cauldrons, the bell, the seal and the circle).
- Change a plan, the kit or the overlay, then run `python3 -I server/tools/gen_harvest_places.py` (CI `--check`) and
  `python3 -I server/tools/gen_harvest_places_test.py`. The places are chosen as with the switch on.
- Placed by `install_all.py --only contentareas` only while the switch is on (it is off until pair 33 ships). A plan
  that changed after it was placed is refused there: restore `<map>.otbm.bak` and install again.
- Review pictures: `area_planner.py render` needs a client pair with the kit (pair 33, not built yet); until then a
  schematic of the compiled tiles (ground families, blocking pieces, set pieces, mechanics and spawns in flat colours)
  is what can be drawn. The kit's own art is never given to an AI tool (docs/SPRITE_STYLE.md, import-only).
