# Swamp kit (kit/swamp.json)

Owner request 2026-10-26: "faça um pântano". Learned from the reference map's swamp island (floor 7).

## Reference windows

| window | tiles | what it shows |
|---|---|---|
| refs/swamp-a | x 32880-33040, y 32150-32260 | coast, bays, densest mosaic. Main source |
| refs/swamp-b | x 33010-33120, y 32010-32120 | north-east coast, town edge. Second source |
| refs/swamp-c | x 32790-32900, y 32110-32220 | swamp meeting the grass continent, a river. Grass share is inflated, use it for plants only |

Other swamp: block x 32896-33023 y 32128-32255 and block x 33024 y 32000 (z7). Blocks at x 17408-17663, y 15104 are far outside the continent, ignored.

## Key finding: the swamp ground is a liquid

The server item table marks olive swamp (18580-18590) and lime swamp (4691, 4700-4712) as BLOCK_SOLID. The client file marks them not walkable too. Mud, grass, moss and planks are walkable. So on the reference map the swamp is a network of walkable trails (mud, grass, moss, planks) in impassable swamp.
- The kit therefore uses olive as `water` (lava style: water is the first layer, the land draws onto it).
- Measured on a and b: liquid is 55-58% of swamp ground tiles, 84% and 76% of land tiles are walkable, one walkable component holds 89% and 65%.
- Do not use olive as `base`. Access then reads 17% walkable and the reach check fails.

## Ids

| role | ids | notes |
|---|---|---|
| water (impassable swamp) | 18580 lead, 18581-18590 | 46-47% of ground tiles in a and b. Plants stand on it (`water_flora`) |
| base (mud) | 18560 lead, 18561-18567 | 13-15% of ground. Lowest land layer |
| sand role (grass) | 9043 family, 9044-9058 | 12-16%. Same grass as the grass kit |
| grey_sand role (moss) | 17667 lead, 17665-17672 | 9-12%. Highest land layer |
| crossing ground (planks) | 18764 | ford ground over swamp, 3.6-5% of ground in the reference |
| mud on swamp | 18568-18579 | named with name_set, 12 of 12 |
| grass on swamp and mud | 7653 set (same ids as the grass kit's base_on_sand) | confirmed on olive tiles |
| moss on swamp, mud, grass | 18141-18152 | named 12 of 12 |
| shore, mountain, rim, ramp | repeat the grass kit | mountains are not wanted, see below |

Layer order, lowest first: swamp, mud, grass, moss (seam_audit: each draws onto the ones before it).
Not used: lime swamp 4691 and 4700-4712 (6-10% of ground), borders 18593-18604 (olive onto lime, 8 of 12 named), 18901-18916 planks borders, wooden plank walkways of both grains (18764-18769).

Families in study/families.json are wrong for the swamp: 18581-18589 sit with the lime family, and mud, moss and plank are split in two each. The studies ran on a merged copy (olive 18580-18590, lime 4691 and 4700-4712, mud 18560-18567, moss 17665-17672, plank 18764-18769). Merge them with `study/family_overrides.json` (not edited here).

## Measured, reference against ours (8 seeds 201-208, size 96)

| number | reference a / b | ours (mean of 8) |
|---|---|---|
| liquid share of swamp ground | 0.55 / 0.58 | 0.54-0.59 |
| land: mud / grass / moss / plank | 0.34 / 0.35 / 0.19 / 0.11 and 0.32 / 0.30 / 0.29 / 0.09 | 0.43 / 0.39 / 0.16 / 0.03 |
| walkable share of land | 0.84 / 0.76 | 0.86-0.90 |
| liquid depth 1 / 2 / 3 / 4+ (1 = edge) | 0.47 / 0.28 / 0.15 / 0.10 | 0.17 / 0.15 / 0.14 / 0.54 |
| land depth 1 / 2 / 3 / 4+ | 0.61 / 0.28 / 0.08 / 0.03 | 0.14 / 0.15 / 0.13 / 0.58 |
| plants per tile on swamp | 0.41 / 0.48 | 0.42 |
| plants per tile on mud | 0.47 / 0.61 | 0.46 |
| plants per tile on grass | 0.57 / 0.70 | 0.40 |
| plants per tile on moss | 0.57 / 0.62 | 0.36 |
| bare seams, odd tiles on mud set | | 0, at most 5 |
| reach on floor 7 | | 99.9-100% |

The two big gaps are depth and the plank share. They need generator features.

## Rounds

1. Swamp as water (reach 100%). Lakes 20, rivers 10 of width 2, sand 62, worn_share 6 (mix mud 79% to 43%, grass 12% to 39%, moss 7% to 16%).
2. Plants: flora rates x2.6 on grass and moss, x2.2 on swamp tiles, clump boost big 2.0 small 2.2 (plants per land tile 0.34 to 0.40).
3. Lime blobs dropped: they came out as 1-3 tile squares with no border (rectangles). Tried sand 46: depth no better and the mix worse, reverted.

## Generator features still needed

1. **Fine patch scale** (biggest gap). The reference grounds are thin: 61-67% of mud, grass and moss tiles touch another ground, and 45-47% of swamp tiles. Patches are 1-3 tiles wide and 3-30 tiles long. Ours are blobs with 58% of tiles 4+ deep. Wanted: a kit key like `patch_scale` (noise octaves for the sand patches) and `worn_blob` `[min, max]` tiles (now 3-7, edge tiles only, spaced 2 apart) with `worn_gap` (now 2).
2. **More than three land grounds.** The reference mixes mud, grass, moss, planks and lime in one mosaic. The generator has base, sand and grey_sand on floor 7 (rock soil and gravel need mountains). Wanted: `patches: [{"ground": "moss", "share": 0.19, "scale": 3, "min": 2}, ...]`, each its own noise field, placed in layer order, with the layer table giving the borders.
3. **A second liquid.** The reference has the swamp liquid and a sea at the coast (shallow water 4608-4613, deep 27725). Ours has one liquid, so the area edge is swamp, not sea. Wanted: `water2` (sea outside, swamp inside) with its shore set 4644-4655 drawn by the swamp's land only at the outer edge.
4. **Liquid variants with their own border.** Lime swamp is 11-18% of liquid tiles by distance from land (d1 0.11, d6+ 0.18, other bright swamp ids 5-12% more) as blobs with an olive border set 18593-18604 drawn onto them. Wanted: variant blobs with a `variant_border` set, so a variant is not a hard-edged square.
5. **Plank walkways as roads.** Planks lie as winding walkways 1-3 tiles wide with their own grain per direction (18764-18766 across, 18767-18769 along) and a border set. Wanted: a kit key `road_ground_ns` and `road_ground_ew`, so roads and fords pick the grain from their direction. Now planks appear only as fords (3% of land, reference 9-11%).
6. **No-mountain maps.** `mountains 0` crashes the summary line (`stats['levels'][0]`), and a level that vanishes does the same (seeds 201, 205, 207 at mountains 1.5). The kit asks mountains 5 so that every seed keeps a level of 50-160 tiles. The reference has 1.6-4.6% mountain tiles in the windows, but of muddy and clay rock, not the grey cliff the kit repeats from the grass kit. Wanted: `mountains 0` working, and `clumps.tops` not required when there are no levels.
7. **Plants on swamp tiles by the shore.** `water_flora` is only read for variants named `crust` or `crust2` (the kit names the olive variant `crust` for that). Wanted: a `plants_on_water: true` key, no variant naming.
8. **Mangroves in the sea.** 5394-5395 and 5398-5399 stand on shallow water near land at 0.02 per tile. Not used, tied to feature 3.

## Render paths

- areas/swamp-review-01/index.html (8 seeds, review page)
- areas/swamp-review-01/seed-201/render.png, seed-205, seed-207 (best three)
- study/swamp-sbs.png (reference window a against seed 203), study/swamp-grid.png (all 8 seeds)

Regenerate: `python3 -B run.py tools/batch.py swamp-review-01 --kit swamp --seeds 201,202,203,204,205,206,207,208`. Kit defaults: mountains 5, rivers 10, river_width 2, lakes 20, roads -1, sand 62.
