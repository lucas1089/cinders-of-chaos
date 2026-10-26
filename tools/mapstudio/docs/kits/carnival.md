# carnival kit

Abandoned macabre circus. Seeds 841-848, review set areas/carnival-review-01. Cave mode, floor 9.
Kit: `kit/carnival.json`. Built from `kit/cave.json` with `gen/cave.py` (read only), new keys: none. Cave defaults are kept (stairs, pocket fill, repair).

Palette: trodden dirt, red-white and purple-gold striped ring floors, dark iron fence, orange and purple string lights, bats.
Layout: rings (chambers radius 4-8) and midways 3-5 wide. The perimeter is an iron cemetery fence over dark mud.
Item ids:
- Floor: lead 103, members 8594 10176 7352. Patches: striped marquee 5159 5160 5174 (sand role), plank floor 29326 (stages, grey_sand role). Solid: 38003.
- Fence walls: iron cemetery fence set 41294 (post), 41295 (horizontal), 41296 (vertical), 41297 (corner).
- Blocking decor: tents 40187-40194, stalls 38985-38992, cages 29132 8781 8783, carts 5544 5546-5548 8581, wagons 8734 8735 26459 26460 26464, barrels 29351 29354 29360 29361 38983, hay 41369 41370, lantern posts 41384 41561 41562, street lamp 39043, pumpkin cart 41214, cauldron 41380, candy pile 41553, hanging chains 41563.
- Walkable decor: banners 9495 9496 9499 9500 10378 10379 10388 10389, torn banners 41557 41558, pumpkin strings 41555 41556, bulb strings 38993-38996, bat flock 41388, crows 41575, fog 41389, straw 41197, leaves 41195, puddle 41198, sweet bowl 38533, lantern 38532, candle 38308 41383.
Good: strings, banners and bats give the circus mood. Weak: no rides (carousel, wheel, swing), no striped big top, striped floor patches are small, tents are plain canvas.

## Generator features missing

- No building or room layout. The closest feature is cave mode (`gen/cave.py`): chambers act as rooms, tunnels as corridors, pillars as blocks. Rooms come out as organic blobs with stair-step outlines, so wall pieces read as broken or ruined runs, not as straight rectangular rooms. A rectangular room and corridor generator with doors would fix it.
- No per-wall variety: the wall set has one piece per direction, so windows, doors and broken pieces (which exist in the item set) are not laid.
- Ground patches (sand, grey_sand roles) have no border set between flat floors, so the summary reports `bare seams` of 6 to 140 tiles per map. This is by design for flat tile floors, not a missing border.
- No structure placement (decor is scattered by the clump tables only).
