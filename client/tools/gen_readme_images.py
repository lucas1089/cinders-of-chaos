#!/usr/bin/env python3
"""The images of the root README.md (docs/images/), made from screenshots of the real client.

  python3 -I client/tools/gen_readme_images.py [name ...]      (no argument = all; names: banner, classes, tree, ...)

Every feature card is a 900x500 window of the Chaos UI skin (client_chaos_theme): the skin's window frame
(data/images/chaos/skin/window.png, 9-slice, shown at 1.5x), its gold corner pieces and crest, a title in the
title font (Cinzel Bold), a caption in the dialogue font (IM Fell English) and labels in Alegreya SC, all from the
OFL fonts in client/fonts-src/. The window's floor glows with the lava of the login artwork (data/images/title.png).
The banner (1280x320) is the login artwork with the Cinders of Chaos logo (docs/brand/cinders_logo.png).

Inputs: client/tools/art_src/readme/*.png, screenshots of the client (Linux build at 1440x900, the Chaos skin) on a
local test server with test characters and test data only. A window was shot twice, once over a black and once over a
white root with the game view hidden, and keyed from the pair (alpha = 1 - (white - black)), so it keeps its real
outline, ornaments and shadow; the other inputs are plain crops of the screen. class_outfits.png is the class looks
(server class_looks_core.lua) drawn by the client's creature widget at 2x, one column per line: base class, then
its two ascensions. Inputs are stored as 256-colour PNGs. To refresh one, shoot the window again the same way and
replace its file; the names are the ones the gen_* functions below ask for.

Needs Pillow and numpy. Deterministic for given library and font versions.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
SRC = os.path.join(HERE, 'art_src', 'readme')
OUT = os.path.join(REPO, 'docs', 'images')
IMG = os.path.join(HERE, '..', 'overlay', 'data', 'images')
SKIN = os.path.join(IMG, 'chaos', 'skin')
FONTS = os.path.join(HERE, '..', 'fonts-src')

W, H = 900, 500
K = 1.5                                   # skin scale on the cards
GOLD = (232, 196, 119)                    # ChaosTheme TITLE_COLOR #e8c477
GOLD_DIM = (196, 160, 96)
TEXT = (222, 208, 180)
MUTED = (170, 150, 120)
ROLE = {'Tank': (110, 160, 230), 'Off-tank': (110, 160, 230), 'Healer': (110, 210, 120), 'Support': (110, 210, 120),
        'Single target': (235, 110, 80), 'Burst': (235, 110, 80), 'Area': (245, 165, 60), 'Pets': (190, 140, 245)}


# ---------------------------------------------------------------- basics
def load(path):
    return Image.open(path).convert('RGBA')


def src(name):
    return load(os.path.join(SRC, name + '.png'))


def font(kind, size):
    if kind == 'title':
        f = ImageFont.truetype(os.path.join(FONTS, 'Cinzel', 'Cinzel-VariableFont_wght.ttf'), size)
        try:
            f.set_variation_by_axes([700])
        except (OSError, AttributeError):
            pass
        return f
    path = {'heading': ('AlegreyaSC', 'AlegreyaSC-Bold.ttf'), 'dialogue': ('IMFellEnglish', 'IMFeENrm28P.ttf'),
            'body': ('AlegreyaSans', 'AlegreyaSans-Medium.ttf')}[kind]
    return ImageFont.truetype(os.path.join(FONTS, *path), size)


def scaled(im, k):
    if abs(k - 1) < 1e-3:
        return im
    w, h = max(1, round(im.width * k)), max(1, round(im.height * k))
    if k > 1 and abs(k - round(k)) < 1e-3:
        return im.resize((w, h), Image.NEAREST)
    return im.resize((w, h), Image.LANCZOS)


def nine(im, w, h, l, t, r, b):
    """9-slice im (borders l t r b) to w x h; edges and centre stretched like the client does"""
    out = Image.new('RGBA', (w, h))
    iw, ih = im.size
    xs, dxs = [0, l, iw - r, iw], [0, l, w - r, w]
    ys, dys = [0, t, ih - b, ih], [0, t, h - b, h]
    for i in range(3):
        for j in range(3):
            box = (xs[i], ys[j], xs[i + 1], ys[j + 1])
            size = (dxs[i + 1] - dxs[i], dys[j + 1] - dys[j])
            if size[0] <= 0 or size[1] <= 0 or box[2] <= box[0] or box[3] <= box[1]:
                continue
            out.alpha_composite(im.crop(box).resize(size, Image.BICUBIC), (dxs[i], dys[j]))
    return out


def text_size(draw, s, f):
    x0, y0, x1, y1 = draw.textbbox((0, 0), s, font=f)
    return x1 - x0, y1 - y0, x0, y0


def draw_text(img, xy, s, f, fill, anchor='mm', shadow=2, glow=None):
    """text with a dark shadow (and an optional soft glow behind it)"""
    layer = Image.new('RGBA', img.size)
    d = ImageDraw.Draw(layer)
    if glow:
        g = Image.new('RGBA', img.size)
        ImageDraw.Draw(g).text(xy, s, font=f, fill=glow, anchor=anchor)
        layer.alpha_composite(g.filter(ImageFilter.GaussianBlur(6)))
    if shadow:
        sh = Image.new('RGBA', img.size)
        ImageDraw.Draw(sh).text((xy[0] + shadow * 0.5, xy[1] + shadow), s, font=f, fill=(0, 0, 0, 230), anchor=anchor)
        layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(1)))
    d.text(xy, s, font=f, fill=fill, anchor=anchor)
    img.alpha_composite(layer)


def drop_shadow(img, piece, x, y, radius=7, offset=(3, 6), strength=0.75):
    a = piece.getchannel('A')
    pad = radius * 3
    sh = Image.new('L', (piece.width + pad * 2, piece.height + pad * 2))
    sh.paste(a, (pad, pad))
    sh = sh.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: int(v * strength))
    black = Image.new('RGBA', sh.size, (0, 0, 0, 255))
    black.putalpha(sh)
    img.alpha_composite(black, (x - pad + offset[0], y - pad + offset[1]))


def framed(im):
    """a plain crop (no window of its own) gets a thin frame: black, the skin's gold, black"""
    out = Image.new('RGBA', (im.width + 6, im.height + 6), (8, 6, 8, 255))
    d = ImageDraw.Draw(out)
    d.rectangle((1, 1, out.width - 2, out.height - 2), outline=(168, 116, 32, 255))
    d.rectangle((2, 2, out.width - 3, out.height - 3), outline=(60, 40, 14, 255))
    out.alpha_composite(im.convert('RGBA'), (3, 3))
    return out


# ---------------------------------------------------------------- the card
_lava = None


def lava():
    """the lava band at the bottom of the login artwork, blurred: the warm floor of every card"""
    global _lava
    if _lava is None:
        t = Image.open(os.path.join(IMG, 'title.png')).convert('RGB')
        band = t.crop((0, 1030, 1920, 1300)).resize((W, 150), Image.LANCZOS)
        _lava = band.filter(ImageFilter.GaussianBlur(10))
    return _lava


def card_base(seed):
    """the window: skin frame, dark floor with a lava glow at the bottom, a few embers"""
    win = load(os.path.join(SKIN, 'window.png'))
    frame = nine(scaled(win, K), W, H, int(12 * K), int(32 * K), int(12 * K), int(12 * K))
    img = Image.new('RGBA', (W, H), (10, 8, 10, 255))
    img.alpha_composite(frame)
    # the floor: the window's own interior, warmed from below by the login lava
    inner = (int(12 * K) + 4, int(32 * K) + 2, W - int(12 * K) - 4, H - int(12 * K) - 4)
    glow = Image.new('RGBA', (W, H))
    lv = lava().convert('RGBA')
    mask = Image.linear_gradient('L').resize((W, lv.height)).point(lambda v: int(v * 0.42))
    lv.putalpha(mask)
    glow.alpha_composite(lv, (0, H - lv.height))
    clip = Image.new('L', (W, H))
    ImageDraw.Draw(clip).rectangle(inner, fill=255)
    glow.putalpha(Image.fromarray(np.minimum(np.asarray(glow.getchannel('A')), np.asarray(clip))))
    img.alpha_composite(glow)
    # vignette inside the frame
    vig = Image.new('L', (W, H), 0)
    ImageDraw.Draw(vig).rectangle(inner, fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(28))
    dark = Image.new('RGBA', (W, H), (0, 0, 0, 255))
    dark.putalpha(Image.fromarray(((255 - np.asarray(vig, np.float32)) * 0.5).astype(np.uint8)))
    under = Image.new('RGBA', (W, H))
    under.alpha_composite(dark)
    under.putalpha(Image.fromarray(np.minimum(np.asarray(under.getchannel('A')), np.asarray(clip))))
    img.alpha_composite(under)
    embers(img, inner, seed)
    return img


def embers(img, box, seed, n=26):
    ember = load(os.path.join(IMG, 'chaos', 'login', 'ember.png'))
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    for _ in range(n):
        s = rnd.uniform(0.25, 0.7)
        e = scaled(ember, s)
        a = e.getchannel('A').point(lambda v, k=rnd.uniform(0.3, 0.9): int(v * k))
        e.putalpha(a)
        y = int(y0 + (y1 - y0) * (1 - rnd.random() ** 1.8))
        img.alpha_composite(e, (rnd.randint(x0, x1 - e.width), min(y, y1 - e.height)))


def ornaments(img):
    """the gold corner pieces and the crest of the skin (client_chaos_theme decorateWindow)"""
    s = round(44 * K * 0.9)
    for name, x, y in (('tl', 0, 0), ('tr', W - s, 0), ('bl', 0, H - s), ('br', W - s, H - s)):
        img.alpha_composite(load(os.path.join(SKIN, 'orn_corner_%s.png' % name)).resize((s, s), Image.LANCZOS), (x, y))


def crest(img, y):
    c = load(os.path.join(SKIN, 'orn_crest.png'))
    img.alpha_composite(c, ((W - c.width) // 2, int(y - c.height / 2)))


def separator(img, y, width=560):
    sep = load(os.path.join(IMG, 'chaos', 'separator.png'))
    img.alpha_composite(nine(sep, width, sep.height, 28, 0, 28, 0), ((W - width) // 2, y))


TITLE_Y = 25                     # centre of the title bar (32 px at 1x)
AREA = (34, 60, W - 34, 426)     # where the screenshots go
CAPTION_Y = 469


def card(name, title, caption, layout, seed=1, extra=None):
    img = card_base(seed)
    if extra:
        extra(img)
    if layout is not None:
        place(img, layout, AREA)
    ornaments(img)
    draw_text(img, (W // 2, TITLE_Y + 5), title.upper(), font('title', 23), GOLD, glow=(255, 120, 30, 90))
    separator(img, CAPTION_Y - 30)
    crest(img, CAPTION_Y - 27)
    draw_text(img, (W // 2, CAPTION_Y), caption, font('dialogue', 19), TEXT)
    save(img, name)


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.png')
    rgb = img.convert('RGB')
    rgb.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)
    print('wrote', os.path.relpath(path, REPO), rgb.size, '%d KB' % (os.path.getsize(path) // 1024))


# ---------------------------------------------------------------- layout: Row / Col of screenshots
GAP = 16


class Shot:
    """a screenshot at k x its pixels; flat = a plain crop (gets a frame); label = small caption under it"""

    def __init__(self, name, k=1.0, flat=False, label=None, dy=0):
        im = src(name)
        self.im = framed(im) if flat else im
        self.k, self.label, self.dy = k, label, dy

    def size(self, s):
        w, h = self.im.width * self.k * s, self.im.height * self.k * s
        return w, h + (22 if self.label else 0)

    def draw(self, img, x, y, s):
        piece = scaled(self.im, self.k * s)
        drop_shadow(img, piece, int(x), int(y + self.dy))
        img.alpha_composite(piece, (int(x), int(y + self.dy)))
        if self.label:
            draw_text(img, (int(x + piece.width / 2), int(y + self.dy + piece.height + 12)), self.label,
                      font('heading', 15), GOLD_DIM, shadow=1)


class Row:
    def __init__(self, *items, gap=GAP, align='center'):
        self.items, self.gap, self.align = items, gap, align

    def size(self, s):
        sizes = [i.size(s) for i in self.items]
        return sum(w for w, _ in sizes) + self.gap * (len(sizes) - 1), max(h for _, h in sizes)

    def draw(self, img, x, y, s):
        _, hh = self.size(s)
        for i in self.items:
            w, h = i.size(s)
            oy = {'center': (hh - h) / 2, 'top': 0, 'bottom': hh - h}[self.align]
            i.draw(img, x, y + oy, s)
            x += w + self.gap


class Col:
    def __init__(self, *items, gap=GAP, align='center'):
        self.items, self.gap, self.align = items, gap, align

    def size(self, s):
        sizes = [i.size(s) for i in self.items]
        return max(w for w, _ in sizes), sum(h for _, h in sizes) + self.gap * (len(sizes) - 1)

    def draw(self, img, x, y, s):
        ww, _ = self.size(s)
        for i in self.items:
            w, h = i.size(s)
            ox = {'center': (ww - w) / 2, 'left': 0, 'right': ww - w}[self.align]
            i.draw(img, x + ox, y, s)
            y += h + self.gap


def place(img, layout, box):
    """the layout at its own size, or smaller when it does not fit the box; centred"""
    x0, y0, x1, y1 = box
    w, h = layout.size(1)
    s = min(1.0, (x1 - x0) / w, (y1 - y0) / h)
    w, h = layout.size(s)
    layout.draw(img, x0 + ((x1 - x0) - w) / 2, y0 + ((y1 - y0) - h) / 2, s)


# ---------------------------------------------------------------- the cards
CLASSES = [
    # base line, plays as, (ascension, role) x 2; vocation order of the sprites in class_outfits.png
    ('Warrior', 'Melee, heavy armour', ('Juggernaut', 'Tank'), ('Berserker', 'Area')),
    ('Ranger', 'Bows and crossbows', ('Deadeye', 'Single target'), ('Beastmaster', 'Pets')),
    ('Mystic', 'Spells, wands, rods', ('Elementalist', 'Area'), ('Illusionist', 'Healer')),
    ('Thief', 'Light blades, stealth', ('Ninja', 'Burst'), ('Samurai', 'Off-tank')),
    ('Necromancer', 'Summoner, curses', ('Lich', 'Single target'), ('Bone Lord', 'Pets')),
    ('Monk', 'Unarmed, chi', ('Shadowfist', 'Burst'), ('Iron Sage', 'Healer')),
    ('Templar', 'Holy melee, aura', ('Inquisitor', 'Area'), ('Sentinel', 'Tank')),
]
ROLE_TEXT = {'Tank': 'Tank', 'Area': 'Area damage', 'Single target': 'Single target', 'Pets': 'Pets',
             'Healer': 'Healer', 'Burst': 'Burst', 'Off-tank': 'Duelist off-tank'}
SECOND = {'Iron Sage': 'Second healer', 'Sentinel': 'Tank, support', 'Beastmaster': 'Pets, single target',
          'Bone Lord': 'Pets, area damage'}


def outfit(sheet, col, row):
    """one outfit of class_outfits.png (cells of 128 px every 140 px: the client's creature widget, sprites at 2x),
    cut to what is drawn"""
    cell = sheet.crop((6 + col * 140, 6 + row * 140, 6 + col * 140 + 128, 6 + row * 140 + 128))
    return cell.crop(cell.getchannel('A').point(lambda v: 255 if v > 20 else 0).getbbox())


def fit_font(kind, size, text, width):
    d = ImageDraw.Draw(Image.new('L', (1, 1)))
    while size > 9 and text_size(d, text, font(kind, size))[0] > width:
        size -= 1
    return font(kind, size)


def classes_extra(img):
    sheet = src('class_outfits')
    x0, x1 = 34, W - 34
    cw = (x1 - x0) / 7
    plate = load(os.path.join(IMG, 'chaos', 'panel_dark.png'))
    top, bottom = 60, 428
    rows = [(104, 190), (198, 312), (318, 428)]          # (top, bottom) of the base sprite and the two ascensions
    for i, (base, plays, a1, a2) in enumerate(CLASSES):
        cx = x0 + cw * i + cw / 2
        col = nine(plate, int(cw - 6), bottom - top, 6, 6, 6, 6)
        img.alpha_composite(col, (int(cx - col.width / 2), top))
        draw_text(img, (cx, top + 17), base, fit_font('heading', 18, base, cw - 14), GOLD, shadow=1)
        draw_text(img, (cx, top + 36), plays, fit_font('body', 13, plays, cw - 12), MUTED, shadow=1)
        for r, (name, role) in enumerate(((None, None), a1, a2)):
            y0, y1 = rows[r]
            room = (y1 - y0) - (34 if name else 4)
            sp = outfit(sheet, i, r)
            k = min(1.0, room / sp.height, (cw - 16) / sp.width)
            sp = scaled(sp, k)
            img.alpha_composite(sp, (int(cx - sp.width / 2), int(y0 + (room - sp.height) / 2)))
            if name:
                ImageDraw.Draw(img).line((cx - cw / 2 + 14, y0 - 4, cx + cw / 2 - 14, y0 - 4), fill=(120, 84, 30, 200))
                draw_text(img, (cx, y1 - 26), name, fit_font('heading', 15, name, cw - 12), TEXT, shadow=1)
                txt = SECOND.get(name, ROLE_TEXT[role])
                draw_text(img, (cx, y1 - 11), txt, fit_font('body', 13, txt, cw - 10), ROLE[role], shadow=1)


def gen_classes():
    card('feature_classes', 'Seven Classes, Fourteen Ascensions',
         'At level 100 every class ascends into one of two paths, each with its own role.', None, 11, classes_extra)


def gen_tree():
    card('feature_passive_tree', 'Passive Tree and Paragon',
         'Over 600 nodes, a class section for every line, and Paragon points after level 1000.',
         Row(Shot('tree_section', 0.56, flat=True), Shot('tree_paragon', 0.7)), 2)


def gen_loot():
    card('feature_loot', 'Fifteen Rarities and the Loot Filter',
         'Every drop has a rarity, an item level and modifiers from T1 to T8.',
         Row(Col(Shot('loot_ground', 0.5, flat=True), Shot('loot_tooltip', 0.62, flat=True), gap=12),
             Shot('loot_filter', 0.66)), 3)


def gen_crafting():
    card('feature_crafting', 'The Crafting Bench',
         'Put an item on the bench and see what every orb would do before you use it.',
         Row(Shot('craft_bench', 0.53), Col(Shot('store_pouches', 0.62, flat=True, label='Orbs in a pouch'))), 4)


def gen_endgame():
    card('feature_endgame', 'World Bosses, Rifts and the Tower',
         'Five colossi behind the temple portals, Rift Keys with tiers and modifiers, and the Infinity Tower.',
         Row(Shot('endgame_worldboss', 0.64, flat=True, label='A world boss'),
             Shot('endgame_rift', 0.95, flat=True, label='A rift run'),
             Shot('endgame_tower', 0.36, label='The Infinity Tower'), gap=14), 5)


def gen_bestiary():
    card('feature_bestiary', 'Bestiary and Kill Tasks',
         'Every kill fills the bestiary in four stages, and the task tracker counts on screen.',
         Row(Shot('bestiary_window', 0.6), Shot('bestiary_tracker', 1.0, label='Task tracker')), 6)


def gen_seasons():
    card('feature_seasons', 'The Season of Ash',
         'A fresh start on the season ladder, with a reward track your whole account keeps.',
         Row(Shot('seasons_window', 0.74)), 7)


def gen_pvp():
    card('feature_pvp', 'Ranked Arena and Guild Siege',
         '1v1 and 2v2 with a rating per mode, and every Saturday the guilds fight for the Chaos Obelisk.',
         Row(Shot('pvp_arena', 0.62), Shot('pvp_siege', 0.6)), 8)


def gen_leaderboards():
    card('feature_leaderboards', 'Weekly Leaderboards and Titles',
         'The top 3 of every board carry a title above their name plate for a week.',
         Row(Shot('leaderboards_window', 0.62), Shot('lb_nameplate', 1.0, flat=True, label='A weekly title')), 9)


def gen_achievements():
    card('feature_achievements', 'Achievements',
         'Over 90 deeds with points, titles and rewards, and a toast the moment you unlock one.',
         Row(Shot('achievements_window', 0.6), Shot('ach_toast', 0.8, flat=True)), 10)


def gen_pets():
    card('feature_pets', 'Pets',
         'A small companion at your side that levels with your kills and has two small abilities.',
         Row(Shot('pets_window', 0.72)), 12)


def gen_qol():
    card('feature_qol', 'Quality of Life',
         'A hunt tracker counted by the server, daily rewards and streaks, and a Town Portal for everyone.',
         Row(Shot('qol_hunt', 0.62), Shot('qol_daily', 0.6),
             Col(Shot('qol_portal_channel', 0.75, flat=True, label='Town Portal'),
                 Shot('qol_portal_open', 0.6, flat=True), gap=8)), 13)


def gen_market():
    card('feature_market', 'The Market',
         'Sell for gold or Chaos Coins, and search the offers by modifier, tier, rarity and price.',
         Row(Shot('market_window', 0.6)), 14)


def gen_store():
    card('feature_store', 'The Store and the Pouches',
         'Convenience, cosmetics and time for Chaos Coins, never gear, and pouches that gather your loot.',
         Row(Shot('store_window', 0.68), Shot('store_pouches', 0.85, flat=True)), 15)


def gen_codex():
    card('feature_codex', 'The Codex',
         'Every modifier with its tiers, every orb, gem, unique and rift modifier, looked up in the client.',
         Row(Shot('codex_window', 0.58)), 16)


def gen_client():
    card('feature_client', 'Our Client',
         'Character plate, buff bar, party frames, cast bars and NPC talk in a speech bubble.',
         Row(Col(Shot('hud_plate_buffs', 0.85, flat=True, label='Character plate and buff bar'),
                 Row(Shot('hud_party', 0.95, flat=True, label='Party frames'),
                     Shot('hud_castbar', 0.85, flat=True, label='Cast bar'), gap=14, align='top'), gap=10),
             Shot('npc_dialogue', 0.78, flat=True, label='Talking to an NPC')), 17)


def gen_banner():
    bw, bh = 1280, 320
    t = Image.open(os.path.join(IMG, 'title.png')).convert('RGB')
    # the city and the lava below the logo of the artwork, darkened towards the middle for the logo
    # (x stops short of the right edge: the artwork's small corner mark stays out of the banner)
    bg = t.crop((0, 896, 1760, 1336)).resize((bw, bh), Image.LANCZOS).convert('RGBA')
    shade = Image.new('L', (bw, bh), 0)
    ImageDraw.Draw(shade).ellipse((bw * 0.22, -bh * 0.3, bw * 0.78, bh * 1.05), fill=150)
    shade = shade.filter(ImageFilter.GaussianBlur(60))
    dark = Image.new('RGBA', (bw, bh), (6, 3, 4, 255))
    dark.putalpha(shade)
    bg.alpha_composite(dark)
    top = Image.linear_gradient('L').resize((bw, bh)).transpose(Image.FLIP_TOP_BOTTOM).point(lambda v: int(v * 0.55))
    d2 = Image.new('RGBA', (bw, bh), (6, 3, 4, 255))
    d2.putalpha(top)
    bg.alpha_composite(d2)
    embers(bg, (0, 0, bw, bh), 99, n=60)
    logo = load(os.path.join(REPO, 'docs', 'brand', 'cinders_logo.png'))
    lh = 236
    logo = logo.resize((round(logo.width * lh / logo.height), lh), Image.LANCZOS)
    glow = Image.new('RGBA', (bw, bh))
    g = Image.new('RGBA', logo.size, (255, 90, 20, 0))
    g.putalpha(logo.getchannel('A').point(lambda v: int(v * 0.55)))
    glow.alpha_composite(g, ((bw - logo.width) // 2, 2))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18)))
    bg.alpha_composite(logo, ((bw - logo.width) // 2, 2))
    draw_text(bg, (bw // 2, 262), 'Seal the rifts. Slay the colossi. Ascend.', font('dialogue', 25), (240, 226, 200),
              glow=(0, 0, 0, 200))
    feats = '  •  '.join(['DARK FANTASY', '7 CLASSES', '14 ASCENSIONS', '15 RARITIES', 'WORLD BOSSES', 'RIFTS',
                               'SEASONS'])
    draw_text(bg, (bw // 2, 296), feats, font('heading', 17), GOLD, glow=(0, 0, 0, 220))
    d = ImageDraw.Draw(bg)
    d.rectangle((0, 0, bw - 1, bh - 1), outline=(120, 80, 24, 255))
    d.rectangle((1, 1, bw - 2, bh - 2), outline=(20, 10, 8, 255))
    save(bg, 'banner')


TASKS = {'banner': gen_banner, 'classes': gen_classes, 'tree': gen_tree, 'loot': gen_loot, 'crafting': gen_crafting,
         'endgame': gen_endgame, 'bestiary': gen_bestiary, 'seasons': gen_seasons, 'pvp': gen_pvp,
         'leaderboards': gen_leaderboards, 'achievements': gen_achievements, 'pets': gen_pets, 'qol': gen_qol,
         'market': gen_market, 'store': gen_store, 'codex': gen_codex, 'client': gen_client}

if __name__ == '__main__':
    for t in sys.argv[1:] or list(TASKS):
        if t not in TASKS:
            sys.exit('unknown image %r; one of: %s' % (t, ', '.join(TASKS)))
        TASKS[t]()
