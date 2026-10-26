"""Groups ground items into families (variants of one ground) and collects border sets: study/families.json.

python -B run.py tools/build_families.py [--brushes <folder with grounds.xml and borders.xml>] [--count]

A family is "G<lead>": the ground ids a mapper lays mixed as one ground (grass and its variants). Sources, the
first that knows an id wins:
  1. study/family_overrides.json, written by hand: {"families": {"<name>": [ids...]}}.
  2. --brushes: a map editor's ground brushes (grounds.xml): one family per brush, and its borders (borders.xml)
     as piece sets "B<id>" (pieces named edge_n ... inner_se; check the naming with tools/name_set.py).
  3. --mix (needs the indexed map): grounds laid mixed with each other (each touches the other on at least
     --share of its edges) and of near-equal mean colour (--colour) are variants of one ground.
  4. items.xml names: ground ids with the same name.
  5. anything left: a family of its own.
--count reads the indexed reference map: each family's lead becomes its most used member, and the uses are
stored (families never laid on the map are kept, marked uses 0). --mix implies --count.
"""
from __future__ import annotations

import argparse
import re
from collections import Counter
from pathlib import Path

from common import FAMILIES, ROOT, iter_tiles, kind_of, load_items, names_of, read_json, write_json

# map editor border edge -> piece name, pieces named toward the region that draws them (docs/CONCEPTS.md).
# Editor "corner" pieces sit where the region is only on the diagonal; "diagonal" pieces where it is on two sides.
BRUSH_EDGES = {"n": "edge_n", "e": "edge_e", "s": "edge_s", "w": "edge_w",
             "cnw": "outer_nw", "cne": "outer_ne", "csw": "outer_sw", "cse": "outer_se",
             "dnw": "inner_nw", "dne": "inner_ne", "dsw": "inner_sw", "dse": "inner_se"}


def attrs(text):
    return dict(re.findall(r'([\w-]+)="([^"]*)"', text))


def brushes(folder):
    """(families {name: [ids]}, borders {"B<id>": {piece: id}}, brush borders {name: [border ids]})."""
    folder = Path(folder)
    families, borders, uses = {}, {}, {}
    text = (folder / "borders.xml").read_text(encoding="utf-8", errors="ignore") if (folder / "borders.xml").exists() else ""
    for m in re.finditer(r"<border\s+([^>]*)>(.*?)</border>", text, re.S):
        bid = attrs(m.group(1)).get("id")
        pieces = {}
        for item in re.finditer(r"<borderitem\s+([^>]*)/>", m.group(2)):
            a = attrs(item.group(1))
            if a.get("edge") in BRUSH_EDGES and a.get("item"):
                pieces[BRUSH_EDGES[a["edge"]]] = int(a["item"])
        if bid and pieces:
            borders[f"B{bid}"] = pieces
    text = (folder / "grounds.xml").read_text(encoding="utf-8", errors="ignore") if (folder / "grounds.xml").exists() else ""
    for m in re.finditer(r"<brush\s+([^>]*)>(.*?)</brush>", text, re.S):
        a = attrs(m.group(1))
        if a.get("type") != "ground" or not a.get("name"):
            continue
        ids = [int(attrs(i.group(1))["id"]) for i in re.finditer(r"<item\s+([^>]*)/>", m.group(2))
               if "id" in attrs(i.group(1))]
        if ids:
            families[a["name"]] = ids
        uses[a["name"]] = [f"B{attrs(b.group(1)).get('id')}" for b in re.finditer(r"<border\s+([^>]*)/>", m.group(2))
                           if attrs(b.group(1)).get("id")]
    return families, borders, uses


def scan(grounds):
    """(uses per ground id, orthogonal touches per (a, b) pair) over the indexed reference map, one 256-tile
    block at a time (pairs across block edges are not counted; that loses little)."""
    uses, touch = Counter(), Counter()
    block, here = None, {}

    def flush():
        for (x, y), g in here.items():
            for nb in ((x + 1, y), (x, y + 1)):
                h = here.get(nb)
                if h is not None and h != g:
                    touch[(g, h)] += 1
                    touch[(h, g)] += 1

    for z, x, y, ids in iter_tiles():
        g = int(ids[0])
        uses[g] += 1
        key = (z, x // 256, y // 256)
        if key != block:
            flush()
            block, here = key, {}
        if g in grounds:
            here[(x, y)] = g
    flush()
    return uses, touch


def mixed_groups(grounds, uses, touch, items, share, colour):
    """Union of grounds laid mixed and of near-equal mean colour."""
    from common import SpriteCache, item_image
    cache, mean = SpriteCache(), {}

    def colour_of(i):
        if i not in mean:
            img = item_image(items[i], cache).convert("RGBA")
            img = img.crop((img.width - 32, img.height - 32, img.width, img.height)).resize((1, 1), 4)
            mean[i] = img.getpixel((0, 0))[:3]
        return mean[i]

    edges = Counter()
    for (g, h), n in touch.items():
        edges[g] += n
    parent = {i: i for i in grounds}

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for (g, h), n in touch.items():
        if g < h and g in parent and h in parent and uses[g] >= 20 and uses[h] >= 20 \
                and n >= share * max(edges[g], edges[h]):
            if sum((p - q) ** 2 for p, q in zip(colour_of(g), colour_of(h))) ** 0.5 <= colour:
                parent[root(g)] = root(h)
    groups = {}
    for i in grounds:
        groups.setdefault(root(i), []).append(i)
    return [sorted(v, key=lambda i: -uses[i]) for v in groups.values() if len(v) > 1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--brushes", help="folder holding the map editor's grounds.xml and borders.xml")
    p.add_argument("--count", action="store_true", help="count uses on the indexed reference map")
    p.add_argument("--mix", action="store_true", help="group grounds laid mixed and of near-equal colour")
    p.add_argument("--share", type=float, default=0.1, help="--mix: share of edges two variants touch on")
    p.add_argument("--colour", type=float, default=24, help="--mix: largest mean RGB distance of variants")
    a = p.parse_args()
    items = load_items()
    grounds = {i for i, o in items.items() if kind_of(o["flags"]) == "ground"}
    a.count = a.count or a.mix
    uses, touch = scan(grounds) if a.count else (Counter(), Counter())
    named, owner = [], {}  # [(name, ids, source)], id -> index in named

    def add(name, ids, source):
        ids = [i for i in ids if i in items and i not in owner]
        if ids:
            for i in ids:
                owner[i] = len(named)
            named.append((name, ids, source))

    overrides = ROOT / "study" / "family_overrides.json"
    if overrides.exists():
        for name, ids in read_json(overrides).get("families", {}).items():
            add(name, ids, "override")
    borders, brush_borders = {}, {}
    if a.brushes:
        fams, borders, brush_borders = brushes(a.brushes)
        for name, ids in fams.items():
            add(name, ids, "brushes")
    if a.mix:
        for ids in mixed_groups(grounds, uses, touch, items, a.share, a.colour):
            add("", ids, "mix")
    by_name = {}
    for i in sorted(grounds):
        if i not in owner and names_of(i):
            by_name.setdefault(names_of(i)[0], []).append(i)
    for name, ids in by_name.items():
        add(name, ids, "name")
    for i in sorted(grounds):
        add("", [i], "single")

    out ={"grounds": {}, "borders": {}, "cliffs": {}}
    for name, ids, source in named:
        lead = max(ids, key=lambda i: (uses[i], -i)) if a.count else ids[0]
        entry = {"lead": lead, "members": ids, "name": name or (names_of(lead) or [f"ground {lead}"])[0],
                 "source": source}
        if a.count:
            entry["uses"] = sum(uses[i] for i in ids)
        if source == "brushes" and brush_borders.get(name):
            entry["borders"] = brush_borders[name]
        out["grounds"][f"G{lead}"] = entry
    for key, pieces in borders.items():
        out["borders"][key] = {"pieces": {piece: [[i, 0]] for piece, i in pieces.items()}, "from": "brushes"}
    write_json(FAMILIES, out)
    by_source = Counter(e["source"] for e in out["grounds"].values())
    print(f"{FAMILIES}: {len(out['grounds'])} ground families {dict(by_source)}, {len(out['borders'])} border sets")
    if a.count:
        top = sorted(out["grounds"].items(), key=lambda kv: -kv[1]["uses"])[:15]
        print("most used:", [(k, v["name"], v["uses"]) for k, v in top])


if __name__ == "__main__":
    main()
