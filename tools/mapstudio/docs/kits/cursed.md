# Cursed kit (kit/cursed.json)

Owner request 2026-10-26: a blighted land, dark purple, grey and sickly green. Review batch: areas/cursed-review-01 (seeds 701-708, `python3 -B run.py tools/batch.py cursed-review-01 --kit cursed`). Built without a reference window; the decor comes from pack 30 (server/data/items/pack30_decor*.csv) and the base items.

## Items by role
- water (bog): black tar 708-711 (not walkable). Lime acid pool 36865 was tried as a second variant and dropped (it scattered as bright confetti over the outer liquid).
- base: purple soil family, lead 11504, members 11490 (dark red), 11491. The real map lays it beside the black gap and tar.
- sand (paths and patches): bone dust 41313-41319 (grey with bones, pack 30).
- grey_sand (patches): dark moss 30490 (green, our own ground item).
- rock_soil: pestiferous ground 29153, unused (mountains 0).
- border: purple_edge = 11741-11752, named with tools/name_set.py on x 33360-33470 y 32352-32500 z14-15 (12 of 12; the pieces sit on black gap tiles beside earth, so the set draws onto the liquid like the lava and swamp kits). Also drawn onto bone dust and moss.
- crossing: ford 18764 (planks, brown). plank_roads 18764-18769.
- trees: magic forest dead trees 39490, 39491, 39492, 39498 (twisted, purple, 3x3), 39499 (purple mushroom tree), 38665, 38667, 38766 (4x4 dead trees), base dead trees 2709, 2710, 2717-2720, 8314, 8583, 8864.
- graves: tombstones 38184-38234 (1x1), 40879-40891 (small), 38672-38678 (2x2 weathered stones and an angel), crosses 40777, 40778, angel 38761, gargoyle 38767, cemetery gate 38771, broken fences 38559-38561, 38566-38568, iron gates 38235, 38237.
- dark crystals: 38782-38785 (purple rock with teal glow). Skull pillars 7058, 7059 (light), ruins 38788, 38789 (glowing, walkable), lamp post 38769 (light), ghost charm 9738-9740 (blue glow), skull candle 3744.
- small walkable: dead grass 40727-40731, thorn plants 40767-40770, twig 40750, branches 40842, 40845, 40846, bones 8407, 8627-8630, 3124-3127, skulls 10094, 2247, 38309 (skull pile), withered plants 11265-11268, dry reeds 38660, 38662-38664, rocks 40739, 40741, 40870, 40871, bones 6408-6410, 6412, skeleton 9521, candles 38308, 40770-40773.
- pocket_fill: dead branches 2713-2716.
- Item sheets: scratch only.

## Reach
All 8 seeds 100 percent of walkable tiles on floor 7 (3633/3633, 5250/5250, 6382/6382, 3800/3800, 5422/5422, 3381/3381, 4889/4889, 6381/6381; no cut-off landmass).

## Needs from the generator
1. A grey-green bog, not a flat tar field. Wanted: liquid variants with blob scale (`variant_scale`) so a second liquid (acid 36865, cursed pool 30492) forms a few big pools, not single tiles; and a `variant_border` set (the swamp doc feature 4).
2. Fog. No fog sprite exists in the pair that reads well; mist border 21592-21604 draws as grey static. Wanted a fog decor or an overlay key.
3. Gravestone rows: `rows` clumps with spacing so tombstones line up, and a fence line along the shore.
4. Bone dust edge: a border set of bone dust onto purple soil is not known, so patches are bordered by the purple edge set only.

## What looks wrong
- Decor is very dense and uniform; the middle of every island is a graveyard. Lower vegetation (default 75) further or add clump quantiles learned from a real graveyard.
- Tar reads as a flat dark grey field, not a liquid. Black gap would be darker but it is already the celestial void.
- The ford (brown planks) is the one warm colour in the map; a dark plank would suit better.
- Moss patches show as dark squares with weak edges.
- The red withered plants (11265-11268) and the orange stone angel tint pull toward brown.

## Best render paths
- areas/cursed-review-01/seed-703/render.png
- areas/cursed-review-01/seed-702/render.png
