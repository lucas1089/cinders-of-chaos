# Sprite forge (O781)

Owner 2026-11-28, pt-BR: "veja o que podemos aplicar ou adaptar no Cinders, para fazermos a nossa versão adaptada".
Source studied: Dotsmith, MIT, Michael Araque, https://github.com/michyaraque/dotsmith at commit 4e33791.
It is a Windows Rust app. It draws pixel art with local diffusion models on an NVIDIA GPU.
Its review sits in docs/AI_TOOLS.md. This page covers what we took and how.

Our version runs without a GPU. The AI part stays out. The steps around it are ours now.
Five Python tools in `client/tools/sprites/`. Each has a `_test.py` on synthetic pictures and `--help`.
Outputs are never committed by the tools.

## What each Dotsmith part does

| Part | What it does | Our call |
| --- | --- | --- |
| `engine/src/sprite.rs` depixel | Finds the grid phase where s x s blocks are flattest. Takes the block median. Cuts alpha at 128. | Adapted: `pixel_grid.py` |
| `gpui/src/pack_split.rs` | Undoes a nearest upscale. Clears magenta. Finds the grid by json, caption, gutters or 32 / 64 px cells. | Adapted: `pixel_grid.py`, `sheet_cut.py pack` |
| `engine/src/sprite.rs` backdrop, despeckle, fit | Keys a flat backdrop from the border. Drops small islands. Places a piece in its cell. | Adapted: `pixel_grid.py`, `sheet_cut.py` |
| `engine/src/pixeloe.rs` | Port of PixelOE: outline expansion, colour transfer, contrast downscale, k-means in OKLab. | Skipped |
| `gpui/src/item_anim.rs`, `animate_mode.rs` | Animate mode. A stack of procedural effect layers over a still sprite. Loop is a function of t mod n. Binary alpha. | Adapted: `idle_loop.py` |
| `gpui/src/jobs.rs` walls | 2 x 2 wall set: post, north, east, corner. Pieces moved bottom right. A closed room preview. | Adapted: `sheet_cut.py walls / room` |
| `gpui/src/jobs.rs` walk, `creature_mode.rs`, `anim.rs` | Walk sheets, rows S W N E. Missing directions by transpose or mirror. GIF export. | Adapted: `walk_sheet.py` |
| `gpui/src/jobs.rs` prompts | Prompt templates per mode. Trigger words of their LoRAs. | Adapted as our own words: `forge_prompts.py` |
| `gpui/src/rig.rs` | A tiny 3D capsule rig. Colour-coded pose blockouts for img2img. | Skipped |
| `gpui/src/pixels.rs` | Viewer helpers, history scan, recycle bin. | Skipped |
| Engine, models, LoRAs | Diffusion on CUDA. | Skipped here. Spike on the owner's PC, see docs/AI_TOOLS.md |

## Adapted

### pixel_grid.py

Picture to a clean pixel grid. For AI drops that come back larger than their art.
- Keys the exact key colour and a flat border backdrop. Flood fill from the border. Enclosed holes only when nearly exact.
- Finds the scale. Exact nearest upscale first. Else the period where colour edges gather. A multiple of the true size scores about half, so the largest strong period wins.
- Finds the phase where blocks are flattest. One pixel per block by median. Alpha 0 or 255.
- Drops specks under 3 px. Clamps the palette by median cut, or snaps to a theme of `style_palettes.json`.
- Why: our drops already go through `item_post.py`, but that tool assumes native 32 px art. A 4x or 6x painted render needed a step before it.
- Skipped from PixelOE: Apache-2.0 code inside an MIT port, a large pipeline, and it targets photos. Our drops are pixel art at a scale. The grid median is enough.

### idle_loop.py

Ambient idle loops for decor and items. No model.
- Effects: pulse, glint, shine, motes, flames, frost, drip, rim. Elements: fire, ice, energy, earth, death, holy.
- Layer options: colour, strength, repeats, amount.
- Our rules: body stays 255. Added pixels 255, or glow 144 with `--soft`. Changed pixels snap in Lab to the sprite colours plus the layer ramps, or to a theme. No lone pixel or speck outside the body. 4 to 24 frames, 80 to 200 ms. Loop closes by construction.
- Writes the strip and a json with every setting. The json makes the same strip again.
- `check STRIP --frames N` holds the rules on any strip.
- Skipped effects: shock, wave, beat, heat, hue, plasma, trail, cycle, smoke, snow, icicles, bubbles, orbit, twinkle, blink. They move or warp the body. Our items keep their silhouette, and eight effects cover the six elements.

### sheet_cut.py

Pack sheets and wall sets cut onto our anchors.
- `pack`: grid by `--grid`, `--cell`, a json next to the sheet, transparent gutters, then 32 / 64 px cells. Upscale undone and backdrop keyed first. Anchors: `item` centred with a 1 px margin, `bottom`, `bottom-right`. Writes `pieces.csv`.
- `walls`: a 2 x 2 sheet of 64 px cells, order post, north, east, corner. Each piece moved bottom right, the tile it stands on. Thin pieces refused.
- `room`: a closed ring of tiles from the four pieces, drawn row by row. A preview, not a map.
- Skipped: caption parsing of their training files. We have no such captions.

### walk_sheet.py

Walk sheets to the engine layout. Columns north, east, south, west. One row a phase.
- `engine`: direction rows in any order, or a frame grid per direction.
- `derive`: a direction from another by mirror or transpose. Refused when the match to a drawn target is under 0.8, or a made east or south leans under 9 px. `--force` overrides.
- `fit`: silhouette match and lean of each derivation.
- Measured on the nine committed PixelLab redraws of ours, `art_import/drive_redraw`:
  - east = transpose of south: match 0.82 to 0.93, all nine hold. The lean stays, made 8 to 23 px.
  - west = transpose of north: 0.77 to 0.93, seven of nine hold.
  - west = mirror of east: 0.20 to 0.41, none hold. A mirror turns the lean round.
- So the transpose rule holds for our view. It gives a draft for a missing direction. A drawn direction still wins.
- PixelLab folders stay with `gen_pixellab_monsters.py` and `gen_drive_monsters.py`. This tool covers other layouts.
- Skipped: GIF export and the player. Our previews are MP4 from ffmpeg.

### forge_prompts.py

Prompt recipes for item, pack, walls and walk. Text only. No service is called. No credit spent.
- Each recipe carries our view, the outline, hard edges, transparent background, theme words, and the post steps.
- The wall recipe asks for the same piece order `sheet_cut.py walls` reads.
- Their templates name another game for the view. We never copy that. `check_names.py` holds the recipes.

## How it fits our steps

1. Prompt: `forge_prompts.py KIND "our words"`. Paste into PixelLab, or a local model on the owner's PC.
2. Clean: `pixel_grid.py clean DROP.png CLEAN.png`.
3. Cut: `sheet_cut.py pack` or `sheet_cut.py walls`, then `room` to judge a wall set.
4. Items: `item_post.py`. Creatures: `walk_sheet.py engine`, `walk_sheet.py fit`, `oblique_lean.py`.
5. Idle loop for decor or items: `idle_loop.py make`.
6. Always: `style_check.py check`, `sprite_quality.py check`, then the import tools. Nothing skips them.

Rules stay as in docs/SPRITE_STYLE.md and docs/AI_TOOLS.md.
Never feed purchased, donor or third-party art to any AI model, local ones included.

## Demo

`forge_demo.mp4`, made in the scratchpad, never committed. Before and after of each tool on our own art:
the golem redraw, the crafting orbs, a code-drawn wall set.

## Licence

Ports close to Dotsmith code keep its MIT notice in the file header: `pixel_grid.py`, `idle_loop.py`, `sheet_cut.py`, `walk_sheet.py`.
Dotsmith is listed in docs/CREDITS.md under Tools.
