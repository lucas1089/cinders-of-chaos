#!/usr/bin/env python3
"""The images of the website's wiki (website/README.md "Wiki art"): an icon for every tab and entry, a hero image for
every guide and a banner for every reference tab.

Run:  python3 -I website/tools/gen_wiki_art.py            write every image (and remove ones nothing names any more)
      python3 -I website/tools/gen_wiki_art.py --check    exit 1 when a file differs from a fresh build (CI)
      python3 -I website/tools/gen_wiki_art.py --sheet OUT.png   a contact sheet of every icon (for review)

The list comes from the generated wiki data (website/overlay/plugins/chaos/wiki/wiki_data.json, written by
server/tools/gen_wiki_data.lua): the `icon` of every tab and entry, the `banner` and `tone` of every tab and
`art.guides` (hero file, emblem, icons, tone), `art.steps` (icons of the guide step diagrams). The Lua file decides
what shows what; this file only draws. Icon names (wiki/i/<name>.png, 48 x 48, items 64 x 64):
  k-<theme>-<glyph>    client/tools/gen_spell_icons.py `render` (our procedural spell icon kit)
  orb-<theme>-<glyph>  a glowing orb drawn here, with a kit glyph in it
  gem-<rrggbb>         a cut gem drawn here
  sp-<clientId>        client/overlay/data/images/game/spells_painted/<clientId>.png (gen_painted_icons.py)
  tr-<iconKey>         a cell of client/overlay/data/images/passivetree/painted_nodes.png (treedata/painted.lua)
  sup-<key>            client/overlay/data/images/game/supports/<key>.png (gen_support_icons.py)
  it-<set>-<kind>      a cell of client/tools/sprites/art_import/theme/items_<set>.png (theme_things.csv), 2x crisp
  top-<name>           client/overlay/data/images/chaos/topbutton_<name>.png (gen_theme_art.py)
  img/class-<key>.png  the class badges of website/tools/gen_site_art.py (not written here, only checked)
Heroes and banners (wiki/hero/*.webp, 960 x 300 and 960 x 180): the site's dark backdrop (gen_site_art.backdrop,
the client's login background), a haze in the tone, embers, a medallion with the emblem and the icons around it.
No text in the images (the page is in two languages), no screenshots: our client's screens show base sprites and
outfits that are not our own art.

Only our own art: the inputs above are procedural or our own paintings committed in the repository. Nothing is read
from outside it. Deterministic: the same inputs and library versions give the same bytes; CI runs --check with the
pinned Pillow and numpy of the other art checks (.github/workflows/ci.yml).
Needs Pillow (with WebP) and numpy.
"""
import csv
import io
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "client", "tools"))
sys.path.insert(0, HERE)
import gen_spell_icons as kit  # noqa: E402  (COL, GLYPH, render)
import gen_site_art as site  # noqa: E402  (backdrop, badge, divider, palette)

PLUGIN = os.path.join(REPO, "website", "overlay", "plugins", "chaos")
DATA = os.path.join(PLUGIN, "wiki", "wiki_data.json")
ASSETS = os.path.join(PLUGIN, "assets")
OUT_DIRS = ("wiki/i", "wiki/hero")
CLIENT = os.path.join(REPO, "client", "overlay", "data", "images")
ITEMS = os.path.join(REPO, "client", "tools", "sprites", "art_import")
PAINTED_LUA = os.path.join(REPO, "client", "overlay", "modules", "game_passivetree", "treedata", "painted.lua")

ICON = 48
ITEM = 64
S = 128  # work size of the drawn icons


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- sources
_CACHE = {}


def _open(path):
    if path not in _CACHE:
        _CACHE[path] = Image.open(path).convert("RGBA")
    return _CACHE[path]


def _painted_cells():
    if "painted" not in _CACHE:
        cells = {}
        with open(PAINTED_LUA, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if "= {file" in line:
                    key = line.split("=", 1)[0].strip()
                    nums = dict(p.strip().split(" = ") for p in line.split("{", 1)[1].rstrip("},").split(",")[1:])
                    cells[key] = (int(nums["x"]), int(nums["y"]), int(nums["w"]), int(nums["h"]))
        _CACHE["painted"] = cells
    return _CACHE["painted"]


def _item_cells():
    if "items" not in _CACHE:
        cells = {}
        with open(os.path.join(ITEMS, "theme_things.csv"), newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                if r["cat"] == "item" and r["atlas"].startswith("theme/items_"):
                    cells[r["key"]] = (r["atlas"], int(r["x"]), int(r["y"]))
        _CACHE["items"] = cells
    return _CACHE["items"]


def kit_glyph_mask(glyph, size):
    """A kit glyph alone, white on transparent, `size` px."""
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    kit.GLYPH[glyph](ImageDraw.Draw(g), (255, 255, 255, 255))
    return g.resize((size, size), Image.LANCZOS)


def draw_orb(theme, glyph):
    """A glowing orb of the theme's colour with the glyph etched in light."""
    c = np.array(kit.COL[theme], np.float32)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    cx = cy = (S - 1) / 2
    r = 46.0
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    # outer glow
    glow = np.clip(1 - (d - r) / 18, 0, 1) ** 2 * (d > r - 1)
    img = np.zeros((S, S, 4), np.float32)
    img[..., :3] = c
    img[..., 3] = glow * 150
    # the sphere: light from the upper left, dark rim
    inside = np.clip(r - d + 0.5, 0, 1)
    lx, ly = cx - 16, cy - 18
    lit = np.clip(1 - np.sqrt((xx - lx) ** 2 + (yy - ly) ** 2) / (r * 1.7), 0, 1)
    rim = np.clip(d / r, 0, 1) ** 3
    col = c[None, None, :] * (0.25 + 0.95 * lit[..., None]) * (1 - 0.55 * rim[..., None])
    col += 255 * (lit[..., None] ** 6) * 0.55
    a = inside[..., None]
    img[..., :3] = img[..., :3] * (1 - a) + np.clip(col, 0, 255) * a
    img[..., 3] = np.maximum(img[..., 3], inside * 255)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA")
    # the glyph: a dark shadow, then pale light
    m = kit_glyph_mask(glyph, 60)
    sh = Image.new("RGBA", m.size, (10, 6, 12, 0))
    sh.putalpha(m.getchannel("A").filter(ImageFilter.GaussianBlur(2)).point(lambda v: int(v * 0.8)))
    out.alpha_composite(sh, (35, 36))
    pale = Image.new("RGBA", m.size, tuple(int(min(255, v * 0.35 + 170)) for v in kit.COL[theme]) + (0,))
    pale.putalpha(m.getchannel("A").point(lambda v: int(v * 0.9)))
    out.alpha_composite(pale, (34, 34))
    # specular spot
    sp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sp).ellipse((38, 30, 56, 44), fill=(255, 255, 255, 150))
    out.alpha_composite(sp.filter(ImageFilter.GaussianBlur(3)))
    return out


def draw_gem(rgb):
    """A cut gem (an octagon with facets) of that colour, lit from the upper left."""
    c = np.array(rgb, np.float32)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((18, 18, S - 18, S - 18), fill=tuple(int(v) for v in c) + (120,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(12)))
    d = ImageDraw.Draw(img)
    cx = cy = S / 2
    outer = [(cx + 46 * math.cos(math.radians(a)), cy + 46 * math.sin(math.radians(a))) for a in range(-90, 270, 45)]
    inner = [(cx + 24 * math.cos(math.radians(a)), cy + 24 * math.sin(math.radians(a))) for a in range(-90, 270, 45)]
    shades = [1.25, 1.05, 0.8, 0.55, 0.45, 0.6, 0.85, 1.15]  # facet light, from the top clockwise
    for i in range(8):
        k = shades[i]
        col = tuple(int(min(255, v * k + (40 if k > 1.1 else 0))) for v in c) + (255,)
        d.polygon([outer[i], outer[(i + 1) % 8], inner[(i + 1) % 8], inner[i]], fill=col)
    d.polygon(inner, fill=tuple(int(min(255, v * 1.1 + 25)) for v in c) + (255,))
    d.polygon(outer, outline=(14, 8, 14, 255), width=3)
    for i in range(8):
        d.line([outer[i], inner[i]], fill=tuple(int(v * 0.4) for v in c) + (200,), width=1)
    spark = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(spark).polygon([(48, 34), (52, 46), (64, 50), (52, 54), (48, 66), (44, 54), (32, 50), (44, 46)],
                                  fill=(255, 255, 255, 210))
    img.alpha_composite(spark.filter(ImageFilter.GaussianBlur(0.8)))
    return img


def source_image(name):
    """The best source of an icon (any size, RGBA) and whether it is pixel art (scaled crisp)."""
    if name.startswith("img/class-"):
        return site.badge(name[len("img/class-"):-4], S), False
    base = os.path.basename(name)[:-4]
    kind, _, rest = base.partition("-")
    if kind == "k":
        theme, glyph = rest.split("-", 1)
        return kit.render(theme, glyph), False
    if kind == "orb":
        theme, glyph = rest.split("-", 1)
        return draw_orb(theme, glyph), False
    if kind == "gem":
        return draw_gem(hexrgb(rest)), False
    if kind == "sp":
        return _open(os.path.join(CLIENT, "game", "spells_painted", rest + ".png")), False
    if kind == "tr":
        x, y, w, h = _painted_cells()[rest]
        return _open(os.path.join(CLIENT, "passivetree", "painted_nodes.png")).crop((x, y, x + w, y + h)), False
    if kind == "sup":
        return _open(os.path.join(CLIENT, "game", "supports", rest + ".png")), False
    if kind == "it":
        atlas, x, y = _item_cells()[rest.replace("-", "_", 1)]
        return _open(os.path.join(ITEMS, atlas + ".png")).crop((x, y, x + 32, y + 32)), True
    if kind == "top":
        return _open(os.path.join(REPO, "client", "overlay", "data", "images", "chaos", "topbutton_" + rest + ".png")), False
    raise ValueError("unknown icon %r" % name)


def icon_at(name, size):
    im, crisp = source_image(name)
    if crisp:
        k = max(1, size // im.width)
        im = im.resize((im.width * k, im.height * k), Image.NEAREST)
        if im.width != size:
            im = im.resize((size, size), Image.LANCZOS)
        return im
    return im.resize((size, size), Image.LANCZOS)


def png_bytes(img):
    q = img.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    b = io.BytesIO()
    q.save(b, "PNG", optimize=True)
    return b.getvalue()


def webp_bytes(img):
    b = io.BytesIO()
    img.convert("RGB").save(b, "WEBP", quality=80, method=6)
    return b.getvalue()


# ---------------------------------------------------------------- scenes
def medallion(size, tone):
    """A dark disc with a gold rim and a glow of the tone, `size` across (with room for the glow)."""
    pad = size // 4
    n = size + 2 * pad
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    g = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse((pad - 10, pad - 10, n - pad + 10, n - pad + 10), fill=tone + (190,))
    im.alpha_composite(g.filter(ImageFilter.GaussianBlur(pad * 0.6)))
    d = ImageDraw.Draw(im)
    d.ellipse((pad, pad, n - pad, n - pad), fill=(8, 6, 9, 240))
    for i, col in enumerate((site.GOLD_1, site.GOLD_3, site.GOLD_2, site.GOLD_0)):
        d.ellipse((pad + i, pad + i, n - pad - i, n - pad - i), outline=tuple(int(v) for v in col) + (255,), width=1)
    d.ellipse((pad + 6, pad + 6, n - pad - 6, n - pad - 6), outline=tuple(int(v) for v in site.BLOOD_2) + (200,), width=1)
    return im, pad


def scene(spec, w, h, seed):
    tone = hexrgb(spec.get("tone") or "#d6c9ae")
    img = site.backdrop(w, h, focus_y=0.62, dark=0.62, seed=seed)
    a = np.asarray(img).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # a haze of the tone around the medallion, broken by smoke
    smoke = site.gta.fbm(h, w, max(30, w / 8), 4, seed + 7)
    haze = np.exp(-(((xx - w / 2) / (w * 0.34)) ** 2 + ((yy - h * 0.56) / (h * 0.55)) ** 2)) * (0.35 + 0.65 * smoke)
    a[..., :3] = a[..., :3] * (1 - 0.45 * haze[..., None]) + np.array(tone, np.float32) * 0.45 * haze[..., None]
    # fade into the page at the top and the bottom
    fade = np.clip(np.minimum(yy / (h * 0.18), (h - 1 - yy) / (h * 0.22)), 0, 1)
    a[..., :3] *= (0.25 + 0.75 * fade)[..., None]
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    rng = random.Random(seed)
    # embers
    sparks = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sparks)
    for _ in range(int(w * h / 3600)):
        x, y = rng.uniform(0, w), h * (1 - rng.random() ** 1.6)
        r = rng.choice((0.8, 1.0, 1.3, 1.8))
        mix = rng.random()
        col = tuple(int(tone[i] * mix + (255, 150, 60)[i] * (1 - mix)) for i in range(3))
        sd.ellipse((x - r, y - r, x + r, y + r), fill=col + (rng.randint(120, 230),))
    img.alpha_composite(sparks.filter(ImageFilter.GaussianBlur(1.2)))
    img.alpha_composite(sparks)
    # the icons around the medallion: half left, half right, lower towards the edges
    big = h > 200
    em = int(h * (0.44 if big else 0.5))
    isz = int(h * (0.24 if big else 0.28))
    icons = list(spec.get("icons") or [])
    left, right = icons[:(len(icons) + 1) // 2], icons[(len(icons) + 1) // 2:]
    cx, cy = w // 2, int(h * 0.52)
    room = w // 2 - em // 2 - 40 - isz - 24  # from the first icon's centre to the last one's, inside the picture
    most = max(len(left), len(right), 2) - 1
    step = min(isz + int(w * (0.045 if big else 0.03)), room // most)
    for side, group in ((-1, left), (1, right)):
        for k, name in enumerate(group):
            x = cx + side * (em // 2 + 40 + step * k + isz // 2)
            y = cy + int(6 * k * k) - (0 if big else 4)
            ic = icon_at(name, isz)
            sh = Image.new("RGBA", ic.size, (0, 0, 0, 0))
            sh.putalpha(ic.getchannel("A").filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.85)))
            fade_k = 1.0 - 0.12 * k
            if fade_k < 1:
                ic = ic.copy()
                ic.putalpha(ic.getchannel("A").point(lambda v, f=fade_k: int(v * f)))
            img.alpha_composite(sh, (x - isz // 2 + 3, y - isz // 2 + 5))
            img.alpha_composite(ic, (x - isz // 2, y - isz // 2))
    if spec.get("emblem"):
        med, pad = medallion(em, tone)
        img.alpha_composite(med, (cx - med.width // 2, cy - med.height // 2))
        ic = icon_at(spec["emblem"], int(em * 0.74))
        img.alpha_composite(ic, (cx - ic.width // 2, cy - ic.height // 2))
    site.divider(img, w // 2, h - 6, w // 2 - 40)
    return img


# ---------------------------------------------------------------- the build
def load_data():
    with open(DATA, encoding="utf-8") as f:
        return json.load(f)


def plan(data):
    """{relative path under assets/: (kind, spec)} of every image the data names."""
    out = {}
    icons = set()
    for t in data["tabs"]:
        icons.add(t["icon"])
        for e in t["entries"]:
            icons.add(e["icon"])
        seen, row = set(), []
        for e in t["entries"]:
            if e["icon"] not in seen and e["icon"] != t["icon"]:
                seen.add(e["icon"])
                row.append(e["icon"])
        # the banner: the tab's icon in the medallion, up to six of its entries' icons around it
        pick = [row[int(i * len(row) / 6)] for i in range(min(6, len(row)))] if len(row) > 6 else row
        out[t["banner"]] = ("banner", {"tone": t.get("tone"), "emblem": t["icon"], "icons": pick, "seed": t["id"]})
    art = data.get("art", {})
    for g in art.get("guides", []):
        icons.add(g["icon"])
        icons.update(g["icons"])
        out[g["hero"]] = ("hero", {"tone": g["tone"], "emblem": g["icon"], "icons": g["icons"], "seed": g["id"]})
    icons.update(art.get("steps", {}).values())
    for name in sorted(icons):
        if name.startswith("img/"):
            out[name] = ("existing", None)
        else:
            out[name] = ("icon", name)
    return out


def seed_of(text):
    return sum((i + 1) * ord(c) for i, c in enumerate(text)) % 10007


def render(kind, spec):
    if kind == "icon":
        size = ITEM if os.path.basename(spec).startswith("it-") else ICON
        return png_bytes(icon_at(spec, size))
    if kind == "hero":
        return webp_bytes(scene(spec, 960, 300, seed_of(spec["seed"])))
    if kind == "banner":
        return webp_bytes(scene(spec, 960, 180, seed_of(spec["seed"]) + 1))
    raise ValueError(kind)


def existing_files():
    out = set()
    for d in OUT_DIRS:
        full = os.path.join(ASSETS, d)
        if os.path.isdir(full):
            for f in os.listdir(full):
                out.add(d + "/" + f)
    return out


def build(check):
    data = load_data()
    want = plan(data)
    bad, total, written = [], 0, 0
    for rel, (kind, spec) in sorted(want.items()):
        path = os.path.join(ASSETS, rel)
        if kind == "existing":
            if not os.path.isfile(path):
                bad.append("missing %s (website/tools/gen_site_art.py writes it)" % rel)
            continue
        blob = render(kind, spec)
        total += len(blob)
        old = open(path, "rb").read() if os.path.isfile(path) else None
        if old != blob:
            if check:
                bad.append("stale " + rel)
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(blob)
                written += 1
    for rel in sorted(existing_files() - set(want)):
        if check:
            bad.append("not named by the wiki data: " + rel)
        else:
            os.remove(os.path.join(ASSETS, rel))
            print("removed " + rel)
    n = sum(1 for k, _ in want.values() if k != "existing")
    if check:
        if bad:
            print("\n".join(bad[:40]))
            print("wiki art is stale: run  python3 -I website/tools/gen_wiki_art.py")
            return 1
        print("wiki art up to date (%d images, %d KB)" % (n, total // 1024))
        return 0
    for b in bad:
        print(b)
    print("wiki art: %d images, %d written, %d KB" % (n, written, total // 1024))
    return 1 if bad else 0


def sheet(out):
    data = load_data()
    names = sorted(n for n, (k, _) in plan(data).items() if k in ("icon", "existing"))
    cols = 24
    rows = (len(names) + cols - 1) // cols
    im = Image.new("RGBA", (cols * 52, rows * 52), (20, 16, 20, 255))
    for i, n in enumerate(names):
        im.alpha_composite(icon_at(n, 48), ((i % cols) * 52 + 2, (i // cols) * 52 + 2))
    im.save(out)
    print("wrote %s (%d icons)" % (out, len(names)))
    return 0


def main(argv):
    if len(argv) > 2 and argv[1] == "--sheet":
        return sheet(argv[2])
    if len(argv) > 1 and argv[1] not in ("--check",):
        print(__doc__)
        return 2
    return build("--check" in argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
