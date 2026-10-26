# Adapters: connecting your data

Every tool reads game data through `tools/common.py`, and `common.py` asks the adapter that `config.json`
names (`"adapter": "<name>"` loads `adapters/<name>.py`). To support a new format, write one adapter; no
tool changes.

## The included adapter: `otbm_dat`

For standard OT data: an OTBM map, `items.otb`, `items.xml`, and a client `Tibia.dat` + `Tibia.spr`.

| config key | meaning |
|---|---|
| `adapter` | `"otbm_dat"` |
| `map` | the reference map (`.otbm`). Index it once with `tools/index_map.py` |
| `items_otb` | the server's `items.otb`: maps server ids to client ids. Optional |
| `items_xml` | the server's `items.xml`: names and attributes (`floorchange`). Optional, but names help a lot |
| `dat`, `spr` | the client's `Tibia.dat` and `Tibia.spr` |
| `dat_format` | `auto` (default), `10.98`, `8.60`, `8.54`, `8.60-extended`, `8.54-extended` |
| `transparency` | `auto` (default: read the `.otfi` beside the `.dat`, else test the sprites), `true`, `false` |
| `map_ids` | `server` (default: TFS and most forks store server ids) or `client` (maps with client ids) |
| `kit` | the default kit name for tools and the generator |

Paths may be absolute or relative to the studio folder. Item data is cached in `cache/items.pickle` and
rebuilt when the `.dat` changes. The map is cached in `cache/map/<name>/`. Run `tools/index_map.py` again
after the map changes.

If `check_setup.py` fails with "reads as none of the known formats", the `.dat` has custom flags (some
servers add their own). Add the flag bytes to a copy of `FORMATS` in the adapter, or write a new adapter.

## The adapter interface

An adapter module defines `class Adapter` with `__init__(self, cfg, root)`, where `cfg` is the parsed
`config.json` and `root` the studio folder. Methods:

| method | returns | used by |
|---|---|---|
| `items()` | `{map id: {"id", "flags": {...}, "groups": [{"width", "height", "layers", "patternX", "patternY", "patternZ", "phases", "sprites": [sprite ids]}]}}` | everything |
| `sprite_rgba(sprite_id)` | 32x32 RGBA bytes (4096), or `None` for an empty sprite | renders, sheets |
| `names()` | `{id: name}` | tool output |
| `attributes()` | `{id: {key: value}}` (at least `floorchange` for ramps and stairs) | access, ramp studies |
| `tiles(map_path, floors, bounds)` | yields `(z, x, y, [ids bottom to top])`. `map_path` None means the configured map; `floors` a set or None; `bounds` `(x1, y1, x2, y2)` or None | every study tool |
| `index(map_path)` | optional: prepares a cache | `tools/index_map.py` |
| `path(key)` | optional: a config path resolved against the studio folder | `tools/check_setup.py` |
| `draw_tweaks()` | optional: `{id: {"offset-x", "offset-y", "opacity", "invisible"}}` per item type | renders |
| `write_map(out_dir, area, name)` | optional: writes an area `{z: {(x, y): [ids]}}` as a map file | export |

**Flag names** the tools understand (from the `.dat`): `ground_speed`, `full_ground`, `ground_border`,
`on_bottom`, `on_top`, `container`, `stackable`, `multi_use`, `fluid_container`, `splash`,
`not_walkable`, `not_moveable`, `block_projectile`, `not_pathable`, `pickupable`, `hangable`,
`hook_south`, `hook_east`, `rotateable`, `dont_hide`, `translucent`, `lying_corpse`, `animate_always`,
`full_ground`, `ignore_look`, `displacement_x`, `displacement_y`, `elevation`, `minimap_color`,
`light_intensity`, `light_color`. Only the ones present are set. The key ones are `ground_speed` or
`full_ground` (a ground), `ground_border`, `on_bottom`, `on_top` and `not_walkable`.

**Sprite index order** inside a group (the client's): `((((((phase * patternZ + z) * patternY + y) *
patternX + x) * layers + layer) * height + h) * width + w)`.

## Writing a new adapter

Copy `adapters/template.py` to `adapters/<name>.py`, fill in the methods, set `"adapter": "<name>"`, then
run `tools/check_setup.py` and look at `study/setup_check.png`. Common cases:

- **Protobuf appearances (client 12+)**: read `appearances.dat` (protobuf) for flags and sprite ids, and the
  catalog's sprite sheets (LZMA-compressed BMP sheets) for pixels. Map ids are usually client ids there.
- **Your own map format**: implement `tiles()` straight from your chunks, or convert to OTBM once.
- **Exporting**: implement `write_map`. For OTBM, write the node tree (map data, tile areas of 256x256,
  tiles with ground and items) with an editor's reference as a guide. Open the result in your map editor
  before trusting it.
