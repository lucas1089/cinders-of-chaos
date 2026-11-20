#!/usr/bin/env python3
"""Web media of the front page (O425; website/README.md "Trailer, gallery and shorts"): small H.264 versions of the
recorded trailer and shorts, a poster for each, and a screenshot gallery, committed under
website/overlay/plugins/chaos/assets/media/ together with media/manifest.json (name, size, sha256).

The recordings are not in git (docs/PROMO.md): --build reads them from a source folder with two sub folders,
`montagens/` (the output of gen_promo_montage.py: trailer-1920x1080.{en,pt-BR}.mp4, short-*-1080x1920.{en,pt-BR}.mp4)
and `rec/clips/` (the raw 1920x1080 recordings the gallery frames come from). --check needs none of that.

  python3 -I website/tools/gen_site_media.py --build SRC_DIR    encode, grab the frames, write the manifest (ffmpeg)
  python3 -I website/tools/gen_site_media.py --build-clips SRC_DIR   the looping mechanics clips (O687) from SRC_DIR/rec/loops/<id>.mp4
  python3 -I website/tools/gen_site_media.py --check            files exist, sizes under budget, sha256 as in the manifest

The mechanics clips (O687, website/README.md "Mechanics clips") are short muted loops, one per slot of CLIPS, recorded
by tools/ci/clip_tour.sh. They are optional: a clip not recorded yet is "planned" and is not an error; a clip that is
there (clip-<id>.mp4 and its poster clip-<id>.jpg) must be in the manifest, under budget and with the manifest's sha256.

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
POSTER_WIDTH = {"trailer": 1280, "short": 540, "clip": 960}
# mechanics clips (O687): (id, start s in the recording, length s, poster second inside the cut). The ids are the slots of
# plugins/chaos/media_lib.php chaos_media_action_slots() and the shots of client/overlay/modules/test_cliptour (SHOTS);
# gen_site_media_clips_test.py holds the three lists equal. No sound; 960x540, 24 frames a second, H.264 main.
CLIPS = (
    ("loot-explosion", 0.0, 8.0, 3.0),
    ("loot-beams", 0.0, 7.0, 3.0),
    ("rift", 0.0, 8.0, 4.0),
    ("pinnacle", 0.0, 8.0, 4.0),
    ("passive-tree", 0.0, 7.0, 3.0),
    ("ember-descent", 0.0, 8.0, 4.0),
    ("infinity-tower", 0.0, 8.0, 4.0),
    ("dungeon-cards", 0.0, 7.0, 3.0),
    ("cosmetics", 0.0, 8.0, 4.0),
    ("spell-effects", 0.0, 7.0, 3.0),
)
CLIP_SIZE = (960, 540)
CLIP_CRF = 32
CLIP_MAXRATE = 480  # k
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
BUDGET_TOTAL = 25 * 1000 * 1000  # trailer, shorts, posters and the gallery
# the clips (O687): ten loops of 7 to 8 seconds at about 480 kb/s are about 450 KB each, so a loop may take 700 KB and a
# poster 90 KB; the ten together at most 9 MB on top of the 25 MB above (the page stays under 34 MB)
BUDGET_CLIP = 700 * 1000
BUDGET_CLIP_POSTER = 90 * 1000
BUDGET_CLIPS_TOTAL = 9 * 1000 * 1000


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


def planned_clips():
    """name -> (kind, size budget in bytes, minimum size) of every file a clip may have (optional files)."""
    out = {}
    for cid, _start, _len, _poster in CLIPS:
        out["clip-%s.mp4" % cid] = ("clip", BUDGET_CLIP, 20 * 1000)
        out["clip-%s.jpg" % cid] = ("clip-poster", BUDGET_CLIP_POSTER, 5 * 1000)
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
    planned = planned_clips()
    # a clip is there or planned: a half pair (video without poster) is a problem, a pair is a required file
    recorded = 0
    for cid, _s, _l, _p in CLIPS:
        have = [n for n in ("clip-%s.mp4" % cid, "clip-%s.jpg" % cid) if os.path.isfile(os.path.join(MEDIA, n)) or n in files]
        if len(have) == 2:
            recorded += 1
            for n in have:
                want[n] = planned[n]
        elif have:
            problems.append("clip-%s: %s without its pair" % (cid, have[0]))
    for name in sorted(set(want) | set(files)):
        if name not in want:
            problems.append("%s: in the manifest but not in the generator" % name)
            continue
        if name not in files:
            problems.append("%s: not in the manifest" % name)
            continue
    total = 0
    clip_total = 0
    for name, (kind, budget, minimum) in sorted(want.items()):
        path = os.path.join(MEDIA, name)
        if not os.path.isfile(path):
            problems.append("%s: file missing" % name)
            continue
        size = os.path.getsize(path)
        total += size
        if kind in ("clip", "clip-poster"):
            clip_total += size
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
    extra = sorted(n for n in os.listdir(MEDIA) if n != "manifest.json" and n not in want and n not in planned) if os.path.isdir(MEDIA) else []
    for n in extra:
        problems.append("%s: committed but not made by the generator" % n)
    if total - clip_total > BUDGET_TOTAL:
        problems.append("total %d bytes, budget %d" % (total - clip_total, BUDGET_TOTAL))
    if clip_total > BUDGET_CLIPS_TOTAL:
        problems.append("clips total %d bytes, budget %d" % (clip_total, BUDGET_CLIPS_TOTAL))
    if manifest.get("total") != total and not problems:
        problems.append("manifest total %s, files %d" % (manifest.get("total"), total))
    if problems:
        print("gen_site_media: %d problem(s)" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("gen_site_media: %d files, %.1f MB of %.0f MB (+ clips %.1f MB of %.0f MB: %d of %d recorded), manifest matches"
          % (len(want) - 2 * recorded, (total - clip_total) / 1e6, BUDGET_TOTAL / 1e6, clip_total / 1e6, BUDGET_CLIPS_TOTAL / 1e6,
             recorded, len(CLIPS)))
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
    return write_manifest()


def write_manifest():
    """manifest.json from the files that are there: every file of expected() and every recorded clip pair."""
    files = {}
    total = 0
    names = sorted(expected())
    names += sorted(n for n in planned_clips() if os.path.isfile(os.path.join(MEDIA, n)))
    for name in names:
        path = os.path.join(MEDIA, name)
        size = os.path.getsize(path)
        total += size
        files[name] = {"size": size, "sha256": sha256(path)}
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump({"total": total, "files": files}, f, indent=1, sort_keys=True)
        f.write("\n")
    print("manifest written: %d files, %.1f MB" % (len(files), total / 1e6))
    return check()


def encode_clip(src, dst, start, length):
    """A mechanics loop: no sound, 960x540, the name of the recorded test character blurred (the boxes of the gallery)."""
    chain = ""
    last = "0:v"
    for i, (x, y, w, h) in enumerate(NAME_BOXES):
        chain += "[%s]split[a%d][b%d];[b%d]crop=%d:%d:%d:%d,boxblur=6:3[c%d];[a%d][c%d]overlay=%d:%d[o%d];" % (
            last, i, i, i, w, h, x, y, i, i, i, x, y, i)
        last = "o%d" % i
    chain += "[%s]scale=%d:%d:flags=lanczos,fps=24[out]" % (last, CLIP_SIZE[0], CLIP_SIZE[1])
    run(["ffmpeg", "-loglevel", "error", "-y", "-ss", "%.2f" % start, "-t", "%.2f" % length, "-i", src,
         "-filter_complex", chain, "-map", "[out]", "-an", "-c:v", "libx264", "-preset", "slow", "-crf", str(CLIP_CRF),
         "-maxrate", "%dk" % CLIP_MAXRATE, "-bufsize", "%dk" % (CLIP_MAXRATE * 2), "-pix_fmt", "yuv420p", "-profile:v", "main",
         "-map_metadata", "-", "-movflags", "+faststart", dst])


def build_clips(srcdir):
    loops = os.path.join(srcdir, "rec", "loops")
    os.makedirs(MEDIA, exist_ok=True)
    made = 0
    for cid, start, length, poster_at in CLIPS:
        src = os.path.join(loops, cid + ".mp4")
        if not os.path.isfile(src):
            print("not recorded: %s" % cid)
            continue
        out = os.path.join(MEDIA, "clip-%s.mp4" % cid)
        print("encode", os.path.basename(out))
        encode_clip(src, out, start, length)
        grab(src, os.path.join(MEDIA, "clip-%s.jpg" % cid), start + poster_at, POSTER_WIDTH["clip"], 8, NAME_BOXES)
        made += 1
    if made == 0:
        sys.exit("no recorded loop in " + loops)
    return write_manifest()


def main(argv):
    if argv == ["--check"]:
        return check()
    if len(argv) == 2 and argv[0] == "--build":
        return build(argv[1])
    if len(argv) == 2 and argv[0] == "--build-clips":
        return build_clips(argv[1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
