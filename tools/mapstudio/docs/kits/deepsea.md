# deepsea kit

Sea floor. Seeds 831-838, review set areas/deepsea-review-01. Cave mode, floor 9, wall style on_floor.
Kit: `kit/deepsea.json`. Built from `kit/cave.json` with `gen/cave.py` (read only), new keys: none. Cave defaults are kept (stairs, pocket fill, repair).

Palette: olive sea floor, pale sand patches, dark ocean rock patches, grey rock walls, purple coral mass, black abyss.
Layout: lagoons (chambers radius 4-7) joined by channels 2-4 wide (mix shape), rock islands as pillars.
Item ids:
- Floor: lead 15232, members 15233-15237 (brown sea floor), 36430. Patches: sand 104 (sand role), ocean floor 5405-5410 (grey_sand role). Mass: coral stone ground 23928-23932. Cliff walls: rock set 4468-4479 (edge n 4471, e 4468, s 4469, w 4472).
- Blocking decor: corals 5413 5422 5423 15158 36128 36136 15566 14666 5414-5416, kelp 5421 36603, anchors 5444 4974 4977 15358, ship hull 4883-4886 4890-4898, cabin 4906, masts 4942 4943 4948 4949, rails 4927 4938, chests 38795 38796 38826-38828, crates 36633, shells 7552 24167, rocks 38310-38312, glowing mushroom 17750.
- Walkable decor: seaweed 15146 15147 15148 36602, coral 36606 36607, shells 5679 5682 23767 36609 7551, barnacles 20161-20163, bubbles 25839 25840 and blue spores 18223 18222, fish 5554, gems 15267 9562 9563, glowing fruit 21179 21180 21213 21216-21218, debris 29205 29207, coral crate 15569.
Good: wreck pieces, corals and chests give a readable reef. Weak: the grey rock walls and purple mass look like a cave, not water; no water tint or fish; sand patches are hard squares; wreck pieces are single hull tiles, not a full ship.

## Generator features (round 8)

Round 8: `wall_check` on (cliff pieces and void counts 0), flat sand and grey patches dropped (`patches` empty, `defaults.sand` 0, `same_look` for the rest), tinted deep water `pools` with their own border (`deep_edge`). Still missing: pools only fit in chambers 7+ wide, small tunnels get none.


## Round 9

Pools on every seed, also narrow ones; landing ring.
