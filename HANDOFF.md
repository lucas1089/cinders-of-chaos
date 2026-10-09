# Cinders of Chaos: status

Private working repo for a dark-fantasy (Diablo / Path of Exile flavour) Open Tibia server. Everything here was written in cloud sessions with no OTClient and no TFS runtime: **nothing has been run**. Treat it as a map to verify.

## Decisions
- Protocol 10.98, server base: the existing server (TFS 1.4.2 with OTClient extensions); best populated map and spawns found.
- Client base: the base client (OTClient engine, same wire protocol as the server). See `client/BASE.md`; the base client tree is not in the repo only because of its size.
- Cosmetic data (wings, auras, mounts, outfits) lives in `Tibia.spr`/`Tibia.dat`, which you provide.

## Layout
- `client/overlay/`: client modules, Chaos theme, top bar, admin panel, monster bar, images. `client/MANIFEST.md` has the status of each.
- `client/base-patches/`, `client/tools/assemble_client.sh`: turn a base client tree into the Cinders of Chaos client.
- `client/assets/`: shaders staged for later.
- `server/data/scripts/chaos/`: Lua for the opcode modules, admin panel, monster tiers. `server/README.md` lists opcodes and assumptions; `server/sql/` has the tables.
- `server/data/monster/`: custom monsters imported from other sources; `CUSTOM_MONSTERS.md` explains the tools.

## Open
- First real run: assemble the client, connect to the server, read the terminal log.
- Build the merged dat/spr (see `server/data/monster/CUSTOM_MONSTERS.md`); 5 imported monsters still have no sprite.
- Game logic that is only a stub: Infinity Tower gameplay, passive tree bonuses, daily reward table.
