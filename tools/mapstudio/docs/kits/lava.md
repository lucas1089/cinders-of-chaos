# Lava kit (kit/lava.json), round 1 notes

Owner request 2026-10-26: "regiao de lava". Status: working first kit, a volcanic isle in a lava sea.
Batch: areas/lava-review-01 (seeds 501-508, kit defaults, no knob variants).

## Reference windows (reference map, ground floor given)

All coordinates are map tiles. Underground windows are floors 8-15 caves, so the render shows the floor named.

| window | where | what |
|---|---|---|
| refs/lava-a | x 32885-33085, y 33035-33250, floor 8 | lava ring round a cave island: earth walls, dirt floor corridors with embers, stones, debris |
| refs/lava-c | x 33095-33295, y 33055-33245, floor 8 | earth field with grey rock blocks, cracked crust patches, lava puddles |
| refs/lava-d | x 32500-32720, y 31790-32020, floor 14 | the best "island in a lava sea": earth shore, big lava lake, dirt floor island |
| refs/lava-b | x 32000-32140, y 32525-32670, floors 0-15 | surface volcano: brown dirt isle in the sea, rock soil, terraced mountain, lava crater on the tops (floors 3-6) |

refs/lava-a7, lava-c7, lava-d7 are the same windows with their one floor relabelled to 7, because many tools
read floor 7 only. Lava is mostly underground on the reference map (floors 8-15: 205k tiles; surface only 1.8k).
Other volcanic spots seen with tools/find_family.py: x 31488-31680 y 32640 (floor 12, white marble), x 33088-33152
y 31616-31680 (floor 15, black marble), x 34176 y 30976 (floors 13-14). Not studied.

## Items by role (all seen on the reference map)

- lava (`water`): ground 598 (lead), 600, 601 (all not walkable). The reference has a crust band (tools/bands.py G598,G599,G5815:
  cracks 16% at distance 1, 9% at 2, 1% at 3), but the kit leaves it out (see lesson below): molten only.
- base: dirt floor G351 = 351, 355, 353, 352, 354. (Window d uses the twin family G9021 = 9021-9025.)
- sand (patches): cracked ground G5815 = 5815, 7354. Crossing ground (fords): 5815.
- rock soil: G4405 (ids of the grass kit); mountain fill: 919.
- border sets, named with tools/name_set.py (12 of 12 each):
  - dirt floor onto lava (`edge_on_lava`): 4808-4819. Rock soil draws the same set onto lava.
  - dirt floor onto cracked ground and onto rock soil (`edge_on_cracks`, `edge_on_rock`): 4796-4807.
  - mountain cliff 4468-4479 and top rim 891-902 (volcano window b, floors 3-6); ramps 1388-1395.
- decor: embers = fire 1487-1489 (2x2, walkable); flame wisps on lava near the shore = burning wall 5061-5067, 8174;
  stones 3610-3614, 3621-3623; ash debris 6476-6487 (kind border, walkable); stalagmites 386, 390, 391 (blocking).

## Layer order (tools/seam_audit.py, tools/pair_items.py)

Lowest to highest: lava, cracked ground, rock soil, dirt floor. Dirt floor draws 4808.. onto lava, 4796.. onto cracks
and rock soil. Cracks onto lava has a rare set 5816-5827 (only 8 of 12 named, few uses), so the kit keeps cracks off
the lava edge (`no_water_border`) and uses the cracks only as inland patches and fords.

## Ours against the reference (walkable ground tiles, per tile)

| number | a | c | d | ours (seeds 501-508) |
|---|---|---|---|---|
| cracks share of walkable ground | 1% | 23% | 0% | 2-3.5% |
| embers (fire 1487-1489) | 0.080 | 0.000 | 0.002 | 0.030-0.035 |
| stones | 0.018 | 0.105 | 0.130 | 0.046-0.060 |
| ash debris 6476-6487 | 0.116 | 0.000 | 0.147 | 0.070-0.084 |
| odd edge_on_lava / edge_on_rock / cliff tiles | | | | 0 / 0 / 0 |
| odd rim tiles | | | | 8-40 per map (13% of rim tiles; the grass kit has the same) |
| bare seams | | | | 0 |

Access: 5/5 to 9/9 ramps usable and 99.9-100% of walkable floor 7 reached on all 8 seeds, 0 bare seams.

Rounds done (kit only): 1) roads to ramp feet made 22% dark cracks: road_limit and sand 1 (now 2-3%). 2) the crust variant
used id 5814, a 2x2 item and not a ground, drawn as black squares: crust variant dropped; sea cliffs off. 3) embers and
debris: fire clump boost 0.5, small 1.6, meadow rates. A fourth try (more dirt inside mountain tops) made tops
unreachable on two seeds, so it was reverted (top_rock stays 1.0 / 0.9).

Lesson: a water variant id is added to access.NO_WALK. A crust variant that reuses a walkable id (5815 is also the
sand patch and the ford ground) made every crack tile count as lava, so seeds 504 and 505 lost 142 and 516 top tiles and
reached 55%. A crust band needs a ground id of its own that is not used as walkable elsewhere, or feature 3 below.

## Generator features still needed (not coded, by instruction)

1. Lava on mountain tops. The volcano (window b) has 7-17% lava on tops at heights 1-6 (71% at the highest top:
   a crater). Kit key wanted: `top_liquid` {"share": [0.07, 0.16], "ground": 598, "band": "centre"}: lava lakes in the
   middle of tops, with edge_on_lava on their rim tiles and kept off ramp landings.
2. Solid cave walls. Caves (windows a, c, d) have no raised tops: the mountain is a not-walkable ground (earth 101,
   5711-5726, 9026-9042) with a wall set drawn on the tiles next to it: dirt wall 5631-5638, 5647-5651 on dirt floor,
   stone wall 5639-5646, 5648 on lava. Wanted: kit key `"solid_mountain": true` (fill without a top floor, no ramps) and
   `wall_set` per lower ground ({"base": <12-piece set>, "water": <set>}). Without it a lava kit can only be an
   island, not a cave.
3. Walkable crust in the liquid. Crust tiles inside the lava (5815) are walkable on the map but count as liquid for
   access. Wanted: kit key `water.walkable_variants`: ["crust"] so access treats them as ground.
4. Corridor shapes (windows a, c): the reference cave floors are 3-6 wide winding corridors with embers on the edges. The
   island generator makes broad plains. Wanted: a "roads as the main ground" mode (`corridor_ground`: true) carving the
   base as corridors inside a solid field.
5. batch.py has knob variants only for seeds 101-108, so batches 501-508 all run the kit defaults. Wanted: variants
   read from the kit (`batch_variants`).
6. Damaging lava (23858-23862, walkable, ground speed 150) is 2% of lava in window a. Left out: players walk onto it.

## Next

- Learn the earth hills of window b (brown dirt G103 with rock soil patches) as a second base.
- Study clumping per window instead of one pooled file (a and d differ a lot: embers against stones).
- Hold a review with the owner on the grey tops: reference tops carry lava, ours carry only stones.
