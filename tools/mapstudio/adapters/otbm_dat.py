"""Adapter for standard OT data: an OTBM map, items.otb, items.xml and a Tibia.dat/.spr pair.

config.json keys used (paths may be absolute or relative to the studio folder):
    "items_otb":  items.otb of the server (server id <-> client id). Optional: without it, map ids are taken to be
                  client ids (the ids of the .dat).
    "items_xml":  items.xml of the server (names, floorchange and other attributes). Optional.
    "dat", "spr": the client's Tibia.dat and Tibia.spr.
    "dat_format": "auto" (default), "10.98", "8.60", "8.54", "8.60-extended" or "8.54-extended".
    "transparency": "auto" (default: a .otfi file beside the .dat, else a look at the sprites), true or false.
    "map":        the reference map, a .otbm file.
    "map_ids":    "server" (default; TFS and most servers) or "client" (maps with client ids).

The map is read once by `python -B run.py tools/index_map.py` into cache/map/ (per floor, 256x256 blocks), and
every tool then reads the cache. Item data and sprites are read directly (item data cached in cache/items.pickle).
"""
from __future__ import annotations

import gzip
import json
import mmap
import os
import pickle
import re
import struct
from pathlib import Path

BLOCK = 256

# ---------------------------------------------------------------- node files (OTBM, OTB)

NODE_START, NODE_END, ESCAPE = 0xFE, 0xFF, 0xFD
SPECIAL = re.compile(b"[\xfd\xfe\xff]")
OTBM_TILE_AREA, OTBM_TILE, OTBM_ITEM, OTBM_HOUSETILE = 4, 5, 6, 14
TILE_ATTR_ITEM = 9
# item attribute -> struct format of its value ("s" = string with a u16 length); used to skip item data
ITEM_ATTRIBUTES = {
    4: "<H", 5: "<H", 6: "s", 7: "s", 8: "<HHB", 10: "<H", 12: "<H", 14: "<B", 15: "<B", 16: "<I", 17: "<B",
    18: "<I", 19: "s", 20: "<I", 21: "<I", 22: "<H", 24: "s", 25: "s", 26: "s", 27: "<I", 28: "<i", 29: "<i",
    30: "<i", 31: "<i", 32: "<b", 33: "<B", 35: "<i", 36: "<H", 37: "<B", 38: "<I", 39: "<B",
}


class Node:
    __slots__ = ("type", "props", "children")

    def __init__(self, node_type):
        self.type = node_type
        self.props = b""
        self.children = []


def walk_nodes(data, start, on_node_end, keep_children_of):
    """Reads a node tree. Calls on_node_end(node, parent) for every finished node; a node is kept in its
    parent's children only when the parent's type is in keep_children_of."""
    stack, parts, segment, skip = [], [], None, -1
    for match in SPECIAL.finditer(data, start):
        index = match.start()
        if index == skip:
            continue  # this byte was escaped
        byte = data[index]
        if byte == ESCAPE:
            parts.append(data[segment:index])
            segment = index + 1
            skip = index + 1
            continue
        if stack and segment is not None:
            parts.append(data[segment:index])
            stack[-1].props = b"".join(parts)
        parts, segment = [], None
        if byte == NODE_START:
            stack.append(Node(data[index + 1]))
            segment = index + 2
        else:
            node = stack.pop()
            parent = stack[-1] if stack else None
            on_node_end(node, parent)
            if parent is not None and parent.type in keep_children_of:
                parent.children.append(node)
            if parent is None:
                return node
    raise ValueError("the file ends inside a node")


def read_otb_pairs(path):
    """[(server id, client id)] for every item of an items.otb file."""
    data = Path(path).read_bytes()
    pairs = []

    def on_node_end(node, parent):
        if parent is None:
            return
        p, pos = node.props, 4  # u32 flags first; the node type is the item group
        server_id = client_id = None
        while pos + 3 <= len(p):
            attribute, length = struct.unpack_from("<BH", p, pos)
            pos += 3
            if attribute == 0x10:
                server_id = struct.unpack_from("<H", p, pos)[0]
            elif attribute == 0x11:
                client_id = struct.unpack_from("<H", p, pos)[0]
            pos += length
        if server_id is not None and client_id:
            pairs.append((server_id, client_id))

    walk_nodes(data, 4, on_node_end, ())
    return pairs


# ---------------------------------------------------------------- Tibia.dat

SIMPLE_1098 = {
    0x01: "ground_border", 0x02: "on_bottom", 0x03: "on_top", 0x04: "container", 0x05: "stackable",
    0x07: "multi_use", 0x0A: "fluid_container", 0x0B: "splash", 0x0C: "not_walkable", 0x0D: "not_moveable",
    0x0E: "block_projectile", 0x0F: "not_pathable", 0x11: "pickupable", 0x12: "hangable", 0x13: "hook_south",
    0x14: "hook_east", 0x15: "rotateable", 0x17: "dont_hide", 0x18: "translucent", 0x1B: "lying_corpse",
    0x1C: "animate_always", 0x1F: "full_ground", 0x20: "ignore_look", 0x24: "wrapable", 0x25: "unwrapable",
}
FORMATS = {
    "10.98": {"extended": True, "durations": True, "frame_groups": True, "simple": SIMPLE_1098,
              "dropped": {0x06, 0x10, 0x26, 0xFE}, "dropped_u16": {0x08, 0x09, 0x21, 0x23},
              "light": 0x16, "displacement": 0x19, "elevation": 0x1A, "minimap": 0x1D, "lens_help": 0x1E,
              "market": 0x22, "bones": 0x27},
    "8.60": {"extended": False, "durations": False, "frame_groups": False,
             "simple": {0x01: "ground_border", 0x02: "on_bottom", 0x03: "on_top", 0x04: "container",
                        0x05: "stackable", 0x07: "multi_use", 0x0A: "fluid_container", 0x0B: "splash",
                        0x0C: "not_walkable", 0x0D: "not_moveable", 0x0E: "block_projectile", 0x0F: "not_pathable",
                        0x10: "pickupable", 0x11: "hangable", 0x12: "hook_south", 0x13: "hook_east",
                        0x14: "rotateable", 0x16: "dont_hide", 0x17: "translucent", 0x1A: "lying_corpse",
                        0x1B: "animate_always", 0x1E: "full_ground", 0x1F: "ignore_look"},
             "dropped": {0x06}, "dropped_u16": {0x08, 0x09, 0x20},
             "light": 0x15, "displacement": 0x18, "elevation": 0x19, "minimap": 0x1C, "lens_help": 0x1D,
             "market": 0x21, "bones": 0x27},
    "8.54": {"extended": False, "durations": False, "frame_groups": False,
             "simple": {0x01: "ground_border", 0x02: "on_bottom", 0x03: "on_top", 0x04: "container",
                        0x05: "stackable", 0x07: "multi_use", 0x0B: "fluid_container", 0x0C: "splash",
                        0x0D: "not_walkable", 0x0E: "not_moveable", 0x0F: "block_projectile", 0x10: "not_pathable",
                        0x11: "pickupable", 0x12: "hangable", 0x13: "hook_south", 0x14: "hook_east",
                        0x15: "rotateable", 0x17: "dont_hide", 0x1B: "lying_corpse", 0x1C: "animate_always",
                        0x1F: "full_ground", 0x20: "ignore_look", 0x24: "wrapable", 0x25: "unwrapable"},
             "dropped": {0x06, 0x08, 0x18}, "dropped_u16": {0x09, 0x0A},
             "light": 0x16, "displacement": 0x19, "elevation": 0x1A, "minimap": 0x1D, "lens_help": 0x1E,
             "market": None, "bones": 0x27},
}
FORMATS["8.60-extended"] = dict(FORMATS["8.60"], extended=True)
FORMATS["8.54-extended"] = dict(FORMATS["8.54"], extended=True)
CATEGORY_ITEM, CATEGORY_OUTFIT = 0, 1
FIRST_ITEM_ID = 100


class _Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, fmt):
        values = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += struct.calcsize(fmt)
        return values[0] if len(values) == 1 else values

    def u8(self):
        self.pos += 1
        return self.data[self.pos - 1]


def _flags(r, fmt):
    flags = {}
    while True:
        flag = r.u8()
        if flag == 0xFF:
            return flags
        if flag == 0x00:
            flags["ground_speed"] = r.take("<H")
        elif flag in fmt["simple"]:
            flags[fmt["simple"][flag]] = True
        elif flag in fmt["dropped"]:
            pass
        elif flag in fmt["dropped_u16"]:
            r.take("<H")
        elif flag == fmt["light"]:
            flags["light_intensity"], flags["light_color"] = r.take("<HH")
        elif flag == fmt["displacement"]:
            flags["displacement_x"], flags["displacement_y"] = r.take("<hh")
        elif flag == fmt["elevation"]:
            flags["elevation"] = r.take("<H")
        elif flag == fmt["minimap"]:
            flags["minimap_color"] = r.take("<H")
        elif flag == fmt["lens_help"]:
            r.take("<H")
        elif flag == fmt["market"]:
            r.take("<HHH")
            name_length = r.take("<H")  # read first: "r.pos += r.take()" keeps the old pos and drops the 2 bytes
            r.pos += name_length
            r.take("<HH")
        elif flag == fmt["bones"]:
            r.take("<8h")
        else:
            raise ValueError(f"unknown flag 0x{flag:02X}")


def _groups(r, category, fmt):
    groups = []
    count = r.u8() if fmt["frame_groups"] and category == CATEGORY_OUTFIT else 1
    for _ in range(count):
        if fmt["frame_groups"] and category == CATEGORY_OUTFIT:
            r.u8()
        width, height = r.u8(), r.u8()
        if width > 1 or height > 1:
            r.u8()  # exact size
        layers, px, py, pz, phases = r.take("<5B")
        if phases > 1 and fmt["durations"]:
            r.take("<Bib")
            r.pos += 8 * phases
        n = width * height * layers * px * py * pz * phases
        kind, size = ("I", 4) if fmt["extended"] else ("H", 2)
        sprites = list(struct.unpack_from(f"<{n}{kind}", r.data, r.pos))
        r.pos += size * n
        groups.append({"width": width, "height": height, "layers": layers, "patternX": px, "patternY": py,
                       "patternZ": pz, "phases": phases, "sprites": sprites})
    return groups


def read_dat(path, name="auto"):
    """(format name, {client id: {"flags", "groups"}}) for every item of a Tibia.dat."""
    data = Path(path).read_bytes()
    errors = []
    for candidate in (FORMATS if name == "auto" else [name]):
        fmt = FORMATS[candidate]
        r = _Reader(data)
        try:
            r.take("<I")
            counts = r.take("<4H")
            items = {}
            for category in range(4):
                for object_id in range(FIRST_ITEM_ID if category == CATEGORY_ITEM else 1, counts[category] + 1):
                    flags = _flags(r, fmt)
                    groups = _groups(r, category, fmt)
                    if category == CATEGORY_ITEM:
                        items[object_id] = {"flags": flags, "groups": groups}
            if r.pos != len(data):
                raise ValueError(f"{len(data) - r.pos} bytes left over")
            return candidate, items
        except (ValueError, IndexError, struct.error) as error:
            errors.append(f"as {candidate}: {error}")
    raise ValueError("the .dat reads as none of the known formats: " + "; ".join(errors))


# ---------------------------------------------------------------- Tibia.spr

class Sprites:
    """Sprite pixels from a Tibia.spr: image(sprite_id) -> 32x32 RGBA bytes or None."""

    def __init__(self, path, extended, transparency):
        self.file = open(path, "rb")
        self.data = mmap.mmap(self.file.fileno(), 0, access=mmap.ACCESS_READ)
        self.header = 8 if extended else 6
        self.count = struct.unpack_from("<I" if extended else "<H", self.data, 4)[0]
        self.alpha = transparency

    def rgba(self, sprite_id):
        if not 0 < sprite_id <= self.count:
            return None
        offset = struct.unpack_from("<I", self.data, self.header + 4 * (sprite_id - 1))[0]
        if offset == 0:
            return None
        size = struct.unpack_from("<H", self.data, offset + 3)[0]  # after the 3-byte colour key
        pos, end = offset + 5, offset + 5 + size
        out, pixel, step = bytearray(32 * 32 * 4), 0, 4 if self.alpha else 3
        while pos + 4 <= end and pixel < 1024:
            transparent, coloured = struct.unpack_from("<HH", self.data, pos)
            pos += 4
            pixel += transparent
            for _ in range(min(coloured, 1024 - pixel)):
                out[pixel * 4:pixel * 4 + 3] = self.data[pos:pos + 3]
                out[pixel * 4 + 3] = self.data[pos + 3] if self.alpha else 255
                pos += step
                pixel += 1
        return bytes(out)


def _transparency(cfg, dat, spr_path, extended):
    value = cfg.get("transparency", "auto")
    if value != "auto":
        return bool(value)
    for f in Path(dat).parent.glob("*.otfi"):
        for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
            key, _, v = line.strip().partition(":")
            if key.strip() == "transparency":
                return v.strip().lower() == "true"
    # no .otfi: try both pixel sizes on the first sprites and keep the one whose runs add up
    s = Sprites(spr_path, extended, False)
    fits = {3: 0, 4: 0}
    for k in range(1, min(s.count, 4000) + 1):
        offset = struct.unpack_from("<I", s.data, s.header + 4 * (k - 1))[0]
        if not offset:
            continue
        size = struct.unpack_from("<H", s.data, offset + 3)[0]
        for px in fits:
            pos, end, pixels = offset + 5, offset + 5 + size, 0
            while pos + 4 <= end:
                t, c = struct.unpack_from("<HH", s.data, pos)
                pos += 4 + c * px
                pixels += t + c
            fits[px] += pos == end and pixels <= 1024
    return fits[4] > fits[3]


# ---------------------------------------------------------------- the adapter

class Adapter:
    def __init__(self, cfg, root):
        self.cfg, self.root = cfg, Path(root)
        self.cache = self.root / "cache"
        self._sprites = None
        self._items = None

    def path(self, key):
        v = self.cfg.get(key)
        if not v:
            return None
        p = Path(v)
        return p if p.is_absolute() else self.root / p

    # items --------------------------------------------------------
    def _server_of(self):
        """{client id: [server ids]} from items.otb, or None when there is none (map ids are client ids)."""
        otb = self.path("items_otb")
        if not otb or self.cfg.get("map_ids") == "client":
            return None
        out = {}
        for server_id, client_id in read_otb_pairs(otb):
            out.setdefault(client_id, []).append(server_id)
        return out

    def items(self):
        """{map id: {"id", "flags", "groups"}}: item data keyed by the ids the map stores."""
        if self._items is not None:
            return self._items
        dat = self.path("dat")
        stamp = [str(dat), os.path.getmtime(dat), str(self.path("items_otb")), self.cfg.get("map_ids", "server")]
        cached = self.cache / "items.pickle"
        if cached.exists():
            with open(cached, "rb") as f:
                saved = pickle.load(f)
            if saved["stamp"] == stamp:
                self._items, self._format = saved["items"], saved["format"]
                return self._items
        fmt, by_client = read_dat(dat, self.cfg.get("dat_format", "auto"))
        servers = self._server_of()
        items = {}
        for client_id, obj in by_client.items():
            for map_id in (servers.get(client_id, []) if servers is not None else [client_id]):
                items[map_id] = {"id": map_id, "client_id": client_id, **obj}
        self.cache.mkdir(parents=True, exist_ok=True)
        with open(cached, "wb") as f:
            pickle.dump({"stamp": stamp, "items": items, "format": fmt}, f)
        self._items, self._format = items, fmt
        return items

    def sprite_rgba(self, sprite_id):
        if self._sprites is None:
            self.items()
            extended = FORMATS[self._format]["extended"]
            spr = self.path("spr")
            self._sprites = Sprites(spr, extended, _transparency(self.cfg, self.path("dat"), spr, extended))
        return self._sprites.rgba(sprite_id)

    def _xml(self):
        path = self.path("items_xml")
        return path.read_text(encoding="utf-8", errors="ignore") if path and path.exists() else ""

    def names(self):
        out = {}
        for m in re.finditer(r'<item\s+([^>]*?)/?>', self._xml()):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
            if not attrs.get("name"):
                continue
            for i in _ids(attrs):
                out[i] = attrs["name"]
        return out

    def attributes(self):
        out = {}
        for m in re.finditer(r'<item\s+([^>]*?)(/>|>(.*?)</item>)', self._xml(), re.S):
            found = dict(re.findall(r'<attribute\s+key="([^"]+)"\s+value="([^"]*)"', m.group(3) or ""))
            if found:
                for i in _ids(dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))):
                    out.setdefault(i, {}).update(found)
        return out

    # map ------------------------------------------------------------
    def map_dir(self, map_path=None):
        src = Path(map_path) if map_path else self.path("map")
        return self.cache / "map" / re.sub(r"[^\w.-]", "_", src.stem), src

    def index(self, map_path=None, log=print):
        """Splits the OTBM into cache/map/<name>/z<z>_<bx>_<by>.txt.gz blocks: 'x y id id ...' per tile."""
        folder, src = self.map_dir(map_path)
        folder.mkdir(parents=True, exist_ok=True)
        for old in folder.glob("*.txt.gz"):
            old.unlink()
        data = src.read_bytes()
        if data[4:5] != bytes([NODE_START]):
            raise ValueError(f"{src} is not an OTBM file")
        counts = {}

        def item_id(node):
            return struct.unpack_from("<H", node.props, 0)[0]

        def on_node_end(node, parent):
            if node.type != OTBM_TILE_AREA:
                return
            bx, by, z = struct.unpack_from("<HHB", node.props)
            lines = {}
            for tile in node.children:
                if tile.type not in (OTBM_TILE, OTBM_HOUSETILE):
                    continue
                p, pos = tile.props, 2
                x, y = bx + p[0], by + p[1]
                if tile.type == OTBM_HOUSETILE:
                    pos += 4
                ids = []
                while pos < len(p):
                    attribute = p[pos]
                    pos += 1
                    if attribute == TILE_ATTR_ITEM:
                        ids.append(struct.unpack_from("<H", p, pos)[0])
                        pos += 2
                    elif attribute == 3:  # tile flags
                        pos += 4
                    else:
                        break
                ids += [item_id(c) for c in tile.children if c.type == OTBM_ITEM]
                if ids:
                    key = (z, x // BLOCK, y // BLOCK)
                    lines.setdefault(key, []).append(f"{x} {y} " + " ".join(map(str, ids)))
            node.children = []
            for (z, cx, cy), rows in lines.items():
                with gzip.open(folder / f"z{z}_{cx}_{cy}.txt.gz", "at", encoding="ascii") as f:
                    f.write("\n".join(rows) + "\n")
                counts[z] = counts.get(z, 0) + len(rows)

        walk_nodes(data, 4, on_node_end, (OTBM_TILE_AREA, OTBM_TILE, OTBM_HOUSETILE))
        (folder / "index.json").write_text(json.dumps({"source": str(src), "tiles_per_floor": counts}, indent=1),
                                           encoding="utf-8")
        log(f"{folder}: {sum(counts.values())} tiles, per floor {dict(sorted(counts.items()))}")
        return folder

    def _blocks(self, map_path=None):
        folder, src = self.map_dir(map_path)
        if not (folder / "index.json").exists():
            raise SystemExit(f"the map is not indexed yet: run  python -B run.py tools/index_map.py  ({src})")
        for f in folder.glob("z*.txt.gz"):
            z, cx, cy = map(int, f.name[1:-7].split("_"))
            yield z, cx, cy, f

    def tiles(self, map_path=None, floors=None, bounds=None):
        """(z, x, y, [ids]) for every tile; bounds = (x1, y1, x2, y2) to read only the blocks it needs."""
        for z, cx, cy, f in self._blocks(map_path):
            if floors is not None and z not in floors:
                continue
            if bounds and (cx * BLOCK > bounds[2] or (cx + 1) * BLOCK <= bounds[0]
                           or cy * BLOCK > bounds[3] or (cy + 1) * BLOCK <= bounds[1]):
                continue
            with gzip.open(f, "rt", encoding="ascii") as rows:
                for row in rows:
                    v = row.split()
                    yield z, int(v[0]), int(v[1]), [int(i) for i in v[2:]]


def _ids(attrs):
    if "id" in attrs:
        return [int(attrs["id"])]
    if "fromid" in attrs and "toid" in attrs:
        return range(int(attrs["fromid"]), int(attrs["toid"]) + 1)
    return []
