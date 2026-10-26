# hauntedfarm kit

Haunted farm. Seeds 821-828, review set areas/hauntedfarm-review-01. Cave mode, floor 9, fields as chambers.
Kit: `kit/hauntedfarm.json`. Built from `kit/cave.json` with `gen/cave.py` (read only), new keys: none. Cave defaults are kept (stairs, pocket fill, repair).

Palette: olive dead grass, dark purple tilled soil, pale corn stubble, orange pumpkins, grey tombstones, black bare trees, fog patches.
Layout: fields (chambers radius 4-8) joined by lanes 3-5 wide (chambers shape). The perimeter is a rotten split-rail fence on dark mud.
Item ids:
- Floor: lead 41102, members 41103-41110 (autumn grass). Patches: tilled soil 41093-41101 (sand role, 14%), corn stubble 41129-41137 (grey_sand role, 12%). Solid: dark muddy ground 38003.
- Fence walls: split rail set 41288 (post), 41289 (horizontal), 41290 (vertical), 41291 (corner).
- Blocking decor: dead trees 38665-38668 41572 41365 41367 39034 38574, scarecrows 41371 41372, pumpkins 41208 41210 41211 41527 41528 41529 41203 41212 41213, hay 41368 41369 41370, corn 41201 41205 41206 41207, wells 41386 38679, tombstones 41373-41376, wheelbarrow 41576, pumpkin cart 41214, gibbet 41542, bell 41545.
- Walkable decor: small pumpkins 41202 41524-41526 38657-38659, dead grass and flowers 38660-38664 40727 40729-40731, fog patches 41389 41390 (heaviest weight), puddle 41198, straw 41197, leaves 41195 41196, bones 41199, crows 41575, graves 41377 41535 41536 41539, crosses 40778 40780 40781, mushrooms 40745 40747, handcart 38656.
Good: the best looking of the set, scarecrows and trees read well. Weak: no barn (barn plank wall pieces 41226-41241 exist but need a building feature), fence is only on the outline, fog is faint, crows are rare.

## Generator features missing

- No building or room layout. The closest feature is cave mode (`gen/cave.py`): chambers act as rooms, tunnels as corridors, pillars as blocks. Rooms come out as organic blobs with stair-step outlines, so wall pieces read as broken or ruined runs, not as straight rectangular rooms. A rectangular room and corridor generator with doors would fix it.
- No per-wall variety: the wall set has one piece per direction, so windows, doors and broken pieces (which exist in the item set) are not laid.
- Ground patches (sand, grey_sand roles) have no border set between flat floors, so the summary reports `bare seams` of 6 to 140 tiles per map. This is by design for flat tile floors, not a missing border.
- No structure placement (decor is scattered by the clump tables only).
