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

## Generator features (round 8)

Round 8: ring, stage, tent, booth and hall rooms (`cave.rooms`), iron fence `walls`, big top `stamps` (split rail outline with lantern posts), carpet floors. `bare seams` 0 through `same_look`.


## Round 9

Doors at room entries; sparse corridor decor (themes.corridor.along); wall_check all 0 (open fences are see-through, gap check skipped).
