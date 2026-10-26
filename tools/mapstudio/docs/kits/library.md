# library kit

Forbidden library. Seeds 851-858, review set areas/library-review-01. Cave mode, floor 9.
Kit: `kit/library.json`. Built from `kit/cave.json` with `gen/cave.py` (read only), new keys: none. Cave defaults are kept (stairs, pocket fill, repair).

Palette: warm parquet floor, red carpet patches, grey flagstone patches, mossy stone walls, candle light, rune circles.
Layout: reading halls (chambers) and stacks (tunnels 2-3 wide), mix shape, pillars as shelf blocks.
Item ids:
- Floor: lead 19796, members 19797 19798. Patches: carpet 12115-12120 (sand role), stone floor 3152-3157 (grey_sand role). Solid: 407.
- Walls: crypt stone set 41256 (post), 41257 (horizontal), 41258 (vertical), 41259 (corner).
- Blocking decor: bookcases 1718 1719 6368-6371 20150-20153 20800 20802 29721 29722, book units 38841 38928, tables 38263 38515, drawer 20241, lectern 41551, black candles 41554, globe 23872, urn 41570, statues 38761 38767, bone tables 12149 12150.
- Walkable decor: candles 9511 9512 41383 41385 21350 38308, scrolls 12948 12949 12954 12955, books 23790-23795 12396-12398 40797-40799 38501, strange runes 24934 24937 24938, rune stones 8919 13884, ritual circles 41530 41531 (4x4), chairs 11934 1662, table 1614, papers 38536 38537.
Good: parquet and moss stone read as a library, books and scrolls scatter well. Weak: shelves are scattered, not lined along walls, no reading tables in rows, no hanging chandeliers.

## Generator features missing

- No building or room layout. The closest feature is cave mode (`gen/cave.py`): chambers act as rooms, tunnels as corridors, pillars as blocks. Rooms come out as organic blobs with stair-step outlines, so wall pieces read as broken or ruined runs, not as straight rectangular rooms. A rectangular room and corridor generator with doors would fix it.
- No per-wall variety: the wall set has one piece per direction, so windows, doors and broken pieces (which exist in the item set) are not laid.
- Ground patches (sand, grey_sand roles) have no border set between flat floors, so the summary reports `bare seams` of 6 to 140 tiles per map. This is by design for flat tile floors, not a missing border.
- No structure placement (decor is scattered by the clump tables only).
