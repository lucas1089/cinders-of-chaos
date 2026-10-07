"""Effect / missile support for datspr: frame rendering, filmstrips, contact sheets, signatures."""
import os, sys, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from datspr import sprite_index

BG = (22, 22, 30, 255)


def render_frame(t, spr, phase=0, x=0, y=0, z=0, layer=0):
    """Full w*h tile frame of an effect/missile at animation phase / pattern (x,y). RGBA PIL image."""
    W, H = t.w * 32, t.h * 32
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    phase %= t.phases
    for hh in range(t.h):
        for ww in range(t.w):
            sid = t.sprites[sprite_index(t, x, y, z, layer, phase, ww, hh)]
            a = spr.sprite(sid)
            if a is None:
                continue
            canvas.alpha_composite(Image.fromarray(a, 'RGBA'), ((t.w - 1 - ww) * 32, (t.h - 1 - hh) * 32))
    return canvas


def missile_pattern(direction='east'):
    # OTClient: x pattern 0/1/2 = dx<0 / 0 / >0 ; y pattern 0/1/2 = dy<0 / 0 / >0
    return {'east': (2, 1), 'west': (0, 1), 'north': (1, 0), 'south': (1, 2)}[direction]


def frame_of(t, spr, phase, missile=False):
    if missile and t.px >= 3 and t.py >= 3:
        x, y = missile_pattern('east')
        return render_frame(t, spr, phase, x, y)
    return render_frame(t, spr, phase)


def frame_indices(t, n=4):
    if t.phases <= n:
        return list(range(t.phases))
    return sorted(set(int(round(i * (t.phases - 1) / (n - 1))) for i in range(n)))


def signature(t, spr, missile=False):
    """exact pixel signature: list of md5 of each frame's RGBA bytes (trimmed to opaque bbox) + size."""
    out = []
    for p in range(t.phases):
        im = frame_of(t, spr, p, missile)
        out.append(hashlib.md5(im.tobytes() + bytes([t.w, t.h])).hexdigest())
    return out


def filmstrip(t, spr, n=4, box=64, missile=False, bg=BG):
    idx = frame_indices(t, n)
    frames = []
    for p in idx:
        im = frame_of(t, spr, p, missile)
        s = min(box / im.width, box / im.height)
        s = min(s, 2.0) if max(im.size) <= 32 else min(s, 1.0)
        if s != 1.0:
            im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.NEAREST if s >= 1 else Image.LANCZOS)
        frames.append(im)
    strip = Image.new('RGBA', (n * box, box), bg)
    for i, im in enumerate(frames):
        strip.alpha_composite(im, (i * box + (box - im.width) // 2, (box - im.height) // 2))
    return strip


def contact_sheet(things, spr, path, cols=5, n=4, box=64, missile=False, labels=None, per=None):
    cw, ch = n * box + 6, box + 16
    rows = (len(things) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * cw, rows * ch), (10, 10, 14, 255))
    dr = ImageDraw.Draw(sheet)
    for i, t in enumerate(things):
        cx, cy = (i % cols) * cw, (i // cols) * ch
        sheet.alpha_composite(filmstrip(t, spr, n, box, missile), (cx + 3, cy + 14))
        lab = (labels[i] if labels else f'{t.id}') + f'  {t.w}x{t.h} f{t.phases}'
        dr.text((cx + 4, cy + 1), lab, fill=(255, 220, 120, 255))
        dr.rectangle([cx, cy, cx + cw - 1, cy + ch - 1], outline=(50, 50, 70, 255))
    sheet.convert('RGB').save(path)
