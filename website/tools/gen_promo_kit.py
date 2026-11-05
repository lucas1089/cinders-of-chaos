#!/usr/bin/env python3
"""Social and forum promo kit: square posts, stories, class cards and forum banners in pt-BR and en (website/README.md
"Promo kit"; docs/PROMO.md says where each one goes).

Built from the repository's own art, like the streamer kit (gen_streamer_kit.py, gen_site_art.py): the backdrop, the gold
panel, the wordmark, the class badges, the same fonts. Nothing third-party. Texts and dates: website/tools/promo_source.json
(an empty date draws no date line). Needs Pillow and numpy. Deterministic.

COMMITTED in website/overlay/plugins/chaos/assets/promo/, checked by --check in CI (fx venv):
  post/      beta-1080.LANG.jpg, launch-1080.LANG.jpg (1080x1080, Instagram / Facebook / Discord)
  story/     beta-1080x1920.LANG.jpg (stories, Reels / TikTok / Shorts cover)
  classes/   CLASS-1080.LANG.jpg (one card per class line)
  forum/     banner-728x90.LANG.png, signature-468x60.LANG.png

  python3 -I website/tools/gen_promo_kit.py                 write the committed files
  python3 -I website/tools/gen_promo_kit.py --check         exit 1 when a file is stale, extra or missing
  python3 -I website/tools/gen_promo_kit.py --preview DIR   write every file to DIR
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
SOURCE = os.path.join(HERE, "promo_source.json")
OUT = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "assets", "promo")
LANGS = ("pt-BR", "en")


def load():
    sys.path.insert(0, HERE)
    import gen_streamer_kit as gsk  # noqa: E402
    gsa = gsk.load_art()
    with open(SOURCE, encoding="utf-8") as f:
        src = json.load(f)
    return gsk, gsa, src


def badges_row(img, gsa, cx, y, size, gap=12):
    n = len(gsa.CLASSES)
    x = cx - (n * size + (n - 1) * gap) // 2
    for name, _ in gsa.CLASSES:
        img.alpha_composite(gsa.badge(name, size), (x, y))
        x += size + gap


def headline(img, gsa, cx, y, text, size, width):
    gsa.gold_text(img, (cx, y), text, gsa.fit(size, "display", text, width), anchor="mm", glow=0.5, spacing=3)


def make_event_post(gsk, gsa, src, lang, kind, W, H, seed):
    """A beta or launch poster: wordmark, headline, date line, subline, features, class badges, site."""
    t = src["text"][lang]
    date = src["dates"][lang].get(kind, "")
    img = gsk.scene(gsa, W, H, 0.32, 0.5, seed)
    gsa.panel(img, (24, 24, W - 24, H - 24), corner=48, fill_alpha=0, gold=True)
    tall = H > W
    cx = W // 2
    lg = gsk.wordmark(gsa, 760 if tall else 600, tagline=False)
    y = 150 if tall else 56
    img.alpha_composite(lg, (cx - lg.width // 2, y))
    y += lg.height + (40 if tall else 26)
    gsa.plain_text(img, (cx, y), t["tag"], gsa.fit(40 if tall else 34, "italic", t["tag"], W - 160), fill=gsa.GOLD_3, anchor="mm")
    y += 120 if tall else 92
    headline(img, gsa, cx, y, t[kind], 132 if tall else 108, W - 140)
    y += 110 if tall else 84
    if date:
        gsa.plain_text(img, (cx, y), date, gsa.fit(52, "heading", date, W - 160), fill=gsa.GOLD_3, anchor="mm")
        y += 80 if tall else 70
    gsa.divider(img, cx, y, 300)
    y += 70 if tall else 50
    sub = t[kind + "_sub"]
    gsa.plain_text(img, (cx, y), sub, gsa.fit(40, "italic", sub, W - 160), fill=gsa.TEXT, anchor="mm")
    y += 130 if tall else 64
    if tall:
        for line in t["features"]:
            gsa.plain_text(img, (cx, y), line, gsa.fit(48, "heading", line, W - 200), fill=gsa.TEXT, anchor="mm")
            y += 84
        y += 90
    badges_row(img, gsa, cx, y, 116 if tall else 80, 18 if tall else 14)
    foot = "%s %s" % (t["join"], src["site"])
    gsa.plain_text(img, (cx, H - 150 if tall else H - 110), t["platforms"], gsa.font(36, "heading"), fill=gsa.GOLD_3, anchor="mm")
    gsa.plain_text(img, (cx, H - 90 if tall else H - 62), foot, gsa.fit(34, "heading", foot, W - 160), fill=gsa.TEXT, anchor="mm")
    return img.convert("RGB")


def jpg_bytes(img, quality=88):
    import io
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "JPEG", quality=quality, optimize=True, progressive=True, subsampling=0)
    return buf.getvalue()


def make_class_card(gsk, gsa, src, lang, name, seed):
    t = src["text"][lang]
    title, pitch, asc_a, asc_b = src["classes"][name][lang]
    W = H = 1080
    cx = W // 2
    img = gsk.scene(gsa, W, H, 0.4, 0.5, seed)
    gsa.panel(img, (24, 24, W - 24, H - 24), corner=48, fill_alpha=0, gold=True)
    lg = gsk.wordmark(gsa, 330, tagline=False)
    img.alpha_composite(lg, (cx - lg.width // 2, 50))
    img.alpha_composite(gsa.badge(name, 240), (cx - 120, 64 + lg.height))
    y = 64 + lg.height + 240 + 34
    gsa.plain_text(img, (cx, y), t["class_title"].upper(), gsa.font(30, "heading"), fill=gsa.GOLD_3, anchor="mm")
    headline(img, gsa, cx, y + 70, title.upper(), 96, W - 160)
    gsa.divider(img, cx, y + 140, 260)
    y += 200
    for line in gsa.wrap(pitch, gsa.font(40, "italic"), W - 200):
        gsa.plain_text(img, (cx, y), line, gsa.font(40, "italic"), fill=gsa.TEXT, anchor="mm")
        y += 52
    y += 30
    for line in (asc_a, asc_b):
        gsa.plain_text(img, (cx, y), line, gsa.fit(38, "heading", line, W - 200), fill=gsa.GOLD_3, anchor="mm")
        y += 58
    gsa.plain_text(img, (cx, H - 66), src["site"], gsa.font(32, "heading"), fill=gsa.TEXT, anchor="mm")
    return img.convert("RGB")


def make_forum(gsk, gsa, src, lang, W, H, seed):
    """Forum banner (728x90) and signature (468x60): wordmark left, the line and the site right."""
    t = src["text"][lang]
    img = gsk.scene(gsa, W, H, 0.4, 0.45, seed)
    gsa.panel(img, (2, 2, W - 3, H - 3), corner=max(6, H // 6), fill_alpha=0, gold=True)
    lg = gsk.wordmark(gsa, int(W * 0.34), tagline=False)
    if lg.height > H - 14:
        s = (H - 14) / lg.height
        lg = lg.resize((max(1, int(lg.width * s)), H - 14))
    img.alpha_composite(lg, (10, (H - lg.height) // 2))
    x0 = 10 + lg.width + 12
    cx = (x0 + W - 10) // 2
    width = W - 10 - x0 - 8
    big = max(10, H // 4)
    gsa.plain_text(img, (cx, H // 2 - big // 2 - 2), t["forum"], gsa.fit(big + 4, "heading", t["forum"], width, low=8), fill=gsa.GOLD_3, anchor="mm")
    gsa.plain_text(img, (cx, H // 2 + big // 2 + 4), src["site"], gsa.fit(big, "heading", src["site"], width, low=8), fill=gsa.TEXT, anchor="mm")
    return img.convert("RGB")


def image_files():
    gsk, gsa, src = load()
    out = {}
    for i, lang in enumerate(LANGS):
        out["post/beta-1080.%s.jpg" % lang] = jpg_bytes(make_event_post(gsk, gsa, src, lang, "beta", 1080, 1080, 71 + i))
        out["post/launch-1080.%s.jpg" % lang] = jpg_bytes(make_event_post(gsk, gsa, src, lang, "launch", 1080, 1080, 73 + i))
        out["story/beta-1080x1920.%s.jpg" % lang] = jpg_bytes(make_event_post(gsk, gsa, src, lang, "beta", 1080, 1920, 75 + i))
        for j, (name, _) in enumerate(gsa.CLASSES):
            out["classes/%s-1080.%s.jpg" % (name, lang)] = jpg_bytes(make_class_card(gsk, gsa, src, lang, name, 80 + j))
        out["forum/banner-728x90.%s.png" % lang] = gsk.png_bytes(make_forum(gsk, gsa, src, lang, 728, 90, 91), 128)
        out["forum/signature-468x60.%s.png" % lang] = gsk.png_bytes(make_forum(gsk, gsa, src, lang, 468, 60, 92), 128)
    return out


def walk(base):
    found = {}
    for dp, _, names in os.walk(base):
        for n in names:
            full = os.path.join(dp, n)
            found[os.path.relpath(full, base).replace(os.sep, "/")] = full
    return found


def write(dest, files):
    for name, data in sorted(files.items()):
        path = os.path.join(dest, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    imgs = image_files()
    if "--preview" in argv:
        write(argv[argv.index("--preview") + 1], imgs)
        return 0
    have = walk(OUT) if os.path.isdir(OUT) else {}
    if "--check" in argv:
        bad = [n for n, d in imgs.items() if n not in have or open(have[n], "rb").read() != d]
        extra = [n for n in have if n not in imgs]
        for n in bad + extra:
            print("promo kit: stale, extra or missing: " + n, file=sys.stderr)
        if bad or extra:
            print("promo kit: run python3 -I website/tools/gen_promo_kit.py (the fx venv in CI)", file=sys.stderr)
            return 1
        print("promo kit: %d files up to date" % len(imgs))
        return 0
    for n in have:
        if n not in imgs:
            os.remove(have[n])
    write(OUT, imgs)
    print("promo kit: wrote %d files to %s" % (len(imgs), os.path.relpath(OUT, REPO)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
