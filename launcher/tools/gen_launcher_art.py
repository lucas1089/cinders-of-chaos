#!/usr/bin/env python3
"""Art of the game launcher window (O339, new look O552), made from the game's own art. No new art is drawn.

  python3 -I launcher/tools/gen_launcher_art.py [--check] [--preview DIR]

Writes into launcher/assets/ (embedded with include_bytes!):
  icon.rgba            128x128 raw RGBA, the brand icon (window icon)
  hero.jpg             1280x800, the login art covered to the window, darkened, a vignette and a fade to the bottom bar
  logo.png             the brand logo cropped to its pixels, 560 px wide
  news_<tag>.jpg       560x140 default news pictures (update, news, event, notice): crops of the login art
  skin_*.png           byte copies of the game's ornate skin: corners, crest, the login screen's buttons
  fonts/cinzel_bold.ttf   Cinzel instanced at weight 700 (egui cannot pick the weight of a variable font)
  fonts/alegreya_sans.ttf copy of the body font
--check: fail when a file is missing, a copy differs from its source, or a picture differs from a fresh render by more than
2 of 255 on average (resampling differs a little between Pillow versions). The font instance is checked by size and,
when fontTools is installed, by its weight.
--preview DIR: also save the generated pictures there as PNG.
"""
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "launcher" / "assets"
CHAOS = ROOT / "client" / "overlay" / "data" / "images" / "chaos"
LOGO = ROOT / "docs" / "brand" / "cinders_logo.png"
ICON = ROOT / "docs" / "brand" / "cinders_logo_icon.png"
CINZEL = ROOT / "client" / "fonts-src" / "Cinzel" / "Cinzel-VariableFont_wght.ttf"
ALEGREYA = ROOT / "client" / "fonts-src" / "AlegreyaSans" / "AlegreyaSans-Medium.ttf"
WW, WH = 1280, 800
IW = 128
TOL = 2.0
# byte copies: file name in launcher/assets -> source under the game's image folder
COPIES = {
    "skin_corner_tl.png": "skin/orn_corner_tl.png",
    "skin_corner_tr.png": "skin/orn_corner_tr.png",
    "skin_corner_bl.png": "skin/orn_corner_bl.png",
    "skin_corner_br.png": "skin/orn_corner_br.png",
    "skin_crest.png": "skin/orn_crest.png",
    "skin_btn.png": "login/btn_normal.png",
    "skin_btn_red.png": "login/btn_red_normal.png",
    "skin_btn_off.png": "login/btn_disabled.png",
}
# default news picture crops of the login art (x0, y0, x1, y1 of the 1920x1080 picture)
NEWS_CROPS = {
    "update": (760, 120, 1760, 580),
    "news": (900, 200, 1900, 660),
    "event": (0, 380, 1000, 840),
    "notice": (200, 40, 1200, 500),
}


def hero():
    art = Image.open(CHAOS / "background.png").convert("RGB")
    s = WH / art.height
    art = art.resize((round(art.width * s), WH), Image.LANCZOS)
    off = min(round(art.width * 0.30), art.width - WW)
    a = np.asarray(art.crop((off, 0, off + WW, WH)), np.float32)
    a = a * 0.62 + np.array((10, 7, 6), np.float32) * 0.38
    y = np.arange(WH, dtype=np.float32)[:, None]
    t = np.clip((y / WH - 0.55) / 0.45, 0, 1) ** 1.6
    k = (t * 0.75)[..., None]
    a = a * (1 - k) + np.array((8, 6, 5), np.float32) * k
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def logo():
    im = Image.open(LOGO).convert("RGBA")
    box = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    im = im.crop(box)
    w = 560
    return im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)


def news(tag):
    art = Image.open(CHAOS / "background.png").convert("RGB").crop(NEWS_CROPS[tag])
    return art.resize((560, 140), Image.LANCZOS)


def icon():
    return Image.open(ICON).convert("RGBA").resize((IW, IW), Image.LANCZOS)


def jpeg(im):
    b = io.BytesIO()
    im.save(b, "JPEG", quality=86, optimize=True)
    return b.getvalue()


def png(im):
    b = io.BytesIO()
    im.save(b, "PNG", optimize=True)
    return b.getvalue()


def pictures():
    """name -> (encoded bytes, fresh image for the comparison)"""
    out = {"hero.jpg": (jpeg(hero()), None), "logo.png": (png(logo()), None)}
    for tag in NEWS_CROPS:
        out["news_%s.jpg" % tag] = (jpeg(news(tag)), None)
    return out


def instance_cinzel(dest):
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    f = TTFont(str(CINZEL))
    f = instancer.instantiateVariableFont(f, {"wght": 700})
    f.save(str(dest))


def decode(b):
    return np.asarray(Image.open(io.BytesIO(b)).convert("RGB"), np.int16)


def check():
    bad = False

    def fail(msg):
        nonlocal bad
        print("FAIL " + msg)
        bad = True

    for name, src in COPIES.items():
        p = OUT / name
        if not p.is_file() or p.read_bytes() != (CHAOS / src).read_bytes():
            fail("%s is not a copy of %s" % (name, src))
    p = OUT / "fonts" / "alegreya_sans.ttf"
    if not p.is_file() or p.read_bytes() != ALEGREYA.read_bytes():
        fail("fonts/alegreya_sans.ttf is not a copy of the source font")
    p = OUT / "icon.rgba"
    want = np.asarray(icon(), np.int16)
    if not p.is_file() or p.stat().st_size != want.size:
        fail("icon.rgba missing or wrong size")
    else:
        got = np.frombuffer(p.read_bytes(), np.uint8).reshape(want.shape).astype(np.int16)
        if float(np.abs(got - want).mean()) > TOL:
            fail("icon.rgba differs from a fresh render")
    for name, (b, _) in pictures().items():
        p = OUT / name
        if not p.is_file():
            fail("%s missing" % name)
            continue
        want, got = decode(b), decode(p.read_bytes())
        if want.shape != got.shape or float(np.abs(got - want).mean()) > TOL:
            fail("%s differs from a fresh render" % name)
    p = OUT / "fonts" / "cinzel_bold.ttf"
    if not p.is_file() or p.stat().st_size < 20000:
        fail("fonts/cinzel_bold.ttf missing")
    else:
        try:
            from fontTools.ttLib import TTFont

            f = TTFont(str(p))
            if "fvar" in f or f["OS/2"].usWeightClass != 700:
                fail("fonts/cinzel_bold.ttf is not the weight 700 instance")
        except ImportError:
            pass
    print("launcher art: %s" % ("stale" if bad else "ok"))
    return 1 if bad else 0


def main():
    argv = sys.argv[1:]
    if "--check" in argv:
        return check()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "fonts").mkdir(exist_ok=True)
    (OUT / "icon.rgba").write_bytes(icon().tobytes())
    for name, src in COPIES.items():
        (OUT / name).write_bytes((CHAOS / src).read_bytes())
    (OUT / "fonts" / "alegreya_sans.ttf").write_bytes(ALEGREYA.read_bytes())
    instance_cinzel(OUT / "fonts" / "cinzel_bold.ttf")
    prev = Path(argv[argv.index("--preview") + 1]) if "--preview" in argv else None
    if prev:
        prev.mkdir(parents=True, exist_ok=True)
    for name, (b, _) in pictures().items():
        (OUT / name).write_bytes(b)
        if prev:
            Image.open(io.BytesIO(b)).save(prev / (name.rsplit(".", 1)[0] + ".png"))
    print("wrote launcher/assets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
