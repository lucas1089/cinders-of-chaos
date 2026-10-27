#!/usr/bin/env python3
"""Test of gen_skin_variants.py: both skins draw the same files at the classic sizes, rings are concentric, the recolour keeps
alpha and status colours, the Lua palette matches the colours the generator draws with.

Usage: python3 client/tools/gen_skin_variants_test.py   (Pillow; not -I)
"""
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_orb_art  # noqa: E402
import gen_skin_variants as G  # noqa: E402
from PIL import Image  # noqa: E402

n = 0


def ok(cond, msg):
    global n
    n += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def hexs(c):
    return '#%02x%02x%02x' % c[:3]


forge, abyss = G.build('forge'), G.build('abyss')
ok(set(forge) == set(abyss), 'both skins draw the same files: %s' % sorted(set(forge) ^ set(abyss)))
ok(len(forge) >= 100, 'the file set is large enough (%d)' % len(forge))
for name, art in (('forge', forge), ('abyss', abyss)):
    for v, img in art.items():
        ok(img.mode == 'RGBA' and img.width > 0, '%s %s is RGBA' % (name, v))
        classic = G.classic_path(v)
        if os.path.isfile(classic):
            ok(Image.open(classic).size == img.size, '%s %s has the classic size' % (name, v))
        ok(v.endswith('.png') and not v.startswith('/') and '..' not in v, 'relative path ' + v)
# the files the styles read are all there (windows, buttons, tabs, scroll bar, HUD, rings, chat)
for need in ('images/chaos/skin/window.png', 'images/chaos/skin/button.png', 'images/chaos/skin/button_primary.png',
             'images/chaos/skin/tab.png', 'images/ui/scrollbar.png', 'images/chaos/skin/hud_plate.png',
             'images/ui/console.png', 'images/chaos/skin/tooltip.png', 'images/chaos/skin/menubar.png',
             'images/chaos/itemslot.png', 'images/chaos/progress_frame.png', 'images/chaos/skin/orn_crest.png'):
    ok(need in forge and need in abyss, 'drawn: ' + need)

# the skins really differ from each other (not a recolour copy) in their frames
ok(forge['images/chaos/skin/window.png'].tobytes() != abyss['images/chaos/skin/window.png'].tobytes(), 'windows differ')

# button sheets: four states, hover is not the normal face
for art in (forge, abyss):
    sheet = art['images/chaos/skin/button.png']
    ok(sheet.size == (64, 96), 'button sheet 64 x 96')
    faces = [sheet.crop((0, 24 * i, 64, 24 * i + 24)).tobytes() for i in range(4)]
    ok(len(set(faces)) == 4, 'four different button states')

# orb rings: 2x the orb size, the opening centred and as wide as the mask
for style, art in (('forge', forge), ('abyss', abyss)):
    for s in G.read_orb_sizes():
        ring = art['modules/game_shaderfx/images/orb_ring_%d.png' % s]
        ok(ring.size == (2 * s, 2 * s), '%s ring %d size' % (style, s))
        hole = gen_orb_art.opening(ring)
        ok(hole is not None, '%s ring %d has an opening' % (style, s))
        mask_r = G.liquid(s) - 1.0
        ok(abs(hole[0] - s) <= 1 and abs(hole[1] - s) <= 1, '%s ring %d centred (%s)' % (style, s, hole))
        ok(abs(hole[2] - mask_r) <= 2, '%s ring %d opening radius %.2f, mask %.2f' % (style, s, hole[2], mask_r))
        a = ring.getchannel('A')
        ok(a.getpixel((0, 0)) == 0 and a.getpixel((2 * s - 1, 2 * s - 1)) == 0, 'corners of the ring are clear')
        ok(sum(1 for v in a.tobytes() if v) > s * s // 2, 'a ring has a body')

# HUD: the portrait cover is open at the portrait centre and closed at the corner
for art in (forge, abyss):
    cover = art['images/chaos/skin/hud_portrait_cover.png']
    ok(cover.getpixel((47, 48))[3] == 0, 'portrait opening')
    ok(cover.getpixel((47, 12))[3] > 0, 'cover closed outside the opening')

# recolour: alpha kept, red status colours kept, neutral grey through the ramp, gold through the accent ramp
src = Image.new('RGBA', (4, 1))
src.putdata([(0, 0, 0, 0), (200, 30, 30, 255), (128, 128, 128, 200), (230, 180, 70, 255)])
for style in (G.Forge, G.Abyss):
    out = G.recolor(src, style.NEUTRAL, style.ACCENT)
    px = [out.getpixel((i, 0)) for i in range(4)]
    ok(px[0][3] == 0, 'transparent stays transparent')
    ok(px[1] == (200, 30, 30, 255), 'a red pixel is kept')
    ok(px[2][3] == 200 and px[2][:3] != (128, 128, 128), 'grey is recoloured, alpha kept')
    ok(px[3][:3] != (230, 180, 70), 'gold is recoloured')

# the Lua palette (skin_core.lua) holds the colours the generator draws with
lua = open(os.path.join(G.OVERLAY, 'modules', 'client_chaos_theme', 'skin_core.lua'), encoding='utf-8').read()


def lua_palette(name):
    block = re.search(r'\n  %s = \{(.*?)\n  \},' % name, lua, re.S).group(1)
    return dict(re.findall(r"(\w+) = '(#[0-9a-fA-F]{6})'", block))


f, a = lua_palette('forge'), lua_palette('abyss')
ok(f['bg'] == hexs(G.Forge.P['void']) and f['ironLight'] == hexs(G.Forge.P['hi']) and f['iron'] == hexs(G.Forge.P['iron']), 'forge iron colours')
ok(f['accent'] == hexs(G.Forge.P['ember']) and f['accent2'] == hexs(G.Forge.P['ember_hi']), 'forge ember colours')
ok(f['health'] == hexs(G.Forge.P['red']) and f['mana'] == hexs(G.Forge.P['blue']), 'forge health and mana')
ok(a['bg'] == hexs(G.Abyss.P['void']) and a['iron'] == hexs(G.Abyss.P['obs']), 'abyss void and obsidian')
ok(a['gold'] == hexs(G.Abyss.P['gold']) and a['goldBright'] == hexs(G.Abyss.P['gold_hi']), 'abyss gold')
ok(a['accent'] == hexs(G.Abyss.P['violet']) and a['accent2'] == hexs(G.Abyss.P['teal']), 'abyss violet and teal')
ok(a['health'] == hexs(G.Abyss.P['red']) and a['mana'] == hexs(G.Abyss.P['blue']), 'abyss health and mana')

# the manifest text lists exactly the drawn files in sorted order and is stable
for style in G.SKIN_IDS:
    mp = os.path.join(G.skin_dir(style), 'manifest.lua')
    if os.path.isfile(mp):
        files = re.findall(r"^    '(.+)',$", open(mp).read(), re.M)
        ok(files == sorted(files), 'manifest sorted')
        ok(set(files) == set(G.build(style)), 'manifest lists the drawn files')

print('gen_skin_variants_test: %d checks ok' % n)
