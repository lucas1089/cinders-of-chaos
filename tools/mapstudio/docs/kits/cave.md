# Cave kit: measurements, kit, generator status and design

Owner request 2026-10-26: "faça uma caverna". Kit: `kit/cave.json`. Review batch: `areas/cave-review-01/index.html` (seeds 301-308).
Raw numbers: `study/cave-measure.txt`, `study/cave-topo.txt`. Clump table: `study/cave-clumps.json`.

## Reference windows (refs/, 140x130 tiles, cut with extract_ref.py)

| ref | x | y | floors | what |
|---|---|---|---|---|
| cave-a | 33050-33189 | 32650-32779 | 8-12 (study floors 9-11) | maze of 2-3 wide winding tunnels in solid earth, bare floor; floor 8 has a walled grid hall (not cave, ignore) |
| cave-b | 32420-32559 | 31860-31989 | 9-11 (render floor 10) | winding tunnels 2-5 wide, grey rock-soil patches, debris, stones, rubble, wood braces, a lava pool |
| cave-c | 33130-33269 | 31090-31219 | 8-10 (render floor 9) | wide chambers joined by bands, sand and dirt floor, debris everywhere, many pillars |
| cave-d | 33100-33239 | 31580-31709 | 10-12 (render floor 11) | built tunnels, not a cave. Kept only for its stalagmites in solid rock |

Whole map: floors 8-15 hold 15.3M tiles. The solid fill (ground family G9026 "earth", item 9026 is 90% of it) covers each floor. Caves are carved floors of
G9021 "dirt floor" (ids 9021-9025) in it. On floor 9 the minimap shows about 60 separate cave regions.

## Structure of the reference (measured)

Walkable = ground walkable and no blocking item (wall pieces on floor tiles are not walkable). Depth d = steps to the nearest non-walkable tile (8 neighbours). Tunnel width = 2d-1 along ridges.

| number | maze caves (a, b) | chamber cave (c) | our output (review-01) |
|---|---|---|---|
| walkable share of window | 11-27% | 14-26% | 16-27% |
| depth d=1 / 2 / 3 / 4+ of walkable | 86-97 / 3-17 / 0-1 / 0 % (a z10, z11: 49-65 / 33 / 4-14 / 4) | 47-69 / 28-30 / 9-16 / 2-7 % | 43-56 / 24-29 / 12-16 / 8-15 % |
| tunnel width (ridge) | 1-3 walkable, 5 on 10% | 1-9 | 1-15 |
| chambers (core d>=4, width 7+) per 18200 tiles | 0-9 (a z11: 9, b: 0) | 6-21 | 5-14 per 9200-16400 |
| chamber area grown 3 tiles | 49-135, median 85 (a z11) | median 69-103, max 201 | median 63-161, max 810 |
| straight edge runs of length 1 / 2 / 3 / 4 / 5+ | 59-65 / 15-24 / 9-10 / 3-5 / 2-5 % | 66 / 18 / 8 / 4 / 4 % | 72 / 15 / 6 / 5 / 2 % (seed 302 l50) |
| rock islands inside floor | 0-12, nearly all 1 tile | 74 small, 1 of 46 | 30-48 small |
| dead ends (ridge ends per 1000 walkable) | 50-58 | 49 | 47-48 |
| components | 6-8 big (2 or 3 hold 90%) | 10-29 | 10-27, largest holds 50-97% (see flaws) |

Reading: reference tunnels are narrow (3 tiles floor, 5 with walls), staircase walls (diagonal steps), few loops, many short spurs, and walkable 15-25% of the rock.
Chamber caves (c) are wide bands 5-9 with pillars. The current generator already reproduces the chamber cave statistics.

### Walls: two styles, both 12 pieces, both named with name_set.py

- Style B, "stone wall on the floor edge" (cave-b, the common one: 1.3% of cave floor tiles carry one). The wall piece lies on the floor tile at the edge, named toward the rock, blocks walking. Stack: `[dirt floor, (decor...), wall]`.
  edge_n 5640, edge_e 5641, edge_s 5642, edge_w 5639, inner_nw 5648, inner_ne 5652, inner_sw 5650, inner_se 5649, outer_nw 5645, outer_ne 5646, outer_sw 5644, outer_se 5643. Variants: 5653 (inner_se), 5654 (inner_sw); a rarer dirt-coloured set 5631-5637 (edge_w 5631, edge_n 5632, outer_se 5633, outer_nw 5635, edge_e 5637, inner_nw 5647 or 5648, inner_se 5649).
  This is the kit's `shore_on_base` (water last layer, `outside` true).
- Style A, "dirt wall instead of the rock tile" (cave-a). The wall piece is the only item of a rock tile beside the floor; the floor stays free to its edge (3 wide stays 3 wide). Named toward the floor: floor south of the wall = edge_s 356, floor north = edge_n 357, floor east = edge_e 358, floor west = edge_w 359, floor SE and S... inner (floor on two sides): inner_se 364 (floor E+S), inner_sw 365 (S+W), inner_nw 366 (N+W), inner_ne 367 (N+E), outer (floor only on the diagonal): outer_se 360, outer_sw 361, outer_nw 362, outer_ne 363.
  Use it with a lava-style layer table (water first, the floor draws onto the rock). Not in the kit yet, because style B is the common one; `water_low` mode exists in the generator, so a kit `cave_dirt` can be tried by moving the layers.

### Grounds

- Solid fill: 9026 (90%), 9027-9033 (1% each), 9034-9041 (0.2%), 9042 (1.6%). Not walkable. Kit role `water`.
- Floor: 9021 33%, 9024 31%, 9025 22%, 9023 10%, 9022 5%. Role `base`. Border of dirt floor onto rock soil (12 pieces, named): edge_n 7654, edge_e 7834, edge_s 7833, edge_w 7666, inner_nw 7671, inner_ne 7672, inner_sw 7836, inner_se 7837, outer_nw 7667, outer_ne 7668, outer_sw 7669, outer_se 7835. Kit key `base_on_rock`.
- Grey patches: rock soil G4405 (4405, 4407-4410, 4413-4420), roles `sand` and `rock_soil`. Other patch grounds seen: dark basalt floor 17625-17628 (cave-b floor 9), sand 9059, sandstone floor 412 (cave-a floor 11), dirt floor 351-355 (cave-c). Not in the kit.

### Decoration (per walkable tile, no clear dependence on depth)

- Stones 3610-3614 (stones), 3621-3623 (stone): walkable 1x1 decor, total 0.28-0.31 per tile (cave-b), same at d=1, 2, 3.
- Debris: items 6374-6386 and 6476-6488 carry the ground_border flag, they are rubble overlays drawn over the floor. 0.43-0.73 per tile in cave-b, 1.0-1.5 in cave-c (laid 2-3 deep, the commonest is 6374 at 0.05-0.09 and 6476 at 0.17-0.20).
- Rubble heaps 5619-5624, 5707-5709, 21934: 2x2, blocking, 0.4% of floor tiles.
- Stalagmites 386, 387, 390, 391 (1x1 blocking), 17765, 18515: 0.4% of dirt-floor tiles and 1.3% of G351 floor. Most sit on the solid fill as scenery.
- Solid fill carries 0.6-1.2% earth decor (8462, 8463, 8467 and similar), nothing from distance 3 up differs.
- Planks 5297, 5300, 5301, buttress 1215, 1216 (support posts): rare, hand-placed.
- Lava (G598), water and stairs/ramps (1388-1395, 8372, 8373) are set pieces, not kit decor.

## Kit (`kit/cave.json`) by role

`water` = solid fill, `base` = dirt floor, `sand` and `rock_soil` = grey rock-soil patches, `shore_on_base` = stone wall (style B), `base_on_rock` = dirt floor border onto grey,
`clumps.big` = rubble and stalagmites, `clumps.small` = debris and stones (weights from the measured rates), `meadow` = stones.
`mountain`, `hill`, `mountain_cliff`, `top_rim`, `hill_*`, `mountain_ramp`, `hill_ramp` are placeholders (the generator reads them, the cave has no relief). Defaults: mountains 0, hills 0, lakes 8, sand 5.

## Does the current generator make a cave?

Partly. Run: `python3 -B run.py gen/generate.py --kit cave --name X --seed 301 --lakes 45 --size 96`. With the solid fill as "water", the floor as one island, and `--lakes` as rock pillars inside it, the output is a **chamber cave** in the style of cave-c: wall pieces are right on every outline, floor and patches draw, decor draws. Depth shares, chamber counts and dead ends are in the reference range (table above).

It cannot make **tunnel caves** (cave-a and cave-b), and it has these flaws:

1. Shape: land is one big blob, floor width 5-25. No tunnels of 3 tiles, no chambers joined by tunnels, no loops by design. Lakes at 35-55% give pillars, not corridors.
2. Reach: the largest connected floor holds 50-97% of the walkable tiles (301 96%, 302 86%, 303 50%, 304 50%, 305 94%, 306 97%, 307 67%, 308 54%). Passes and pocket sealing only work for water, relief and shores with walkable borders. Pockets of 1-50 tiles stay.
3. Stubs: lone wall pieces and 1-5 tile pockets near the edge of the area (seed 304 top and bottom).
4. `gen/generate.py` main(): `stats['levels'][0]` raises IndexError when the kit makes no mountain (mountains 0). `area.txt` is saved before the crash, but `render.png` and the access check are not written. I rendered with `tools/render.py` and measured with a scratch tool.
5. `Z = 7`: the cave must be on floor 8+ (the render and checks assume 7). The reference has the floor above with rock too.
6. `tools/batch.py` VARIANTS carry mountain and river knobs and only know seeds 101-108. Seeds 301-308 run with kit defaults only, so batch.py cannot give varied cave seeds. Needs a kit key `batch_variants`.
7. The kit must carry placeholder relief keys (list above).
8. Weights: `lead` is used 60%, the reference uses 90% for the fill and 31-33% for the dirt floor leads. Worked around by repeating ids in `members`.

## Design: cave mode (generator extension behind a kit key)

Kit key `"cave": {...}`. Without it nothing changes. Shape algorithm, all numbers measured above:

1. Solid fill everywhere (role `water`), margin of 5 solid tiles at the area edge.
2. Chambers: place `chambers.per_1000` per 1000 tiles (0.4-1.2 for chamber caves, 0-0.7 for tunnel caves, default 0.6), centres by Poisson-disc spacing 14+. Radius 3-6 (width 7-13), drawn as a noisy disc, then `roughen`/`break_runs` (staircase walls: straight edge runs of 1 about 62%, 2 about 18%, 3 about 9%, 4+ about 11%).
3. Tunnels: join chambers by a minimum spanning tree, then add `loops` extra edges (about 0.1-0.15 of the tree edges, so few loops). Each edge is a cheapest path (`road_path`) over a meander noise field, smoothed (`smooth_course`), drawn with a round brush of walkable width from `tunnel_width`: `{"2": 0.2, "3": 0.6, "4": 0.1, "5": 0.1}` (walkable, wall pieces come on top of the edge row in style B so 3 wide is 5 across). Width changes along a tunnel on 8-20 tile runs.
4. Spurs: dead-end branches 4-12 tiles long, `spurs_per_1000` about 3 per 1000 floor tiles (reference 50-58 ridge ends per 1000, a large part are staircase artefacts).
5. Target walkable share `floor_share` 0.15-0.25 of the area inside the margin; stop adding when reached. Optional cellular smoothing (one pass, 5-of-8 rule) only to round chamber outlines, never on tunnels (it closes 3-wide tunnels).
6. Clean: `lib.clean` with the pinch rule, drop pockets under 20 tiles and anything not joined to the biggest component (target 100% reached), remove 1 tile spurs of wall.
7. Pillars: rock islands inside chambers, `pillars_per_chamber` 0-3 of 2-8 tiles (reference chamber cave: 74 small islands, 1 of 46 per 18200 tiles).
8. Grounds, patches, wall set, decor: the existing steps with the kit above (sand patches 3-6% with `base_on_rock` borders; decor from `clumps`).
9. Floor and exits: kit/arg `floor` (default 9 for caves) replaces the hard-coded 7; `stairs`: `{"up": [ids], "down": [ids]}` pairs placed at dead ends or chamber walls (ramp ids 1388-1395 and the hole above), each joined to the main floor. Needed for a usable underground level; without them the area is a closed floor.
10. Summary: print walkable share, widths by d, chambers, reach per floor (guard `levels` empty).

Kit keys to add: `cave.chambers {per_1000, radius [3,6], spacing}`, `cave.tunnel_width {width: share}`, `cave.loops`, `cave.spurs_per_1000`, `cave.floor_share`, `cave.pillars_per_chamber`, `cave.wall_style` (`"on_floor"` = style B through `shore_on_base`, `"on_rock"` = style A through a lava-style layer table), `cave.stairs`, `floor`, `batch_variants` (per-seed knob strings). Check with the same tools (`tools/path_study.py` on windows, the depth/width/chamber counts of this note's tables).

## Next

1. Owner reviews `areas/cave-review-01/index.html` for the look (wall, floor, patches, decor). Ask: tunnel caves (a, b) or chamber caves (c)? Style B walls (grey stones) or style A (dirt)?
2. Generator owner builds cave mode from the design above (needs edits in gen/generate.py and tools/batch.py, kept out of this task).
3. Kit follow-ups: dark basalt patch ground, lava pools and wooden braces as set pieces, a style A kit `cave_dirt`.

## Owner decisions (2026-10-26)

- Cave shape: both kinds, chosen by kit key: tunnels 2-5 wide joining chambers; a kit can ask for tunnels only, chambers only, or a mix.
- Wall style: mixed; each cave picks the stone wall (on_floor) or the dirt wall (on_rock) at random (seeded). Both sets go into kit/cave.json.
