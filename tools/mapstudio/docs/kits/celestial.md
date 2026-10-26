# Celestial kit (kit/celestial.json)

Owner request 2026-10-26: a sky realm, white and gold with blue accents. Review batch: areas/celestial-review-01 (seeds 601-608, `python3 -B run.py tools/batch.py celestial-review-01 --kit celestial`). Built without a reference window: the pair has no cloud or sky ground, so the void is the black gap ground and the clouds are snow.

## Items by role
- water (void): G15212 deep black gap, lead 15212. Not walkable, blocks projectiles. The real map uses it as the black sky round floating earth islands on floors 11-15 (x 33408 y 32576 z11). Members 15623 and 22658 were dropped (they draw grey speckle). Not used: G9726 pitch black gap, G100 "void" (that one is a lava-look sprite).
- base (cloud): snow, lead 670, members 6587, 6580-6593 (white, the same snow as the ice kit).
- sand (gold paths): sandstone tile 7350, 419 (gold). Appears as bridge approaches and small patches (3-8 percent).
- grey_sand (blue patches): ice 6684, 6683, 6685, 6686 (cyan). Patches 4-9 tiles, small.
- rock_soil: snow variants, unused (mountains 0). mountain, cliff, rim and ramp keys repeat the swamp kit's so the generator loads; no mountains are made.
- border: snow_on_void = ids 4737-4748 (the ice kit's snow_on_ice, drawn by the snow onto void, gold and ice tiles). A white fringe over black.
- crossing: ford ground 7350 (gold). plank_roads: gold 7350 (4 walkways).
- trees: cherry blossom 38616-38623 (forest pack, pink), 36110 white coral tree, 39006 blossom fruit tree.
- crystals: 8633, 8634 (blue, cyan, large, light), 9779, 9786 (cyan columns), small 8637, 8638 (also pocket_fill).
- ruins and statues (pale blue-white, frozen-ruins pack, walkable 2x2): 38913 statue, 38915 pillar, 38916 broken pillar, 38917 and 38918 arches, 38919 fountain, 38920, 38921 monuments, 38923 obelisk, 38926 table; 38829 gold urn, 38830 flower vase; 38832 white lady statue, 38834 small statue.
- flowers (walkable 1x1): 2742 white, 4150-4154 gold, 2740, 38357 and 38358 (blue). Candles 40771, 40772 as small lights.
- 

## Reach
All 8 seeds 100 percent of walkable tiles on floor 7 (tools/unreached.py: 3321/3321, 4060/4060, 5721/5721, 3131/3131, 4782/4782, 3623/3623, 4036/4036, 5868/5868; no cut-off landmass).

## Needs from the generator
Nothing blocks the kit, but these would make it look right:
1. Separate floating islands. The generator keeps one big landmass with void lakes and rivers inside, so the map reads as a cloud continent with holes. Wanted: `islands` {"count", "radius", "gap"}: several land blobs in the void joined by ford or plank bridges only, no land neck, plus a kit key for a no-sea-border "outside" that shows pure black.
2. Light sources need a light tag. Crystals (8633, 8634, 9779, 9786) carry a light attribute in items.xml but the generator has no way to scatter lights by distance so they do not clump. Wanted: `lights` {"<id>": spacing}.
3. Gold paths. `road_limit` plus `roads -1` leaves only bridge roads. Wanted: a `path_network` option for roads between island centres that works with `roads -1`, and a gold border set (gold onto snow) so paths have their own fringe. Now the snow draws onto the gold.
4. Void 1-tile holes. Single void tiles inside land show as hard black squares with no fringe (a few per seed). Wanted: `lake_min` (smallest void lake, 4 tiles).
5. Mist and cloud decor on the void (mist border 21592-21604) drew as grey static on black, so it is off. Wanted a cloud sprite set; none exists in the pair.

## What looks wrong
- Snow and gold are flat; no marble floor with its own border is known (white marble 406 and 9144-9146 have no border set learned).
- Decor is dense and the pink trees dominate; lower the weights of 38616-38623 for a calmer look.
- Gold shows mostly as thin strips at the edge (bridge roads), not as paths.
- Obelisk, marble pillar and golden lamp items drew as odd diagonal wall pieces and were removed.

## Best render paths
- areas/celestial-review-01/seed-603/render.png
- areas/celestial-review-01/seed-608/render.png
