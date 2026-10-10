#!/usr/bin/env python3
"""PixelLab's repaint of a line's standing frames, and every other frame dressed in it (the studio's creature way:
the shape is Python, PixelLab only repaints it, the animation re-uses the painting).

    python3 -I client/tools/outfit_art/repaint.py sheet  [line]            # out/repaint_<line>/input.png
    python3 -I client/tools/outfit_art/repaint.py edit   [line] [N]        # N repaints (spends PixelLab generations)
    python3 -I client/tools/outfit_art/repaint.py review [line]            # silhouette overlap per cell, compare png
    python3 -I client/tools/outfit_art/repaint.py apply  [line] <edit.png> <variant>   # out/<key>/frames_<variant>.npz

The sheet: one row per outfit (class x sex, build.py order), the four directions across (north, east, south, west),
64 px cells, standing on foot, in the client's default colours. A frame is re-dressed pixel by pixel: the same part
of the same body point in the repainted standing frame of that direction (nearest point of that part when it was
hidden there). The silhouette, the outline and the colour template stay the shape's own (so the mask always fits);
under the template the repainted colour is turned back into grey (divided by the colour it was painted in).
"""
import os
import random
import sys

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build  # noqa: E402
import rig  # noqa: E402

KIT = os.path.join(os.path.dirname(HERE), "art_studio", "kit")
sys.path.insert(0, KIT)

PROMPT = """Improve and refine the texture quality of this existing pixel-art sprite sheet: {N} dark-fantasy player characters, one per row, each in 4 views (columns: facing north/away, east/right, south/toward the viewer, west/left), 64x64 cells, standing.

Do NOT redesign them.
Do NOT change silhouettes, proportions, positions, perspective or where parts are.

THE CHARACTERS (rows):
{ROWS}

LIGHTING / DEPTH:
Tibia-style 45-degree oblique top-down 2.5D perspective: height goes up and to the left. Light from the upper-left, deeper shadows on the lower-right. Glowing orange embers stay bright.

OUTLINE:
A thin 1-pixel dark outline around each silhouette, tinted toward the character's own colors, not pure black.

PIXEL ART QUALITY:
Crisp fantasy game sprites like classic Tibia player outfits. Charred iron, embers, bone, worn leather. Hue-shifted shading, readable pixel clusters.
No blur, no smooth gradients, no anti-aliasing, no ground shadow.

IMPORTANT:
Keep each silhouette: the same characters, only better texture, shading and detail.
"""

ROWS = {
    "warrior": {
        ("warrior", "male"): "Warrior, a man: short yellow hair, blue cloth tunic and skirt, leather belt and bracers, one iron shoulder plate, a steel sword in his right hand, a round wooden shield with an iron rim on his left arm.",
        ("warrior", "female"): "Warrior, a woman: the same gear, long yellow hair and a braid.",
        ("juggernaut", "male"): "Juggernaut, a man: heavy charred black-iron plate, a great helm with a glowing ember eye slit and a yellow crest, blue tabard and cape, a glowing ember crack on the breastplate, a flanged mace, a tall obsidian tower shield with a glowing crack.",
        ("juggernaut", "female"): "Juggernaut, a woman: the same plate, an open-faced helm with a glowing ember band, a long yellow braid.",
        ("berserker", "male"): "Berserker, a man: ash-grey skin, a horned bone skull helm with glowing ember eyes, a yellow mane, a blue fur mantle, a leather strap, a kilt, fur boots, a great axe with glowing ember edges over his shoulder.",
        ("berserker", "female"): "Berserker, a woman: the same, a smaller skull cap, a blue fur chest wrap, long wild yellow hair.",
    }
}


def outdir(line):
    d = os.path.join(build.OUT, "repaint_" + line)
    os.makedirs(d, exist_ok=True)
    return d


def outfits(line):
    return [(c, sx) for c in build.LINES[line] for sx in build.SEXES]


def cmd_sheet(line):
    rows = []
    for c, sx in outfits(line):
        idle, _ = build.load_frames(c, sx)
        rows.append(np.concatenate([build.tinted(idle[0, 0, d, 0], idle[0, 0, d, 1], build.DEFAULT_COLOURS)
                                    for d in range(4)], 1))
    sheet = np.concatenate(rows, 0)
    p = os.path.join(outdir(line), "input.png")
    Image.fromarray(sheet, "RGBA").save(p)
    print(p, sheet.shape)
    return p


def prompt(line):
    rows = "\n".join("%d. %s" % (i + 1, ROWS[line][k]) for i, k in enumerate(outfits(line)))
    return PROMPT.format(N=len(outfits(line)), ROWS=rows)


def cmd_edit(line, n):
    import pixellab
    src = cmd_sheet(line)
    pr = prompt(line)
    print("prompt: %d characters" % len(pr))
    print("balance before:", pixellab.balance())
    rgba = np.asarray(Image.open(src).convert("RGBA"))
    d = outdir(line)
    have = [f for f in os.listdir(d) if f.startswith("edit_v")]
    k0 = len(have) + 1
    for k in range(k0, k0 + n):
        imgs = pixellab.edit_image_pro(rgba, pr, seed=random.randint(1, 2 ** 30), label="v%d" % k)
        for i, a in enumerate(imgs):
            Image.fromarray(a, "RGBA").save(os.path.join(d, "edit_v%d%s.png" % (k, "" if i == 0 else "_%d" % (i + 1))))
    print("balance after:", pixellab.balance())
    cmd_review(line)


def cut_alpha(a):
    a = np.asarray(a).copy()
    on = a[..., 3] >= 128
    a[..., 3] = np.where(on, 255, 0)
    a[~on, :3] = 0
    return a


def cmd_review(line):
    d = outdir(line)
    src = np.asarray(Image.open(os.path.join(d, "input.png")).convert("RGBA"))
    b = src[..., 3] > 0
    names = sorted(f for f in os.listdir(d) if f.startswith("edit_v") and f.endswith(".png"))
    ims = [("input", src)]
    for f in names:
        a = cut_alpha(Image.open(os.path.join(d, f)).convert("RGBA"))
        if a.shape != src.shape:
            print(f, "size", a.shape)
            continue
        on = a[..., 3] > 0
        ious = []
        for r in range(src.shape[0] // 64):
            for c in range(4):
                sl = (slice(r * 64, r * 64 + 64), slice(c * 64, c * 64 + 64))
                ious.append((on[sl] & b[sl]).sum() / max((on[sl] | b[sl]).sum(), 1))
        print(f, "silhouette overlap min %.2f mean %.2f" % (min(ious), float(np.mean(ious))))
        ims.append((f, a))
    z = 3
    H, W = src.shape[:2]
    out = Image.new("RGBA", (len(ims) * (W * z + 8), H * z), (34, 32, 32, 255))
    for i, (_, a) in enumerate(ims):
        g = build.ash_ground(W, H)
        g.alpha_composite(Image.fromarray(a, "RGBA"))
        out.alpha_composite(g.resize((W * z, H * z), Image.NEAREST), (i * (W * z + 8), 0))
    p = os.path.join(d, "edit_compare.png")
    out.convert("RGB").save(p)
    print(p)


# ------------------------------------------------------------------------------------------------ re-dressing
def lum(c):
    return 0.299 * c[..., 0] + 0.587 * c[..., 1] + 0.114 * c[..., 2]


REGION_COLOUR = {(255, 255, 0): 0, (255, 0, 0): 1, (0, 255, 0): 2, (0, 0, 255): 3}


def degrey(rgb, tmpl):
    """Under the template: the painted colour back to grey, divided by the colour the input was painted in."""
    out = rgb.astype(np.float64).copy()
    for col, i in REGION_COLOUR.items():
        m = (tmpl[..., 3] > 0) & np.all(tmpl[..., :3] == col, -1)
        if not m.any():
            continue
        tc = np.array(rig.outfit_color(build.DEFAULT_COLOURS[i]), float)
        g = np.clip(lum(out[m]) / max(lum(tc), 1.0) * 255.0, 0, 255)
        out[m] = g[:, None]
    return out.round().astype(np.uint8)


def redress(painting, part0, rest0, part, rest, base, tmpl):
    """One frame: every inside pixel takes the painting's colour at the same point of the same part."""
    out = base.copy()
    inside = part > 0
    ok0 = (part0 > 0) & (painting[..., 3] > 0)
    for p in np.unique(part[inside]):
        src = np.nonzero(ok0 & (part0 == p))
        dst = np.nonzero(inside & (part == p))
        if len(src[0]) == 0:
            continue
        tree = cKDTree(np.asarray(rest0[src], float))
        _, idx = tree.query(np.asarray(rest[dst], float))
        out[dst[0], dst[1], :3] = painting[src[0][idx], src[1][idx], :3]
    out[..., :3] = np.where((tmpl[..., 3] > 0)[..., None], degrey(out[..., :3], tmpl), out[..., :3])
    return out


def cmd_apply(line, edit, variant):
    d = outdir(line)
    sheet = cut_alpha(Image.open(edit if os.path.isabs(edit) else os.path.join(d, edit)).convert("RGBA"))
    for r, (c, sx) in enumerate(outfits(line)):
        idle, walk = build.load_frames(c, sx)
        maps = np.load(os.path.join(build.OUT, build.key(c, sx), "maps.npz"))
        idle2, walk2 = idle.copy(), walk.copy()
        for di, v in enumerate(rig.VIEWS):
            painting = sheet[r * 64:(r + 1) * 64, di * 64:(di + 1) * 64]
            p0, r0 = maps["part_%s_idle_x" % v], maps["rest_%s_idle_x" % v].astype(np.float32)
            for z, kind in ((0, "idle"), (1, "mount")):
                tag = "%s_%s_x" % (v, kind)
                idle2[0, z, di, 0] = redress(painting, p0, r0, maps["part_" + tag], maps["rest_" + tag].astype(np.float32),
                                             idle[0, z, di, 0], idle[0, z, di, 1])
            for k in range(build.WALK):
                for z, kind in ((0, "walk"), (1, "mount")):
                    tag = "%s_%s_%d" % (v, kind, k)
                    walk2[k, z, di, 0] = redress(painting, p0, r0, maps["part_" + tag], maps["rest_" + tag].astype(np.float32),
                                                 walk[k, z, di, 0], walk[k, z, di, 1])
        p = os.path.join(build.OUT, build.key(c, sx), "frames_%s.npz" % variant)
        np.savez_compressed(p, idle=idle2, walk=walk2)
        print(p)


def main():
    a = sys.argv[1:]
    if not a:
        raise SystemExit(__doc__)
    cmd, line = a[0], (a[1] if len(a) > 1 else "warrior")
    if cmd == "sheet":
        cmd_sheet(line)
    elif cmd == "edit":
        cmd_edit(line, int(a[2]) if len(a) > 2 else 1)
    elif cmd == "review":
        cmd_review(line)
    elif cmd == "apply":
        cmd_apply(line, a[2], a[3])
    elif cmd == "prompt":
        print(prompt(line))
        print(len(prompt(line)))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
