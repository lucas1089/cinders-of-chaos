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

## Keys added 2026-10-26 (cave, lava, swamp, ice)

Every key is off unless the kit has it, so older kits (grass) generate the same files as before.

| key | what |
|---|---|
| `floor` | the map's main floor (default 7). Cave kit: 9. Also `--floor N` on the command line |
| `cave` | cave mode (gen/cave.py): solid rock is the "water" role, the carved floor is the land. Sub keys: `shape` (`tunnels`, `chambers`, `mix`), `wall_style` (`on_floor`: a wall piece on the floor edge, tunnels are carved 2 wider; `on_rock`: a wall on the rock tile; `mixed`: seeded pick per cave), `chambers` {`per_1000`, `radius` [lo, hi], `spacing`}, `tunnel_width` {width: share}, `loops` [lo, hi], `spurs_per_1000`, `floor_share` [lo, hi], `pillars_per_chamber`, `stairs` {`count` [lo, hi]}, `styles` {style: {`layers`, `no_water_border`}} overriding the kit's table per wall style. Flags `--cave-shape`, `--wall-style` |
| `corridor_ground` | the same sub keys as `cave`, used only with `--corridor-ground`: the base ground is carved as winding corridors in the liquid (lava) |
| `stairs` | in `cave`: ramps between floors with a small landing floor of the base ground |
| `pocket_fill` | see above; cave mode uses it for every sealed pocket |
| `solid_mountain` | `true` (or `--solid-mountain`): the mountain is a solid fill with no top floor and no ramps |
| `solid_fill` | ground spec for that fill (members repeat to weight the lead) |
| `wall_set` | `{ground key: 12-piece set name}`: the wall set drawn on the floor and liquid tiles beside a solid mountain |
| `top_liquid` | `{"share": [lo, hi], "inner": 3}`: lakes of the kit's liquid in the middle of a mountain top, 3+ tiles from the rim and from ramp arrivals and departures; a lake that would split the walkable top is skipped |
| `water.walkable_variants` | names of band variants a player can stand on (cooled crust); they leave `water_ids` and so count as walkable |
| `patches` | `[{"ground": role, "share": s, "scale": cell, "min": tiles}]`: blobs of a ground role inside the base ground (swamp: grey sand) |
| `patch_scale`, `worn_blob`, `worn_gap` | finer noise for the worn rim: `[[cell, weight], ..]`, blob size `[min, max]`, gap between blobs |
| `plank_roads` | `{"count": n, "width": {"1": .5, "2": .3, "3": .2}, "ew": ground spec, "ns": ground spec}`: winding plank walkways over liquid, 12-45 tiles long, grain follows the way |
| `plants_on_water` | `true`: `water_flora` grows on the kit's plain liquid (swamp reeds, lily pads) |
| `crossing` | `{"type": "ford", "ground": id}`: fords instead of bridges |
| `road_rough`, `road_brush`, `road_broad` | road shape knobs, see the 2026-10-26 round 3 decision in STATUS.md |
| `edge_smooth` | `{"blur": passes, "longest": run, "jag": run}`: rounder outlines. `blur` smooths the layout masks, `longest` is the longest straight outline run `break_runs` leaves (default 3), `jag` the jag size `tidy_grounds` removes (default 2). Not set in any kit: measured on lava it did not shorten the straight runs of the lava edge (see STATUS.md) |
| `mountain_fill_decor` | `{"<id>": rate}`: decor rolled once per mountain fill tile (ice: 2x2 snow chips and stones of ids 6939-6950, 6871-6881, 6926-6937, about 22% of the fill) |
| `lake_water` | `{"ground": spec, "decor": {id: rate}, "border": layer key, "rim_water": bool, "fringe": {"north": id, "west": id}}`: inland water (a component touching no map edge) takes the sheet ground instead of the liquid. `border` (ice: `mountain_cliff`) draws that layer's 12-piece set on the land beside the lake, which closes the black east and south edge tiles of the sheet 6869; `rim_water` is the older fix (plain water on the rim). Used by kit/ice.json |
| `cave.void_beyond`, `cave.void_jitter` | cave mode: solid tiles farther than `void_beyond` steps from any floor (plus noise of `void_jitter` tiles) get no tile, so the rock mass shows black like the reference |
| `cave.meander` | `{"amp": tiles, "scale": tiles, "width_jitter": n}`: tunnels swing sideways (two harmonics, zero at the ends) and vary in width, fewer pure 45 degree stairs |
| `coast_round` | `{"radius": r, "keep": n, "longest": n}`: liquid-low kits (lava, swamp): box blur of radius r and a 0.5 threshold on the land mask removes 1-tile notches and spikes; tiles within `keep` steps of relief keep their value; `longest` is the straight run limit afterwards |
| `crossing.as_land` | `true`: a ford strip becomes ordinary base ground and land (no road or sand rectangles on lava) |
| `creeks` | `{"share": s, "scale": cell, "wide": 2, "min": tiles, "away": steps}`: thin winding channels of the liquid cut into the land (swamp: reference land is a trail network). A creek never splits a land part: pieces other than the biggest go back to liquid. Swamp kit: share 0.4, away 3 |
| `batch_variants` | `{"<seed>": "<knobs>", "*": "<knobs for any other seed>"}`: per kit batch knobs for tools/batch.py (cave 301-308, swamp 201-208, ice 401-408, lava 501-508) |

## Keys added 2026-10-26 (round 7)

Every key is off unless the kit has it (grass seeds 101-103 area.txt md5 unchanged).

| key | what |
|---|---|
| `scatter` | `{"<id>": rate}`: props (blocking ones too) dropped on open base ground after the meadow pass, each on tiles no plant stands on. The clump density puts big props in a few groves only (ice); `scatter` spreads lone trees, shards and rocks over the whole floor. Access repair still clears any that close a path. Used by ice and lava |
| `pocket_fill_tops` | `n`: with `pocket_fill`, unreached walkable pockets of up to `n` tiles on the floors above the main one (top parts that cliff pieces cut off) get the same blocking 1x1 plants as the main floor. Used by ice and lava |
| `same_look` | `[[role, role], ...]`: ground pairs that look alike (ice: snow `base` and `rock_soil`; cave: the brown floor variants). Their missing border is counted in `same_look_seams` of the area header, not in `bare_seams` |
| `top_corridor_walk` | `true`: the route corridor on mountain tops also takes walkable `top_flora` items (blocking ones stay out). Used by lava, whose tops were flat grey |
| `patches` (cave) | the cave kit now uses `patches` for its floor: `clay` (G103), `stain` (G12234), `slate` (G9068), `rock_soil` (smooth members only); `defaults.sand` 0 so no 1-tile grey squares |
| `top_gravel`, `gravel_on_rock`, `top_mix` (lava) | same keys as the grass kit: gravel patches (G4571) in the grey rock soil of tops, borders from `gravel_on_rock` |

## Keys added 2026-10-26 (round 8: walls, rooms, islands, pools, stamps)

All opt-in. A kit without them generates byte-identical maps (grass seeds 101-103 checked by md5).

| Key | What it does |
|---|---|
| `walls` | The wall set of a room or building kit, laid from the floor mask by `gen/walls.py`: `{"h": [id], "v": [id], "corner": id, "pole": id, "end_h": id, "end_v": id, "variants": {"h": {id: share}, "v": {id: share}}, "cover": 2, "solid": ground spec}`. Every tile beside the floor (4 neighbours, plus the diagonal tile that closes a convex corner) gets one piece chosen from its wall neighbours: both ways east and west is `h`, north and south is `v`, a turn east and south is `corner`, every other turn or junction is `pole`, the west end of a run is `end_h`, the north end `end_v`. `variants` (window, broken) replace single run pieces, never two touching. The wall tiles and `cover` rings behind them get solid ground (`solid`, else the kit's liquid role), so no void shows between or behind walls. `gen/walls.py wall_spec(base, windows, broken)` builds the key for a pack 30 16-piece set (post, h, v, corner, 2 ends, doors, windows, broken pieces) |
| `wall_check` | `true`: area.txt header gets `wall_check` = `{void_touch, wall_wrong, wall_missing}` (gen/wallcheck.py; also `python3 -B run.py tools/wall_check.py areas/<batch>`, exit 1 on any count above 0). `void_touch`: tiles with no ground, or a black ground (mean luma under 12), 8-adjacent to a walkable tile or a wall tile. `wall_wrong`: wall pieces that differ from the piece their neighbours ask for. `wall_missing`: wall tiles with no piece. Kits with the 12-piece cliff set on the floor edge (`wall_style on_floor`) are checked against `edge_pieces`; ramp seats and pool tiles are exempt |
| `cave.rooms` | Dungeon mode (gen/rooms.py): rectangular rooms and cell blocks joined by straight 2-4 wide L and Z corridors, in place of organic chambers. `{"per_1000": nodes per 1000 inner tiles, "gap": free tiles between nodes, "corridor": {"2": share, "3": share}, "loops": [lo, hi], "floor_share": [lo, hi], "kinds": [{"name", "theme", "w": [lo, hi], "h": [lo, hi], "weight"}, {"name": "cellblock", "structure": "cells", "cells": [lo, hi], "cell": [w, h], "hall": 3, "theme": "cell", "hall_theme": "hall", "both": 0.7}]}`. Corridors meet a room flush with a side or 2+ tiles in, so no wall stub is left at a doorway. A cell block is a hall with 1-tile doors into small cells that share walls |
| `themes` | `{"<theme name>": {"floor": {"role": .., "accent": {"role": .., "share": .., "size": [lo, hi]}}, "along": [..], "rows": [..], "grid": [..], "center": [..], "props": [..], "scatter": {id: rate}}}` (gen/themes.py, see its docstring for the pattern keys). Each room has the theme of its kind; the theme `corridor` takes `scatter` only. Items stay out of the 2 tiles inside every doorway; `single: true` gives a 64x64 sprite one tile of occupancy |
| `islands` | Celestial mode (gen/islands.py): separate landmasses over void, joined only by straight 2-3 wide bridges. `{"per_1000": islands per 1000 inner tiles, "radius": [lo, hi], "gap": void tiles kept between islands, "margin": land keeps this far from the area edge, "width": {"2": share, "3": share}, "max_len": longest bridge, "loops": [lo, hi] bridges beyond the spanning tree, "lake_min": an enclosed void pocket under this size is filled, "bridge_key": ground role of the strips}`. Island outlines are tidied (no 1-tile spur or inlet, `lib.clean`), unjoined islands are dropped. A kit with `islands` has no `crossing`, `join_land`, rivers or lakes |
| `void_cover` | `{"ground": [ids], "rings": n, "extra": share, "decor": {id: rate}}`: the void within `n` tiles of land (and a ragged extra ring on `extra` of the tiles) gets a dark non-black ground (celestial: 30492, a violet mist) with clouds and sparkles, so no black tile touches an island. The ids are not walkable (added to `NO_WALK`) |
| `pools` | Liquid pools on open land or cave floor (gen/pools.py): `[{"ground": [ids], "border": "<12-piece set key>", "share": share of the allowed land, "scale": blob radius in tiles, "min": smallest blob, "decor": {id: rate}}]`. Rounded blobs (`lib.clean`) at least 3 tiles from shore, cliffs, ramps and bridges, with the set's pieces on the land around them. The grounds are not walkable. Used by cursed (acid 36865 with `acid_edge`, tar 708-711 with `purple_edge`) and deepsea (deep water 36891 with `deep_edge`) |
| `stamps`, `stamp_walls` | Prefabs from tile patterns (gen/stamps.py): `[{"name", "pattern": ["row", ..], "legend": {char: cell}, "count": [lo, hi], "in": [room themes], "margin": n, "mirror": true}]`. A space is not part of the stamp. A cell is `{"wall": "<stamp_walls key>"}` (piece chosen like `walls`), `{"wall": .., "piece": id}` (a fixed door or window that counts as wall), `{"ground": [ids], "items": [ids], "chance": p}` or `{}`. `stamp_walls` is `{name: {h, v, corner, pole, end_h, end_v}}`. Decor inside the footprint is cleared, ground and border pieces stay. Used for the farm barn and scarecrow field, the fenced graves of cursed and the big top of carnival |
| `same_look` for flat patches | Round 8 kits list every role pair of their flat floors in `same_look`, or drop the patch (deepsea and fungal: `patches` empty, `defaults.sand` 0), so `bare_seams` is 0 |
