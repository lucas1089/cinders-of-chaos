# asylum kit

Abandoned madhouse. Seeds 801-808, review set areas/asylum-review-01. Cave mode, floor 9, 96-128 tiles.
Kit: `kit/asylum.json`. Built from `kit/cave.json` with `gen/cave.py` (read only), new keys: none. Cave defaults are kept (stairs, pocket fill, repair).

Palette: cream and grey marble, pale blue cracked tiles, dark crypt flagstone patches, dark red blood patches, pale grey clapboard walls, black beyond the walls. Dim light from hanging lanterns and a floor lamp.
Layout: wards (chambers, radius 3-6) joined by corridors 2-3 wide (tunnels), cell blocks (pillars, 3 per chamber), one stair alcove. Chambers shape for seeds 801, 803, 806; mix 802, 805, 807; tunnels 804, 808.
Item ids:
- Floor: lead 457 (white stone tile), members 15791 (chess white), 406, 9146, 8959, 23717 (marble), 14931 (cracked temple). Patches: crypt flagstones 41304-41312 (sand), blood 20932-20937 (grey_sand role, 5%). Solid beside walls: black marble 407.
- Walls: clapboard set 41242 (post), 41243 (horizontal), 41244 (vertical), 41245 (corner). Ring corners reuse horizontal and vertical pieces.
- Blocking decor: beds 1754 1755 1760-1763, cell bed 38584, iron cage 38588, cell barrel 38583, bone shelf 38581, bars 1546 1547 3794 3795, drawer cabinet 20241, shackles 5481.
- Walkable decor: bloodspots 1900 1901 1903 1905 7137 7139 9731 9732, blood 38580, skeleton 38592, bones 38590 3124, straw 38591, cobweb 38587, chains 38578 38842 5472 5473, chair 38586, chain unit 38585, trashed bars 3958 3959, lights 38308 38516 38975 3744 9512.
- Stairs: ramps 1388-1395 from the cave kit.
Good: walls and floors read as a clean institution gone bad, blood and chains scatter works. Weak: ward outlines are blobs, no cell rows, no real bars lines or doors, floor is mostly one cream tone.

## Generator features missing

- No building or room layout. The closest feature is cave mode (`gen/cave.py`): chambers act as rooms, tunnels as corridors, pillars as blocks. Rooms come out as organic blobs with stair-step outlines, so wall pieces read as broken or ruined runs, not as straight rectangular rooms. A rectangular room and corridor generator with doors would fix it.
- No per-wall variety: the wall set has one piece per direction, so windows, doors and broken pieces (which exist in the item set) are not laid.
- Ground patches (sand, grey_sand roles) have no border set between flat floors, so the summary reports `bare seams` of 6 to 140 tiles per map. This is by design for flat tile floors, not a missing border.
- No structure placement (decor is scattered by the clump tables only).
