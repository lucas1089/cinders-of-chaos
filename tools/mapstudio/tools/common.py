"""Shared loading for Map Studio: config, the data adapter, item facts and names, map areas, kits, sprites.

Everything game-specific (file formats, paths, item ids) comes from config.json and the adapter it names
(adapters/<name>.py). Tools only use the functions below, so a new data format needs only a new adapter.
"""
from __future__ import annotations

import importlib.util
import json
import os
from functools import lru_cache
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TILE = 32
MAX_ELEVATION = 24
FLOORCHANGE_DIRS = ("north", "south", "east", "west")
DEFAULT_REFS = ROOT / "refs"
FAMILIES = ROOT / "study" / "families.json"


# ---------------------------------------------------------------- json and config

def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path, value, indent=1):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, indent=indent, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(path)


@lru_cache(maxsize=1)
def config():
    path = ROOT / "config.json"
    if not path.exists():
        raise SystemExit("config.json is missing: copy config.example.json to config.json and fill in your paths "
                         "(see AGENT_GUIDE.md, step 1)")
    return read_json(path)


@lru_cache(maxsize=1)
def adapter():
    name = config().get("adapter", "otbm_dat")
    spec = importlib.util.spec_from_file_location(f"adapter_{name}", ROOT / "adapters" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Adapter(config(), ROOT)


REFERENCE_MAP = None  # tools pass None for "the map in config.json"


# ---------------------------------------------------------------- items

@lru_cache(maxsize=1)
def load_items():
    """{map id: {"id", "flags": {flag: value}, "groups": [{width, height, layers, patternX/Y/Z, phases,
    sprites}]}} for every item the map can hold. Flag names: see docs/ADAPTERS.md."""
    return adapter().items()


def kind_of(flags):
    """One word for what an item is on a map. The order of the checks is the rule."""
    if "ground_speed" in flags or "full_ground" in flags:
        return "ground"
    if "ground_border" in flags:
        return "border"
    if "on_bottom" in flags:
        return "wall" if "not_walkable" in flags else "bottom"
    if "on_top" in flags:
        return "overhead"
    if "hangable" in flags or "hook_east" in flags or "hook_south" in flags:
        return "hangable"
    if "lying_corpse" in flags:
        return "corpse"
    if "container" in flags:
        return "container"
    if "splash" in flags or "fluid_container" in flags:
        return "fluid"
    if "pickupable" in flags:
        return "pickup"
    return "decor"


def blocking_of(flags):
    return {
        "walkable": "not_walkable" not in flags,
        "pathable": "not_walkable" not in flags and "not_pathable" not in flags,
        "blocks_projectile": "block_projectile" in flags,
        "moveable": "not_moveable" not in flags,
    }


@lru_cache(maxsize=1)
def _names():
    names = adapter().names()
    extra = ROOT / "study" / "item_names.json"  # names the user or the agent gave to unnamed items
    if extra.exists():
        names.update({int(k): v for k, v in read_json(extra).items()})
    return names


def names_of(item_id):
    name = _names().get(int(item_id))
    return [name] if name else []


@lru_cache(maxsize=1)
def _attributes():
    return adapter().attributes()


def attributes_of(item_id):
    return dict(_attributes().get(int(item_id), {}))


@lru_cache(maxsize=2)
def floorchanges(any_kind=False):
    """{item id: north|south|east|west} for every item with a directional floorchange attribute (any_kind: also
    down, up and the rest)."""
    return {i: a["floorchange"] for i, a in _attributes().items()
            if a.get("floorchange") and (any_kind or a["floorchange"] in FLOORCHANGE_DIRS)}


@lru_cache(maxsize=1)
def items_otml():
    """{id: {offset-x, offset-y, opacity, invisible}}: per-type draw tweaks, when the adapter has any."""
    get = getattr(adapter(), "draw_tweaks", None)
    return get() if get else {}


# ---------------------------------------------------------------- families and kits

@lru_cache(maxsize=1)
def load_families():
    """Ground families and piece sets (tools/build_families.py writes study/families.json):
    {"grounds": {"G<lead>": {"lead", "members", "name"}}, "borders": {...}, "cliffs": {...}}."""
    if not FAMILIES.exists():
        raise SystemExit("study/families.json is missing: run  python -B run.py tools/build_families.py  first")
    fam = read_json(FAMILIES)
    fam.setdefault("borders", {})
    fam.setdefault("cliffs", {})
    sets = fam.setdefault("piece_sets", {})
    for key, b in fam["borders"].items():  # every border set, also as {piece: id}
        sets.setdefault(key, {"pieces": {name: ids[0][0] for name, ids in b["pieces"].items()}})
    for path in sorted((ROOT / "kit").glob("*.json")):  # and every named 12-piece set of every kit
        try:
            kit = read_json(path)
        except ValueError:
            continue
        for name, v in kit.items():
            if isinstance(v, dict) and "edge_n" in v and all(isinstance(i, int) and i for i in v.values()):
                sets.setdefault(f"K{path.stem}:{name}", {"pieces": v})
    return fam


def kit_name(name=None):
    """The kit to use: the one asked for, else $MAPSTUDIO_KIT, else config.json's "kit"."""
    return name or os.environ.get("MAPSTUDIO_KIT") or config().get("kit") or "example"


def load_kit(name=None):
    return read_json(ROOT / "kit" / f"{kit_name(name)}.json")


def kit_ids(kit, *keys):
    """Every item id under the given kit keys: a piece set's pieces, a ground's lead and members, ramp pairs."""
    out = set()
    for key in keys:
        v = kit.get(key) or {}
        if "lead" in v:
            out |= {v["lead"], *v.get("members", [])}
            continue
        for piece in v.values():
            out |= set(piece) if isinstance(piece, list) else {piece} if isinstance(piece, int) else set()
    return out


# ---------------------------------------------------------------- map areas

class Placed(int):
    """An item id on a map tile, carrying a per-placement pixel offset (when a format stores one).
    Behaves as a plain int everywhere else."""

    def __new__(cls, item_id, offset=(0, 0)):
        obj = super().__new__(cls, item_id)
        obj.offset = offset
        return obj

    def token(self):
        return f"{int(self)}@{self.offset[0]},{self.offset[1]}" if self.offset != (0, 0) else str(int(self))


def parse_token(token):
    if "@" in token:
        i, _, off = token.partition("@")
        ox, oy = off.split(",")
        return Placed(int(i), (int(ox), int(oy)))
    return int(token)


def iter_tiles(map_path=None, floors=None):
    """(z, x, y, [item ids bottom to top]) for every tile of a whole map (default: config.json's map)."""
    yield from adapter().tiles(map_path, None if floors is None else set(floors))


def read_area(map_path, x1, y1, x2, y2, floors=range(16)):
    """{z: {(x, y): [item ids bottom to top]}} for every tile inside the bounds."""
    floors = set(floors)
    result = {}
    for z, x, y, ids in adapter().tiles(map_path or None, floors, (x1, y1, x2, y2)):
        if x1 <= x <= x2 and y1 <= y <= y2 and ids:
            result.setdefault(z, {})[(x, y)] = ids
    return result


def save_area(path, area, meta):
    """Compact text form: one line per tile, 'z x y id id id'."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as f:
        f.write("# " + json.dumps(meta, sort_keys=True) + "\n")
        for z in sorted(area):
            for (x, y), ids in sorted(area[z].items(), key=lambda kv: (kv[0][1], kv[0][0])):
                f.write(f"{z} {x} {y} " + " ".join(i.token() if isinstance(i, Placed) else str(i) for i in ids) + "\n")


def load_area(path):
    meta, area = {}, {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            meta = json.loads(line[1:])
            continue
        parts = line.split()
        area.setdefault(int(parts[0]), {})[(int(parts[1]), int(parts[2]))] = [parse_token(t) for t in parts[3:]]
    return meta, area


def write_map(out_dir, area, name="Map Studio area"):
    """Writes an area as a map in the adapter's own format, when the adapter can (see docs/ADAPTERS.md)."""
    write = getattr(adapter(), "write_map", None)
    if not write:
        raise SystemExit("this adapter cannot write maps yet (docs/ADAPTERS.md: write_map)")
    return write(out_dir, area, name)


# ---------------------------------------------------------------- sprites

class SpriteCache:
    def __init__(self):
        self.images = {}

    def image(self, sprite_id):
        if not sprite_id:
            return None
        if sprite_id not in self.images:
            if len(self.images) > 200_000:
                self.images.clear()
            raw = adapter().sprite_rgba(sprite_id)
            self.images[sprite_id] = Image.frombytes("RGBA", (TILE, TILE), raw) if raw else None
        return self.images[sprite_id]


def item_image(obj, cache, x=0, y=0, phase=0, pattern=None):
    """The item drawn as one image, its bottom-right tile being the item's tile.
    Ground-style patterns follow the map position, as the client does."""
    g = obj["groups"][0]
    w, h = g["width"], g["height"]
    px = pattern[0] if pattern else x % g["patternX"]
    py = pattern[1] if pattern else y % g["patternY"]
    pz = pattern[2] if pattern else 0
    phase = phase % g["phases"]
    canvas = Image.new("RGBA", (w * TILE, h * TILE))
    for layer in range(min(g["layers"], 1)):
        for hh in range(h):
            for ww in range(w):
                idx = ((((((phase * g["patternZ"] + pz) * g["patternY"] + py) * g["patternX"] + px)
                         * g["layers"] + layer) * h + hh) * w + ww)
                sprite = cache.image(g["sprites"][idx])
                if sprite is not None:
                    canvas.alpha_composite(sprite, ((w - ww - 1) * TILE, (h - hh - 1) * TILE))
    return canvas


def displacement(obj):
    f = obj["flags"]
    return f.get("displacement_x", 0), f.get("displacement_y", 0)
