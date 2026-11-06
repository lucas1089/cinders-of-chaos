#!/usr/bin/env python3
"""Web media of the front page (O425; website/README.md "Trailer, gallery and shorts"): small H.264 versions of the
recorded trailer and shorts, a poster for each, and a screenshot gallery, committed under
website/overlay/plugins/chaos/assets/media/ together with media/manifest.json (name, size, sha256).

The recordings are not in git (docs/PROMO.md): --build reads them from a source folder with two sub folders,
`montagens/` (the output of gen_promo_montage.py: trailer-1920x1080.{en,pt-BR}.mp4, short-*-1080x1920.{en,pt-BR}.mp4)
and `rec/clips/` (the raw 1920x1080 recordings the gallery frames come from). --check needs none of that.

  python3 -I website/tools/gen_site_media.py --build SRC_DIR    encode, grab the frames, write the manifest (ffmpeg)
  python3 -I website/tools/gen_site_media.py --check            files exist, sizes under budget, sha256 as in the manifest

The music of the trailer and the shorts is the game's own (client/tools/gen_music.py, docs/CREDITS.md); the clips are
recordings of the game itself, so nothing third-party is in the committed media.
"""
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
MEDIA = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "assets", "media")
MANIFEST = os.path.join(MEDIA, "manifest.json")

LANGS = ("en", "pt-BR")

# (name, source in SRC/montagens, width, height, crf, maxrate k, poster second)
TRAILER = ("trailer", "trailer-1920x1080.%s.mp4", 1280, 720, 30, 760, 39.0)
SHORTS = (
    ("short-classes", "short-classes-1080x1920.%s.mp4", 720, 1280, 30, 640, 10.0),
    ("short-boss", "short-boss-1080x1920.%s.mp4", 720, 1280, 30, 640, 8.0),
    ("short-rift", "short-rift-1080x1920.%s.mp4", 720, 1280, 30, 640, 12.0),
)
POSTER_WIDTH = {"trailer": 1280, "short": 540}
# gallery: (name, clip in SRC/rec/clips, second). The page's captions are in plugins/chaos/media_lib.php.
GALLERY = (
    ("shot-boss", "boss_s.mp4", 11.2),
    ("shot-passive-tree", "09_ui_tour.mp4", 6.7),
    ("shot-hunt", "necro.mp4", 10.0),
    ("shot-ice", "04_hunt_mystic.mp4", 1.0),
    ("shot-tower", "tower_s.mp4", 7.5),
    ("shot-rift", "rift_s.mp4", 3.0),
    ("shot-arena", "arena_s2.mp4", 16.0),
    ("shot-inferno", "boss_s.mp4", 28.0),
)
GALLERY_WIDTH = 1280
# the recorded test character's name, on the health bar at the top left and over its head at the centre: blurred
# in the gallery frames (docs/PROMO.md: no "Test" names on show). Boxes of the 1920x1080 frame.
NAME_BOXES = ((120, 54, 200, 24), (860, 405, 200, 46))
GALLERY_QUALITY = 5  # ffmpeg -q:v, 2 best .. 31 worst

# budgets in bytes
BUDGET_TRAILER = 6 * 1000 * 1000
BUDGET_SHORT = 3 * 1000 * 1000
BUDGET_POSTER = 160 * 1000
BUDGET_SHOT_MIN = 60 * 1000
BUDGET_SHOT_MAX = 300 * 1000
BUDGET_TOTAL = 25 * 1000 * 1000


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def expected():
    """name -> (kind, size budget in bytes, minimum size) of every committed file."""
    out = {}
    for lang in LANGS:
        out["trailer.%s.mp4" % lang] = ("trailer", BUDGET_TRAILER, 100 * 1000)
        out["trailer.%s.jpg" % lang] = ("poster", BUDGET_POSTER, 10 * 1000)
        for short in SHORTS:
            out["%s.%s.mp4" % (short[0], lang)] = ("short", BUDGET_SHORT, 100 * 1000)
            out["%s.%s.jpg" % (short[0], lang)] = ("poster", BUDGET_POSTER, 10 * 1000)
    for shot in GALLERY:
        out[shot[0] + ".jpg"] = ("shot", BUDGET_SHOT_MAX, BUDGET_SHOT_MIN)
    return out


def check():
    problems = []
    try:
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)
    except (OSError, ValueError) as e:
        print("gen_site_media: no readable manifest.json (%s)" % e)
        return 1
    files = manifest.get("files") if isinstance(manifest, dict) else None
    if not isinstance(files, dict):
        print("gen_site_media: manifest.json has no 'files' table")
        return 1
    want = expected()
    for name in sorted(set(want) | set(files)):
        if name not in want:
            problems.append("%s: in the manifest but not in the generator" % name)
            continue
        if name not in files:
            problems.append("%s: not in the manifest" % name)
            continue
    total = 0
    for name, (kind, budget, minimum) in sorted(want.items()):
        path = os.path.join(MEDIA, name)
        if not os.path.isfile(path):
            problems.append("%s: file missing" % name)
            continue
        size = os.path.getsize(path)
        total += size
        if size > budget:
            problems.append("%s: %d bytes, budget %d" % (name, size, budget))
        if size < minimum:
            problems.append("%s: %d bytes, suspiciously small" % (name, size))
        entry = files.get(name)
        if isinstance(entry, dict):
            if entry.get("size") != size:
                problems.append("%s: manifest size %s, file %d" % (name, entry.get("size"), size))
            if entry.get("sha256") != sha256(path):
                problems.append("%s: sha256 differs from the manifest (run --build)" % name)
    extra = sorted(n for n in os.listdir(MEDIA) if n != "manifest.json" and n not in want) if os.path.isdir(MEDIA) else []
    for n in extra:
        problems.append("%s: committed but not made by the generator" % n)
    if total > BUDGET_TOTAL:
        problems.append("total %d bytes, budget %d" % (total, BUDGET_TOTAL))
    if manifest.get("total") != total and not problems:
        problems.append("manifest total %s, files %d" % (manifest.get("total"), total))
    if problems:
        print("gen_site_media: %d problem(s)" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("gen_site_media: %d files, %.1f MB of %.0f MB, manifest matches" % (len(want), total / 1e6, BUDGET_TOTAL / 1e6))
    return 0


def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        sys.exit("ffmpeg failed: %s\n%s" % (" ".join(cmd), r.stderr.decode("utf-8", "replace")[-2000:]))


def encode(src, dst, width, height, crf, maxrate):
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", src,
         "-vf", "scale=%d:%d:flags=lanczos" % (width, height),
         "-c:v", "libx264", "-preset", "slow", "-crf", str(crf), "-maxrate", "%dk" % maxrate,
         "-bufsize", "%dk" % (maxrate * 2), "-pix_fmt", "yuv420p", "-profile:v", "high",
         "-c:a", "aac", "-b:a", "48k", "-ac", "2", "-map_metadata", "-", "-movflags", "+faststart", dst])


def grab(src, dst, second, width, quality, blur=()):
    """One frame as JPG. blur: (x, y, w, h) boxes of the 1920x1080 source that are blurred first."""
    chain = ""
    last = "0:v"
    for i, (x, y, w, h) in enumerate(blur):
        chain += "[%s]split[a%d][b%d];[b%d]crop=%d:%d:%d:%d,boxblur=6:3[c%d];[a%d][c%d]overlay=%d:%d[o%d];" % (
            last, i, i, i, w, h, x, y, i, i, i, x, y, i)
        last = "o%d" % i
    chain += "[%s]scale=%d:-2:flags=lanczos[out]" % (last, width)
    run(["ffmpeg", "-loglevel", "error", "-y", "-ss", "%.2f" % second, "-i", src, "-frames:v", "1",
         "-filter_complex", chain, "-map", "[out]", "-q:v", str(quality), "-map_metadata", "-", dst])


def build(srcdir):
    mont = os.path.join(srcdir, "montagens")
    clips = os.path.join(srcdir, "rec", "clips")
    os.makedirs(MEDIA, exist_ok=True)
    for lang in LANGS:
        for kind, spec in [("trailer", TRAILER)] + [("short", s) for s in SHORTS]:
            name, pattern, w, h, crf, maxrate, poster_at = spec
            src = os.path.join(mont, pattern % lang)
            if not os.path.isfile(src):
                sys.exit("missing source: " + src)
            out = os.path.join(MEDIA, "%s.%s.mp4" % (name, lang))
            print("encode", os.path.basename(out))
            encode(src, out, w, h, crf, maxrate)
            grab(src, os.path.join(MEDIA, "%s.%s.jpg" % (name, lang)), poster_at, POSTER_WIDTH[kind], 8)
    for name, clip, second in GALLERY:
        src = os.path.join(clips, clip)
        if not os.path.isfile(src):
            sys.exit("missing source: " + src)
        print("grab", name)
        grab(src, os.path.join(MEDIA, name + ".jpg"), second, GALLERY_WIDTH, GALLERY_QUALITY, NAME_BOXES)
    files = {}
    total = 0
    for name in sorted(expected()):
        path = os.path.join(MEDIA, name)
        size = os.path.getsize(path)
        total += size
        files[name] = {"size": size, "sha256": sha256(path)}
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump({"total": total, "files": files}, f, indent=1, sort_keys=True)
        f.write("\n")
    print("manifest written: %d files, %.1f MB" % (len(files), total / 1e6))
    return check()


def main(argv):
    if argv == ["--check"]:
        return check()
    if len(argv) == 2 and argv[0] == "--build":
        return build(argv[1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
