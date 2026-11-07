#!/usr/bin/env python3
"""Purchased pack monsters for the Unity front-art scene (the extras around the four test figures).

The purchased monster packs (docs/CREDITS.md, tracing alias "set30 mutter") may ship inside the game but their files may not be shared on
their own. This repository is public, so the converted pictures are never committed in the clear: they travel as one encrypted
file, unity/art/front_art_packs.enc (AES-256, key in the repository secret CHAOS_ART_KEY), and the Unity build opens it into
Resources/FrontArt/pk_<name>/ (ignored by git). Without the secret the scene simply leaves the extras out.

Steps:
  build PACKS_DIR OUT_DIR   from the extracted packs (any folder tree with the *_idle_strip*.png files below) write
                            OUT_DIR/pk_<name>/idle.png (the idle animation, frames side by side, facing right), idle_w.png
                            (each frame mirrored, facing left), and for both _n (normal map) and _e (emission mask)
  seal OUT_DIR ENC          tar.gz OUT_DIR's pk_* folders and encrypt to ENC (key from the environment variable CHAOS_ART_KEY)
  open ENC DEST             decrypt ENC and unpack its pk_* folders into DEST (CI: Resources/FrontArt); exit 0 and say so when
                            CHAOS_ART_KEY is not set

A figure: every idle frame, trimmed by the box around all frames (so the figure never jumps) and set on a square canvas of the
frame's size with the feet on the bottom row and centred. The packs draw one side view facing right: it stands for the four
east-ish and the north and south pictures, the mirror (idle_w) for the three west ones. The normal map is a dome over each frame's
silhouette (distance to the nearest clear pixel), the emission mask the glow rule of gen_front_art_emission.py, frame by frame.
The scene plays the frames at FPS (Unity/FrontArtScene.cs PackFps).

Usage: python3 -I unity/tools/front_art_packs.py build|seal|open ...
"""
import glob
import io
import os
import re
import subprocess
import sys
import tarfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:   # build needs Pillow; seal and open (the CI step) do not
    from PIL import Image
    import gen_front_art_emission as emission
except ImportError:
    Image = emission = None

DOME = 4.0          # pixels from the edge to the flat top of the dome
OPENSSL = ["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "200000", "-md", "sha256", "-pass", "env:CHAOS_ART_KEY"]

# folder (pk_<name>), the strip's file name (without directory), pack (docs/CREDITS.md Source line), glow:
#   rule   gen_front_art_emission.py as is
#   warm   every warm pixel (a body of fire)
#   nocool the rule without its cool cyan part (an ice body would glow all over)
FIGURES = [
    ("vampire", "Vampire_idle_strip9.png", "Classic Horror Monsters", "rule"),
    ("werewolf", "Werewolf_idle_strip9.png", "Classic Horror Monsters", "rule"),
    ("headless", "Headless_Horseman_idle_strip9.png", "Classic Horror Monsters", "rule"),
    ("fire_demon", "Demon_Creature_2_idle_strip9.png", "Demon Creatures", "warm"),
    ("winged_demon", "Demon_Creature_5_idle_strip9.png", "Demon Creatures", "rule"),
    ("frost_demon", "Demon_Creature_3_idle_strip9.png", "Demon Creatures", "nocool"),
    ("ghost_king", "Ghost_6_idle_strip16.png", "Haunted Ghosts", "rule"),
    ("ghost_knight", "Ghost_5_idle_strip16.png", "Haunted Ghosts", "rule"),
    ("cultist_red", "Cult_member_2_idle_strip9.png", "Animated Cult NPCs", "rule"),
    ("cultist_dark", "Cult_member_4_idle_strip9.png", "Animated Cult NPCs", "rule"),
    ("lizard_mystic", "Lizard_Mystic_idle_strip9.png", "Animated War Beasts 1", "rule"),
    ("goblin_shaman", "Goblin_Shaman_idle_strip9.png", "Animated Goblins", "rule"),
    ("rat_king", "spr_rat_king_idle_strip13.png", "Vermin Pro Expansion", "rule"),
    ("armored_skeleton", "spr_Armored_Skeleton_idle_strip9.png", "Animated Skeleton NPC Pack", "rule"),
]


def frame_count(name):
    m = re.search(r"strip(\d+)", name)
    return int(m.group(1)) if m else 1


def frames_of(strip, frames):
    """The frames of a strip, each on a square canvas of the frame's larger side: cropped by the box around all frames, feet on
    the bottom row, centred."""
    w, h = strip.size
    fw = w // frames
    raw = [strip.crop((k * fw, 0, (k + 1) * fw, h)) for k in range(frames)]
    size = max(fw, h)
    boxes = [r.getbbox() for r in raw if r.getbbox()]
    if not boxes:
        return [Image.new("RGBA", (size, size), (0, 0, 0, 0)) for _ in raw]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    out = []
    for r in raw:
        c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        c.alpha_composite(r.crop((x0, y0, x1, y1)), ((size - (x1 - x0)) // 2, size - (y1 - y0)))
        out.append(c)
    return out


def figure(strip, frames):
    """The first frame (frames_of)."""
    return frames_of(strip, frames)[0]


def side_by_side(pics, mode):
    size = pics[0].width
    out = Image.new(mode, (size * len(pics), size), (0, 0, 0, 0) if mode == "RGBA" else (128, 128, 255) if mode == "RGB" else 0)
    for k, p in enumerate(pics):
        out.paste(p, (k * size, 0))
    return out


def normal_map(im):
    """A dome over the opaque pixels: height = distance to the nearest clear pixel (capped at DOME), normal = minus its slope
    (OpenGL: +x right, +y up), encoded 0..255; clear pixels get the flat normal."""
    w, h = im.size
    px = im.load()
    inf = 10 ** 6
    dist = [[0 if px[x, y][3] < 128 else inf for x in range(w)] for y in range(h)]
    for y in range(h):   # two-pass chamfer distance (outside the canvas counts as clear)
        for x in range(w):
            if dist[y][x]:
                best = min(x + 1, y + 1, dist[y][x])
                if x > 0: best = min(best, dist[y][x - 1] + 1)
                if y > 0: best = min(best, dist[y - 1][x] + 1)
                dist[y][x] = best
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            if dist[y][x]:
                best = min(dist[y][x], w - x, h - y)
                if x < w - 1: best = min(best, dist[y][x + 1] + 1)
                if y < h - 1: best = min(best, dist[y + 1][x] + 1)
                dist[y][x] = best

    def height(x, y):
        if x < 0 or y < 0 or x >= w or y >= h:
            return 0.0
        d = min(dist[y][x], DOME) / DOME
        return 1.0 - (1.0 - d) ** 2

    out = Image.new("RGB", (w, h), (128, 128, 255))
    opx = out.load()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] < 128:
                continue
            gx = (height(x + 1, y) - height(x - 1, y)) * 0.5
            gy = (height(x, y - 1) - height(x, y + 1)) * 0.5   # +y up: the row above minus the row below
            nx, ny, nz = -gx * 2.2, -gy * 2.2, 1.0
            ln = (nx * nx + ny * ny + nz * nz) ** 0.5
            opx[x, y] = tuple(int(round((c / ln * 0.5 + 0.5) * 255)) for c in (nx, ny, nz))
    return out


def glow_pixels(im, glow):
    """The glowing (x, y) pixels of a picture under a figure's glow mode."""
    px = im.load()
    kind = {}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a >= 128:
                kind[(x, y)] = emission.classify(r, g, b)
    if glow == "warm":
        return {p for p, k in kind.items() if k in ("w", "core")}
    keep = emission.mask(im)
    if glow == "nocool":
        keep = {p for p in keep if kind.get(p) != "c"}
    return keep


def emission_mask(im, glow="rule"):
    out = Image.new("L", im.size, 0)
    opx = out.load()
    for p in glow_pixels(im, glow):
        opx[p] = 255
    return out


def build(packs_dir, out_dir):
    found = {}
    for f in glob.glob(os.path.join(packs_dir, "**", "*.png"), recursive=True):
        found.setdefault(os.path.basename(f), f)
    missing = [s for _, s, _, _ in FIGURES if s not in found]
    if missing:
        print("missing strips: " + ", ".join(missing))
        return 1
    for name, strip, _, glow in FIGURES:
        frames = frames_of(Image.open(found[strip]).convert("RGBA"), frame_count(strip))
        d = os.path.join(out_dir, "pk_" + name)
        os.makedirs(d, exist_ok=True)
        for f in glob.glob(os.path.join(d, "*.png")):
            os.remove(f)
        for side, pics in (("idle", frames), ("idle_w", [p.transpose(Image.FLIP_LEFT_RIGHT) for p in frames])):
            side_by_side(pics, "RGBA").save(os.path.join(d, side + ".png"), optimize=True)
            side_by_side([normal_map(p) for p in pics], "RGB").save(os.path.join(d, side + "_n.png"), optimize=True)
            side_by_side([emission_mask(p, glow) for p in pics], "L").save(os.path.join(d, side + "_e.png"), optimize=True)
        print("pk_%s %d frames of %dx%d" % (name, len(frames), frames[0].width, frames[0].height))
    return 0


def seal(out_dir, enc):
    if not os.environ.get("CHAOS_ART_KEY"):
        print("CHAOS_ART_KEY is not set")
        return 1
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.PAX_FORMAT) as tar:
        for d in sorted(glob.glob(os.path.join(out_dir, "pk_*"))):
            for f in sorted(os.listdir(d)):
                info = tar.gettarinfo(os.path.join(d, f), arcname=os.path.basename(d) + "/" + f)
                info.mtime = 0; info.uid = info.gid = 0; info.uname = info.gname = ""
                with open(os.path.join(d, f), "rb") as fh:
                    tar.addfile(info, fh)
    subprocess.run(OPENSSL + ["-salt", "-out", enc], input=buf.getvalue(), check=True)
    print("sealed %s (%d bytes)" % (enc, os.path.getsize(enc)))
    return 0


def safe_members(tar):
    """Only plain files directly inside a pk_<name>/ folder."""
    for m in tar.getmembers():
        parts = m.name.split("/")
        if m.isfile() and len(parts) == 2 and re.fullmatch(r"pk_[a-z0-9_]+", parts[0]) and re.fullmatch(r"idle(_w)?(_[ne])?\.png", parts[1]):
            yield m


def open_(enc, dest):
    if not os.environ.get("CHAOS_ART_KEY"):
        print("CHAOS_ART_KEY is not set: the front-art scene runs without the pack monsters")
        return 0
    data = subprocess.run(OPENSSL + ["-d", "-in", enc], stdout=subprocess.PIPE, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        members = list(safe_members(tar))
        for m in members:
            target = os.path.join(dest, m.name)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as fh:
                fh.write(tar.extractfile(m).read())
    print("opened %d pictures into %s" % (len(members), dest))
    return 0


def main(argv):
    if len(argv) == 3 and argv[0] == "build":
        return build(argv[1], argv[2])
    if len(argv) == 3 and argv[0] == "seal":
        return seal(argv[1], argv[2])
    if len(argv) == 3 and argv[0] == "open":
        return open_(argv[1], argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
