#!/usr/bin/env python3
"""Tests of class_art.py / class_art_line.py (no real pair needed; a few low-resolution renders).

python3 -I client/tools/outfit_art/class_art_test.py      (numpy and Pillow: system packages, python3-numpy python3-pil)
"""
import csv
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(os.path.dirname(HERE), "sprites")
sys.path.insert(0, HERE)
sys.path.insert(0, SPRITES)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import class_art as CA  # noqa: E402
import class_art_line as L  # noqa: E402
import rig  # noqa: E402

FAILS = []


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print("FAIL", what)


def test_designs():
    """every look builds for its sexes, with two non-empty addons of parts the base does not have."""
    keys = CA.all_keys()
    expect(len(keys) == 10, "10 looks: %s" % keys)
    for look, sex in keys:
        lk = L.LOOKS[look][0](sex)
        names = {p.name for p in lk.rig.parts}
        for a in (1, 2):
            add = lk.addons[a - 1]
            expect(add and not ({p.name for p in add} & names), "%s %s addon %d: new parts" % (look, sex, a))
            for p in add:
                expect(p.mat in lk.rig.mats and p.bone in lk.rig.bones, "%s %s %s: material and bone exist" % (look, sex, p.name))
        expect(look in L.COLOURS and all(0 <= c < 133 for c in L.COLOURS[look]), look + ": default colours")
    expect(CA.pick_keys(["necromancer_female"]) == [("necromancer", "female")], "pick one key")
    expect(len(CA.pick_keys(["thief"])) == 2, "pick both sexes")


def test_addon_layer():
    z = np.zeros((4, 4, 4), np.uint8)
    b0, t0 = z.copy(), z.copy()
    b0[1, 1] = (10, 20, 30, 255)
    t0[1, 1] = (255, 0, 0, 255)
    b1, t1 = b0.copy(), t0.copy()
    b1[2, 2] = (50, 50, 50, 255)                   # a new pixel
    b1[1, 1] = (11, 20, 30, 255)                   # a changed one (the addon's shadow)
    t1[3, 3] = (0, 255, 0, 255)                    # the template changed alone
    a, t = CA.addon_layer((b0, t0), (b1, t1))
    expect(a[2, 2, 3] == 255 and tuple(a[1, 1]) == (11, 20, 30, 255), "changed pixels are in the addon")
    expect(a[0, 0, 3] == 0 and int((a[..., 3] > 0).sum()) == 2, "unchanged pixels are not")
    expect(tuple(t[1, 1]) == (255, 0, 0, 255) and tuple(t[3, 3]) == (0, 255, 0, 255) and t[2, 2, 3] == 0,
           "the addon's template follows the variant's")


def synth_slots(layout):
    """distinct flat colours per slot, with valid template colours."""
    groups = CA.LAYOUTS[layout]
    sl = {}
    regions = list(rig.REGIONS.values())
    k = 0
    for g, phs in enumerate(groups):
        for i in range(len(phs)):
            for z in (0, 1):
                for y in (0, 1, 2):
                    for d in range(4):
                        k += 1
                        a = np.zeros((64, 64, 4), np.uint8)
                        a[40:60, 40:60] = (k % 251, (k * 7) % 251, (k * 13) % 251, 255)
                        t = np.zeros((64, 64, 4), np.uint8)
                        t[40:50, 40:60, :3] = regions[k % 4]
                        t[40:50, 40:60, 3] = 255
                        sl[(g, i, z, y, d)] = (a, t)
    return sl


def test_sheet_matches_importer(tmp):
    """the sheet is read back by import_art_things.py's own layout code slot for slot."""
    import import_art_things as IA
    for layout in ("2+4", "1+8"):
        sl = synth_slots(layout)
        img = CA.sheet(sl, layout)
        row = CA.things_row("templar", "male", layout)
        Image.fromarray(img, "RGBA").save(os.path.join(tmp, row["atlas"] + ".png"))
        IA.ATLAS_DIR[0] = tmp
        IA._atlas.clear()
        r = dict(row)
        for k in ("x", "y", "w", "h"):
            r[k] = int(r[k])
        r["ex"] = IA.extra_of(r)
        lay = IA.OutfitLayout(r)
        expect(lay.phases == tuple(len(p) for p in CA.LAYOUTS[layout]) and lay.py == 3 and lay.pz == 2 and lay.layers == 2,
               layout + ": layout keys")
        fr = IA.outfit_frames(r, lay)
        bad = 0
        for (g, i, z, y, d), (a, t) in sl.items():
            bad += not np.array_equal(fr[(g, i, d, 0, y, z)], a) or not np.array_equal(fr[(g, i, d, 1, y, z)], t)
        expect(bad == 0, "%s: %d slots read back differently" % (layout, bad))
        expect(r["flags"] == "displacement:8:8" and IA.outfit_flags(r) == bytes([IA.NEW_BYTE["displacement"]]) + b"\x08\x00\x08\x00",
               layout + ": displacement 8,8")


def test_render():
    """a quick render (ss 1): template colours are the four regions, addons add pixels, the output is deterministic."""
    for look, sex in (("templar", "female"), ("necromancer", "male")):
        jobs = [(look, sex, var, 0, "south", None, 1) for var in CA.VARIANTS]
        res, _ = CA.run(jobs, 1)
        b0, t0 = res[jobs[0]]
        expect((b0[..., 3] > 0).sum() > 300, "%s %s: a figure" % (look, sex))
        ok, bad = CA.check_template(t0)
        expect(ok and (t0[..., 3] > 0).sum() > 50, "%s %s: template regions only (%s)" % (look, sex, bad))
        for y in (1, 2):
            a, t = CA.addon_layer(res[jobs[0]], res[jobs[y]])
            expect((a[..., 3] > 0).sum() > 8, "%s %s addon %d adds pixels" % (look, sex, y))
        res2, _ = CA.run(jobs[:1], 1)
        expect(np.array_equal(res2[jobs[0]][0], b0), "%s %s: deterministic" % (look, sex))
    # the breath phase moves the upper body 1 px, the feet stay
    lk = CA.get_look("thief", "male")
    a = rig.render(lk.rig, "south", CA.pose_of(lk.stance, None, False), ground=CA.GROUND, ss=1)
    b = rig.render(lk.rig, "south", CA.pose_of(lk.stance, "breath", False), ground=CA.GROUND, ss=1)
    top = lambda m: int(np.nonzero(m.any(1))[0][0])  # noqa: E731
    expect(top(b["on"]) == top(a["on"]) + 1, "breath: the head is 1 px lower")


def test_import_roundtrip(tmp):
    """a sheet and its row through import_art_things.py onto a tiny pair: the importer's and the guard's checks pass."""
    import check_pair_test as cpt
    import check_pair as cp
    recs = [cpt.record({0: (1, 2, 3, 255)})]
    items = [cpt.entry(b"", [cpt.group([1])])]
    outfits = [cpt.entry(b"", [cpt.group([1] * 4, px=4, gtype=0)], outfit=True)]
    effects = [cpt.entry(b"", [cpt.group([1])])]
    missiles = [cpt.entry(b"", [cpt.group([1] * 9, px=3, py=3)])]
    pair = os.path.join(tmp, "pair")
    os.makedirs(pair)
    open(os.path.join(pair, "Tibia.dat"), "wb").write(cpt.dat_bytes(items, outfits, effects, missiles))
    open(os.path.join(pair, "Tibia.spr"), "wb").write(cpt.spr_bytes(recs))
    out = os.path.join(tmp, "sheets")
    os.makedirs(out)
    sl = synth_slots("2+4")
    row = CA.things_row("lich", "female", "2+4")
    Image.fromarray(CA.sheet(sl, "2+4"), "RGBA").save(os.path.join(out, row["atlas"] + ".png"))
    with open(os.path.join(out, "things.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, CA.FIELDS, lineterminator="\n")
        w.writeheader()
        w.writerow(row)
    res = subprocess.run([sys.executable, "-I", os.path.join(SPRITES, "import_art_things.py"),
                          "--ours-dat", os.path.join(pair, "Tibia.dat"), "--ours-spr", os.path.join(pair, "Tibia.spr"),
                          "--out-dir", os.path.join(tmp, "new"), "--things", os.path.join(out, "things.csv"),
                          "--first-outfit", "5", "--expect-items", "100"], capture_output=True, text=True)
    expect(res.returncode == 0 and "append-only guard passed" in res.stdout,
           "import_art_things.py takes the row: %s %s" % (res.stdout[-600:], res.stderr[-1200:]))
    if res.returncode:
        return
    _, counts, things, _ = cp.parse_dat(open(os.path.join(tmp, "new", "Tibia.dat"), "rb").read())
    t = things["outfit"][-1]
    g = t.groups
    expect(counts[1] == 5 and [x.phases for x in g] == [2, 4], "outfit 5 with idle 2 and walk 4 phases")
    expect((g[0].w, g[0].h, g[0].layers, g[0].px, g[0].py, g[0].pz) == (2, 2, 2, 4, 3, 2), "2x2, 2 layers, 4 dirs, 3 addons, 2 mounts")
    expect(t.flag("displacement") == (8, 8), "displacement 8,8")


def main():
    tmp = tempfile.mkdtemp(prefix="class_art_test_")
    try:
        test_designs()
        test_addon_layer()
        test_sheet_matches_importer(tmp)
        test_render()
        test_import_roundtrip(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if FAILS:
        print("%d failures" % len(FAILS))
        return 1
    print("class_art_test: all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
