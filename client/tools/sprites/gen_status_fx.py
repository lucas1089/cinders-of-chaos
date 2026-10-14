#!/usr/bin/env python3
"""Status words: animated word effects ("STUNNED!", "FROZEN!", "REVIVED!" ...) with a small scene round the word, from
the owner's text effect set (Google Drive "ots/text_effects.zip", 2026-10-14; the owner: "Pode usar eles abertamente
onde forem cabiveis", use them openly where they fit; the zip holds no licence or readme).

    python3 -I gen_status_fx.py build --src DIR        # DIR = the unzipped text_effects/ folder
    python3 -I gen_status_fx.py build --check          # CI: the spec and the strips match the PICKS table below
    python3 -I gen_status_fx.py build --src DIR --check    # rebuild from the set, compare pixel for pixel
    python3 -I gen_status_fx.py preview --out DIR      # every strip 2x on a ground with the tile grid + a GIF each

The set: 15 words (blessed, charmed, cursed, drenched, feared, frozen, impaled, oblivion, reaped, revived, rooted,
shackled, shocked, smite, stunned) and second / third takes of revived and rooted. Its folder "cataclysm" holds the
OBLIVION! word (named word_oblivion here, after what it says). Each is a vertical strip of square
frames (96 px = 3 x 3 tiles; the first revived take 64 px), 8-16 frames at 110 ms, soft alpha. Only the strips
(<word>/<word>.png, <word>/vN/<word>_vN.png) are read; the set's preview sheets (_sheet, _frames, .gif) are not (the
_frames sheets also show older plain word effects for comparison, which are not used anywhere).

Written (committed; the owner gives the set for open use):
  art_import/status_fx/<name>.png   frames left to right, 96 x 96 each (import_fx_art.py's effect layout)
  art_import/status_fx.csv          the spec for import_fx_art.py: 3 x 3, sent at the target + (1, 1) like the class
                                    signature effects, alpha soft (the pair's spr has an alpha channel)
Changes from the set: frames turned from a column into a row; the 64 px revived take centred in a 96 px frame (its
word on the others' baseline); an empty frame of a strip dropped (the client would show nothing for 110 ms);
pixels under alpha 12 cleared (invisible, they only cost sprites); nothing else.
Appended after the large spell effects (effects 656.. of the next pair; things_custom24 ends at 655) with
import_fx_art.py (client/MANIFEST.md "Status words"); server side server/data/lib/chaos_status_fx.lua (which spell
or event sends which word, behind the switch ChaosStatusFx.STATUS_FX, off until that pair is published).
Deterministic: numpy and Pillow only (CI pins Pillow 12.3.0 / numpy 2.5.3).
"""
import argparse
import csv
import io
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'status_fx')
SPEC = os.path.join(ART, 'status_fx.csv')
MS = 110
ALPHA_MIN = 12
SIZE = 96

# name, source strip (relative to the set), note (what it says and where the server sends it)
PICKS = [
    ('word_blessed', 'blessed/blessed.png', 'BLESSED!: a golden ankh disc, light wings and sparkles (holy heals)'),
    ('word_oblivion', 'cataclysm/cataclysm.png', 'OBLIVION!: red streaks crash down into a grey debris cloud (a boss channel)'),
    ('word_charmed', 'charmed/charmed.png', 'CHARMED!: red hearts over a pink ring (charms)'),
    ('word_cursed', 'cursed/cursed.png', 'CURSED!: a dark orb with a skull, violet haze, dripping shadow (curses)'),
    ('word_drenched', 'drenched/drenched.png', 'DRENCHED!: a water serpent rises and splashes (water)'),
    ('word_feared', 'feared/feared.png', 'FEARED!: a violet orb turns into a grinning skull (fear and terror)'),
    ('word_frozen', 'frozen/frozen.png', 'FROZEN!: an ice crystal grows over the word and shatters (freezing)'),
    ('word_impaled', 'impaled/impaled.png', 'IMPALED!: a dark spiked beast looms, blood drips (spears and spikes)'),
    ('word_reaped', 'reaped/reaped.png', 'REAPED!: a hooded shade rises with a violet glow (reaping strikes)'),
    ('word_revived', 'revived/v3/revived_v3.png', 'REVIVED!: a fire bird rises from flames (a return from death)'),
    ('word_revived_rise', 'revived/v2/revived_v2.png', 'REVIVED!: a sunburst, flames, a great fire bird with a ring (big returns)'),
    ('word_revived_small', 'revived/revived.png', 'REVIVED!: a small fire bird over the word (centred from 2 x 2)'),
    ('word_rooted', 'rooted/rooted.png', 'ROOTED!: roots and sprouts close over the word (roots and snares)'),
    ('word_rooted_vines', 'rooted/v2/rooted_v2.png', 'ROOTED!: green vines and thorns grow into a cage (vine prisons)'),
    ('word_shackled', 'shackled/shackled.png', 'SHACKLED!: chains and a padlock close round the word (bindings)'),
    ('word_shocked', 'shocked/shocked.png', 'SHOCKED!: pink and blue sparks arc over the word (lightning)'),
    ('word_smite', 'smite/smite.png', 'SMITE!: a holy starburst and a golden sword of light (holy strikes)'),
    ('word_stunned', 'stunned/stunned.png', 'STUNNED!: a ring of stars circles over the word (stuns)'),
]
SPEC_FIELDS = ['kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'alpha', 'note']


def load_strip(src, rel):
    a = np.asarray(Image.open(os.path.join(src, rel)).convert('RGBA')).copy()
    w = a.shape[1]
    assert a.shape[0] % w == 0, (rel, a.shape)
    frames = [a[i * w:(i + 1) * w] for i in range(a.shape[0] // w)]
    if w != SIZE:                       # the 64 px take: centred, its word on the 96 px takes' baseline
        assert w == 64, (rel, w)
        out = []
        for f in frames:
            c = np.zeros((SIZE, SIZE, 4), np.uint8)
            c[8:8 + 64, 16:16 + 64] = f
            out.append(c)
        frames = out
    clean = []
    for f in frames:
        f = f.copy()
        f[f[..., 3] < ALPHA_MIN] = 0
        if f[..., 3].any():
            clean.append(f)
    return clean


def build_all(src):
    """{name: strip H x (W * n) x 4}"""
    out = {}
    for name, rel, _note in PICKS:
        frames = load_strip(src, rel)
        assert 6 <= len(frames) <= 20, (name, len(frames))
        out[name] = np.concatenate(frames, axis=1)
    return out


def spec_text(strips):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=SPEC_FIELDS, lineterminator='\n')
    w.writeheader()
    for name, _rel, note in PICKS:
        n = strips[name].shape[1] // SIZE
        w.writerow({'kind': 'effect', 'name': name, 'file': 'status_fx/%s.png' % name, 'w': 3, 'h': 3, 'phases': n,
                    'ms': MS, 'dx': 1, 'dy': 1, 'alpha': 'soft', 'note': note})
    return buf.getvalue()


def check_rules(name, a):
    assert a.shape[0] == SIZE and a.shape[1] % SIZE == 0, (name, a.shape)
    al = a[..., 3]
    assert not ((al > 0) & (al < ALPHA_MIN)).any(), (name, 'alpha under %d' % ALPHA_MIN)
    for i in range(a.shape[1] // SIZE):
        assert al[:, i * SIZE:(i + 1) * SIZE].any(), (name, 'empty frame', i)
    assert (a[al == 0] == 0).all(), (name, 'colour under alpha 0')


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a).save(buf, 'PNG', compress_level=9)
    return buf.getvalue()


def cmd_build(a):
    if a.src:
        strips = build_all(a.src)
    elif a.check:
        strips = {}
        for name, _rel, _note in PICKS:
            path = os.path.join(OUT, name + '.png')
            if not os.path.exists(path):
                sys.exit('%s missing: run build --src DIR' % os.path.relpath(path, REPO))
            strips[name] = np.asarray(Image.open(path).convert('RGBA'))
    else:
        sys.exit('build needs --src (the text effect set); without it only --check runs')
    for name, s in strips.items():
        check_rules(name, s)
    spec = spec_text(strips)
    if a.check:
        bad = []
        if not os.path.exists(SPEC) or open(SPEC, encoding='utf-8').read() != spec:
            bad.append(os.path.relpath(SPEC, REPO) + ' differs')
        if a.src:
            for name, s in strips.items():
                path = os.path.join(OUT, name + '.png')
                have = np.asarray(Image.open(path).convert('RGBA')) if os.path.exists(path) else None
                if have is None or have.shape != s.shape or not (have == s).all():
                    bad.append(os.path.relpath(path, REPO) + ' differs')
        known = {n + '.png' for n, _r, _t in PICKS}
        extra = sorted(set(os.listdir(OUT)) - known) if os.path.isdir(OUT) else []
        bad += ['%s: not in PICKS' % os.path.join('art_import/status_fx', e) for e in extra]
        if bad:
            print('\n'.join(bad))
            sys.exit('status words: out of date (python3 -I client/tools/sprites/gen_status_fx.py build --src DIR)')
        print('status words up to date (%d strips, %d frames)' % (len(strips), sum(s.shape[1] // SIZE for s in strips.values())))
        return
    os.makedirs(OUT, exist_ok=True)
    for name, s in strips.items():
        open(os.path.join(OUT, name + '.png'), 'wb').write(png_bytes(s))
    open(SPEC, 'w', encoding='utf-8', newline='').write(spec)
    print('wrote %d strips and %s' % (len(strips), os.path.relpath(SPEC, REPO)))


def cmd_preview(a):
    os.makedirs(a.out, exist_ok=True)
    sc = 2
    ground = (58, 54, 48, 255)
    grid = (74, 70, 62, 255)
    tile = 32 * sc
    rows = []
    for name, _rel, _note in PICKS:
        s = np.asarray(Image.open(os.path.join(OUT, name + '.png')).convert('RGBA'))
        n = s.shape[1] // SIZE
        frames = []
        for i in range(n):
            bg = Image.new('RGBA', (SIZE * sc, SIZE * sc), ground)
            for k in range(0, SIZE * sc, tile):
                bg.paste(grid, (k, 0, k + 1, SIZE * sc)); bg.paste(grid, (0, k, SIZE * sc, k + 1))
            fr = Image.fromarray(s[:, i * SIZE:(i + 1) * SIZE]).resize((SIZE * sc, SIZE * sc), Image.NEAREST)
            bg.alpha_composite(fr)
            frames.append(bg)
        frames[0].convert('RGB').save(os.path.join(a.out, name + '.gif'), save_all=True,
                                      append_images=[f.convert('RGB') for f in frames[1:]], duration=MS, loop=0)
        rows.append(frames)
    w = max(len(r) for r in rows) * SIZE * sc
    sheet = Image.new('RGBA', (w, len(rows) * SIZE * sc), (20, 18, 16, 255))
    for y, r in enumerate(rows):
        for x, f in enumerate(r):
            sheet.alpha_composite(f, (x * SIZE * sc, y * SIZE * sc))
    sheet.save(os.path.join(a.out, 'status_fx_frames.png'))
    print('preview in', a.out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    a = ap.parse_args()
    (cmd_build if a.cmd == 'build' else cmd_preview)(a)


if __name__ == '__main__':
    main()
