# Pixel art studio

Three commands, in Tibia's oblique perspective:

| command | example |
|---|---|
| `/creature` | `/creature a pirate frog with a sabre` |
| `/item-sheet` | `/item-sheet 8 alchemist potions` |
| `/floor` | `/floor dark grass with tufts and small flowers` |

What is generated goes to `out/`. The PixelLab token lives in `PIXELLAB_API_TOKEN` or in `.pixellab_token` (never in
git). The why of every rule is in the skills (`.claude/skills/`) and in `PIXEL-ART-STUDIO.md`; the journal, in
`NOTES.md`.

A creature, by hand:

```
cp creatures/_template.py creatures/<name>.py      # and replace the beetle with the creature
python creatures/<name>.py shape                   # the shape
python creatures/<name>.py preview                 # the animation on the shape (no PixelLab)
python creatures/<name>.py edit 3                  # 3 repaints on PixelLab (spends balance)
python creatures/<name>.py pick out/<name>/edit/edit_v2.png
python creatures/<name>.py animate                 # the sheet <name>_idle8_walking8.png and the GIFs
```

## Project Chaos

This studio lives in `client/tools/art_studio/` (set up from `PIXEL-ART-STUDIO.md`, section 4). Nothing here touches
the client pair: what it makes goes to `out/` (gitignored, with `.pixellab_token`); an import into the client is a
separate, deliberate step (`client/tools/sprites/`).

A fourth command, **`/pixelart`**, writes a ready-to-paste PixelLab prompt (grimdark by default) that you paste into
the PixelLab website yourself: it needs no token and spends nothing. Examples for our content (crafting orbs, a
support rune, the rift key): `prompts/pixelart/examples.md`.

What needs the PixelLab token (`PIXELLAB_API_TOKEN` or `.pixellab_token`): `/creature`'s `edit` (the repaint, Edit
images Pro; then `pick` and `animate` work from that painting) and `/item-sheet`'s `gen` (Create image Pro). Without
it: `/floor`, `/pixelart`, and `/creature`'s `shape` and `preview`.

**The commands are project skills of THIS folder**: open the agent in `client/tools/art_studio/` and `/creature`,
`/item-sheet`, `/floor` and `/pixelart` appear. From the repo root they do not load on their own; ask the agent to
follow `client/tools/art_studio/.claude/skills/<name>/SKILL.md`, or run the scripts directly (every script finds the
studio from its own path, so any working directory works):

```
python3 client/tools/art_studio/floors/cracked_obsidian.py        # also ash_stone.py, blood_moss.py
python3 client/tools/art_studio/floors/blood_moss_border.py       # the border set blood moss -> ash stone + scene
python3 client/tools/art_studio/creatures/ghoul.py shape          # the ghoul's shape
python3 client/tools/art_studio/creatures/ghoul.py preview        # its idle + walk on the shape (no PixelLab)
python3 client/tools/art_studio/kit/items.py split <sheet.png> <name> 64
```

(`kit/items.py gen` takes the prompt file's path: from the root, `client/tools/art_studio/prompts/items/<slug>.md`.)
