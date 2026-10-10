#!/usr/bin/env python3
"""Survey of the outfit art we already have, for the class looks.

    python3 -I client/tools/outfit_art/survey.py live    --pair PAIR --server BASE_SERVER_DIR
    python3 -I client/tools/outfit_art/survey.py donors  --library LIBRARY_DIR
    python3 -I client/tools/outfit_art/survey.py board   --pair PAIR --line warrior --looks 131,139,...

live: every outfit look type of the pair, south-facing and standing in the client's default colours, on contact
sheets (1x and 2x pages, id labels) with a colour band for what already uses it (class look, store, season, achievement,
donor class outfit, mount, monster or NPC, staff, the base server's player list) and out/survey/live_usage.csv.
donors: the player-style outfits (2 layers: art + colour template, 4 directions, 3 addon patterns) of each donor
library, with the catalogue's tags. board: candidates of a class line side by side (south, east, north, west).
Output in client/tools/outfit_art/out/survey/ (not committed).
"""
import argparse
import csv
import glob
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, HERE)
import rig  # noqa: E402
import stockread  # noqa: E402
from build import ash_ground  # noqa: E402

OUT = os.path.join(HERE, "out", "survey")
DEFAULT = (78, 69, 58, 76)
CHAOS = os.path.join(REPO, "server", "data", "scripts", "chaos")

TAGS = [  # (tag, band colour), in priority order for the band
    ("class", (230, 80, 40)), ("donorclass", (240, 150, 40)), ("store", (80, 160, 240)), ("season", (200, 90, 220)),
    ("achievement", (240, 220, 60)), ("staff", (255, 255, 255)), ("mount", (120, 120, 120)),
    ("addons", (60, 120, 200)), ("player", (90, 200, 90)), ("monster", (150, 60, 60)), ("npc", (150, 110, 60)), ("unused", (40, 40, 40)),
]
BAND = dict(TAGS)


# ------------------------------------------------------------------------------------------------ who uses what
def nums(pattern, text):
    return [int(x) for x in re.findall(pattern, text)]


def usage(server):
    use = {}

    def add(t, tag, why):
        use.setdefault(t, {}).setdefault(tag, set()).add(why)
    txt = open(os.path.join(CHAOS, "class_looks_core.lua")).read()
    for name, m, f in re.findall(r'name = "([^"]+)", male = (\d+), female = (\d+)', txt):
        add(int(m), "class", name)
        add(int(f), "class", name)
    txt = open(os.path.join(CHAOS, "chaos_constants.lua")).read()
    blk = txt[txt.index("\toutfits = (function()"):]
    blk = blk[:blk.index("end)()")]
    for t, n in re.findall(r'lookType = (\d+), name = "([^"]+)"', blk):
        add(int(t), "donorclass", n)
    txt = open(os.path.join(CHAOS, "shop_cosmetics.lua")).read()
    outf, rest = txt.split("\taddons = {", 1)
    for a, b, n in re.findall(r'looktype = (\d+), lookfemale = (\d+), name = "([^"]+)"', outf):
        add(int(a), "store", n)
        add(int(b), "store", n)
    for a, b, n in re.findall(r'looktype = (\d+), lookfemale = (\d+), name = "([^"]+)"', rest.split("mounts = {")[0]):
        add(int(a), "addons", n + " (outfit free to all, addons sold)")
        add(int(b), "addons", n + " (outfit free to all, addons sold)")
    for f in ("shop_config.lua", "pets_config.lua"):
        txt = open(os.path.join(CHAOS, f)).read()
        for t in nums(r'"outfit:(\d+)"', txt) + nums(r'look = (\d+)', txt):
            add(t, "store", f)
    for f, tag in (("seasonpass_config.lua", "season"), ("season_config.lua", "season"),
                   ("achievements_data.lua", "achievement")):
        txt = open(os.path.join(CHAOS, f)).read()
        for a, b in re.findall(r'male = (\d+), female = (\d+)', txt) + [(y, x) for x, y in re.findall(r'female = (\d+), male = (\d+)', txt)]:
            add(int(a), tag, f)
            add(int(b), tag, f)
    data = os.path.join(server, "data")
    ox = open(os.path.join(data, "XML", "outfits.xml"), encoding="utf-8", errors="replace").read()
    for t, n, prem in re.findall(r'looktype="(\d+)" name="([^"]+)" premium="(\w+)"', ox):
        add(int(t), "player", "%s%s" % (n, " (premium)" if prem == "yes" else ""))
    mx = open(os.path.join(data, "XML", "mounts.xml"), encoding="utf-8", errors="replace").read()
    for t, n in re.findall(r'clientid="(\d+)" name="([^"]+)"', mx):
        add(int(t), "mount", n)
    for t in (75, 266, 302):
        add(t, "staff", "gamemaster / tutor / god look")
    for root, tag in ((os.path.join(data, "monster"), "monster"), (os.path.join(REPO, "server", "data", "monster"), "monster"),
                      (os.path.join(data, "npc"), "npc")):
        for p in glob.glob(os.path.join(root, "**", "*.*"), recursive=True):
            if not p.endswith((".xml", ".lua")):
                continue
            t = open(p, encoding="utf-8", errors="replace").read()
            for x in nums(r'(?i)look ?type ?[=:]? ?"?(\d+)', t):
                add(x, tag, os.path.basename(p))
    for p in glob.glob(os.path.join(REPO, "server", "data", "items", "*outfits*.csv")):
        for row in csv.DictReader(open(p)):
            if row.get("look_type"):
                add(int(row["look_type"]), "monster", os.path.basename(p))
    return use


def main_tag(u):
    for tag, _ in TAGS:
        if tag in u:
            return tag
    return "unused"


# ------------------------------------------------------------------------------------------------ drawing
def outfit_img(F, d=2, z=0, addons=0, cols=DEFAULT):
    """The outfit as the client draws it standing: base layer + addons, tinted by the template."""
    keys = [k for k in F if k[0] == 0 and k[1] == 0]
    if not keys:
        return None
    nd = max(k[2] for k in keys) + 1
    d = d if nd >= 4 else 0
    layers = max(k[5] for k in keys) + 1
    W = F[keys[0]].shape
    out = np.zeros(W, np.uint8)
    for a in range(addons + 1):
        base = F.get((0, 0, d, a, min(z, max(k[4] for k in keys)), 0))
        if base is None:
            continue
        if layers > 1:
            base = rig.colourize(base, F[(0, 0, d, a, min(z, max(k[4] for k in keys)), 1)], *cols)
        m = base[..., 3] > 0
        out[m] = base[m]
    return out


def fit(img, cell):
    """Bottom-right anchored as the client draws; bigger looks shrink to the cell."""
    im = Image.fromarray(img, "RGBA")
    if im.width > cell:
        im = im.resize((cell, cell), Image.NEAREST if im.width % cell == 0 else Image.BILINEAR)
    c = Image.new("RGBA", (cell, cell))
    c.alpha_composite(im, (cell - im.width, cell - im.height))
    return c


def sheet(cells, cols, zoom, path, cell=64, label_h=11):
    """cells: [(img or None, label, band colour)]"""
    rows = (len(cells) + cols - 1) // cols
    cw, ch = cell * zoom + 2, cell * zoom + label_h + 4
    out = Image.new("RGBA", (cols * cw + 2, rows * ch + 2), (22, 20, 20, 255))
    dr = ImageDraw.Draw(out)
    for i, (img, lab, band) in enumerate(cells):
        x, y = 2 + (i % cols) * cw, 2 + (i // cols) * ch
        g = ash_ground(cell, cell)
        if img is not None:
            g.alpha_composite(fit(img, cell))
        out.alpha_composite(g.resize((cell * zoom, cell * zoom), Image.NEAREST), (x, y + label_h + 2))
        dr.rectangle((x, y, x + cell * zoom - 1, y + label_h), fill=band)
        dr.text((x + 2, y), lab, fill=(0, 0, 0) if sum(band) > 300 else (235, 230, 220))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.convert("RGB").save(path)
    print(path)


def legend(path):
    out = Image.new("RGB", (190, 14 * len(TAGS) + 4), (22, 20, 20))
    dr = ImageDraw.Draw(out)
    for i, (t, c) in enumerate(TAGS):
        dr.rectangle((2, 2 + i * 14, 14, 13 + i * 14), fill=c)
        dr.text((20, 2 + i * 14), t, fill=(235, 230, 220))
    out.save(path)


# ------------------------------------------------------------------------------------------------ commands
def cmd_live(pair, server):
    d, s = stockread.load(pair)
    use = usage(server)
    rows, cells, player_cells = [], [], []
    for t in range(1, len(d.outfits) + 1):
        th = d.outfit(t)
        F = stockread.frames(d, s, t, idle_only=True)
        img = outfit_img(F)
        empty = img is None or not img[..., 3].any()
        u = use.get(t, {})
        tag = main_tag(u) if not empty else "unused"
        playerlike = (th.layers == 2 and th.px == 4 and th.py == 3)
        rows.append([t, "%dx%d" % (th.w, th.h), th.layers, th.px, th.py, th.pz, int(empty), int(playerlike), tag,
                     "; ".join("%s: %s" % (k, ", ".join(sorted(v))[:80]) for k, v in sorted(u.items()))])
        if empty:
            continue
        cells.append((img, str(t), BAND[tag]))
        if playerlike:
            player_cells.append((img, "%d %s" % (t, tag[:5]), BAND[tag]))
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "live_usage.csv"), "w", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["look_type", "size", "layers", "dirs", "addon_patterns", "mount_patterns", "empty", "player_layout", "tag", "used_by"])
        w.writerows(rows)
    legend(os.path.join(OUT, "legend.png"))
    per = 300
    for p in range(0, len(cells), per):
        sheet(cells[p:p + per], 20, 1, os.path.join(OUT, "live_all_%02d_1x.png" % (p // per + 1)))
    per = 120
    for p in range(0, len(player_cells), per):
        sheet(player_cells[p:p + per], 12, 2, os.path.join(OUT, "live_player_%02d_2x.png" % (p // per + 1)))
        sheet(player_cells[p:p + per], 12, 1, os.path.join(OUT, "live_player_%02d_1x.png" % (p // per + 1)))
    print("outfits %d, drawn %d, player layout %d" % (len(d.outfits), len(cells), len(player_cells)))


def cmd_donors(library):
    for lib in sorted(glob.glob(os.path.join(library, "donor*", "catalogue.csv"))):
        name = os.path.basename(os.path.dirname(lib))
        rows = [r for r in csv.DictReader(open(lib)) if r["category"] == "outfit" and r["frames"].startswith("L2P4")]
        if not rows:
            continue
        d, s = stockread.load(os.path.dirname(lib))
        cells = []
        for r in rows:
            t = int(r["lib_id"])
            img = outfit_img(stockread.frames(d, s, t, idle_only=True))
            if img is None or not img[..., 3].any():
                continue
            tagged = "named" in r["description"] or "library only" in r["description"]
            cells.append((img, "%s %d%s" % (name[-1], t, " X" if tagged else ""), (150, 40, 40) if tagged else (60, 110, 60)))
        per = 120
        for p in range(0, len(cells), per):
            sheet(cells[p:p + per], 12, 2, os.path.join(OUT, "donor_%s_%02d_2x.png" % (name, p // per + 1)))
        print(name, len(cells))


def cmd_board(pair, looks, names, path, extra=None):
    """Each look in 4 directions (south, east, north, west), 1x row on top, 3x below."""
    d, s = stockread.load(pair)
    cells = []
    for t, n in zip(looks, names):
        F = stockread.frames(d, s, t, idle_only=True) if isinstance(t, int) else None
        for di in (2, 1, 0, 3):
            img = outfit_img(F, d=di) if F is not None else t[di]
            cells.append((img, n if di == 2 else "", (60, 60, 60)))
    sheet(cells, 8, 1, path.replace(".png", "_1x.png"), label_h=0)
    sheet(cells, 8, 3, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("--pair")
    ap.add_argument("--server")
    ap.add_argument("--library")
    a = ap.parse_args()
    if a.cmd == "live":
        cmd_live(a.pair, a.server)
    elif a.cmd == "donors":
        cmd_donors(a.library)
    elif a.cmd == "final":
        cmd_finalboards(a.pair)
    elif a.cmd == "boards":
        cmd_lineboards(a.pair, a.library)
    else:
        raise SystemExit(__doc__)



# ------------------------------------------------------------------------------------------------ boards per class line
# (label, source, look): source "L" the live pair, a donor letter (library/donorX), or "G" our generated frames
# (look = "<class>_<sex>"). Picked by eye from the contact sheets; the owner judges.
LINE_BOARDS = {
    "warrior": [
        ("now Warrior M/F", "L", 131), ("", "L", 139), ("now Juggernaut", "L", 633), ("", "L", 632),
        ("now Berserker", "L", 919), ("", "L", 920),
        ("ours Warrior", "G", "warrior_male"), ("ours Juggernaut", "G", "juggernaut_male"), ("ours Berserker", "G", "berserker_male"),
        ("live 1455 unused", "L", 1455), ("live 1456 unused", "L", 1456), ("live 1009 monster", "L", 1009),
        ("live 1011 monster", "L", 1011), ("live 1060 monster", "L", 1060),
        ("D744", "D", 744), ("D245", "D", 245), ("D246", "D", 246), ("D1033", "D", 1033), ("D383", "D", 383),
        ("F11", "F", 11), ("F12", "F", 12), ("J27", "J", 27), ("J125", "J", 125), ("Q71", "Q", 71), ("Q72", "Q", 72),
        ("Q73", "Q", 73), ("Q58", "Q", 58), ("D60", "D", 60),
    ],
    "ranger": [
        ("now Ranger M/F", "L", 684), ("", "L", 683), ("now Deadeye", "L", 915), ("", "L", 916),
        ("now Beastmaster", "L", 637), ("", "L", 636),
        ("live 1001 monster", "L", 1001), ("live 1002 monster", "L", 1002), ("live 1457 unused", "L", 1457),
        ("live 1458 unused", "L", 1458), ("D981", "D", 981), ("D1039", "D", 1039), ("D1040", "D", 1040),
        ("H65", "H", 65), ("J81", "J", 81), ("D735", "D", 735), ("D761", "D", 761), ("H69", "H", 69),
    ],
    "mystic": [
        ("now Mystic M/F", "L", 130), ("", "L", 138), ("now Elementalist", "L", 925), ("", "L", 926),
        ("now Illusionist", "L", 634), ("", "L", 635),
        ("live 1019 monster", "L", 1019), ("live 1028 monster", "L", 1028), ("H133", "H", 133), ("H134", "H", 134),
        ("J32", "J", 32), ("J50", "J", 50), ("D182", "D", 182), ("D292", "D", 292), ("D593", "D", 593),
        ("D1118", "D", 1118), ("J43", "J", 43), ("D829", "D", 829),
    ],
    "thief": [
        ("now Thief M/F", "L", 913), ("", "L", 914), ("now Ninja", "L", 1206), ("", "L", 1205),
        ("now Samurai", "L", 921), ("", "L", 922),
        ("donor 1505", "L", 1505), ("donor 1506", "L", 1506), ("donor 1508", "L", 1508), ("donor 1510", "L", 1510),
        ("J70", "J", 70), ("J71", "J", 71), ("H70", "H", 70), ("H71", "H", 71), ("D531", "D", 531), ("D532", "D", 532),
        ("D219", "D", 219), ("D220", "D", 220), ("live 1007 monster", "L", 1007),
    ],
    "necromancer": [
        ("now Necromancer M/F", "L", 699), ("", "L", 698), ("now Lich", "L", 923), ("", "L", 924),
        ("now Bone Lord", "L", 697), ("", "L", 696),
        ("H225", "H", 225), ("H226", "H", 226), ("D626", "D", 626), ("J157", "J", 157), ("J158", "J", 158),
        ("D939", "D", 939), ("J18", "J", 18), ("F224", "F", 224), ("Q59", "Q", 59), ("live 1010 monster", "L", 1010),
    ],
    "monk": [
        ("now Monk M/F", "L", 911), ("", "L", 912), ("now Shadowfist", "L", 1373), ("", "L", 1372),
        ("now Iron Sage", "L", 853), ("", "L", 852),
        ("live 1464 unused", "L", 1464), ("live 1465 unused", "L", 1465), ("live 1374 npc", "L", 1374),
        ("D1001", "D", 1001), ("D1015", "D", 1015), ("J72", "J", 72), ("H86", "H", 86), ("D760", "D", 760),
        ("D976", "D", 976), ("C773", "C", 773),
    ],
    "templar": [
        ("now Templar M/F", "L", 984), ("", "L", 985), ("now Inquisitor", "L", 1014), ("", "L", 1015),
        ("now Sentinel", "L", 1188), ("", "L", 1189),
        ("J20", "J", 20), ("J63", "J", 63), ("J64", "J", 64), ("J65", "J", 65), ("D745", "D", 745), ("D747", "D", 747),
        ("H176", "H", 176), ("H177", "H", 177), ("J17", "J", 17), ("D1188", "D", 1188), ("live 1488 monster", "L", 1488),
    ],
}


def cmd_lineboards(pair, library, lines=None):
    import build
    cache = {}

    def src(s):
        if s not in cache:
            cache[s] = stockread.load(pair if s == "L" else os.path.join(library, "donor" + s))
        return cache[s]
    for line, entries in LINE_BOARDS.items():
        if lines and line not in lines:
            continue
        cells = []
        for lab, s, look in entries:
            if s == "G":
                cls, sx = look.rsplit("_", 1)
                idle, _ = build.load_frames(cls, sx)
                imgs = [build.tinted(idle[0, 0, d, 0], idle[0, 0, d, 1], DEFAULT) for d in (2, 1, 0, 3)]
            else:
                d, sp = src(s)
                F = stockread.frames(d, sp, look, idle_only=True)
                imgs = [outfit_img(F, d=di) for di in (2, 1, 0, 3)]
            for i, im in enumerate(imgs):
                cells.append((im, lab if i == 0 else "", (60, 60, 60) if s != "G" else (120, 60, 30)))
        sheet(cells, 8, 1, os.path.join(OUT, "board_%s_1x.png" % line), label_h=0)
        sheet(cells, 8, 3, os.path.join(OUT, "board_%s_3x.png" % line))


# ------------------------------------------------------------------------------------------------ final boards
LINES_ORDER = [("Warrior", (4, 8, 14)), ("Ranger", (3, 7, 15)), ("Mystic", (1, 5, 10)), ("Thief", (11, 12, 13)),
               ("Monk", (17, 18, 19)), ("Necromancer", (20, 21, 22)), ("Templar", (23, 24, 25))]
COLOUR_SETS = [((0, 114, 95, 114), "ash & blood"), ((95, 76, 57, 114), "ember"), ((114, 87, 86, 95), "iron & bone")]


def class_looks():
    text = open(os.path.join(CHAOS, "class_looks_core.lua")).read()
    block = re.search(r"L\.looks = \{(.*?)\n\}", text, re.S).group(1)
    return {int(v): (n, int(m), int(f)) for v, n, m, f in
            re.findall(r'\[(\d+)\] = \{name = "([^"]+)", male = (\d+), female = (\d+)\}', block)}


def walk_imgs(F, d, cols=DEFAULT):
    keys = sorted({k[1] for k in F if k[0] == 1})
    out = []
    for ph in keys:
        G = {(0, 0) + k[2:]: v for k, v in F.items() if k[0] == 1 and k[1] == ph}
        out.append(outfit_img(G, d=d, cols=cols))
    return out


def cmd_finalboards(pair):
    d, sp = stockread.load(pair)
    looks = class_looks()
    for line, vocs in LINES_ORDER:
        cells = []
        for v in vocs:
            name, m, f = looks[v]
            for sex, look in (("M", m), ("F", f)):
                F = stockread.frames(d, sp, look)
                row = [(outfit_img(F, d=di), "%s %s %d" % (name.replace(" Class", ""), sex, look) if di == 2 else "", (60, 60, 60))
                       for di in (2, 1, 0, 3)]
                wk = walk_imgs(F, 2)
                for i in range(4):
                    row.append((wk[(i * len(wk)) // 4] if wk else None, "walk" if i == 0 else "", (45, 70, 45)))
                for cols, cname in COLOUR_SETS:
                    row.append((outfit_img(F, d=2, cols=cols), cname, (70, 45, 45)))
                cells += row
        sheet(cells, 11, 1, os.path.join(OUT, "final_%s_1x.png" % line.lower()), label_h=0)
        sheet(cells, 11, 3, os.path.join(OUT, "final_%s_3x.png" % line.lower()))


if __name__ == "__main__":
    main()
