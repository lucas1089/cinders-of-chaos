# Map Studio

A toolkit for generating OT map areas that look hand-made: hunting islands with coasts, rivers,
multi-level mountains, ramps, roads, ground mosaics and vegetation. You study a reference map you admire,
learn its rules and items into a "kit", and generate new areas from it.

It is built to be driven by an AI coding agent working with you: the agent studies, builds and measures,
and you decide and review. It works just as well by hand.

## What's inside

- **A generator** (`gen/generate.py`) driven by a kit: island shape, lakes and rivers, stacked mountain
  levels with cliffs, rims and ramps, passes and crossings, layered ground borders, and clumped
  vegetation. Every map is checked for broken borders and for reachability.
- **About 40 study tools** (`tools/`) that measure a reference map: which grounds, borders, cliffs and
  plants a biome uses, how they clump, how wide roads and terraces are, how outlines bend. Run the same
  tools on generated maps to compare.
- **A review loop**: `tools/batch.py` renders eight varied seeds and builds a review page where you click
  a spot and write a note. The agent reads the notes and fixes the rules.
- **A data adapter** for standard OT data (OTBM map, `items.otb`, `items.xml`, `Tibia.dat`/`.spr`), and
  an interface to write your own for other formats.
- **Documentation** of the mapping concepts, the study recipes, the kit format, and the lessons learned.

No item ids, sprites or maps are included. Everything game-specific is learned from your own data.

## Quick start

Requirements: Python 3.10+ and Pillow (`pip install -r requirements.txt`).

**With an AI agent** (recommended): open this folder in your agent (Claude Code, Codex, and so on) and
say: *"Read AGENT_GUIDE.md and set up Map Studio with me."* It will ask about your data, your reference
map and your goals, then walk you through every step.

**By hand:**

```bash
cp config.example.json config.json        # then fill in your paths
python -B run.py tools/check_setup.py     # items load? look at study/setup_check.png
python -B run.py tools/index_map.py       # read the reference map once (minutes)
python -B run.py tools/build_families.py --mix
python -B run.py tools/minimap.py --floor 7
```

Then follow `docs/STUDY_RECIPES.md` to build a kit, and generate:

```bash
python -B run.py gen/generate.py --kit <biome> --name first --seed 1
python -B run.py tools/batch.py review-01 --kit <biome>
```

## Documentation

| file | read it for |
|---|---|
| `START_HERE.md` | the two-minute start |
| `AGENT_GUIDE.md` | the agent's playbook: interview, setup, study, generate, review |
| `FILES.md` | what every file in the package does |
| `docs/CONCEPTS.md` | how OT maps are built, and the rules for a hand-made look |
| `docs/STUDY_RECIPES.md` | how to learn each part of a biome, tool by tool |
| `docs/KIT_SCHEMA.md` | every field of a kit |
| `docs/ADAPTERS.md` | config keys, the adapter interface, supporting other formats |
| `docs/LESSONS.md` | rules learned the hard way |
| `STATUS.md` | the project's living state: kept by you or your agent |

## Good to know

- Every script runs through `run.py`, which refuses to write outside this folder. Your server and client
  files are only read.
- Generated areas land in `areas/<name>/` as `area.txt` (one line per tile) plus `render.png`. Exporting to
  a map file needs an adapter's `write_map` (see `docs/ADAPTERS.md`). That's the natural next contribution.
- The rules and numbers in the docs were measured on one hand-made map. Re-measure them on yours: that's
  the point of the tools.
- Study and copy only maps you have the rights to use.
