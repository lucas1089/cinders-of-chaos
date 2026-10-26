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

## State

- Setup: checked 2026-10-26 (34349 items, 89% named; the adapter's market-name read was fixed), indexed (19.5M tiles), 695 ground families (--mix), floor 7 minimap
- Kits: kit/grass.json, learned from refs/a, refs/b, refs/c (see its notes). Sets: grass on dirt 7653.., grass on rock 4542.., shore 4644.., cliff 4468.., rim 4456.., ramps 1388-1395. Clumps: study/grass_clumps*.json
- Last batch: areas/review-02 (8 seeds). review-01 had dirt 15-22% and ramps unusable 0/6 on seeds 104 and 107. review-02 (roads 0, sand 1): dirt 11-16%, all ramps usable, 0 bare seams, 0 odd ground or cliff borders (rim odd only). Reach on floor 7 reads about 50% of counted walkable tiles on every seed: not understood yet. Dirt is still wide where roads join ramp feet.

## Next

1. Owner reviews areas/review-02/index.html (notes by click).
2. Find why reached/walkable on floor 7 is about 50% (summary line access).
3. Narrow ramp-foot roads and dirt patches to the measured 3% (generator road width, gen/generate.py road code).
4. Forest on open ground looks thinner than the reference: measure with tools/compare_stats.py, raise clumps.boost.
5. Learn bridges (wooden bridge in refs/a river) and a hill set; make mountain tops rock soil instead of grass.
