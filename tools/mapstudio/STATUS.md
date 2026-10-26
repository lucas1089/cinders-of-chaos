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
- 2026-10-26: no bridges and no hills in the grass kit yet; hill keys repeat the mountain's because the generator reads them. Rivers are cut by passes only.
- 2026-10-26: kit defaults levels 1, hills 0, roads 0, sand 1 (roads 3-5 wide made 15-22% dirt, reference has 3%). tools/batch.py got a kit field batch_cap so the batch variants never exceed one level.

- 2026-10-26 (round 3): reach on floor 7 reading about 50% was a counting mistake. The kit's "deep" water variant (27725 and 27728-27731) is a walkable item in items.xml, far out at sea behind the not walkable shallow band, so ~2400 sea tiles counted as walkable and unreached. gen/access.py now has NO_WALK (ids that never count as walkable); generate.py and tools/unreached.py fill it from the kit's water (all variants). Reach is now 98-99.9% on floor 7 on 7 of 8 seeds.
- 2026-10-26: dirt narrowed in the generator, not the kit numbers. Cause: 4 passes of break_runs "grow" thickened a 3-wide road to 7-9 tiles. New kit keys: road_rough 1 (bump passes), road_brush 1 (plus-shaped brush), road_broad 2 (no 5-wide roads). Without the keys the old behaviour stays.
- 2026-10-26: mountain tops: new kit key top_rock {"1": [band, inner]} = rock soil shares asked of the noise (0.8, 0.22 for level 1). Reference z6 walkable tops are 25-34% rock soil (the rest are grounds the kit does not have: G413, G4571/4572, G9067), ours now 19-32% (mean 27%).
- 2026-10-26: lowland forest: clumps.boost big 2.2, small 1.1 (was 1.0, 1.0). Reason: placement loses trees to blocking rules; measured with tools/clump_study.py G9043.

## State

- Setup: checked 2026-10-26 (34349 items, 89% named; the adapter's market-name read was fixed), indexed (19.5M tiles), 695 ground families (--mix), floor 7 minimap
- Kits: kit/grass.json, learned from refs/a, refs/b, refs/c (see its notes). Sets: grass on dirt 7653.., grass on rock 4542.., shore 4644.., cliff 4468.., rim 4456.., ramps 1388-1395. Clumps: study/grass_clumps*.json
- Last batches: areas/review-03 and areas/review-04 (review-01, 02 deleted). review-04: dirt 2-4% of non-sea floor 7 tiles (reference 2.6-4.1%; seed 108 8% by its own knobs --sand 8 --roads 6), dirt depth 1/2/3 = 0.52/0.34/0.10 (ref 0.62/0.29/0.08), rock soil on z6 tops 27% (ref 28%), big plants per tile by edge distance 0.151/0.103/0.053/0.048 (ref 0.147/0.094/0.046/0.042), small 0.16/0.29/0.43/0.49 (ref 0.25/0.36/0.44/0.45). 0 bare seams, odd tiles in hill_rim only, all ramps usable.
- Still wrong: seed 103 (2 rivers, 3 lakes) has a second landmass of 617 floor 7 tiles that no player can reach (rivers cut it, the kit has no bridges or fords) = 86% reached. Floor 6 has small pockets (tops without a ramp, or closed by trees; 2-8% unreached per seed). Small plants near edges are ~35% thin. Grass on tops is plain (the reference mixes other grounds).

## Next

1. Owner reviews areas/review-04/index.html.
2. Learn bridges (wooden bridge in refs/a river) or let a pass join split landmasses; then seed 103 reaches 98%.
3. Seal or ramp the floor 6 pockets (tools/unreached.py).
4. Add the other top grounds (G413, G4571, G4572, G9067) to the kit if the owner wants a richer top.
