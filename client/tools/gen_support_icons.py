#!/usr/bin/env python3
"""Procedural 32x32 icons for the spell support runes (client module game_spellsupports).

Run: python3 client/tools/gen_support_icons.py [OUTDIR]
     default OUTDIR: client/overlay/data/images/game/supports  ->  <key>.png, one per support

Same drawing kit as the spell icons (gen_spell_icons.py: its colour themes and glyphs), on a carved rune-stone plate
(an octagon with a bevel) instead of the spell's square plate, so a rune never reads as a spell. The keys and the order
come from SUPPORTS below; they must match server/data/lib/chaos_supports_config.lua (checked when the config is found).
Our own procedural art: nothing is copied from anywhere.
"""
import math, os, re, sys
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_spell_icons import COL, GLYPH  # noqa: E402

S = 128
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(ROOT, 'client', 'overlay', 'data', 'images', 'game', 'supports')
CONFIG = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_supports_config.lua')

SUPPORTS = [  # (key, theme, glyph)
    ('emberbrand', 'fire', 'burst'), ('rimebrand', 'frost', 'crystal'), ('dawnbrand', 'holy', 'cross'),
    ('gravebrand', 'necrotic', 'skull'), ('stormbrand', 'arcane', 'bolt'), ('quickening', 'light', 'swirl'),
    ('thrift', 'water', 'drop'), ('keenedge', 'steel', 'sword'), ('echo', 'arcane', 'twin'),
    ('fork', 'light', 'arrows'), ('breadth', 'ember', 'wave'), ('shatter', 'frost', 'thorns'),
    ('deathburst', 'blood', 'burst'), ('surge', 'light', 'rift'), ('reprisal', 'steel', 'shield'),
    ('bloodthirst', 'blood', 'drop'), ('siphon', 'arcane', 'drop'), ('sunder', 'ember', 'hammer'),
    ('hex', 'shadow', 'eye'), ('mercy', 'nature', 'leaf'),
]


def stone(n=8, r=60):
    return [(64 + r * math.cos(math.pi * 2 * i / n + math.pi / n), 64 + r * math.sin(math.pi * 2 * i / n + math.pi / n))
            for i in range(n)]


def render(theme, glyph):
    c = COL[theme]
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon(stone(r=62), fill=(96, 88, 92, 255))           # bevel
    d.polygon(stone(r=54), fill=(28, 22, 26, 255))           # carved face
    d.line(stone(r=58) + [stone(r=58)[0]], fill=(150, 138, 140, 255), width=3)
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((22, 22, S - 22, S - 22), fill=c + (130,))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(12)))
    g = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    GLYPH[glyph](ImageDraw.Draw(g), c + (255,))
    g = g.resize((78, 78), Image.LANCZOS)
    shadow = Image.new('RGBA', g.size, (0, 0, 0, 0))
    shadow.putalpha(g.getchannel('A').point(lambda v: int(v * .7)))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(2)), (27, 27))
    img.alpha_composite(g, (25, 25))
    return img


def check_config():
    if not os.path.exists(CONFIG):
        return
    keys = re.findall(r'\{key\s*=\s*"(\w+)"', open(CONFIG, encoding='utf-8').read())
    mine = [k for k, _t, _g in SUPPORTS]
    if keys != mine:
        raise SystemExit('SUPPORTS does not match chaos_supports_config.lua: %s vs %s' % (mine, keys))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    check_config()
    os.makedirs(out, exist_ok=True)
    for key, theme, glyph in SUPPORTS:
        render(theme, glyph).resize((32, 32), Image.LANCZOS).save(os.path.join(out, key + '.png'), optimize=True)
    print(len(SUPPORTS), 'support icons written to', out)


if __name__ == '__main__':
    main()
