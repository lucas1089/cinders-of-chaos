# bloodhospital kit

Butcher hospital. Seeds 811-818, review set areas/bloodhospital-review-01. Cave mode, floor 9.
Kit: `kit/bloodhospital.json`. Built from `kit/cave.json` with `gen/cave.py` (read only), new keys: none. Cave defaults are kept (stairs, pocket fill, repair).

Palette: sterile pale blue-grey cracked tile, red brick walls, blood pools, bone and skull piles, red torch light.
Layout: operating wards (chambers radius 3-6) and corridors 2-3 wide (mix shape), blocks as pillars.
Item ids:
- Floor: lead 14931, members 14932-14939 (cracked temple floor), 457, 15791. Patches: blood 20932-20937 (sand role), crypt flagstones 41304-41312 (dirty tiles). Solid: 407.
- Walls: crypt brick set 41391 (post), 41392 (horizontal), 41393 (vertical), 41394 (corner).
- Blocking decor: bone tables 12149 12150 12153 12154 12155 12151 as surgical tables, cell beds 38584 and beds 1754 1755 1760 1762, chain unit 38585, cage 38588, crates 7481 9686 36633 36635, barrels 38983 29361 29362, coffins 41378 41421, bone piles 41419 11122 11253 41550, ritual table 29387, blood basin 9441, bloodfire torch 12009, bone shelf 38581, table 38263.
- Walkable decor: bloodspots (as asylum), blood bowl 38840, blood 38580, bones 3124 3125 3127 41360 41361 41199, skeleton 38592, pile of bones 38590, chains 38578 38842, cobweb 38587, chair 11934, hanging lamp 38975.
Good: brick and pale tile contrast, torches give red accents. Weak: no real gurneys, no wheeled stretchers, no operating lamps (see kits_wanted.json); decor density is low in tunnels.

## Generator features (round 8)

Round 8: rooms, wards and cell blocks (`cave.rooms`), brick `walls` with windows, crypt flagstone floors, themed rooms. Pair 49 carcass piles and skeleton not placed yet in the room themes (left to a later round). `bare seams` 0 through `same_look`.

