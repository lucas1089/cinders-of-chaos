#!/usr/bin/env python3
"""Tests of front_art_packs.py on synthetic pictures: canvas placement, frames sharing one box, the strip layout, the normal map's
signs (OpenGL), the glow modes, the tar filter and a seal / open round trip (openssl).

Usage: python3 -I unity/tools/front_art_packs_test.py
"""
import io
import os
import sys
import tarfile
import tempfile

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import front_art_packs as fap  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print("FAIL: " + what)


# a strip of 3 frames 20 x 16; frame 0 holds a 6 x 10 block at (3, 2)
strip = Image.new("RGBA", (60, 16), (0, 0, 0, 0))
for y in range(2, 12):
    for x in range(3, 9):
        strip.putpixel((x, y), (90, 80, 70, 255))
strip.putpixel((45, 5), (255, 255, 255, 255))   # frame 2 must not leak in
fig = fap.figure(strip, 3)
check(fig.size == (20, 20), "figure: a square canvas of the frame's larger side")
bb = fig.getbbox()
check(bb == (7, 10, 13, 20), "figure: trimmed, centred, feet on the bottom row (%s)" % (bb,))
check(fap.frame_count("Ghost_6_idle_strip16.png") == 16 and fap.frame_count("x.png") == 1, "frame count from the name")

# all frames share one box: a figure that bobs keeps its feet still and does not slide sideways
bob = Image.new("RGBA", (40, 16), (0, 0, 0, 0))
for y in range(4, 14):
    bob.putpixel((5, y), (90, 80, 70, 255))      # frame 0: a post at x 5, rows 4-13
for y in range(3, 13):
    bob.putpixel((25, y), (90, 80, 70, 255))     # frame 1: the same post one row higher
    bob.putpixel((28, y), (90, 80, 70, 255))     # and an arm 3 to the right
fr = fap.frames_of(bob, 2)
check(len(fr) == 2 and all(f.size == (20, 20) for f in fr), "frames: one square canvas each")
check(fr[0].getbbox()[3] == 20 and fr[1].getbbox()[3] == 19, "frames: the lowest frame stands on the bottom row, the bob stays")
check(fr[0].getbbox()[0] == fr[1].getbbox()[0], "frames: the post keeps its column")
strip_out = fap.side_by_side(fr, "RGBA")
check(strip_out.size == (40, 20) and strip_out.crop((20, 0, 40, 20)).tobytes() == fr[1].tobytes(), "side by side: frame k at k * size")
check(fap.side_by_side([Image.new("RGB", (4, 4), (1, 2, 3))], "RGB").size == (4, 4), "side by side of one frame")

# normal map of a disc: left edge points left, top edge up, the middle at the viewer
disc = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
for y in range(24):
    for x in range(24):
        if (x - 11.5) ** 2 + (y - 11.5) ** 2 < 100:
            disc.putpixel((x, y), (120, 120, 120, 255))
n = fap.normal_map(disc)
check(n.getpixel((3, 12))[0] < 100, "normal: the left edge leans left (r low)")
check(n.getpixel((20, 12))[0] > 156, "normal: the right edge leans right (r high)")
check(n.getpixel((12, 3))[1] > 156, "normal: the top edge leans up (g high, OpenGL)")
check(n.getpixel((12, 20))[1] < 100, "normal: the bottom edge leans down")
mid = n.getpixel((12, 12))
check(abs(mid[0] - 128) < 3 and abs(mid[1] - 128) < 3 and mid[2] > 250, "normal: the dome's top faces the viewer")
check(n.getpixel((0, 0)) == (128, 128, 255), "normal: clear pixels are flat")

# glow modes: one cyan pixel and a patch of warm (orange) pixels inside a body
body = Image.new("RGBA", (16, 16), (60, 60, 60, 255))
body.putpixel((2, 2), (40, 230, 230, 255))
for y in range(8, 11):
    for x in range(8, 11):
        body.putpixel((x, y), (240, 120, 20, 255))
warm = fap.glow_pixels(body, "warm")
rule = fap.glow_pixels(body, "rule")
nocool = fap.glow_pixels(body, "nocool")
check(len(warm) == 9 and (2, 2) not in warm, "glow warm: every warm pixel, no cyan")
check((2, 2) in rule, "glow rule: cyan glows")
check((2, 2) not in nocool and nocool <= rule, "glow nocool: the rule without cyan")
check(fap.emission_mask(body, "warm").getpixel((9, 9)) == 255, "the emission mask is white where it glows")

# tar filter: only pk_<name>/<direction>[_n|_e].png files
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w:gz") as tar:
    for name in ["pk_ok/idle.png", "pk_ok/idle_w_n.png", "../evil/idle.png", "pk_ok/../../x.png", "pk_ok/sub/idle.png",
                 "other/idle.png", "pk_ok/run.sh", "pk_Bad/idle.png", "pk_ok/east.png"]:
        info = tarfile.TarInfo(name)
        info.size = 1
        tar.addfile(info, io.BytesIO(b"x"))
    link = tarfile.TarInfo("pk_ok/idle_w.png")
    link.type = tarfile.SYMTYPE
    link.linkname = "/etc/passwd"
    tar.addfile(link)
buf.seek(0)
with tarfile.open(fileobj=buf, mode="r:gz") as tar:
    names = [m.name for m in fap.safe_members(tar)]
check(names == ["pk_ok/idle.png", "pk_ok/idle_w_n.png"], "tar filter keeps only safe picture files (%s)" % names)

# seal / open round trip
with tempfile.TemporaryDirectory() as tmp:
    src = os.path.join(tmp, "src")
    os.makedirs(os.path.join(src, "pk_demo"))
    strip_out.save(os.path.join(src, "pk_demo", "idle.png"))
    enc = os.path.join(tmp, "a.enc")
    os.environ["CHAOS_ART_KEY"] = "test-key-not-a-secret"
    check(fap.seal(src, enc) == 0 and os.path.getsize(enc) > 0, "seal writes the file")
    with open(enc, "rb") as fh:
        check(b"PNG" not in fh.read(), "the sealed file shows no picture")
    dst = os.path.join(tmp, "dst")
    check(fap.open_(enc, dst) == 0, "open")
    with open(os.path.join(src, "pk_demo", "idle.png"), "rb") as a, open(os.path.join(dst, "pk_demo", "idle.png"), "rb") as b:
        check(a.read() == b.read(), "open gives the same picture back")
    del os.environ["CHAOS_ART_KEY"]
    empty = os.path.join(tmp, "none")
    check(fap.open_(enc, empty) == 0 and not os.path.exists(empty), "open without the key: a note, nothing written, exit 0")

print("front_art_packs tests: " + ("ok" if not failed else "%d failed" % failed))
sys.exit(1 if failed else 0)
