# fungal kit

Giant fungal caverns. Seeds 861-868, review set areas/fungal-review-01. Cave mode, floor 9, wall style on_floor.
Kit: `kit/fungal.json`. Built from `kit/cave.json` with `gen/cave.py` (read only), new keys: none. Cave defaults are kept (stairs, pocket fill, repair).

Palette: dark mossy floor, pink sponge and white mold patches, grey rock walls, orange and green giant caps, coloured spores.
Layout: as kit/cave.json (mix of chambers and tunnels, cave defaults), only floor and decor differ.
Item ids:
- Floor: lead 17665, members 17666-17672 (mossy floor). Patches: mushroom sponge 18053-18055 (sand role), mold floor 17647-17652 (grey_sand role). Mass: 919. Cliff walls: rock set 4468-4479.
- Blocking decor: giant caps 4184 21565 21439 4172 4173 10778 10779 10787 10811 10813, boletus 17753 17754, sticky 17756 17758, spongy 17759, huge brown 17760-17763, 17778 17714 17723, small caps 17747 17749 17750 17751, puffball 18220, roots 20875 4227.
- Walkable decor: small mushrooms 17744-17746 4178-4183 38290 38291 40745-40749, spores 18221-18224 (overhead), slime fungus 13597, border mushrooms 17811-17814, roots 20850 20852 20855 4223-4226, mushroom table 17777.
Good: giant caps with spores and moss on the cave look read well. Weak: the cave wall is the plain grey rock, no glowing caps in the walls, no huge (3x3 and larger) mushroom trees since the titanic mushroom pieces need to be laid as multi-tile sets.

## Generator features (round 8)

Round 8: `wall_check` on (counts 0), flat patches dropped, `same_look` for the remaining roles, `bare seams` 0. No pools yet.


## Round 9

Detached floor squares and unjoined stair landings fixed (landing_ring); a few acid pools (acid_edge, pools).
