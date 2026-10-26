# File index

Every file in the package and what it does. Written by the package build from each file's own description, so it stays current. Start with `START_HERE.md`.

## Top level

Entry points and project files.

| file | what it does |
|---|---|
| `.gitignore` | Keeps your config, caches, references and generated areas out of version control. |
| `AGENT_GUIDE.md` | The agent's playbook: ground rules, the interview, setup, study, generation, the review loop, troubleshooting. Hand this to your AI agent. |
| `config.example.json` | Copy to config.json and fill in your paths (docs/ADAPTERS.md). |
| `FILES.md` | This index (written by the package build; do not edit by hand). |
| `README.md` | What Map Studio is, what's inside, the quick start, and where each doc lives. |
| `requirements.txt` | Python packages the studio needs. |
| `run.py` | Run a MapStudio Python tool with writes confined to this sandbox process. |
| `START_HERE.md` | The two-minute start: install, open in your AI agent, answer its questions. |
| `STATUS.md` | The project's living state (facts, decisions, next steps), kept current by you or your agent. |

## adapters/

Data adapters: how the studio reads a game's items, sprites and maps (docs/ADAPTERS.md).

| file | what it does |
|---|---|
| `adapters/otbm_dat.py` | Adapter for standard OT data: an OTBM map, items.otb, items.xml and a Tibia.dat/.spr pair. |
| `adapters/template.py` | Template for a new data adapter: copy to adapters/<name>.py, fill in each method, and set "adapter": "<name>" in config.json. |

## docs/

Documentation.

| file | what it does |
|---|---|
| `docs/ADAPTERS.md` | Every tool reads game data through `tools/common.py`, and `common.py` asks the adapter that `config.json` names (`"adapter": "<name>"` loads `adapters/<name>.py`). |
| `docs/CONCEPTS.md` | What an OT map is made of, and the rules this studio learned for making one look hand-made. |
| `docs/KIT_SCHEMA.md` | A kit (`kit/<biome>.json`) holds everything biome-specific: which items to use and the numbers learned from the reference map. `gen/generate.py --kit <biome>` reads it. |
| `docs/LESSONS.md` | Rules this studio learned the hard way while building jungle and lava islands. |
| `docs/STUDY_RECIPES.md` | How to learn each part of a biome from the reference map, which tool measures it, and what to carry into the kit. |

## gen/

The generator and its shape, placement and access logic.

| file | what it does |
|---|---|
| `gen/access.py` | Walkability over all floors of a generated area, and the repair that keeps every ramp usable. |
| `gen/generate.py` | Kit-driven hunting island generator: coast, lakes, rivers, stacked mountain levels with ramps, passes and crossings, layered ground borders, roads and patches, and clumped vegetation, all checked for reachability. |
| `gen/lib.py` | Shared generation steps: noise, mask cleanup, 12-piece edges, trees and decor. |
| `gen/shapes.py` | Region shapes shared by the generators: noise blends, distance fields, connected parts, and ramp spots. |

## kit/

Biome kits: item ids and learned numbers (docs/KIT_SCHEMA.md).

| file | what it does |
|---|---|
| `kit/TEMPLATE.json` | Starting point for a new biome kit; every 0 is an item id to fill in. |

## tools/

Setup, study, check and review tools. Run each as `python -B run.py tools/<name>.py`; most print their usage with `--help`.

| file | what it does |
|---|---|
| `tools/above_items.py` | What lies on the floor above tiles of a given ground, over refs/. |
| `tools/bands.py` | How a group of ground families is layered inside its bodies: per distance from the group's edge (1 = touches other ground), the share of each family. |
| `tools/bank_study.py` | What lines the water in reference windows: bank grounds, bank items, and water widths. |
| `tools/batch.py` | Renders a review batch: 8 varied seeds into areas/<batch>/seed-NNN/ (area.txt, render.png, summary.txt), then writes the review page areas/<batch>/index.html (tools/review_page.py). |
| `tools/build_families.py` | Groups ground items into families (variants of one ground) and collects border sets: study/families.json. |
| `tools/check_setup.py` | Checks that config.json, the adapter and the data work, and shows a few items so a person can confirm the sprites look right. |
| `tools/clump_study.py` | How plants clump on a ground family: the distribution of local density, by distance to the nearest edge. |
| `tools/common.py` | Shared loading for Map Studio: config, the data adapter, item facts and names, map areas, kits, sprites. |
| `tools/compare_stats.py` | Side-by-side numbers for area files: ground variety, item density, floors used. |
| `tools/double_cliff.py` | How the reference map stacks a cliff two levels high: finds columns of height 2+ next to a column of height 0 and prints the stacks on floors 5-7 around one, plus counts of what the floor-6 and floor-7 tiles below the edge carry. |
| `tools/edge_density.py` | Plant density on a ground family by distance to the nearest tile of another family (path, sand, water, cliff). |
| `tools/extract_ref.py` | Copies a reference area out of a map into refs/<name>/area.txt, and renders it with --render. |
| `tools/family_items.py` | Per ground family: which non-border items lie on its tiles, per tile, with size and walkability. |
| `tools/family_sheet.py` | Picture of ground families, one row per family (lead first, then its members), to check the grouping by eye. |
| `tools/find_family.py` | Where ground families sit on the reference map: tile counts per 64x64 block and floor, with the other grounds in the best blocks. |
| `tools/ground_context.py` | Where a ground family sits: its share per floor, its depth (distance to its own edge, i.e. patch/road width), and how far its tiles are from raised ground (mountain fill or cliff pieces) on floor 7. |
| `tools/index_map.py` | Reads the reference map once into cache/map/ so every tool can read windows of it quickly. |
| `tools/learn_kit.py` | Learns a biome kit from reference windows: which ground families make the surface, which pairs touch and with which border, and what grows on each family. |
| `tools/meadow_items.py` | What lies on a ground family deep inside open areas (edge distance >= --min), per tile, with kind and walkability. |
| `tools/minimap.py` | A 1-pixel-per-tile minimap of a map folder's floor, for finding areas worth studying. |
| `tools/name_set.py` | Names the pieces of a border/cliff set from where the reference map lays them: for every id in a range, the ground it lies on, the family it borders (the commonest other family around it) and, from the directions that family lies in, its pi |
| `tools/odd_borders.py` | Tiles whose border pieces of one 12-piece set face opposite ways (e.g. a north edge with a south-east outer corner): the signature of a strip of ground too thin for the set, where the pieces pile up and look broken. |
| `tools/outline_study.py` | How outlines are shaped, read from the 12-piece sets drawn along them: the share of straight edge pieces, inner corners (two sides) and outer corners (diagonal only). |
| `tools/pair_items.py` | What lies on the boundary tiles between two ground families in reference windows. |
| `tools/path_study.py` | How walkable space behaves around relief, per floor: corridor widths, room around ramps, plants near ramps. |
| `tools/piece_check.py` | Which neighbours a piece set's pieces see in reference windows. |
| `tools/ramp_check.py` | Geometry of ramp pieces over the whole reference map. |
| `tools/relief_study.py` | How raised ground is shaped in reference windows: levels, terrace widths, tops, outlines, cliff plants. |
| `tools/render.py` | Draws a map area with the real sprites. |
| `tools/review_page.py` | Writes areas/<batch>/index.html: a review viewer for a batch of rendered maps (tools/batch.py). |
| `tools/rim_check.py` | Where a raised floor's rim pieces sit, over refs/. |
| `tools/rim_items.py` | What lies on the edge tiles of raised tops and what climbs between floors, in reference windows. |
| `tools/rim_plants.py` | Plants on raised-floor rim tiles vs inner top tiles in reference windows. |
| `tools/seam_audit.py` | Seams between different grounds: how often a border covers them, per pair of ground families. |
| `tools/separators.py` | What separates an unreachable pocket from the reached ground: blocked tiles that lie within 2 steps of both. |
| `tools/shape_lab.py` | Shape lab: scores outline treatments against the reference map's outline signature (tools/outline_study.py: about 0.30 edge, 0.34 inner, 0.34 outer pieces, almost no 4+ runs of one edge piece). |
| `tools/sheet.py` | Labelled sheet of item sprites: python -B run.py tools/sheet.py <out.png> <id> [<id> ...] |
| `tools/side_by_side.py` | The yardstick: a reference window and a generated window of the same size, rendered at the same scale, side by side, with their numbers underneath. |
| `tools/species_mix.py` | Which plants make up dense and sparse parts of a family's ground: share of each big plant among the big plants whose 5x5 neighbourhood holds few (<= 2), some (3-5) or many (6+) big plants. |
| `tools/stacks.py` | Prints the floor-7 stacks of a window of an area file, one row per tile row, ids by kind. |
| `tools/sweep.py` | Runs gen/generate.py's build() without rendering over seeds and knob values, and prints the measures that matter for tuning: sea-cliff share of water edges, ground reached, ramps usable, mountain share. |
| `tools/test_clean.py` | Checks lib.clean on random and adversarial masks: it settles, leaves no pinched outside tile and no isolated region tile. python -B run.py tools/test_clean.py |
| `tools/top_ground_study.py` | Which grounds make raised tops, by place on the top: rim tiles (a rim piece), cliff-foot tiles (a cliff piece of the level above), and inner tiles. |
| `tools/top_items.py` | What the reference map stacks on tiles of a given ground, over refs/. |
| `tools/unreached.py` | Walkable tiles a player cannot reach, grouped into pockets, with what blocks each pocket's rim. |

## Folders the tools create

| folder | what it holds |
|---|---|
| `cache/` | Indexed map and item data (tools/index_map.py, the adapter). Safe to delete; rebuilt on demand. |
| `refs/` | Reference windows cut from the reference map (tools/extract_ref.py): area.txt and render.png. |
| `study/` | Study output: families.json, clumping tables, sheets, minimaps. |
| `areas/` | Generated areas and review batches: area.txt, render.png, summary.txt, index.html. |
