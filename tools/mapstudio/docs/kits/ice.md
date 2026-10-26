# Ice kit notes

Kit file: kit/ice.json. Review batch: areas/ice-review-01 (seeds 401-408, `--kit ice`).

## Reference windows
- refs/ice-a: x 32300-32470, y 31140-31360, floors 3-7. Snow island, icy terraces, small ice patches.
- refs/ice-b: x 31950-32130, y 31130-31300. Frozen lake sheet, snow mainland, ridges, a river.
- refs/ice-c: x 31900-32110, y 31480-31650. Snow island, fir and dead trees, grass tufts.

## Items by role
- water: shallow lead 4608 (members 4609-4613), deep lead 27725 (27728-27731). Bands measured with tools/bands.py.
- base: snow, lead 670 with the snow variants 6580-6593.
- sand role: ice patches, lead 6684 (6683, 6685, 6686). Walkable 1x1.
- rock_soil: snow variants (6587 lead). Not 6869, that is a 2x2 non-walkable sheet.
- layers: sand, rock_soil, base (draws snow_on_ice onto ice), water (shore_on_base onto land).
- snow_on_ice set: 4737-4748. shore_on_base set: 6627-6638.
- mountain_cliff: 6719-6727, 6761, 6762, 6768. Ramps: 6909-6916. Mountain lead 919.
- top_rim and hill_rim: snow_on_ice.
- plants: chips 6715-6718, grass 6218, stones 6999-7003, flakes 7145-7157, fir 2697/2698, 7020-7022.
- Clump quantiles: study/ice_clumps.json, study/ice_clumps_top1.json.
- Default knobs: levels 1, mountains 25, lakes 1, rivers 0, roads 0, sand 2.

## Ours against reference (batch 401-408)
- Access 99.8-100 percent, ramps usable all, cut off none.
- Mountains 19-21 percent of land. Sand 10-20 percent at sand 2.
- Bare seams base|rock_soil 178-414 per map. These are same-look snow variants, not real gaps.
- Cliff clashes 273-494 per map.
- Reference: 4 levels, heights 8.7, 3, 1.9, 7.8 percent. Ours has 1 level.

## Known look flaws
- Ice patches render as small 2x2 squares. Reference patches are 5-30 tiles.
- An inland lake reads as a dark deep pocket.
- Black wedges at cliff inner and outer pieces. They are in the sprites and also in the reference.
- Relief is sparse next to the reference.

## Generator features still needed
Each line: need, reference number, wanted kit key.
- Frozen sheet liquid: 2x2 non-walkable ground 6869, 7 percent of floor 7, snow border 4737-4748 on it. Key: `lake_water`.
- No top rim. Key: `top_rim: null`.
- Top sand share per level. Reference has about 3 percent ice on tops. Key: `top_sand`.
- Decor on mountain fill: ids 6939-6950, about 22 percent of fill tiles. Key: `mountain_fill_decor`.
- Bigger irregular ice patches, 5-30 tiles. Key: `sand_patch_min`, `sand_patch_max`.
- Broad multi-level terraces. Reference has 4 levels.
- Separate coast style. ice-c uses the grass shore set 4644-4655 with a dirt rim. Key: `coast_set`.
- Treat same-look ground pairs as seam-free. Key: `same_look: [["base","rock_soil"]]`.

## Best render paths
- areas/ice-review-01/seed-405/render.png
- areas/ice-review-01/seed-403/render.png
- areas/ice-review-01/seed-401/render.png
