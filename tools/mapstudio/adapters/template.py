"""Template for a new data adapter: copy to adapters/<name>.py, fill in each method, and set
"adapter": "<name>" in config.json. The interface and the flag names are described in docs/ADAPTERS.md;
adapters/otbm_dat.py is a complete example.
"""
from __future__ import annotations

from pathlib import Path


class Adapter:
    def __init__(self, cfg, root):
        self.cfg, self.root = cfg, Path(root)

    def path(self, key):
        """A config path, resolved against the studio folder when relative."""
        v = self.cfg.get(key)
        if not v:
            return None
        p = Path(v)
        return p if p.is_absolute() else self.root / p

    def items(self):
        """{map id: {"id": id, "flags": {flag name: value}, "groups": [{"width", "height", "layers", "patternX",
        "patternY", "patternZ", "phases", "sprites": [sprite id, ...]}]}} for every item a map can hold."""
        raise NotImplementedError

    def sprite_rgba(self, sprite_id):
        """32x32 RGBA pixels (4096 bytes) of one sprite, or None when it is empty."""
        raise NotImplementedError

    def names(self):
        """{item id: name}; return {} when the format has no names."""
        return {}

    def attributes(self):
        """{item id: {key: value}}; at least "floorchange" (north, south, east, west, down, up) for ramps."""
        return {}

    def tiles(self, map_path=None, floors=None, bounds=None):
        """Yields (z, x, y, [item ids bottom to top]) for every tile of the map (map_path None: the configured
        map), only on `floors` when given, and only in blocks touching bounds (x1, y1, x2, y2) when given."""
        raise NotImplementedError

    def index(self, map_path=None, log=print):
        """Optional: prepare a cache for tiles() (tools/index_map.py)."""
        log("this adapter needs no index")
