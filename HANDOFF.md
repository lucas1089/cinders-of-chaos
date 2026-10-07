# Project Chaos: status

Private working repo for a dark-fantasy (Diablo / Path of Exile flavour) Open Tibia server. Everything here was written in cloud sessions with no OTClient and no TFS runtime: **nothing has been run**. Treat it as a map to verify.

## Decisions
- Protocol 10.98, server base Hellgrave Exodus v3.7.5 (TFS 1.4.2 with OTCv8 extensions); best populated map and spawns found.
- Client base: Astra (OTCv8 engine, same wire protocol as Exodus). See `client/BASE.md`; the Astra tree is not in the repo (no licence file).
- Cosmetic data (wings, auras, mounts, outfits) lives in `Tibia.spr`/`Tibia.dat`, which you provide.

## Layout
- `client/overlay/`: client modules, Chaos theme, top bar, admin panel, monster bar, images. `client/MANIFEST.md` has the status of each.
- `client/base-patches/`, `client/tools/assemble_client.sh`: turn an Astra tree into the Chaos client.
- `client/assets/`: Exodus shaders staged for later.
- `server/data/scripts/chaos/`: Lua for the opcode modules, admin panel, monster tiers. `server/README.md` lists opcodes and assumptions; `server/sql/` has the tables.
- `server/data/monster/`: custom monsters imported from other servers; `CUSTOM_MONSTERS.md` explains the tools.

## Open
- First real run: assemble the client, connect to Exodus, read the terminal log.
- Sprites for 26 imported monsters (lookType above the 1465 outfits in our dat).
- Game logic that is only a stub: Infinity Tower gameplay, passive tree bonuses, daily reward table.
- Licences: most sources are other servers' files; keep this repo private.
