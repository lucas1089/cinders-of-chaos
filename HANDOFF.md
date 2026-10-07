# Project Chaos: handoff note

Written from a cloud Claude Code session that could only see the owner's Google Drive through a connector and could not touch their computer. It is meant for a session running locally (Claude Desktop or CLI) that can work on the real files. Everything below was inferred from file and folder names. No source code was read except one small `.otui` file, so treat it as a map to verify, not as fact.

## Goal

Build "the greatest OT server ever" in this repo (`project-chaos`, currently only a README). Open questions the owner has not answered yet are in the last section.

## Where the material lives

A Google Drive folder named `ots` (the owner has the link; it is not recorded here on purpose, because the folder holds other projects' files). It had about 53 archives plus 28 extracted folders, all uploaded 5–7 Oct 2026. Some archives were still not unpacked at the time of writing. Most extracted folders contain one wrapper folder with the real content one level down.

### Server candidates

| Item | What was seen |
|---|---|
| `crystalserver` (extracted) | Full C++ source: `CMakeLists.txt`, `CMakePresets.json`, `vcpkg.json`, `src/`, `data/`, `data-crystal/`, `data-global/`, `schema.sql`, `config.lua.dist`, `docker/`, `tests/`, `.github/`, `docs/`, installers. Also zips for a 15.24 game client and a 15.24 map editor build. |
| `Hellgrave_Exodus_Server_v3.7.5` (extracted) | TFS-style tree: `cmake/`, `vc17/`, `data/`, `CUSTOM_SCRIPTS/`, `SQL_Server/` |
| `Evolisca_server` (extracted) | OTX-style: `data/`, `mods/`, `logs/`, `sources_test/`; plus `Evolisca_proxy_system` and `Evolisca_client` |
| `mordragor` | Five `.rar` files still packed: Hellgrave v6 server (Linux), client, editor, object builder, ZnoteAAC site |
| `blacktalon_d`, `archlight`, `Demolidores_22-06-26` | One wrapper folder each, not inspected |
| `Server + Client + All Sources.zip` (2 GB) | Not unpacked |
| `pka22072026`, `PSTORY19072026`, `pokestone`, `pkmd`, `Tyron`, `paulistinha`, `rots`, `rots_2026`, `world of fragment`, `30_09_26`, `WoNOv7`, `WAT` | Not unpacked |

### Clients

OTClient-style (`init.lua`, `modules/`, `config.ini`, `.otui`, `.otmod`): `OTC-Fonticak` (has `src/`, `modules/`, `tests/`, so it looks buildable), `AstraClient-main`, `Exodus_Client_Github`, `Evolisca_client`, `Luminaris`, `balrogot`, `magicheard`. Not unpacked: `oxygenOT`, `oxygenOT_client`, `ZerionOT`, `RubinOT - RTC_Data_Modules`, `RA`, `update_8`.

### Assets and tools

- Shared client resources: `assets`, `conteudo` (fonts, maps, sprites, shaders, audio), `bars`.
- Sprite and object files: `Tibia.spr` / `Tibia.dat` / `Tibia.otfi` in several client folders, a `Tibia_66.spr` to `Tibia_99.spr` series, and a 7.72 set under `Medivia_772_Albane`. Large sprite packs are still packed (`SPRS + 2026.zip` is 5.7 GB).
- Object Builder in three copies (Adobe AIR build, `ObjectBuilder_0_5_6`, one inside `magicheard`), plus `game_helper_windows` (purpose unknown).

### Maps

Only small `.otbm` files were found: crystalserver samples (`ebb-flow`, `ebb-flow-empty`, near-empty `edron` and `ankrahmun`), `login_fox.otbm` (client login backdrop), `tutorial.otbm`. The `.otmm` files are client minimap caches, not editable maps. No full server world was found; it is probably inside archives that were not unpacked.

## Recommended direction (not yet confirmed by the owner)

1. **Server base: crystalserver.** It is the only candidate seen with a clean CMake and vcpkg build, Docker setup, CI and tests. Prefer its public upstream repo as the base, and use the owner's copy in Drive as a diff reference for any local changes.
2. **Client:** choose between the official 15.24 client (proprietary, cannot be redistributed) and an open-source OTClient fork such as `OTC-Fonticak`. **Unknown:** which protocol each fork speaks. Check before committing to a pairing.
3. **Content:** ship original or properly licensed sprites, maps and data only.

## Cautions

- Do not commit private keys. `crystalserver/key.pem` looks like one; regenerate it if it is real.
- Do not commit binaries (`.exe`, `.dll`). Rebuild from source.
- Many folders look like other live servers' files (RubinOT, Ravendawn, Medivia, Albane sprite packs, Hellgrave, and others), and the `Tibia_*.spr` series looks like official Cipsoft assets. Use them for reference and for testing tools. Do not ship them in Chaos, and do not copy their proprietary code or art into this repo.
- Keep multi-GB archives and sprite files out of git.

## Suggested first steps for the local session

1. Unpack the remaining archives, starting with `Server + Client + All Sources.zip`, then the `mordragor` and Hellgrave inner `.rar` files, then `oxygenOT`, `ZerionOT` and the `pka`, `PSTORY` and `pkmd` packs.
2. Re-run a map search (`.otbm`, `.otb`, spawn and house XML) once they are unpacked, and find a real world map.
3. Get crystalserver building from source, then add a docker-compose file (server plus MariaDB) and CI.
4. Read crystalserver's `config.lua.dist` and `src/`, then plan what makes Chaos different.
5. Write a small `.spr` / `.dat` parser to extract sprites to PNG (format: signature, sprite count, offset table, RLE-compressed 32×32 sprites), using `Tibia.dat` from the 7.72 folder as a test.

## Open questions for the owner

- Which protocol and client should players use: the official 15.24 client or an OTClient fork?
- What is the theme: classic Tibia-style, or a themed game (Pokémon, One Piece, anime)?
- Is the Hellgrave and Evolisca code the owner's own, or taken from other servers?
- What does `game_helper_windows` do?
