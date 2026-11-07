#!/usr/bin/env python3
"""Purchased pack monsters for the Unity front-art scene (the extras around the four test figures).

The purchased monster packs (docs/CREDITS.md, tracing alias "set30 mutter") may ship inside the game but their files may not be shared on
their own. This repository is public, so the converted pictures are never committed in the clear: they travel as one encrypted
file, unity/art/front_art_packs.enc (AES-256, key in the repository secret CHAOS_ART_KEY), and the Unity build opens it into
Resources/FrontArt/pk_<name>/ (ignored by git). Without the secret the scene simply leaves the extras out.

Steps:
  build PACKS_DIR OUT_DIR   from the extracted packs (any folder tree with the *_idle_strip*.png and *_walk_strip*.png files
                            below) write OUT_DIR/pk_<name>/idle.png (the idle animation, frames side by side, facing right),
                            idle_w.png (each frame mirrored, facing left), the same for walk and for attack (when the pack
                            has one), and for each _n (normal map) and _e (emission mask)
  fx PROJ_DIR OUT_DIR       the spell art: OUT_DIR/fx_<name>/missile.png from the projectile pack's sheets (PROJ_DIR: its
                            sheets/32px/projectiles; MISSILES) and fx_<name>/impact.png, a burst drawn in its colours
  seal OUT_DIR ENC          tar.gz OUT_DIR's pk_* and fx_* folders and encrypt to ENC (key from the environment variable CHAOS_ART_KEY)
  open ENC DEST             decrypt ENC and unpack its pk_* and fx_* folders into DEST (CI: Resources/FrontArt); exit 0 and
                            say so when CHAOS_ART_KEY is not set

A figure: every idle and walk frame, trimmed by the box around all of them (so the figure never jumps, also when it starts
walking) and set on a square canvas of the frame's size with the feet on the bottom row and centred. The packs draw one side view facing right: it stands for the four
east-ish and the north and south pictures, the mirror (idle_w) for the three west ones. The normal map is a dome over each frame's
silhouette (distance to the nearest clear pixel), the emission mask the glow rule of gen_front_art_emission.py, frame by frame.
The scene plays idle at PackFps and walk at WalkFps (Unity/FrontArtScene.cs) along the patrols of Core/FrontArt.cs.

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


def walk_name(idle_strip):
    """The walk strip next to an idle strip: Vampire_idle_strip9.png -> Vampire_walk_strip9.png."""
    return idle_strip.replace("_idle_", "_walk_")


def attack_name(idle_strip):
    """The attack strip next to an idle strip (not every figure has one: the ghosts do not)."""
    return idle_strip.replace("_idle_", "_attack_")


def frame_count(name):
    m = re.search(r"strip(\d+)", name)
    return int(m.group(1)) if m else 1


def raw_frames(strip, frames):
    w, h = strip.size
    fw = w // frames
    return [strip.crop((k * fw, 0, (k + 1) * fw, h)) for k in range(frames)]


def place(raws, size):
    """Frames on square canvases of size: cropped by the box around all of them, feet on the bottom row, centred."""
    boxes = [r.getbbox() for r in raws if r.getbbox()]
    if not boxes:
        return [Image.new("RGBA", (size, size), (0, 0, 0, 0)) for _ in raws]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    out = []
    for r in raws:
        c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        c.alpha_composite(r.crop((x0, y0, x1, y1)), ((size - (x1 - x0)) // 2, size - (y1 - y0)))
        out.append(c)
    return out


def frames_of(strip, frames):
    """The frames of a strip, each on a square canvas of the frame's larger side: cropped by the box around all frames, feet on
    the bottom row, centred."""
    raws = raw_frames(strip, frames)
    return place(raws, max(raws[0].size))


def frames_of_set(strips):
    """frames_of for several strips of one figure (idle, walk) at once: one box and one canvas size for all, so switching between
    them keeps the feet and the size. strips: [(picture, frame count)]; returns one frame list per strip."""
    raws = [raw_frames(s, n) for s, n in strips]
    size = max(max(r[0].size) for r in raws)
    every = place([f for r in raws for f in r], size)
    out, k = [], 0
    for r in raws:
        out.append(every[k:k + len(r)])
        k += len(r)
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
    missing = [n for _, s, _, _ in FIGURES for n in (s, walk_name(s)) if n not in found]
    if missing:
        print("missing strips: " + ", ".join(missing))
        return 1
    for name, strip, _, glow in FIGURES:
        names = [strip, walk_name(strip)] + ([attack_name(strip)] if attack_name(strip) in found else [])
        sets = frames_of_set([(Image.open(found[n]).convert("RGBA"), frame_count(n)) for n in names])
        idle, walk = sets[0], sets[1]
        attack = sets[2] if len(sets) > 2 else []
        d = os.path.join(out_dir, "pk_" + name)
        os.makedirs(d, exist_ok=True)
        for f in glob.glob(os.path.join(d, "*.png")):
            os.remove(f)
        for anim, frames in (("idle", idle), ("walk", walk), ("attack", attack)):
            if not frames:
                continue
            for side, pics in ((anim, frames), (anim + "_w", [p.transpose(Image.FLIP_LEFT_RIGHT) for p in frames])):
                side_by_side(pics, "RGBA").save(os.path.join(d, side + ".png"), optimize=True)
                side_by_side([normal_map(p) for p in pics], "RGB").save(os.path.join(d, side + "_n.png"), optimize=True)
                side_by_side([emission_mask(p, glow) for p in pics], "L").save(os.path.join(d, side + "_e.png"), optimize=True)
        print("pk_%s idle %d, walk %d, attack %d frames of %dx%d" % (name, len(idle), len(walk), len(attack), idle[0].width, idle[0].height))
    return 0


# spell art for the casters (Core/FrontArt.cs FaSpell): fx_<name>/missile.png is the projectile pack's sheet as it is (8 rows of
# directions E, SE, S, SW, W, NW, N, NE; 8 frames of 64 x 64 side by side) and fx_<name>/impact.png a burst drawn here in the
# missile's own colours (IMPACT_FRAMES square frames of 128, side by side). Pack: docs/CREDITS.md "Projectiles" (32px renders).
MISSILES = [
    ("fireball", "proj_fireball", "hellfire"),
    ("frost", "proj_frost_shard", "frost"),
    ("arcane", "proj_arcane_missile", "arcane"),
    ("skull_necrotic", "proj_soul_skull", "necrotic"),
    ("skull_spirit", "proj_soul_skull", "spirit"),
    ("blood", "proj_shadow_bolt", "blood"),
    ("shadow", "proj_shadow_bolt", "shadow"),
    ("holy", "proj_holy_orb", "holy"),
]
IMPACT_FRAMES = 12


def palette(sheet):
    """Three colours of a missile: its hot core (the brightest), its body and its rim (the darker opaque pixels)."""
    px = [p for p in sheet.getdata() if p[3] >= 160]
    if not px:
        return [(255, 255, 255), (200, 200, 200), (120, 120, 120)]
    px.sort(key=lambda p: p[0] + p[1] + p[2])
    pick = lambda q: tuple(px[min(len(px) - 1, int(q * len(px)))][:3])
    return [pick(0.97), pick(0.7), pick(0.35)]


def impact_strip(sheet):
    """A burst in the missile's colours: a flash that shrinks, a ring that grows and thins, sparks that fly out and fade. Drawn
    on 64 x 64 and doubled (hard pixels like the packs), IMPACT_FRAMES frames side by side."""
    import math
    core, body, rim = palette(sheet)
    small = 64
    out = Image.new("RGBA", (small * 2 * IMPACT_FRAMES, small * 2), (0, 0, 0, 0))
    sparks = [(k * 2.399963 % (2 * math.pi), 0.6 + 0.4 * ((k * 7919) % 13) / 12.0) for k in range(14)]
    for f in range(IMPACT_FRAMES):
        u = f / (IMPACT_FRAMES - 1.0)
        im = Image.new("RGBA", (small, small), (0, 0, 0, 0))
        px = im.load()
        c = small / 2.0 - 0.5
        flash = 9.0 * (1.0 - u) ** 1.3 + (2.0 if u < 0.9 else 0.0)
        ring = 6.0 + 22.0 * u ** 0.7
        width = 4.0 * (1.0 - u) + 1.0
        for y in range(small):
            for x in range(small):
                d = math.hypot(x - c, y - c)
                if d <= flash:
                    px[x, y] = core + (255,) if d < flash * 0.55 else body + (255,)
                elif abs(d - ring) <= width / 2 and u < 0.95:
                    px[x, y] = (body if abs(d - ring) < width / 4 else rim) + (int(255 * (1.0 - u * 0.6)),)
        for a, sp in sparks:
            r = (8.0 + 24.0 * sp) * u ** 0.6 + 3.0
            if u > 0.92:
                continue
            sx, sy = int(round(c + math.cos(a) * r)), int(round(c + math.sin(a) * r))
            size = 2 if u < 0.5 else 1
            for dy in range(size):
                for dx in range(size):
                    if 0 <= sx + dx < small and 0 <= sy + dy < small:
                        px[sx + dx, sy + dy] = core + (255,)
        out.paste(im.resize((small * 2, small * 2), Image.NEAREST), (f * small * 2, 0))
    return out


def build_fx(proj_dir, out_dir):
    """fx_<missile>/missile.png from the projectile sheets and fx_<missile>/impact.png drawn in its colours."""
    for name, proj, variant in MISSILES:
        src = os.path.join(proj_dir, proj, variant, "%s_%s_main.png" % (proj, variant))
        if not os.path.isfile(src):
            print("missing " + src)
            return 1
        im = Image.open(src).convert("RGBA")
        if im.size != (512, 512):
            print("%s: expected 8 x 8 frames of 64, got %s" % (src, im.size))
            return 1
        d = os.path.join(out_dir, "fx_" + name)
        os.makedirs(d, exist_ok=True)
        im.save(os.path.join(d, "missile.png"), optimize=True)
        impact_strip(im).save(os.path.join(d, "impact.png"), optimize=True)
    print("fx: %d missiles with their impacts" % len(MISSILES))
    return 0


def seal(out_dir, enc):
    if not os.environ.get("CHAOS_ART_KEY"):
        print("CHAOS_ART_KEY is not set")
        return 1
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.PAX_FORMAT) as tar:
        for d in sorted(glob.glob(os.path.join(out_dir, "pk_*")) + glob.glob(os.path.join(out_dir, "fx_*"))):
            for f in sorted(os.listdir(d)):
                info = tar.gettarinfo(os.path.join(d, f), arcname=os.path.basename(d) + "/" + f)
                info.mtime = 0; info.uid = info.gid = 0; info.uname = info.gname = ""
                with open(os.path.join(d, f), "rb") as fh:
                    tar.addfile(info, fh)
    subprocess.run(OPENSSL + ["-salt", "-out", enc], input=buf.getvalue(), check=True)
    print("sealed %s (%d bytes)" % (enc, os.path.getsize(enc)))
    return 0


def safe_members(tar):
    """Only plain picture files directly inside a pk_<name>/ or fx_<name>/ folder."""
    for m in tar.getmembers():
        parts = m.name.split("/")
        if not (m.isfile() and len(parts) == 2):
            continue
        if re.fullmatch(r"pk_[a-z0-9_]+", parts[0]) and re.fullmatch(r"(idle|walk|attack)(_w)?(_[ne])?\.png", parts[1]):
            yield m
        elif re.fullmatch(r"fx_[a-z0-9_]+", parts[0]) and parts[1] in ("missile.png", "impact.png"):
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
    if len(argv) == 3 and argv[0] == "fx":
        return build_fx(argv[1], argv[2])
    if len(argv) == 3 and argv[0] == "seal":
        return seal(argv[1], argv[2])
    if len(argv) == 3 and argv[0] == "open":
        return open_(argv[1], argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
