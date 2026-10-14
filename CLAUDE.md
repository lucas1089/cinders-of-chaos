# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Compressed Profile
# Best for: high-volume output workloads where token cost dominates

## Core Rules
Short sentences only (8-10 words max). No filler, no preamble, no pleasantries. Tool first. Result first. No explain unless asked. Code stays normal. English gets compressed.

## Formatting
Output sounds human. Never AI-generated. Never use em-dashes or replacement hyphens. Avoid parenthetical clauses entirely. Hyphens map to standard grammar only.

## Trade-offs
Aggressive compression. Loses fabrication guards from the minimal profile. Pair with code-review or analysis profile if hallucination matters for your workload.

# Project

Cinders of Chaos: dark fantasy Open Tibia server, protocol 10.98, own client.
Server base: TFS 1.4.2 fork. Client base: OTClient-family engine.
Neither base tree is committed. The repo holds overlays, patches and install tools.

## Commands

All checks CI runs (`.github/workflows/ci.yml`):

```
# server unit tests: run FROM server/, each under both interpreters
cd server && for t in tests/*_test.lua; do luajit "$t" && lua5.3 "$t"; done
cd server && luajit tests/arena_test.lua          # one test

# client unit tests: run from the repo root
for t in client/overlay/modules/*/*_test.lua; do luajit "$t" && lua5.3 "$t"; done

python3 -I tools/ci/check_modules.py   # client .otmod names and scripts
python3 -I tools/ci/check_content.py   # server XML, spells, items, monsters
python3 -I tools/ci/check_names.py     # no other server/game/client names anywhere
python3 -I tools/ci/check_locales.py   # every client tr() key has pt-BR; no hard-coded UI text (--missing, --fix)
python3 client/tools/make_fonts_test.py
python3 -I client/tools/check_shaders.py  # GLSL compile (glslangValidator) or smoke test
python3 -I website/tools/gen_sprite_images_test.py   # website sprite images: colour maths, synthetic pair
for t in website/tests/*_test.php; do php "$t"; done  # website PHP tests

# generated files must be committed up to date (CI diffs them)
python3 client/tools/gen_spell_data.py                       # -> game_chaosspells/spelldata.lua
cd server && python3 -I tools/gen_unique_specs.py            # -> data/lib/chaos_unique_specs.lua
cd server && luajit tools/gen_codex_data.lua                 # -> client game_codex/codex_data.lua
cd server && lua5.3 tools/gen_codex_data.lua --check
cd server && luajit tools/gen_wiki_data.lua                  # -> website wiki/wiki_data.json
cd server && lua5.3 tools/gen_wiki_data.lua --check
python3 -I website/tools/gen_wiki_art.py                     # -> website wiki icons, heroes (--check in CI)
```

Every `.lua` must parse in Lua 5.3 and LuaJIT. Run Python tools with `-I`.

Install into a base server folder: `python3 -I server/tools/install_all.py SERVER_DIR [--dry-run] [--only STEP,...]`.
Every step is idempotent. Its docstring lists the steps in order.
Client: `client/tools/assemble_client.sh <base-client-dir> <out>` applies `base-patches/` and copies `overlay/`.
`windows-package.yml` is manual only. Its large inputs live on the private branch `windows-assets`.

## Architecture

- **Server Lua** lives in `server/data/scripts/chaos/` as revscripts.
  - Each system is split into `*_core.lua` (pure logic, unit tested), `*_config.lua` (numbers) and a thin engine file.
  - Tests `dofile` the core against a mocked engine API.
  - `chaos_constants.lua` holds every opcode, storage key, table name and shared helper.
  - New opcodes must not collide (server/README.md "Opcode collision check").
  - Storage keys use reserved blocks in 7100000-7127999. Table in server/README.md "Storage keys". DB tables are `chaos_*` in `server/sql/`.
- **Client/server protocol:** JSON over extended opcodes, one opcode per module.
  - Payloads over 8192 bytes must go through `Chaos.sendChunked`.
- **Base data is never hand-edited.** Changes to the installed base server go through idempotent `server/tools/patch_*.py` and `install_*.py`, wired into `install_all.py`.
- **Engine C++ changes** are numbered patches.
  - Server: `server/src-patches/NNNN-*.patch`.
  - Client: `client/base-patches/NNNN-*.patch`.
  - Patches apply in order and later ones depend on earlier context. Add a new number; keep earlier patches applying.
- **Client modules** live in `client/overlay/modules/<name>/` (`.otmod`, `.otui`, `.lua`). Art comes from generator scripts in `client/tools/`.
- **Sprites:** the merged `Tibia.dat`/`Tibia.spr` pair is not in git. Import tools are in `client/tools/sprites/`. The pair md5s are recorded in `client/MANIFEST.md`.
- **Classes:** vocation ids, ascensions and kits are in `docs/CLASSES.md`. Vocations are written by `server/tools/add_vocations.py`.

## Docs to keep in sync

- `ROADMAP.md`: status of each item.
- `server/README.md`: one section per server system, install steps, assumptions.
- `client/MANIFEST.md`: client modules. `client/BASE.md`: client base patches.
- `docs/CLASSES.md`: classes.
- `server/data/spells/README.md`: measured balance numbers.

`HANDOFF.md` is an early snapshot and is outdated.

## Rules

- No names of other servers, games or clients in the repo. `check_names.py` enforces it.
- No real account data or player logs in the repo.
