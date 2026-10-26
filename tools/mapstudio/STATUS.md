# Status

The project's living state. The agent keeps it current at the end of every session, so a fresh agent can
continue from this file alone. Replace the placeholders as you go.

## Project facts

- Server and client: TFS 1.4.2 fork, own client, protocol 10.98; dat 10.98 extended (u32 sprites, frame groups, durations) plus our flag 39 (bones)
- Data paths: in `config.json` (git-ignored). The data comes from the release asset `CindersOfChaos-MapFiles.zip` (world map, items.otb / items.xml, the sprite pair); never commit it
- Map ids: server
- Reference map: our own world map (floor 7 continent, x 30500-34074, y 30400-33592; top-left blocks are instanced, ignored). Best grass/forest work: refs/a x 32450-32649 y 31880-32099 (grass, forest belts, rivers, mountain edge), refs/b x 32100-32299 y 32050-32249 (coast, forest, rock patches), refs/c x 32380-32579 y 32020-32179 (terraced mountain standing in grass). Chosen with the minimap and renders: dense, varied, hand-made look with borders, rivers and a mountain
- Map editor brushes: no
- How items are chosen: agent studies the reference map (option 1)
- Goal: a hunting island about 96x96 tiles with one raised mountain floor (floor 6)
- Biomes, in order: grass and forest first
- Gameplay rules: not stated yet (defaults of docs/CONCEPTS.md: every ramp usable, 98%+ reached)

## Decisions

Each with the date and the reason. Example: _2026-01-05: roads are dirt, never stone (the person: "dirt
reads better in forests")._

- 2026-10-26: grass and forest first, one mountain floor, 96x96 (owner). Reason: owner's Step 0 answers.
- 2026-10-26: map ids are server ids and items are learned from the reference map (owner).
- 2026-10-26: grass is one family: ids 9043-9058 merged in study/family_overrides.json (they are laid mixed; before, edge-distance studies saw every grass tile as an edge).
- 2026-10-26: kit/grass.json has no gravel and no worn sand, and rock soil draws nothing onto dirt (the reference never touches them; the generator keeps them apart). Reason: no such pair seen in refs.
- 2026-10-26: no hills in the grass kit yet; hill keys repeat the mountain's because the generator reads them. (Bridges: see round 4 below.)
- 2026-10-26: kit defaults levels 1, hills 0, roads 0, sand 1 (roads 3-5 wide made 15-22% dirt, reference has 3%). tools/batch.py got a kit field batch_cap so the batch variants never exceed one level.

- 2026-10-26 (round 3): reach on floor 7 reading about 50% was a counting mistake. The kit's "deep" water variant (27725 and 27728-27731) is a walkable item in items.xml, far out at sea behind the not walkable shallow band, so ~2400 sea tiles counted as walkable and unreached. gen/access.py now has NO_WALK (ids that never count as walkable); generate.py and tools/unreached.py fill it from the kit's water (all variants). Reach is now 98-99.9% on floor 7 on 7 of 8 seeds.
- 2026-10-26: dirt narrowed in the generator, not the kit numbers. Cause: 4 passes of break_runs "grow" thickened a 3-wide road to 7-9 tiles. New kit keys: road_rough 1 (bump passes), road_brush 1 (plus-shaped brush), road_broad 2 (no 5-wide roads). Without the keys the old behaviour stays.
- 2026-10-26: mountain tops: new kit key top_rock {"1": [band, inner]} = rock soil shares asked of the noise (0.8, 0.22 for level 1). Reference z6 walkable tops are 25-34% rock soil (the rest are grounds the kit does not have: G413, G4571/4572, G9067), ours now 19-32% (mean 27%).
- 2026-10-26: lowland forest: clumps.boost big 2.2, small 1.1 (was 1.0, 1.0). Reason: placement loses trees to blocking rules; measured with tools/clump_study.py G9043.

- 2026-10-26 (round 4, bridges and necks): kit bridge_ew / bridge_ns added to kit/grass.json, ids read off the two bridges of the reference map's floor 7 (east-west: lip 11865, deck 11860, end 11861, rails north 11878-11882, south 11883-11887, at x 32060-32065 y 32191-32194; north-south: lip 11866, deck 11858, end 11859, rails west 11888-11892, east 11893-11897, at x 33187-33189 y 31122-31126). The generator already had the bridge code; the kit lacked the keys. Seed 103: 86% -> 99.6% reached on floor 7.
- 2026-10-26: new kit key join_land {"least": 12, "gap": 14} (gen/generate.py join_landmass). A landmass no bridge joins (a river bank or sea islet) gets a 5-wide land neck by the cheapest way over water, nearest first; off without the key. Seed 108 gets one (a 84-tile islet). Reason: bridges only fit straight river stretches.
- 2026-10-26: floor 6 pockets. Kit keys ramp_least 6 (tops of 6+ clear tiles get a ramp, was 30), notch_level0 (ramp seated in a notch of the mountain's foot when no clean landing exists), road_least 30 (those small-top ramps get no road, else dirt grows), repair_pocket 1 (access.repair clears plants for any pocket, was 4+), drop_cut_off_tops (last resort: a top group nobody can reach is removed, rock below stays; seeds 103 and 106 lose 53 and 9 walkable top tiles = rock stubs jutting into the sea with no ground to start a ramp from). Floor 6 unreached 2-8% (103: 27%) -> 0.0% on all seeds.
- 2026-10-26: thin small plants near edges. Kit keys clumps.edge_boost small [4.5, 1.55, 0.9, 0.93] (needs a 6-line change in gen/lib.py place_clumped: boost was per class only), bank_flora small rates 6219 0.12 -> 0.03 and 6218 0.09 -> 0.02 (tools show grass beside water carries small plants on 17% of tiles, reference 5%; grass beside rock soil and dirt carries 29%, reference 40-44%), apron_flora G4405 (rock soil on floor 7 had 0.04 small plants per tile, reference 0.22; tiles that touch a cliff stay bare, growable() forbids them). Small plants per tile window by edge distance 0.162/0.289/0.434/0.487 -> 0.210/0.348/0.441/0.458 (reference 0.248/0.358/0.438/0.449).
- 2026-10-26: tools/unreached.py now also lists landmasses (4-connected, corner contact is no way over) of 30+ tiles with no reached tile, and the unreached share per floor. Use it as the check for round 4.

## State

- Setup: checked 2026-10-26 (34349 items, 89% named; the adapter's market-name read was fixed), indexed (19.5M tiles), 695 ground families (--mix), floor 7 minimap
- Kits: kit/grass.json, learned from refs/a, refs/b, refs/c (see its notes). Sets: grass on dirt 7653.., grass on rock 4542.., shore 4644.., cliff 4468.., rim 4456.., ramps 1388-1395. Clumps: study/grass_clumps*.json
- Last batches: areas/review-03, review-04, review-05 (round 4: bridges, necks, floor 6 access, edge plants; seeds 101-108, same knobs as review-04, run with `tools/batch.py review-05 --kit grass`; without --kit the batch uses config.json's kit TEMPLATE and fails). Older note: review-04 (review-01, 02 deleted). review-04: dirt 2-4% of non-sea floor 7 tiles (reference 2.6-4.1%; seed 108 8% by its own knobs --sand 8 --roads 6), dirt depth 1/2/3 = 0.52/0.34/0.10 (ref 0.62/0.29/0.08), rock soil on z6 tops 27% (ref 28%), big plants per tile by edge distance 0.151/0.103/0.053/0.048 (ref 0.147/0.094/0.046/0.042), small 0.16/0.29/0.43/0.49 (ref 0.25/0.36/0.44/0.45). 0 bare seams, odd tiles in hill_rim only, all ramps usable.
- Still wrong (after round 4): small plants beside edges are still 15% thin at distance 1 (0.210 vs 0.248; tiles touching water or cliff take no clump plants, and our floor 7 has less grass beside rock soil than the reference: 19% against 31% of edge tiles). Dirt share by my count (G103 over non-water floor 7 tiles) is 2.5-11%, mean 6.3% against 6.1% in review-04; seeds 103, 107, 108 are high (bridge roads, ramp feet, roads 6). Bridges are the reference's red-railed type only. Tops that can not get a ramp are dropped, not ramped (53 and 9 tiles, seeds 103 and 106). Floor 7 holds a few unreached pockets of 3-30 tiles between cliff and water (0-0.7%). Grass on tops is plain (the reference mixes other grounds).

## Next

1. Owner reviews areas/review-05/index.html (bridges in seeds 103, 104, 108; the neck in 108).
2. Check the red bridge look with the owner; the reference has other bridge families (ids 27905-27974, 23632-23648) if they want wood.
3. Add the other top grounds (G413, G4571, G4572, G9067) to the kit if the owner wants a richer top.
4. Small plants at edge distance 1: allow clump plants on tiles that touch water or cliff (growable in gen/generate.py), or add rock-soil patches on floor 7.
