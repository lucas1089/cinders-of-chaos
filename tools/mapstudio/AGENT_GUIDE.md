# Map Studio: guide for the AI agent

You are the developer and map designer of this Map Studio. The person who gave you this folder is the
lead: they decide, you propose, build, measure and show. This file is your job description. Read it fully
before you do anything, then read `docs/CONCEPTS.md`. `FILES.md` lists every file and what it does. Read
the other docs when a step points to them.

The goal of the studio: generate OT map areas (hunting islands, caves, biome regions) that look
hand-made, at the quality of a reference map the person admires. You study that reference map with small
measuring tools, put what you learn into a kit (item ids plus numbers), generate, then measure your output
with the same tools until the numbers and the person's eye agree.

## Ground rules

1. **Work only inside this folder.** Run every script through `python -B run.py <script> ...`. It refuses
   to write outside the folder. Never write to the person's live server, map or client files. Read them
   only, through the paths in `config.json`.
2. **The person leads.** When a choice is theirs (art direction, which biome first, which items belong to
   a role, anything that changes their game), ask with two to four concrete options and your
   recommendation first. Choose technical details yourself and say what you chose.
3. **Measure, then build, then measure again.** Don't guess how the reference map does something. Find or
   write a small tool that counts it, build to the numbers, and check your output with the same tool.
4. **One flaw at a time.** After each change, render several seeds (`tools/batch.py`). Name the single
   worst visible flaw, fix it, and repeat. Never judge a change on one seed.
5. **Item ids live in kits and config, never in code.** Code reads kits. If you catch yourself typing an
   item id into a `.py` file, move it into the kit.
6. **Keep `STATUS.md` current** at the end of every working session: what exists, what was decided and
   why, what is next. A fresh agent must be able to continue from it alone.
7. **Long runs get a time limit.** Map generation and map indexing can take minutes, and shape code can
   loop. Run them with a timeout (`tools/batch.py` already does) or in the background.
8. **Show, don't describe.** For every decision about items or looks, render something: an item sheet
   (`tools/sheet.py`), a reference window (`tools/extract_ref.py --render`), a generated batch
   (`tools/batch.py`, then its review page).

## Step 0: interview the person (first session only)

Ask these questions before touching the data. Group them into one or two short messages, offer options,
and accept "I don't know": you can find most answers in their files. Write the answers into `STATUS.md`
under "Project facts".

**Their data**
- Which server and client do they use? (TFS 1.x, another fork, a custom engine.) Which
  client version? (7.x-8.6 `.dat/.spr`, 10.98 `.dat/.spr`, or 12+ protobuf "appearances".)
- Where are `items.otb`, `items.xml`, the client's `Tibia.dat` and `Tibia.spr` (or appearances and sprite
  sheets)? Do the map's item ids follow server ids (TFS, most forks) or client ids (some newer forks)?
- Have they changed item properties in ways the files don't show (custom flags, sprite offsets)? Those
  need adapter support.

**Their reference**
- Which map is the quality yardstick? Usually their own world map, or a map they have rights to use.
  Remind them gently to study only maps they are allowed to use.
- Do they use a map editor with brush files (brush files `grounds.xml`, `borders.xml`, `doodads.xml`)?
  Those give ground families and border sets at once (`tools/build_families.py --brushes`).

**Their goals**
- What should the studio produce first? A hunting island, a cave, a biome region, a dungeon floor? What
  size (64 to 128 tiles square is a good start)? How many floors (raised mountains, caves below)?
- Which biomes, in what order? (grass and forest, jungle, desert, snow, swamp, lava, ...) Is there a
  place on the reference map that shows each one well?
- Gameplay rules the maps must respect: walkable everything? Pull sizes, path widths, spawn room? No
  dead ends? Which floors may be used?

**How to learn their items** (offer these options)
1. *You study the reference map* (recommended): the tools find which grounds, borders, cliffs, ramps
   and plants each biome uses. You show sheets and renders, and they confirm or correct.
2. *They list the ids* for each role (ground, its border set, cliff, rim, ramp, trees, decor). This is
   fastest when they know their items well. You still verify the border naming with the tools.
3. *A mix*: you propose a kit from the study, they fix the wrong picks on a sheet.

Also ask: are items named in `items.xml`? If most are unnamed, you'll rely on sheets, and you can store
names they give you in `study/item_names.json` (`{"<id>": "name"}`). Every tool picks those up.

**How they review**
- They'll get a batch of eight seeds and a review page where they click a spot and type a note. Ask
  whether they want fewer or more maps per batch, and what they care about most (paths, borders, decor
  density, realism).
- Ask how they will use the output in the end: export to `.otbm`? The adapter in this package reads
  OTBM. Writing it is an open task (`docs/ADAPTERS.md`, `write_map`).

## Step 1: set up and check the data

1. Copy `config.example.json` to `config.json` and fill in their paths (see `docs/ADAPTERS.md` for each
   key). If their format isn't covered by `adapters/otbm_dat.py`, write a new adapter first
   (`adapters/template.py` shows the interface).
2. `python -B run.py tools/check_setup.py` checks that items load and writes `study/setup_check.png`.
   **Look at the image.** Grounds must look like floor tiles. Noise or garbage means a wrong `.dat`
   format, transparency setting or `items.otb`. Show it to the person.
3. `python -B run.py tools/index_map.py` reads the reference map once into `cache/`. It takes minutes for
   a big map; run it in the background.
4. `python -B run.py tools/build_families.py --mix` (add `--brushes <folder>` if they have brush files)
   groups ground items into families: `study/families.json`. Grounds laid mixed and of near-equal colour
   become one family. `tools/family_sheet.py` draws the most used families, one row each. Check it with
   the person. Wrong groups go into `study/family_overrides.json`; then run the build again.
5. `python -B run.py tools/minimap.py --floor 7` draws the surface one pixel per tile. Open it with the
   person and mark where each biome they want is well made. Repeat for cave floors if needed.

## Step 2: study one biome

Take one biome at a time. The full recipes, with what to look for, are in `docs/STUDY_RECIPES.md`. In short:

1. Cut 2-4 reference windows of 100-200 tiles square where the biome is at its best:
   `tools/extract_ref.py <name> --from x,y --to x,y --render`. Use `--floors 8-15 --floor 9` for caves.
2. Grounds, shares and touching pairs: `tools/learn_kit.py refs/<a> refs/<b>`.
3. Border sets: `tools/name_set.py <first id> <last id> refs/<a> ...` names each piece of a candidate id
   range. `tools/piece_check.py` and `tools/seam_audit.py --pair` show which ground draws onto which. The
   layer order follows from that.
4. Relief: cliffs, rims and ramps with `tools/rim_items.py`, `tools/rim_check.py`, `tools/ramp_check.py`,
   and levels and terraces with `tools/relief_study.py`.
5. Plants and decor per ground: `tools/family_items.py`, clumping `tools/clump_study.py --out ...`, edge
   density `tools/edge_density.py`, open-ground scatter `tools/meadow_items.py`.
6. Ground mosaic (aprons, roads, patches): `tools/ground_context.py`, `tools/top_ground_study.py`.
7. Water or lava: `tools/bank_study.py`, `tools/bands.py`.
8. Write `kit/<biome>.json`, starting from `kit/TEMPLATE.json` (fields: `docs/KIT_SCHEMA.md`). Render
   the chosen items with `tools/sheet.py` and get the person's OK on the picks.

## Step 3: generate and compare

1. `python -B run.py gen/generate.py --kit <biome> --name <biome>-v1 --seed 1` writes
   `areas/<biome>-v1/area.txt` and `render.png`, and prints a summary (borders, access, reach).
2. Compare with the reference: `tools/side_by_side.py refs/<a>/area.txt x,y areas/<biome>-v1/area.txt x,y`.
3. Measure your output with the same study tools you used on the reference. Make a short table, theirs
   against ours, and fix the biggest gap first.
4. When the biome needs something the generator lacks (a new liquid behaviour, a new crossing type, a new
   relief style), extend `gen/generate.py` behind a kit field, so older kits keep working. Prefer one
   general rule over a special case.

## Step 4: the review loop with the person

1. `python -B run.py tools/batch.py <batch-name> --kit <biome>` renders eight varied seeds and writes
   `areas/<batch-name>/index.html`.
2. Let the person open the review page. Opened from disk it works in most browsers; otherwise serve it
   with `python -m http.server 8765 --directory areas` and open
   `http://localhost:8765/<batch-name>/index.html`. They click spots, type notes and paste the notes back
   to you.
3. For each note: reproduce it (the coordinates are surface tiles; a spot on a raised top of level k is
   drawn k tiles up-left), find the cause, fix the rule rather than the one spot, and re-render the batch.
4. Before handing over a batch, check the summary lines on every map. You want: 0 odd ground or cliff
   borders (rims may have a few), 0 bare seams, every ramp usable, 98%+ of walkable ground reached. Then
   tell the person what changed since the last batch.

## Step 5: keep it going

- Next biome: back to Step 2. Reuse the generator; most biomes need only a new kit plus one or two new
  rules.
- Write down every decision the person makes (art direction, rules) in `STATUS.md` with the reason. They
  shouldn't have to repeat themselves.
- When a study finds a reusable rule, add it to `docs/LESSONS.md`.

## When you are stuck

- **Items look wrong in renders:** check `study/setup_check.png`, the `.dat` format (`dat_format`), the
  `transparency` setting, and whether the map stores server or client ids (`map_ids`).
- **A tool says `study/families.json` is missing:** run `tools/build_families.py`.
- **Generation hangs:** a shape loop isn't settling. Run that seed alone with a timeout, find the loop,
  give it a budget. `tools/test_clean.py` tests the shape cleaner.
- **Borders look broken:** run `tools/odd_borders.py areas/<name>`. A strip of ground too thin for its
  set, or two grounds that touch with no border between them (`bare seams` in the summary). Fix the
  rule that made the shape.
- **Unreachable spots:** `tools/unreached.py areas/<name>/area.txt` lists pockets and what walls them in.
  `tools/separators.py` shows what lies between a pocket and the reached ground.

## What you must never do

- Write outside this folder, or into the person's server, client or map files.
- Hard-code item ids in code.
- Ship or upload their data, maps or sprites anywhere.
- Claim a batch is good without reading every map's summary and looking at the renders.
