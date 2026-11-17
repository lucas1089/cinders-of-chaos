#!/usr/bin/env python3
"""Effects for roles that had none: a pick of a purchased 32 px effect set (O606; joins client pair 73).

    python3 -I gen_gap_fx.py build DAT SPR OUT_DIR --src DIR   # DIR: the unzipped set (any layout, the sheets are found by
                                                              # digest); OUT_DIR gets Tibia.dat, Tibia.spr and strips/
    python3 -I gen_gap_fx.py build DAT SPR OUT_DIR --src DIR --write   # also writes art_import/gap_fx.csv and .sums
    python3 -I gen_gap_fx.py check                             # CI, no art, no pair: table, sums, ids file, tags agree
    python3 -I gen_gap_fx.py ids [--check]                     # server/data/lib/chaos_gapfx_ids.lua, the tags of
                                                              # spell_fx_elements.csv
    python3 -I gen_gap_fx.py live DAT SPR                      # the pair holds every piece at its id, pixel for pixel

Owner (O603 review, O606): replace nothing that works; take the set only for events that send no effect of their own
today (a class unlocked, a bounty paid, a rift opening, a boss mark ...) and for the boss telegraph pulse. The senders:
server/data/lib/chaos_gapfx.lua (README "Effects for roles that had none (O606)").

The art is purchased (docs/CREDITS.md "Effect set for roles without an effect (O606)"): use and change are allowed, the
picture files may not be passed on, also not changed, and may not train a model. So no picture is in the repository.
Committed are this script, the table art_import/gap_fx.csv (one row per effect: our name, the review number of O603,
src = the first 12 hex of the sha256 of the sheet file, the frame grid, the result) and art_import/gap_fx.sums (the
digest of every built strip). The sheets are read by this local script only: they are never sent to a web or AI
service. `build` needs them; `check` and `live` work from the table and the pair alone.

Input pair: 253 missiles and 4,742 to 5,189 effects (pair 72, or pair 72 plus the other effect steps of pair 73: the
spell effects own 4743..5142, the next step 5143..5189). The gap up to 5189 is padded with blank effects (one empty
phase, no sprite), so this step's ids are fixed whatever came before: 5190 onward, dense, in table order. A step that
later fills its own ids rebuilds them in place (import_fx_art.py `replace`). No missile is added.

O613 (owner 2026-11-17): the "Jackpot" effect was used for nothing worth a word on the screen, so it left the table and
its sender (prizes.lua); the rows after it moved up one id (pair 73 is not shipped): 47 effects, 5190..5236.

A sheet is one row of frames of whole 32 px tiles, drawn for a 32 px tile: nothing is scaled. Per effect:
  plain   the set's combined sheet (what lies behind and in front of a character in one picture), drawn over the creature
          as every effect is; one id, no split.
  frames  the sheet's frames f0..f1 (at most MAX_PHASES), MS ms each, as the set plays them (12 a second). An empty frame
          at either end is dropped. The strike circle is cut in two: its ring half is the danger pulse, the filling
          frames the last pulse before the hit; its burst (wider than a 3 x 3 mark) is not used.
  alpha   the cut of docs/SPRITE_STYLE.md with the lift of gen_spell_vfx.py (alpha through 1 - (1 - a)^LIFT, 255 from CUT
          up, one glow level GLOW from HALO up, nothing below). The colours are the set's (it is drawn in few colours).
  place   the set stands a unit 8 px right of and 4 px below our standing point (its ground rings are centred on
          24, 24 of the tile, as the rings of the same author's first set in pair 36 are; ours is 16.5, 20) and does
          not hold that for every sheet. So the art is moved by what its own pixels say (column `at`):
            stand  round a creature: the alpha centroid of all frames goes to x 16.5; down by the same amount + 4
            tile   a mark on the floor: the centroid goes to x 16; down by the same amount (ring centre 16, 16)
            gate   a thing that stands on the tile: the centroid goes to x 16; the height is the set's
          sx, sy are in the table. The tile canvas follows the art; dx, dy are the send offset.

Needs numpy and Pillow (the fx venv of CI). Deterministic: the same sheets give the same strips.
"""
import argparse
import csv
import hashlib
import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'gap_fx.csv')
SUMS = os.path.join(ART, 'gap_fx.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_gapfx_ids.lua')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')

sys.path.insert(0, HERE)
from gen_spell_vfx import CUT, GLOW, HALO, LIFT  # noqa: E402  the game cut of O596

MIN_EFFECTS, NEED_MISSILES = 4742, 253      # the input pair: pair 72 or later steps of pair 73
FIRST = 5190                                # this step's first effect id; 4743..5189 belong to the steps before
LAST = 5289                                 # and its block ends here
PAIR = 73
MS = 83                                     # the set plays 12 frames a second
MAX_PHASES = 24
MAX_TILES = 7
AT = {'stand': (16.5, 4), 'tile': (16.0, 0), 'gate': (16.0, None)}      # centroid x target, what is added to sx for sy
FIELDS = ['kind', 'id', 'name', 'num', 'src', 'fw', 'fh', 'frames', 'ax', 'ay', 'f0', 'f1', 'at', 'sx', 'sy',
          'w', 'h', 'phases', 'ms', 'dx', 'dy', 'tag', 'note']
STATIC = ['kind', 'id', 'name', 'num', 'src', 'fw', 'fh', 'frames', 'ax', 'ay', 'f0', 'f1', 'at', 'tag', 'note']
# the effects a spell script sends get an element tag (tools/ci/check_spell_fx.py): the snares of every element
TAGGED = {'gx_mine_armed': 'any', 'gx_trap_spikes': 'any'}

# (name, review number of O603, src, frame w, frame h, frames of the sheet, anchor tile x, y, first frame, last frame, at, note)
PICKS = [
    ('gx_talent_point', 19, '8eef8689f739', 96, 96, 18, 1, 1, 0, 17, 'stand', 'a point of the passive tree spent'),
    ('gx_class_unlock', 13, 'b623707460e2', 128, 128, 18, 2, 2, 0, 17, 'stand', 'a class unlocked for the account'),
    ('gx_spell_mastery', 5, '036f0a8fe448', 96, 96, 20, 1, 1, 0, 19, 'stand', 'a spell mastery chosen'),
    ('gx_paragon', 35, 'a3b12092b1e4', 96, 96, 24, 1, 1, 0, 23, 'stand', 'Paragon points spent'),
    ('gx_title', 40, 'ea951509c2ac', 96, 128, 18, 1, 2, 0, 17, 'stand', 'a new title earned'),
    ('gx_rank_up', 9, '66c3f24ae6c4', 128, 128, 18, 2, 2, 0, 17, 'stand', 'a profession level gained'),
    ('gx_class_change', 2, '8b209cf7ce48', 96, 96, 20, 1, 1, 0, 19, 'stand', 'the ascension, the class changes'),
    ('gx_milestone_bronze', 31, 'dcd9e3113d49', 96, 96, 14, 1, 1, 0, 13, 'stand', 'a level milestone, first quarter'),
    ('gx_milestone_silver', 34, 'f2457960e944', 96, 128, 16, 1, 2, 0, 15, 'stand', 'a level milestone, second quarter'),
    ('gx_milestone_gold', 33, '5ab9b469d934', 128, 160, 18, 1, 2, 0, 17, 'stand', 'a level milestone, third quarter'),
    ('gx_milestone_diamond', 32, '3052ef829d5f', 128, 160, 20, 1, 2, 0, 19, 'stand', 'a level milestone, last quarter'),
    ('gx_respec', 22, 'c904e310e6f5', 96, 96, 18, 1, 1, 0, 17, 'stand', 'the passive tree or the Paragon points reset'),
    ('gx_quest_complete', 56, 'c0fe238d8dd6', 160, 160, 20, 2, 2, 0, 19, 'stand', 'a chapter of the main quest done'),
    ('gx_daily', 47, '10cdd8561312', 128, 128, 22, 1, 1, 0, 21, 'stand', 'the daily login reward'),
    ('gx_bounty', 61, '9a1f9f3ee437', 128, 160, 24, 1, 2, 0, 23, 'stand', 'a bounty paid'),
    ('gx_chest_royal', 42, '21ad683a70bc', 160, 160, 22, 2, 2, 0, 21, 'stand', 'the weekly chest or a cursed chest opened'),
    ('gx_season_tier', 78, '6bd315f3416c', 128, 160, 22, 1, 2, 0, 21, 'stand', 'a season pass tier'),
    ('gx_set_complete', 79, '27cd22351e05', 160, 160, 22, 2, 2, 0, 21, 'stand', 'a piece of an item set found'),
    ('gx_card_common', 62, '3ca75f6b2762', 96, 96, 16, 1, 1, 0, 15, 'stand', 'a new card'),
    ('gx_card_rare', 63, 'c44b7178b2f5', 128, 160, 22, 1, 2, 0, 21, 'stand', 'a new rare card'),
    ('gx_relic', 77, '46f976a376ca', 128, 128, 24, 1, 1, 0, 23, 'stand', 'a relic drops'),
    ('gx_masterwork', 71, '47c55c7d9766', 128, 160, 24, 1, 2, 0, 23, 'stand', 'a craft that ends on the best outcome'),
    ('gx_tele_zone', 145, '55e87a349225', 128, 128, 16, 1, 1, 0, 7, 'tile', 'boss telegraph, the danger pulse (strike circle, first half)'),
    ('gx_tele_fill', 145, '55e87a349225', 128, 128, 16, 1, 1, 8, 12, 'tile', 'boss telegraph, the last pulse before the hit (strike circle, the filling)'),
    ('gx_spread', 157, '8c655382ee4b', 160, 160, 16, 2, 2, 0, 15, 'stand', 'boss puddles on players: spread out'),
    ('gx_chase', 142, 'cfefa26d3423', 128, 128, 16, 1, 1, 0, 15, 'stand', 'boss follow circle: you are chased'),
    ('gx_safe_zone', 156, 'ad1dc9b33fa2', 128, 128, 24, 1, 1, 0, 23, 'tile', 'boss line of sight attack: cover'),
    ('gx_countdown', 147, '849af6025b39', 128, 128, 24, 1, 1, 0, 23, 'stand', 'boss channel: the count to the hit'),
    ('gx_meteor_shadow', 152, 'fb8427539cdb', 160, 160, 18, 2, 2, 0, 17, 'tile', 'Meteor Rain: the shadow before the hit'),
    ('gx_gate', 342, '41588e918d39', 128, 128, 24, 2, 2, 0, 23, 'gate', 'the loop of a town portal style that has none'),
    ('gx_rift_open', 354, 'e84354093e1e', 128, 128, 16, 2, 2, 0, 15, 'gate', 'the way into a rift opens'),
    ('gx_rift', 353, '7a9434ac1864', 128, 128, 24, 2, 2, 0, 23, 'gate', 'a breach tears open in a rift'),
    ('gx_rift_close', 352, '60efde5b042d', 128, 128, 16, 2, 2, 0, 15, 'gate', 'the way out of a rift closes'),
    ('gx_waystone', 359, 'e721ded0f702', 128, 160, 18, 2, 3, 0, 17, 'gate', 'a waystone put into the map device'),
    ('gx_dungeon_beacon', 345, '3fcabf265407', 96, 128, 24, 1, 2, 0, 23, 'gate', 'a dungeon entrance opens'),
    ('gx_spawn_in', 355, '90dac77cd23f', 128, 128, 14, 2, 2, 0, 13, 'gate', 'a boss appears'),
    ('gx_mine_armed', 336, '0814436e61d2', 96, 96, 24, 1, 1, 0, 23, 'tile', 'Seeker Mine laid'),
    ('gx_trap_spikes', 339, 'e4b6d3cb0f03', 96, 96, 14, 1, 1, 0, 13, 'tile', 'Snare Trap laid'),
    ('gx_mining', 407, 'a982f59fc4eb', 96, 96, 14, 1, 1, 0, 13, 'stand', 'mining'),
    ('gx_herb', 406, '460a5fcffeba', 96, 96, 16, 1, 1, 0, 15, 'stand', 'herb gathering'),
    ('gx_fishing', 404, '545bca467b86', 96, 96, 20, 1, 1, 0, 19, 'stand', 'fishing'),
    ('gx_craft_success', 403, '153bb58ab1f6', 96, 128, 16, 1, 2, 0, 15, 'stand', 'a craft that works'),
    ('gx_craft_fail', 402, 'be7aeeccde64', 96, 96, 16, 1, 1, 0, 15, 'stand', 'a craft that fails'),
    ('gx_enchant', 427, '5d7fcfb801f4', 128, 128, 20, 1, 1, 0, 19, 'stand', 'a gem set or taken out'),
    ('gx_boss_beacon', 121, '8f6d427c8786', 128, 128, 24, 1, 1, 0, 23, 'tile', 'a world boss is here'),
    ('gx_summon_gate', 175, '19ce2479af6c', 128, 128, 24, 1, 1, 0, 23, 'tile', 'a summon or a boss add appears'),
    ('gx_rift_seal', 179, '2cb51cef9a78', 128, 128, 24, 1, 1, 0, 23, 'tile', 'a rift opens'),
]


def pieces():
    """the table rows that need no art, at FIRST.. in order"""
    out = []
    for i, (name, num, src, fw, fh, frames, ax, ay, f0, f1, at, note) in enumerate(PICKS):
        out.append(dict(kind='effect', id=FIRST + i, name=name, num=num, src=src, fw=fw, fh=fh, frames=frames, ax=ax, ay=ay,
                        f0=f0, f1=f1, at=at, tag=TAGGED.get(name, ''), note=note))
    return out


def table_errors(rows):
    """rules of the table that hold without art"""
    errs = []
    ids = [int(r['id']) for r in rows]
    if ids != list(range(FIRST, FIRST + len(ids))):
        errs.append('effect ids are not %d.. in order' % FIRST)
    if ids and ids[-1] > LAST:
        errs.append('effect ids past %d' % LAST)
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names) or any(not n.startswith('gx_') for n in names):
        errs.append('names: not unique or not gx_*')
    used = set()
    for r in rows:
        fw, fh, n, f0, f1 = (int(r[k]) for k in ('fw', 'fh', 'frames', 'f0', 'f1'))
        if len(r['src']) != 12 or any(c not in '0123456789abcdef' for c in r['src']):
            errs.append('%s: src is not 12 hex' % r['name'])
        if fw % 32 or fh % 32 or not (1 <= fw // 32 <= MAX_TILES and 1 <= fh // 32 <= MAX_TILES):
            errs.append('%s: a frame is 1 to %d whole tiles a side' % (r['name'], MAX_TILES))
        if not (0 <= int(r['ax']) < max(1, fw // 32) and 0 <= int(r['ay']) < max(1, fh // 32)):
            errs.append('%s: the anchor tile is not in the frame' % r['name'])
        if not (0 <= f0 <= f1 < n) or f1 - f0 + 1 > MAX_PHASES:
            errs.append('%s: frames %d..%d of %d (at most %d)' % (r['name'], f0, f1, n, MAX_PHASES))
        if r['at'] not in AT:
            errs.append('%s: at' % r['name'])
        if r['tag'] not in ('', 'any'):
            errs.append('%s: tag' % r['name'])
        for f in range(f0, f1 + 1):                              # a sheet may be cut in parts, a frame is used once
            if (r['src'], f) in used:
                errs.append('%s: frame %d of its sheet is used twice' % (r['name'], f))
            used.add((r['src'], f))
    return errs


def pair_ok(effects, missiles):
    return MIN_EFFECTS <= effects < FIRST and missiles == NEED_MISSILES


def pads(effects):
    """how many blank effects come before FIRST on a pair with this many effects"""
    return FIRST - 1 - effects


# ------------------------------------------------------------------------------------------------- the art
def digest(strip):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


def find_sheets(src):
    """{12 hex: path} of the PNG files under src"""
    out = {}
    for base, _dirs, files in os.walk(src):
        for f in sorted(files):
            if f.lower().endswith('.png'):
                p = os.path.join(base, f)
                with open(p, 'rb') as fh:
                    out.setdefault(hashlib.sha256(fh.read()).hexdigest()[:12], p)
    return out


def game_cut(f):
    """uint8 RGBA -> uint8 RGBA: alpha 0, GLOW or 255 after the lift; the colours stay; a transparent pixel carries none"""
    import numpy as np
    a = 1.0 - (1.0 - f[..., 3].astype(np.float64) / 255.0) ** LIFT
    out = f.copy()
    out[..., 3] = np.where(a >= CUT - 1e-9, 255, np.where(a >= HALO - 1e-9, GLOW, 0)).astype(np.uint8)
    out[out[..., 3] == 0] = 0
    return out


def frames_of(sheet, r):
    """the frames f0..f1 of a sheet after the cut, empty ones at either end dropped"""
    import numpy as np
    fw, fh, n = int(r['fw']), int(r['fh']), int(r['frames'])
    a = np.asarray(sheet.convert('RGBA'))
    assert a.shape[:2] == (fh, fw * n), ('sheet size', r['name'], a.shape)
    fr = [game_cut(a[:, i * fw:(i + 1) * fw]) for i in range(int(r['f0']), int(r['f1']) + 1)]
    while fr and not fr[-1][..., 3].any():
        fr.pop()
    while fr and not fr[0][..., 3].any():
        fr.pop(0)
    assert fr, (r['name'], 'no art')
    assert all(f[..., 3].any() for f in fr), (r['name'], 'an empty frame inside')
    return fr


def shift_of(frames, ax, at):
    """(sx, sy): how far the art moves so that it stands where `at` says (see the docstring)"""
    import numpy as np
    w = np.sum([f[..., 3].astype(np.float64) for f in frames], 0)
    cx = float((w.sum(0) * (np.arange(w.shape[1]) + 0.5)).sum() / w.sum()) - ax * 32
    want, down = AT[at]
    sx = int(np.floor(want - cx + 0.5))
    return sx, (0 if down is None else sx + down)


def build_effect(r, sheet):
    """-> (strip uint8, the computed fields)"""
    import numpy as np
    fr = frames_of(sheet, r)
    ax, ay = int(r['ax']), int(r['ay'])
    sx, sy = shift_of(fr, ax, r['at'])
    ys, xs = np.nonzero(np.max([f[..., 3] for f in fr], 0))
    x0, x1 = int(xs.min()) - ax * 32 + sx, int(xs.max()) + 1 - ax * 32 + sx      # the art from the target tile's corner
    y0, y1 = int(ys.min()) - ay * 32 + sy, int(ys.max()) + 1 - ay * 32 + sy
    left, up = max(0, -(x0 // 32)), max(0, -(y0 // 32))
    right, down = max(0, (x1 - 1) // 32), max(0, (y1 - 1) // 32)
    w, h = left + 1 + right, up + 1 + down
    assert w <= MAX_TILES and h <= MAX_TILES, (r['name'], 'too big', w, h)
    fh, fw = fr[0].shape[:2]
    ox, oy = left * 32 - ax * 32 + sx, up * 32 - ay * 32 + sy                    # the frame's corner on the canvas
    pad = max(fw, fh) + 32
    strip = np.zeros((h * 32, w * 32 * len(fr), 4), np.uint8)
    for i, f in enumerate(fr):
        c = np.zeros((h * 32 + 2 * pad, w * 32 + 2 * pad, 4), np.uint8)
        c[pad + oy:pad + oy + fh, pad + ox:pad + ox + fw] = f
        tile = c[pad:pad + h * 32, pad:pad + w * 32]
        assert (tile[..., 3] > 0).sum() == (f[..., 3] > 0).sum(), (r['name'], 'art clipped')
        strip[:, i * w * 32:(i + 1) * w * 32] = tile
    return strip, dict(sx=sx, sy=sy, w=w, h=h, phases=len(fr), ms=MS, dx=right, dy=down)


def build_rows(src):
    """[(row with the computed fields, strip)] from the sheets under src"""
    from PIL import Image
    sheets = find_sheets(src)
    out = []
    for r in pieces():
        if r['src'] not in sheets:
            sys.exit('%s: no sheet with digest %s under %s' % (r['name'], r['src'], src))
        strip, more = build_effect(r, Image.open(sheets[r['src']]))
        r.update(more)
        out.append((r, strip))
    return out


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    n = len(rows)
    w.writerow(dict(kind='total', id=n, name='effects_%d_%d' % (FIRST, FIRST + n - 1),
                    note='this step appends exactly %d effects at %d.. after blank effects up to %d and no missile; '
                         'its block ends at %d' % (n, FIRST, FIRST - 1, LAST)))
    return buf.getvalue()


def sums_text(pairs):
    return ''.join('%s  %s\n' % (digest(s), r['name']) for r, s in pairs)


def read_spec():
    with open(SPEC, newline='') as fh:
        return [r for r in csv.DictReader(fh) if r['kind'] != 'total']


def read_total():
    with open(SPEC, newline='') as fh:
        return [int(r['id']) for r in csv.DictReader(fh) if r['kind'] == 'total']


def read_sums():
    return dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))


def import_spec(path, strips, first, pairs):
    """the spec import_fx_art.py reads: blank effects from `first` up to FIRST - 1, then the built strips"""
    import numpy as np
    from PIL import Image
    blank = os.path.join(strips, 'gx_blank.png')
    Image.fromarray(np.zeros((32, 32, 4), np.uint8)).save(blank, optimize=False)
    with open(path, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs', 'lua', 'blank'])
        for i in range(first, FIRST):
            w.writerow(['', 'effect', 'gx_pad_%d' % i, blank, 1, 1, 1, MS, 0, 0, 'blank', 'soft', '', '', 1])
        for r, s in pairs:
            f = os.path.join(strips, r['name'] + '.png')
            Image.fromarray(np.ascontiguousarray(s)).save(f, optimize=False)
            w.writerow(['', 'effect', r['name'], f, r['w'], r['h'], r['phases'], r['ms'], r['dx'], r['dy'], r['note'],
                        'soft', '', '', ''])


def build(dat, spr, out, src, write):
    from datspr import Dat
    d = Dat(dat)
    if not pair_ok(len(d.effects), len(d.missiles)):
        sys.exit('refused: the input pair has %d effects and %d missiles, this step needs %d to %d effects and %d missiles '
                 '(pair 72 or the earlier steps of pair 73)' % (len(d.effects), len(d.missiles), MIN_EFFECTS, FIRST - 1,
                                                                NEED_MISSILES))
    errs = table_errors(pieces())
    if errs:
        sys.exit('\n'.join(errs))
    pairs = build_rows(src)
    rows = [r for r, _ in pairs]
    texts = {SPEC: spec_text(rows), SUMS: sums_text(pairs)}
    if write:
        for p, t in texts.items():
            open(p, 'w', newline='').write(t)
            print('wrote', os.path.relpath(p, ROOT))
    else:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        if bad:
            sys.exit('the sheets do not give the committed %s (run with --write after a wanted change)' % ', '.join(
                os.path.relpath(p, ROOT) for p in bad))
    strips = os.path.join(os.path.abspath(out), 'strips')
    os.makedirs(strips, exist_ok=True)
    spec = os.path.join(strips, 'import.csv')
    first = len(d.effects) + 1
    import_spec(spec, strips, first, pairs)
    cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', dat, '--ours-spr', spr, '--out-dir', out,
           '--spec', spec, '--expect-first-effect', str(first), '--keep-donor-names']
    if subprocess.run(cmd).returncode:
        sys.exit('import_fx_art.py failed')
    for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv'):                # this step's ids come from the table
        p = os.path.join(out, f)
        if os.path.exists(p):
            os.remove(p)
    print('gap fx: %d blank effects %d..%d, then %d effects %d..%d' % (pads(len(d.effects)), first, FIRST - 1, len(rows), FIRST,
                                                                    FIRST + len(rows) - 1))
    return live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))


# ------------------------------------------------------------------------------------------------- server files
def lua_text(rows):
    L = ['-- GENERATED by client/tools/sprites/gen_gap_fx.py from art_import/gap_fx.csv (O606). Do not edit by hand.',
         '-- Effects for roles that had none (a purchased effect set, docs/CREDITS.md), drawn by client pair %d:' % PAIR,
         '-- %d effects at the ids %d..%d, after the blank effects that fill the pair up to %d. No projectile.' % (
             len(rows), FIRST, FIRST + len(rows) - 1, FIRST - 1),
         '-- dx, dy: the send offset (the bottom-right tile of the art is the target tile + dx, dy); ms: the whole play.',
         '-- A plain table: data/lib/chaos_gapfx.lua sends these ids only when config.lua chaosClientPair is %d or more,' % PAIR,
         '-- so a server on an older pair never sends one.',
         'ChaosGapFxIds = {',
         '\tpair = %d, first = %d, count = %d,' % (PAIR, FIRST, len(rows)),
         '\teffects = {']
    for r in rows:
        L.append('\t\t%s = {id = %s, dx = %s, dy = %s, ms = %d},  -- %s' % (
            r['name'], r['id'], r['dx'], r['dy'], int(r['ms']) * int(r['phases']), r['note']))
    L += ['\t},', '}']
    return '\n'.join(L) + '\n'


def tags_text(rows):
    """spell_fx_elements.csv with this step's tagged rows (id, name, element) in id order, the other rows as they are"""
    with open(TAGS, encoding='utf-8', newline='') as fh:
        keep = [l for l in fh.read().splitlines() if not l.split(',')[1:2] or not l.split(',')[1].startswith('gx_')]
    mine = ['%s,%s,%s' % (r['id'], r['name'], r['tag']) for r in rows if r['tag']]
    return '\n'.join(keep[:1] + sorted(keep[1:] + mine, key=lambda l: int(l.split(',')[0]))) + '\n'


def ids(check):
    rows = read_spec()
    want = {LUA: lua_text(rows), TAGS: tags_text(rows)}
    if check:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_gap_fx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


def check():
    errs = table_errors(pieces())
    rows = read_spec() if os.path.exists(SPEC) else []
    if [[str(r[k]) for k in STATIC] for r in pieces()] != [[r[k] for k in STATIC] for r in rows]:
        errs.append('art_import/gap_fx.csv does not list the picks of the script in order')
    n = len(rows)
    if read_total() != [n] if rows else True:
        errs.append('gap_fx.csv: the total row does not record the %d effects' % n)
    for r in rows:
        w, h, dx, dy, ph, ms, sx, sy = (int(r[k]) for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms', 'sx', 'sy'))
        if not (0 <= dx < w and 0 <= dy < h and 1 <= w <= MAX_TILES and 1 <= h <= MAX_TILES):
            errs.append('%s: size or offset' % r['name'])
        if not (1 <= ph <= int(r['f1']) - int(r['f0']) + 1 and ms == MS):
            errs.append('%s: phases or ms' % r['name'])
        if abs(sx) > 24 or (r['at'] != 'gate' and sy - sx != AT[r['at']][1]) or (r['at'] == 'gate' and sy):
            errs.append('%s: the shift does not follow its `at`' % r['name'])
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS)] if os.path.exists(SUMS) else []
    if sums != [r['name'] for r in rows]:
        errs.append('gap_fx.sums does not list the table names in order')
    for p in (SPEC, SUMS, LUA, os.path.abspath(__file__)):             # no pack name outside docs/CREDITS.md
        text = open(p, encoding='utf-8').read().lower() if os.path.exists(p) else ''
        for word in PACK_WORDS:
            if word in text:
                errs.append('%s names the pack' % os.path.relpath(p, ROOT))
    for e in errs:
        print(e)
    bad = ids(True) if rows else 1
    print('gap fx: %d effects %d..%d, %s' % (n, FIRST, FIRST + n - 1, 'OK' if not errs and not bad else 'PROBLEMS'))
    return 1 if errs or bad else 0


# the set's name and its author's file prefix, split so this file does not name them either (docs/CREDITS.md does)
PACK_WORDS = ['mega' + ' vfx', 'mega' + '_vfx', 'w' + 'st_']


def live(dat_path, spr_path):
    """the pair holds each piece at its id: size, phases, durations and the pixels of the sums"""
    import numpy as np
    from datspr import Dat, Spr
    from import_vfx import render_back
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_spec()
    sums = read_sums()
    errs = []
    n = len(rows)
    if len(dat.effects) < FIRST + n - 1 or len(dat.missiles) != NEED_MISSILES:
        errs.append('the pair has %d effects and %d missiles' % (len(dat.effects), len(dat.missiles)))
    for r in rows if not errs else []:
        t = dat.effects[int(r['id']) - 1]
        ph, w, h = int(r['phases']), int(r['w']), int(r['h'])
        if (t.w, t.h, t.phases) != (w, h, ph):
            errs.append('%s: size or phases differ at %s' % (r['name'], r['id']))
            continue
        if t.anim and set(t.anim[3]) not in ({int(r['ms'])}, {(int(r['ms']), int(r['ms']))}):
            errs.append('%s: durations differ' % r['name'])
        back = render_back(t, spr, 1)
        strip = np.concatenate([back[(f, 0, 0, 0)] for f in range(ph)], axis=1).copy()
        strip[strip[..., 3] == 0] = 0
        if digest(strip) != sums.get(r['name']):
            errs.append('%s: pixels differ from the sum' % r['name'])
    for e in errs:
        print(e)
    print('gap fx live: %d effects at %d..%d, %s' % (n, FIRST, FIRST + n - 1, 'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'check', 'ids', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--src')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'build':
        if not a.src or len(a.rest) != 3:
            sys.exit('build DAT SPR OUT_DIR --src DIR')
        return build(a.rest[0], a.rest[1], a.rest[2], a.src, a.write)
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'live':
        if len(a.rest) != 2:
            sys.exit('live DAT SPR')
        return live(*a.rest)
    return check()


if __name__ == '__main__':
    sys.exit(main())
