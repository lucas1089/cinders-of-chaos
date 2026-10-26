# Kit schema

A kit (`kit/<biome>.json`) holds everything biome-specific: which items to use and the numbers learned
from the reference map. `gen/generate.py --kit <biome>` reads it. Start from `kit/TEMPLATE.json`. All ids
are the ids your map stores (see `map_ids` in `docs/ADAPTERS.md`). Keys starting with `_` are notes and are
ignored.

## Ground roles

The generator thinks in roles, not item names. Each role is a ground spec:
`{"family": "G<lead>", "lead": <id>, "members": [<id>, ...]}`. Per tile, the lead is used 60% of the time,
otherwise a random member.

| key | role | needed |
|---|---|---|
| `water` | the liquid around and inside the island (sea, lakes, rivers; or lava) | yes |
| `base` | the main walkable ground (grass, slab, snow) | yes |
| `sand` | roads and patches (dirt, sand, cobble) | yes |
| `rock_soil` | aprons at cliff feet, and the ground on high mountain tops | yes |
| `gravel` | a second apron ground, between rock soil and sand | no |
| `grey_sand` | worn rims inside roads, along their edges | no (set `worn_share` to 0) |
| `mountain` | the fill item of raised rock: `{"lead": <id>, "members": [<id>]}` | yes |
| `hill` | the fill of a second raised family (earth hills) | yes if `--hills` > 0 |

`water` may also carry depth bands (lava-style liquids, or shallow and deep water):
- `bands`: `[[max distance to land, {variant: share}], ...]`, ascending, the last band catching everything.
- `variants`: `{variant: {"lead": <id>, "members": [...]}}`, and `order`: the variant names, used to
  rank a smooth noise field into the shares.
- `deep_flora_max`: liquid decor only within this many tiles of land.

## The layer table

`layers` lists the ground roles from the lowest to the highest. Where two grounds meet, the higher one
draws its border onto the lower tile (`docs/CONCEPTS.md`).

```json
"layers": [
  {"kit": "sand", "border": null},
  {"kit": "rock_soil", "border": "rock_on_sand"},
  {"kit": "base", "border": {"sand": "base_on_sand", "rock_soil": "base_on_rock"}},
  {"kit": "water", "border": "shore_on_base", "onto": ["base", "rock_soil"], "outside": true}
]
```

- `border`: one 12-piece set name used onto every lower ground, or a dict per lower ground (a ground left
  out of the dict gets nothing), or `null` for none.
- `onto`: with a single set name, the lower grounds it is drawn onto. Others get nothing.
- `outside`: what counts as this layer beyond the area's edge. Set it true for the sea.
- Water as the **first** layer (lava style) makes the land draw onto liquid tiles. Water as the **last**
  layer (water style) makes the shore draw onto land tiles.
- `no_water_border`: grounds that have no border onto the water. They are kept away from it
  automatically.

## 12-piece sets

Any key whose value is `{"edge_n": <id>, "edge_e": ..., "edge_s", "edge_w", "inner_nw", "inner_ne",
"inner_sw", "inner_se", "outer_nw", "outer_ne", "outer_sw", "outer_se"}`. Names: `docs/CONCEPTS.md`. Get
them with `tools/name_set.py` and confirm them with `tools/piece_check.py`. The layer table refers to
them by key. Fixed keys the generator uses:

| key | what |
|---|---|
| `mountain_cliff` | cliff pieces around each mountain level, on the outside tiles |
| `top_rim` | rim pieces on the edge tiles of mountain tops |
| `hill_cliff`, `hill_rim` | the same for hills |

## Ramps

`mountain_ramp` and `hill_ramp`: `{"n": [<ramp>, <lower half>], "s": [...], "e": [...], "w": [...]}`.
The direction is the side the raised ground is on. The ramp item needs a `floorchange` attribute in
`items.xml` so the access check can follow it (`tools/ramp_check.py`, `tools/rim_items.py` list them).

## Crossings

- Bridges: `bridge_ew` `{"lip", "deck", "end", "north": [5 rail pieces], "south": [5]}` and `bridge_ns`
  `{"lip", "deck", "end", "west": [5], "east": [5]}`. Rails run end, first, middle (repeated), last, end.
  Without both keys there are no bridges. `lip` may be left out (the first tile keeps its own ground), `end`
  defaults to `deck`, and a rail list of one id repeats that piece along the whole side (rope bridge: the rail
  is one ground-border piece).
- `bridge_families`: `[{"name": "red", "ew": {...}, "ns": {...}}, ...]`, each `ew` / `ns` shaped like
  `bridge_ew` / `bridge_ns`. Each crossing takes one family at random, seeded by the area seed and the
  crossing (same seed, same bridges). Without the key every crossing uses `bridge_ew` / `bridge_ns`; keep
  those two keys even with the list (they gate bridge sites). The summary line names the choice (`kinds`).
- Fords: `"crossing": {"type": "ford", "ground": <walkable liquid-crust id>}` crosses any narrow liquid
  instead of using bridges.

## Plants and decor

| key | what |
|---|---|
| `flora` | `{"G<family>": {"<id>": rate per tile}}`: per-tile plants on each lower ground (sand etc.) |
| `top_flora` | the same for mountain tops, per top ground family |
| `bank_flora` | `{"G<base family>": {...}}`: plants on base tiles touching water |
| `water_flora` | `{"deep": {...}, "crust": {...}}`: decor on liquid tiles (bands) |
| `meadow` | `{"<id>": rate}`: walkable scatter on base ground with no plant within 2 tiles |
| `hill_top` | `{"<id>": weight}`: decor on hill tops |
| `clumps` | clumped plants on the base ground: `quantiles` (a `tools/clump_study.py --out` file), `tops` (`{"1": file, "2": file}` per top level), `big` and `small` (`{"<id>": weight}`), `boost` (`{"big": 1.0, "small": 1.0}` density factors) |
| `swap_walkable` | `{"2x2": [...], "3x3": [...], "2x3": [...], "1x1": [...]}`: walkable plants of each footprint, used where a blocking plant would close a path |

Rates are learned with `tools/family_items.py` and `tools/learn_kit.py`, clumping with
`tools/clump_study.py`, and edge density with `tools/edge_density.py`.

## Other keys

| key | what |
|---|---|
| `worn_share` | share of road area that gets the `grey_sand` worn rim (0 when the kit has none) |
| `defaults` | knob values for this biome, used when the command line leaves a knob at its default, e.g. `{"hills": 0, "river_width": 4}` |
| `join_land` | `{"least": walkable tiles, "gap": most water tiles}`: a landmass of `least`+ walkable tiles that no bridge joins gets a land neck (5 wide, staircase shores) over at most `gap` water tiles. Off without the key |
| `ramp_least` | smallest top part (8-connected clear tiles) that gets a ramp; default 30 |
| `notch_level0` | `true`: a top with no clean landing gets its ramp seated in a notch cut into the mountain's foot (as higher levels always did). Off by default |
| `road_least` | ramps onto top parts smaller than this, and notch seats at level 0, get no road to their foot (keeps dirt down when `ramp_least` is small). Default 0 = every ramp gets one |
| `repair_pocket` | smallest pocket of walkable tiles that only plants wall off, for which access repair clears a way in; default 4 |
| `drop_cut_off_tops` | `true`: last resort, a group of tiles above the main floor that nobody can reach is removed (the rock below stays solid). Reported as `tops_dropped` |
| `apron_flora` | `{"G<family>": {id: rate}}`: plants on rock soil / gravel on the main floor, in place of the top table |
| `clumps.edge_boost` | `{"small": [factor per edge bucket]}`: multiplies the clump chance by edge distance bucket (corrects thinning near edges) |
| `road_limit` | `{"share": s, "bridge": n}`: a road budget. `share` caps road plus sand patch tiles (before roughening) at `s` of the non-water tiles; ramp feet and shore points past the budget get no road, and a branch that meets it stops short. `bridge` caps the road leading from each bridge end to `n` tiles. Off without the key (a 3-wide road tree to every ramp foot) |
| `top_mix` | `{"gravel": g, "stone": s, "plank": p}`: shares of the top tiles for the grounds of roles `top_gravel`, `top_stone`, `top_plank` (each a ground spec like `base`, and each a layer of the table). Gravel is carved out of the rock soil region (so raise `top_rock` by the same amount); stone and plank are blobs inside the grass, 2+ tiles from each other. Their borders: the layer table says which set each draws onto which ground; the grass draws its rock border onto all three. Off without the key |
| `top_rock` | `{"1": [band, inner]}`: rock soil shares asked of the noise on level 1 tops (rim band, inner area); cleaning loses about a third |
| `rock_patches` | share of open floor 7 ground (3+ tiles from cliffs) that becomes rock soil patches, besides the cliff-foot aprons. Default 0 |
| `clumps.cliff_small` | factor on the small clump density for grass tiles touching the mountain but not water (walkable small plants only). Default off |
| `pocket_fill` | ids of 1x1 blocking plants. A walkable pocket of up to 30 tiles on the main floor that no walk reaches (a strip cut off by cliff pieces and shore) gets one of them on every tile, so nothing walkable is stranded. Reported as `pocket tiles closed`. Off without the key |
| `name`, `notes` | free text: where the kit was learned and how |
