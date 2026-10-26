# Status

The project's living state. The agent keeps it current at the end of every session, so a fresh agent can
continue from this file alone. Replace the placeholders as you go.

## Project facts

- Server and client: TFS 1.4.2 fork, own client, protocol 10.98; dat 10.98 extended (u32 sprites, frame groups, durations) plus our flag 39 (bones)
- Data paths: in `config.json` (git-ignored). The data comes from the release asset `CindersOfChaos-MapFiles.zip` (world map, items.otb / items.xml, the sprite pair); never commit it
- Map ids: server
- Reference map: _(which, and which places are its best work)_
- Map editor brushes: _(yes/no, where)_
- How items are chosen: _(agent studies / person lists ids / mix)_
- Goal: _(what to generate first, size, floors)_
- Biomes, in order: _(...)_
- Gameplay rules: _(walkability, pull sizes, path widths, ...)_

## Decisions

Each with the date and the reason. Example: _2026-01-05: roads are dirt, never stone (the person: "dirt
reads better in forests")._

## State

- Setup: checked 2026-10-26 (34349 items, 89% named; the adapter's market-name read was fixed), indexed (19.5M tiles), 695 ground families (--mix), floor 7 minimap
- Kits: _(kit/<biome>.json: learned from which windows, status)_
- Last batch: _(areas/<batch>: what changed, numbers from the summaries)_

## Next

1. _(the next step)_
