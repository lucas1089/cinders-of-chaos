#!/usr/bin/env python3
"""Art of the game launcher window (O339, new look O552), made from the game's own art. No new art is drawn.

  python3 -I launcher/tools/gen_launcher_art.py [--check] [--preview DIR]

Writes into launcher/assets/ (embedded with include_bytes!):
  icon.rgba            128x128 raw RGBA, the brand icon (window icon)
  app.ico              the brand icon at 16, 20, 24, 32, 40, 48, 64, 128 and 256 px: the icon of the exe, so of the setup program,
                       the installed launcher and its shortcuts (build.rs links it on Windows). Frames up to 48 px are classic
                       32-bit bitmaps (every shell path reads them, the Start menu and the notification area included), 64 px
                       and up are PNG (O705)
  hero.jpg             1280x800, the login art covered to the window, darkened, a vignette and a fade to the bottom bar
  logo.png             the brand logo cropped to its pixels, 560 px wide
  news_<tag>.jpg       560x140 default news pictures (update, news, event, notice): crops of the login art
  skin_corner_*.png    the four gold corner ornaments, drawn here at 108 px (the 54 px they are shown at, twice: a 2x screen shows
                       them 1:1, a 1x screen shrinks them by 2) by client/tools/gen_skin.py ornament_corner(px=); not the 44 px
                       pictures of the game, which looked pixelated when drawn bigger (O705)
  skin_crest.png       the title crest, drawn at 264 x 94 px (shown at 132 x 47) by gen_skin.py ornament_crest(px=)
  skin_btn.png         the button tile: a dark iron plate with a gold rim, drawn at 160 x 120 px (gen_skin.py button_face), a
                       nine-slice of 14 px corners whose edges and middle the window tiles at 1:1, never stretches (O705). It
                       replaces the login screen's 54 x 30 px button picture, which was scaled 0.6x with nearest-neighbour
  fonts/cinzel_bold.ttf   Cinzel instanced at weight 700 (egui cannot pick the weight of a variable font)
  fonts/alegreya_sans.ttf copy of the body font
--check: fail when a file is missing, a copy differs from its source, or a picture or skin piece differs from a fresh render by more than
2 of 255 on average (resampling differs a little between Pillow versions). The font instance is checked by size and,
when fontTools is installed, by its weight.
--preview DIR: also save the generated pictures there as PNG.
"""
import io
import sys
from pathlib import Path

import struct

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "client" / "tools"))
OUT = ROOT / "launcher" / "assets"
CHAOS = ROOT / "client" / "overlay" / "data" / "images" / "chaos"
LOGO = ROOT / "docs" / "brand" / "cinders_logo.png"
ICON = ROOT / "docs" / "brand" / "cinders_logo_icon.png"
CINZEL = ROOT / "client" / "fonts-src" / "Cinzel" / "Cinzel-VariableFont_wght.ttf"
ALEGREYA = ROOT / "client" / "fonts-src" / "AlegreyaSans" / "AlegreyaSans-Medium.ttf"
WW, WH = 1280, 800
IW = 128
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
TOL = 2.0
# skin pieces (O705): drawn by client/tools/gen_skin.py at twice the size the window shows them. Corner 54 px -> 108, crest
# 132 x 47 -> 264 x 94, the button tile 160 x 120 with 14 px corners (7 shown). The design sizes are 44, 84 x 30.
CORNER_PX = 108
CREST_PX = (264, 94)
BTN_PX = (160, 120)
BTN_BORDER = 14
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


def skin_pieces():
    """file name -> RGBA image of every skin piece, drawn at the size it is shown at, twice (O705)."""
    import gen_skin as gs

    corner = gs.ornament_corner(CORNER_PX, px=CORNER_PX / 44)
    out = {}
    for nm, fx, fy in (("tl", 0, 0), ("tr", 1, 0), ("bl", 0, 1), ("br", 1, 1)):
        out["skin_corner_%s.png" % nm] = gs.to_img(gs.mirror(corner, fx, fy))
    out["skin_crest.png"] = gs.to_img(gs.ornament_crest(*CREST_PX, px=CREST_PX[0] / 84))
    out["skin_btn.png"] = gs.to_img(gs.button_face(*BTN_PX, BTN_BORDER, "normal", seed=11, rim_w=2))
    return out


def ico_frame_bmp(im):
    """One 32-bit bottom-up DIB frame of an icon file: the BITMAPINFOHEADER (height doubled for the AND mask), BGRA rows, an
    all-zero AND mask (the alpha channel does the cutting)."""
    n = im.width
    a = np.asarray(im.convert("RGBA"), np.uint8)
    bgra = a[::-1][..., [2, 1, 0, 3]]
    head = struct.pack("<IiiHHIIiiII", 40, n, 2 * n, 1, 32, 0, n * n * 4, 0, 0, 0, 0)
    mask = b"\0" * (((n + 31) // 32) * 4 * n)
    return head + np.ascontiguousarray(bgra).tobytes() + mask


def ico_bytes():
    """The icon file: classic bitmap frames up to 48 px, PNG from 64 px (O705). Some shell paths (small sizes of a
    shortcut, the notification area) read only bitmap frames of the small sizes."""
    src = Image.open(ICON).convert("RGBA")
    big = src.resize((256, 256), Image.LANCZOS)
    frames = []
    for n in ICO_SIZES:
        im = big.resize((n, n), Image.LANCZOS)
        if n <= 48:
            frames.append((n, ico_frame_bmp(im)))
        else:
            b = io.BytesIO()
            im.save(b, "PNG", optimize=True)
            frames.append((n, b.getvalue()))
    out = struct.pack("<HHH", 0, 1, len(frames))
    off = 6 + 16 * len(frames)
    for n, data in frames:
        w = 0 if n >= 256 else n
        out += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(data), off)
        off += len(data)
    return out + b"".join(d for _, d in frames)


def ico_frames(data):
    """size -> RGBA array of every frame of an .ico"""
    im = Image.open(io.BytesIO(data))
    out = {}
    for n in ICO_SIZES:
        if (n, n) in im.info.get("sizes", set()):
            im.size = (n, n)
            out[n] = np.asarray(im.convert("RGBA"), np.int16)
    return out


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


def bitmap_sizes(data):
    """sizes of the frames of an .ico file that are DIB (not PNG), read from the file itself"""
    n = struct.unpack_from("<H", data, 4)[0]
    out = []
    for i in range(n):
        w, _h, _c, _r, _p, _b, _size, off = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
        if data[off : off + 8] != b"\x89PNG\r\n\x1a\n":
            out.append(w or 256)
    return sorted(out)


def decode(b):
    return np.asarray(Image.open(io.BytesIO(b)).convert("RGB"), np.int16)


def check():
    bad = False

    def fail(msg):
        nonlocal bad
        print("FAIL " + msg)
        bad = True

    for name, want_im in skin_pieces().items():
        p = OUT / name
        if not p.is_file():
            fail("%s missing" % name)
            continue
        got = np.asarray(Image.open(p).convert("RGBA"), np.int16)
        want = np.asarray(want_im, np.int16)
        if want.shape != got.shape or float(np.abs(got - want).mean()) > TOL:
            fail("%s differs from a fresh render" % name)
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
    p = OUT / "app.ico"
    if not p.is_file():
        fail("app.ico missing")
    else:
        want, got = ico_frames(ico_bytes()), ico_frames(p.read_bytes())
        if sorted(got) != list(ICO_SIZES):
            fail("app.ico has the sizes %s, want %s" % (sorted(got), list(ICO_SIZES)))
        elif any(float(np.abs(got[n] - want[n]).mean()) > TOL for n in ICO_SIZES):
            fail("app.ico differs from a fresh render")
        elif bitmap_sizes(p.read_bytes()) != [n for n in ICO_SIZES if n <= 48]:
            fail("app.ico: frames up to 48 px must be bitmaps, from 64 px PNG")
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
    (OUT / "app.ico").write_bytes(ico_bytes())
    for name, im in skin_pieces().items():
        (OUT / name).write_bytes(png(im))
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
