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
python3 -I tools/ci/check_desktop_commands.py   # desktop admin app (O312) table names the same chaos-ctl commands as android/
cd desktop && cargo fmt --check && cargo clippy --locked --all-targets -- -D warnings && cargo test --locked
for d in crates/selfupdate launcher; do (cd $d && cargo fmt --check && cargo clippy --locked --all-targets -- -D warnings && cargo test --locked); done   # game launcher (O314) and its shared crate; launcher/tests/mass_update.rs updates a fake install many times from a local HTTP server (interrupted download, bad hash, bad signature, rollback, self-update); needs curl
python3 -I client/tools/set_launcher_config_test.py && python3 -I server/deploy/publish_client_update_test.py   # launcher.json from init.lua; the publisher's "native" section for the launcher
python3 -I tools/ci/check_credits.py   # every pack of the art *sources.csv files is in docs/CREDITS.md; pt-BR headings
python3 -I tools/ci/check_credits_test.py && python3 -I client/tools/gen_credits_test.py
cd server && luajit tools/weapon_coverage.lua --check && lua5.3 tools/weapon_coverage.lua --check  # every class has 3+ weapons per level band (thresholds: tools/weapon_coverage_config.lua); table in server/README.md (--write)
cd server && luajit tools/gear_coverage.lua --check && lua5.3 tools/gear_coverage.lua --check  # every class has 3+ pieces per slot and level band, weapon drops are fair (thresholds: tools/gear_coverage_config.lua); table in server/README.md (--write)
python3 -I tools/ci/check_attack_counts.py   # every class and ascension has the same number of attack spells
python3 -I tools/ci/check_spell_icons.py && python3 -I tools/ci/check_spell_icons_test.py   # every spell of spelldata.lua has a drawn cell in the 3 spell icon sheets (O157)
python3 -I tools/ci/check_rotation_kit.py && python3 -I tools/ci/check_rotation_kit_test.py   # every attack spell of the kit and of each class is in Auto setup's rotation data, area rule by shape (O157)
cd server && luajit tools/progression_model.lua --check && lua5.3 tools/progression_model.lua --check  # smooth leveling: stages, minutes per level 8-2200, hunts in reach (limits: data/scripts/chaos/progression_config.lua); no flag prints the table, --spells the unlock gaps
python3 -I server/tools/pack_model.py --check   # level-scaled late packs (hunting level 670+) die in at most 3x a base hunt pack of the median class (O138; pace_config.lua scaled.health)
python3 -I server/tools/tower_model.py --check && python3 -I server/tools/tower_model_test.py   # Infinity Tower: seconds per floor, boss heals, breather after milestone floors, level 800 reaches floor 30-40 (O144; limits: data/scripts/chaos/infinitytower_balance_config.lua; --derive prints the generated curves, no flag the table)
cd server && luajit tools/rift_layout_model.lua --check && lua5.3 tools/rift_layout_model.lua --check  # Rift maps: walkable tiles per monster, per live monster, full sweep seconds, size per band (O309; limits: data/scripts/chaos/rift_layout_balance_config.lua; no flag prints the table, --typical the layout.typical numbers); tests/rift_layout_model_test.lua runs in the server test loop
python3 -I tools/ci/rift_looks_test.py   # check_content.py: every rift look (rift_config.lua looks) is an outfit the client pair draws, not a blank one (O309)
python3 -I server/tools/minion_model.py --check && python3 -I server/tools/minion_model_test.py   # Necromancer minions: alive share in a hunt pack cycle, damage against the median class, minion share (O160; limits: data/scripts/chaos/necro_balance_config.lua; no flag prints the tables, --legacy the numbers before the fix)
python3 -I server/tools/companion_model.py --check && python3 -I server/tools/companion_model_test.py   # Beastmaster companion: seconds alive under 2 hunt-level monsters, bites' share of the class damage, class total against before (O306; limits: data/scripts/chaos/companion_balance_config.lua; no flag prints the table, --legacy the numbers before)
cd server && luajit tools/store_model.lua --check && lua5.3 tools/store_model.lua --check  # store prices: coin packs, boost caps, gold per coin, no coin -> gold loop (limits: data/scripts/chaos/store_balance_config.lua; no flag prints the tables; docs/PRICES.md)
cd server && luajit tools/skill_model.lua --check && lua5.3 tools/skill_model.lua --check  # skill training: tries per hour of hunting / exercise weapons / offline training, hours per skill level, a dummy hour in hunting hours (inputs and limits: data/scripts/chaos/skill_model_config.lua; no flag prints the tables, --sensitivity the assumptions; also bounds exercise weapon prices in store_model.lua; docs/PRICES.md "Skill training (O150)")
python3 -I server/tools/patch_skill_stages_test.py   # skills_stages.lua x5 from skill / magic level 101 (O154; factor: data/scripts/chaos/skill_stages_config.lua; the skill model reads it)
python3 -I server/tools/tester_checks_test.py   # tester bot system checks on a mocked game: summons / wolf (O86), pets, party, rift, chests, Auto setup list (O110)
python3 -I server/tools/progress_metrics_test.py   # progress metrics report: medians from time buckets, top 10, churn shares (O253; core test: server/tests/metrics_test.lua)
cd server && luajit tools/roulette_model.lua --check && lua5.3 tools/roulette_model.lua --check  # a roulette spin is worth its token: orbs, gold, chests against boss kills or Tower Defense runs (limits: data/scripts/chaos/roulette_value_config.lua; no flag prints the table; server/README.md "Roulette prizes against token drops")
cd server && luajit tools/gen_card_descriptions.lua --check   # -> data/items/card_descriptions.csv (card texts name current spells)
python3 -I server/tools/survey_base_weapons_test.py   # base_weapons.csv: re-run server/tools/survey_base_weapons.py on an installed server when a base weapon changes
python3 client/tools/make_fonts_test.py
python3 -I client/tools/check_text_fit.py          # options menu entries fit their buttons (en + pt-BR)
python3 -I client/tools/gen_orb_art.py --check     # liquid orb art, one ring and mask per orb size
python3 client/tools/gen_rain_art.py --check        # rain tiles of game_chaosweather (O208)
python3 -I client/tools/gen_aura_art.py --check     # chest and Templar aura strips of game_chestaura (O315; CI uses the fx venv)
python3 -I client/tools/gen_toast_art.py --check    # toast icons of game_chaosnotify (O317; CI uses the fx venv)
python3 -I server/tools/patch_base_rain_test.py     # base rain off in config.lua (install_all step baserain)
python3 -I server/tools/patch_base_fusion_allowlist_test.py   # item fusion (67) only for the ids of item_fusion_config.lua, fail closed (O310; install_all step fusionlist)
python3 -I client/tools/check_shaders.py  # GLSL compile (glslangValidator) or smoke test
python3 -I website/tools/gen_sprite_images_test.py   # website sprite images: colour maths, synthetic pair
for t in website/tests/*_test.php; do php "$t"; done  # website PHP tests

# generated files must be committed up to date (CI diffs them)
python3 client/tools/gen_spell_data.py                       # -> game_chaosspells/spelldata.lua
python3 -I client/tools/gen_credits.py                       # docs/CREDITS.md -> client_chaos_credits/credits_data.lua, website credits_data.json (--check)
cd server && python3 -I tools/gen_unique_specs.py            # -> data/lib/chaos_unique_specs.lua
cd server && luajit tools/gen_codex_data.lua                 # -> client game_codex/codex_data.lua
cd server && lua5.3 tools/gen_codex_data.lua --check
cd server && luajit tools/gen_wiki_data.lua                  # -> website wiki/wiki_data.json
cd server && lua5.3 tools/gen_wiki_data.lua --check
python3 -I server/tools/weapon_sim.py --power --check             # -> data/scripts/chaos/weapon_power_config.lua (--power --write)
python3 -I website/tools/gen_wiki_art.py                     # -> website wiki icons, heroes (--check in CI)
python3 -I website/tools/gen_calendar_data.py                  # -> website calendar/calendar_data.json from season_config.lua and others (--check in CI; O320)
python3 -I website/tools/gen_calendar_data_test.py
python3 -I website/tools/gen_media_kit.py                       # -> creators/media_kit_manifest.json (--check in CI; the zip is built by install_site.sh, not committed)
python3 -I client/tools/sprites/gen_owner_art.py build --check  # owner art of pair 26 (CI uses the fx venv)
python3 -I server/tools/install_owner_decor.py --lua --check     # -> data/lib/chaos_owner_decor.lua
python3 -I client/tools/sprites/style_check.py build-palettes --check  # -> style_palettes.json; check new sprites: docs/SPRITE_STYLE.md
python3 -I client/tools/sprites/gen_fx_send_offsets.py --check       # -> data/lib/chaos_fx_send_offsets.lua (pair 36 in-place fx centring)
python3 -I client/tools/sprites/gen_portal_art.py build --check && python3 -I client/tools/sprites/gen_portal_art_test.py  # pickup looks of pair 55: Ember portal, health and mana globe (CI uses the fx venv)
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
- `docs/CREDITS.md`: every third-party source. The game and the website show it.
- `server/data/spells/README.md`: measured balance numbers.

`HANDOFF.md` is an early snapshot and is outdated.

## Rules

- No names of other servers, games or clients in the repo. `check_names.py` enforces it.
  - Art pack names may appear only in `docs/CREDITS.md` and the two files generated from it.
- Every third-party asset, font, library or tool that ships goes into `docs/CREDITS.md`. Then run `gen_credits.py`.
- No real account data or player logs in the repo.
- When telling the owner to run a VPS step, say first if the admin app (`android/`) can do it, and where (tab > card > button).
  Give the shell command only as a fallback. Any `chaos-ctl.sh` command the owner runs often should get a button there.
