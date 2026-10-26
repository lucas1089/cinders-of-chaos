# Study recipes

How to learn each part of a biome from the reference map, which tool measures it, and what to carry into
the kit. Every recipe ends the same way: measure your generated output with the same tool and compare.

All commands are run from the studio folder as `python -B run.py <script> ...`. `refs/<a>` stands for
reference windows cut with `tools/extract_ref.py`.

## Find good places to study

- `tools/minimap.py --floor 7`: the whole surface, one pixel per tile. Find each biome, and ask the person
  which places they consider best made.
- `tools/find_family.py G<lead> --block 128`: where a ground is laid most, per floor and block, with the
  grounds around it.
- Cut 2-4 windows per biome, 100-200 tiles square:
  `tools/extract_ref.py <name> --from x1,y1 --to x2,y2 --render [--floors 8-15 --floor 9]`.

## Grounds and their shares

- `tools/learn_kit.py refs/<a> refs/<b> --floors 7`: ground families by share, the plants on each,
  touching pairs and which border sets the windows draw. Choose `base` (the commonest walkable ground),
  `sand` (roads and patches) and the apron grounds from it.
- `tools/family_sheet.py G<a> G<b>`: look at the families. Wrong grouping: `study/family_overrides.json`.
- `tools/ground_context.py G<family> refs/<a>`: share per floor, depth (how wide its patches or roads are)
  and distance to raised ground. This tells you whether a ground is a road, a patch or an apron.
- `tools/top_ground_study.py refs/<a> --floors 4,5,6`: which grounds cover mountain tops, on rims and inside.

## Border sets and the layer order

1. Find candidate pieces: `tools/learn_kit.py` lists the sets drawn, and `tools/stacks.py` shows whole
   tile stacks.
2. Name them: `tools/name_set.py <first id> <last id> refs/<a> ... --floors 7`. It prints, per id, the
   ground it lies on, the family it borders, and the piece name from where that family lies. Expect 12
   names. Missing names are rare pieces, so add more windows.
3. Confirm: `tools/piece_check.py ids:<id,...> --target G<owner>` shows the neighbour patterns each
   piece sees.
4. Order: `tools/seam_audit.py refs/<a> --pair G<a>,G<b>` shows what is drawn on each side of an A|B
   seam. The side that draws is the higher layer. Pairs where nothing is drawn must not touch in the kit.

## Mountains, hills, rims and ramps

- `tools/relief_study.py refs/<a>`: share of raised ground, level counts, terrace widths, and what grows
  on tops.
- `tools/rim_items.py refs/<a> --floors 4-6`: border items on top edge tiles, and every floorchange
  item (ramps, stairs) with counts.
- `tools/rim_check.py <set key or ids>`: where rim pieces sit relative to the drop.
- `tools/ramp_check.py <ramp>:<lower half>`: over the whole map, the ground under a ramp, its neighbours,
  where the lower half lies and what the floor above holds.
- `tools/double_cliff.py refs/<a>`: how a two-level cliff is stacked.
- `tools/path_study.py refs/<a>`: corridor widths near relief and room around ramps. Use it to set
  path rules.

## Plants and decor

- `tools/family_items.py G<family> refs/<a> --floors 7`: per-tile rates of every non-border item on a
  ground, with size and walkability. These go into `flora`.
- `tools/clump_study.py G<base> refs/<a> --out study/<biome>_clumps.json`: clumping quantiles per
  distance-to-edge band (the `clumps.quantiles` file). Add `--floor 6` and so on for tops (`clumps.tops`).
- `tools/edge_density.py G<base> refs/<a>`: plants per tile by distance to the nearest other ground.
- `tools/meadow_items.py G<base> refs/<a> --min 5`: what lies on deep open ground (the `meadow` scatter).
- `tools/species_mix.py G<base> refs/<a>`: which species make dense and sparse parts.
- `tools/rim_plants.py refs/<a>`: plants on rim tiles against inner top tiles.
- `tools/top_items.py <ground id>` and `tools/above_items.py <ground id>`: what is stacked on a ground, and what
  lies on the floor above it (over all of `refs/`).

## Water, liquids and banks

- `tools/bank_study.py refs/<a>`: bank tiles (land touching water): ground, cliff share and bank plants
  (`bank_flora`).
- `tools/bands.py <id>,<id>,... refs/<a> --floors 7`: liquid variants by distance to land, which give `water.bands`.
- `tools/pair_items.py G<a> G<b> refs/<a>`: what lies on the boundary between two grounds.

## Checks on generated output

These run on `areas/<name>` the same way as on refs:

- `tools/odd_borders.py areas/<name>`: tiles where one set's pieces face opposite ways (target 0, a few
  for rims).
- `tools/outline_study.py areas/<name>`: edge, inner and outer piece shares and straight runs.
- `tools/unreached.py areas/<name>/area.txt`: unreachable pockets and what walls them.
- `tools/separators.py areas/<name>/area.txt x,y`: what lies between a pocket and the reached ground.
- `tools/compare_stats.py`: ground ids, items per tile, border coverage and distinct ids, ours against
  theirs.
- `tools/side_by_side.py`: one picture, reference and ours at the same scale.
- `tools/sweep.py --knob <knob> --values a,b,c`: runs the generator without rendering over seeds and
  values, and prints sea-cliff share, reach, ramps and mountain share.
