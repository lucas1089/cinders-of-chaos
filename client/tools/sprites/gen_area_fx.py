#!/usr/bin/env python3
"""Area bursts, beams and markers of the purchased effect packs of pair 36 (O607; joins client pair 73).

    python3 -I gen_area_fx.py build DAT SPR OUT_DIR --src DIR [--src DIR ...]   # DIR: the unzipped packs (any sub folders;
                                                         # only the picked sheets and the packs' json tables are needed)
    python3 -I gen_area_fx.py build DAT SPR OUT_DIR --src DIR --write   # also writes art_import/area_fx.csv and .sums
    python3 -I gen_area_fx.py check                      # CI, no art, no pair: table, sums, ids file, tags, pair 51 lists
    python3 -I gen_area_fx.py ids [--check]              # server/data/lib/chaos_area_fx_ids.lua, spells/area_fx_catalog.csv,
                                                         # the tags of spell_fx_elements.csv
    python3 -I gen_area_fx.py live DAT SPR               # the pair holds every row at its id, pixel for pixel

The owner approved the review O604: five area bursts of ours are faint, the beam spells draw balls on a line, and the pack
has markers we lack. 42 effects in two kinds of rows:
  refill  39 effects that pair 36 imported at their ids and pair 51 blanked as unused (prune_pair.py): two area bursts,
          four beams of eight headings each, five markers. Each is put back AT ITS PAIR 36 ID, in the size, the send
          offset and the phase count of its pair 36 spec (art_import/pack36_*.csv), so the names and offsets of
          server/data/lib/chaos_pack36_fx_ids.lua stay true. Their rows moved from pair51_removed.csv to pair51_keep.csv.
  new     3 area bursts of a set pair 36 did not have, appended at 5300..5302. The input pair may end anywhere from 4742
          to 5299: every id from its last effect + 1 up to 5299 is padded with a blank effect (one 1x1 frame, sprite 0,
          the bytes of a pair 51 blank), so this step runs LAST of the effect steps of pair 73, after the steps that own
          4743..5142 (O596, gen_spell_vfx.py) and 5190..5237 (O606, gen_gap_fx.py; then 5238..5299 are padded here).
          It never touches an id below 5300 that has art.

The cut is the one the pair 36 tools use now (gen_pack36_fx.load: the 32 px sheets 1:1, alpha cut hard at 0.5; the 64 px
set halved, the same cut; no dither mesh): O604's numbers show the hard cut keeps 84% to 106% of the alpha mass of every
pick, so none needs the game size cut of O596. A looping pack effect plays once and its last 3 frames dissolve, as in
pair 36. Placing is the pack's own anchor tile: an area burst is sent at the centre tile of the spell, a beam at the
caster's tile, a marker at the marked tile.

The art is purchased (docs/CREDITS.md: use and change allowed, no resale or redistribution, never machine-learning data),
so no picture is in the repository. Committed: this script, art_import/area_fx.csv (one row per effect: the name, a
neutral set key, src = the first 12 hex of the sha256 of the sheet file, the result) and art_import/area_fx.sums (the
digest of every strip). The sheets are read by this local script only: never sent to a web or AI service.

Needs numpy and Pillow (the fx venv of CI). Deterministic.
"""
import argparse
import csv
import hashlib
import io
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'area_fx.csv')
SUMS = os.path.join(ART, 'area_fx.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_area_fx_ids.lua')
CATALOG = os.path.join(ROOT, 'server', 'data', 'spells', 'area_fx_catalog.csv')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')
PACK36_LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_pack36_fx_ids.lua')
REMOVED = os.path.join(HERE, 'pair51_removed.csv')
KEEP = os.path.join(HERE, 'pair51_keep.csv')

PAIR = 73
FIRST = 5300                               # the new effects; ids below it are other steps' or padding
MIN_EFFECTS, NEED_MISSILES = 4742, 253     # pair 72 at least; a later step's effects may already be there
BLANK = bytes([0xFF, 1, 1, 1, 1, 1, 1, 1]) + struct.pack('<I', 0)     # a blank effect, as pair 51 writes one
DIRS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']
STEP = {'n': (0, -1), 'ne': (1, -1), 'e': (1, 0), 'se': (1, 1), 's': (0, 1), 'sw': (-1, 1), 'w': (-1, 0), 'nw': (-1, -1)}
ELEMENTS = ('physical', 'fire', 'ice', 'energy', 'earth', 'holy', 'death', 'arcane', 'any')
KEEP_REASON = 'kept since O607 (pair 73): refilled from the pack, sent by data/lib/chaos_area_fx.lua'
FIELDS = ['kind', 'id', 'name', 'role', 'set', 'src', 'dir', 'element', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note']

# (kind, first id, name, role, set key, src, element, directional, note)
#   set: a neutral key of the pack and its family (the names are in docs/CREDITS.md): a3 the area set pair 36 did not have,
#   g the tile-grid area skills, v1 the 500 effect set, ui the 64 px interface set
PICKS = [
    ('new', 5300, 'ab_fire_rain', 'area', 'a3', '88fd2670bf53', 'fire', False, 'burning shards rain on a 5 x 5 square'),
    ('new', 5301, 'ab_blood_sigil', 'area', 'a3', '91d7c5fd23cc', 'physical', False, 'a blood sigil, a disc of 5 tiles'),
    ('new', 5302, 'ab_arcane_clock', 'area', 'a3', '8fb10e93aff5', 'arcane', False, 'a clock face of runes, a disc of 7 tiles'),
    ('refill', 1612, 'area_whiteout', 'area', 'g', '0c1ea500c11a', 'ice', False, 'a white burst of snow, a disc of 5 tiles'),
    ('refill', 1642, 'area_radiant_repulse', 'area', 'g', '77a6f450cafc', 'holy', False, 'a burst of light that pushes out, a disc of 5 tiles'),
    ('refill', 3356, 'mega_blood_siphon', 'beam', 'v1', 'e004c7df3c91', 'physical', True, 'a red stream'),
    ('refill', 3404, 'mega_glacier_breath', 'beam', 'v1', '7778956be1cd', 'ice', True, 'a breath of frost'),
    ('refill', 3492, 'mega_soul_chain', 'beam', 'v1', '406a12a645e7', 'death', True, 'a chain of souls'),
    ('refill', 3508, 'mega_sunbeam_lance', 'beam', 'v1', '3959fb2e44aa', 'holy', True, 'a lance of sunlight'),
    ('refill', 3685, 'mega_util_checkpoint_crystal', 'mark', 'v1', '56953a0c7351', 'any', False, 'a checkpoint crystal'),
    ('refill', 3688, 'mega_util_interact_hand', 'mark', 'v1', 'ceab1f723e41', 'any', False, 'a hand: something to use'),
    ('refill', 3690, 'mega_util_locked_marker', 'mark', 'v1', '1fdc423525e8', 'any', False, 'a lock: the way is shut'),
    ('refill', 4051, 'w_fx_quest_marker', 'mark', 'ui', '695411437e97', 'any', False, 'a gold quest marker'),
    ('refill', 4076, 'w_marker_skull', 'mark', 'ui', '6ec163293be4', 'any', False, 'a skull mark'),
]
PACK36_GROUP = {'g': 'area', 'v1': 'mega', 'ui': 'ui'}      # set key -> the pair 36 spec that holds a refill's row


def digest(a):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def pieces():
    """the rows of PICKS, a directional one as its eight headings: dicts with the static fields"""
    out = []
    for kind, first, name, role, sk, src, element, directional, note in PICKS:
        for i, d in enumerate(DIRS if directional else ['']):
            out.append(dict(kind=kind, id=first + i, name=name + ('_' + d if d else ''), role=role, set=sk, src=src, dir=d,
                            element=element, note=note + (', towards ' + d if d else '')))
    return out


def pack36_rows():
    """{name: row} of the pair 36 specs the refills come from (size, phases, ms, send offset)"""
    rows = {}
    for g in sorted(set(PACK36_GROUP.values())):
        with open(os.path.join(ART, 'pack36_%s.csv' % g), newline='') as fh:
            for r in csv.DictReader(fh):
                rows[r['name']] = r
    return rows


def pack36_ids():
    """{name: (id, dx, dy)} of server/data/lib/chaos_pack36_fx_ids.lua"""
    out = {}
    for line in open(PACK36_LUA, encoding='utf-8'):
        if line.startswith('ChaosVfx.') and '{id = ' in line:
            name = line[len('ChaosVfx.'):].split(' ')[0]
            out[name] = (int(line.split('{id = ')[1].split(',')[0]), int(line.split('dx = ')[1].split(',')[0]),
                         int(line.split('dy = ')[1].split(',')[0]))
    return out


def table_errors(rows):
    errs = []
    ids = [r['id'] for r in rows]
    names = [r['name'] for r in rows]
    if len(set(ids)) != len(ids) or len(set(names)) != len(names):
        errs.append('an id or a name twice')
    new = [r for r in rows if r['kind'] == 'new']
    if [r['id'] for r in new] != list(range(FIRST, FIRST + len(new))):
        errs.append('the new effects are not the dense block %d..' % FIRST)
    for r in rows:
        if r['kind'] not in ('new', 'refill') or r['role'] not in ('area', 'beam', 'mark') or r['element'] not in ELEMENTS:
            errs.append('%s: kind, role or element' % r['name'])
        if len(r['src']) != 12 or any(c not in '0123456789abcdef' for c in r['src']):
            errs.append('%s: src is the first 12 hex of the sheet digest' % r['name'])
        if r['kind'] == 'refill' and r['id'] >= MIN_EFFECTS:
            errs.append('%s: a refill is an id of pair 36' % r['name'])
        if (r['role'] == 'beam') != bool(r['dir']):
            errs.append('%s: a beam has a heading, nothing else has' % r['name'])
    for sk in {r['set'] for r in rows}:
        if sk not in ('a3',) + tuple(PACK36_GROUP):
            errs.append('set %s' % sk)
    return errs


# ----------------------------------------------------------------------------------------------------------- the cut
def sheet_file(P, s):
    """the picture file whose digest names a pack effect: the combined sheet"""
    import json
    if s.fmt == 'meta':
        v = s.meta['variants']['oblique/32']
        p = os.path.join(s.root, v['files']['all'])
        return p if os.path.exists(p) else None
    if s.fmt == 'catalog':
        d = json.load(open(s.root))
        sheets = d['sheets']
        if isinstance(next(iter(sheets.values())), dict) or 'full' not in sheets:
            return None
        p = os.path.join(os.path.dirname(s.root), sheets['full'])
        return p if os.path.exists(p) else None
    return None


def find_sheets(P, srcs):
    """{12 hex: Src} of every pack effect under the folders whose sheet file is there"""
    out = {}
    for lst in P.discover(srcs).values():
        for s in lst:
            p = sheet_file(P, s)
            if p:
                out.setdefault(hashlib.sha256(open(p, 'rb').read()).hexdigest()[:12], s)
    return out


def prepared(P, frames, loop):
    """the frames as pair 36 plays them: empty ones dropped, a loop's last FADE frames dissolved"""
    frames = P.trim(frames)
    assert frames, 'no art'
    if loop and len(frames) > P.FADE + 2:
        for j in range(P.FADE):
            k = len(frames) - P.FADE + j
            frames[k] = P.G.dissolve(frames[k], (P.FADE - j) / (P.FADE + 1))
        frames = P.trim(frames)
    return frames


def fixed_strip(P, name, frames, anchor, point, loop, w, h, dx, dy, phases):
    """a refill: the frames in the canvas of the pair 36 spec (w x h tiles, the anchor tile dx from the right and dy from
    the bottom), `phases` phases with the empty ones at the end. Art that leaves the canvas stops the build."""
    import numpy as np
    frames = prepared(P, frames, loop)
    if len(frames) + 1 > phases:
        raise SystemExit('%s: %d frames do not fit the %d phases of pair 36' % (name, len(frames), phases))
    left, top = w - 1 - dx, h - 1 - dy
    strip = np.zeros((h * 32, w * 32 * phases, 4), np.uint8)
    for i, f in enumerate(frames):
        strip[:, i * w * 32:(i + 1) * w * 32] = P.G.place(f, anchor, point, left, top, w, h, name)
    return strip


def build_rows(srcs):
    """[(row with every field, strip)] from the packs under srcs"""
    sys.path.insert(0, HERE)
    import gen_pack36_fx as P
    sheets = find_sheets(P, srcs)
    old = pack36_rows()
    out = []
    loaded = {}
    for r in pieces():
        if r['src'] not in sheets:
            sys.exit('%s: no sheet with digest %s under %s' % (r['name'], r['src'], ', '.join(srcs)))
        if r['src'] not in loaded:
            loaded[r['src']] = P.load(sheets[r['src']])
        rows, anchor, point, ms, loop, directional = loaded[r['src']]
        if bool(r['dir']) != directional:
            sys.exit('%s: the sheet has %s headings' % (r['name'], 'eight' if directional else 'no'))
        frames = rows[P.DIRS8.index(r['dir'])] if r['dir'] else rows[0]
        if r['kind'] == 'refill':
            o = old[r['name']]
            w, h, n, dx, dy = (int(o[k]) for k in ('w', 'h', 'phases', 'dx', 'dy'))
            if int(o['ms']) != ms:
                sys.exit('%s: the pack plays at %d ms, pair 36 at %s' % (r['name'], ms, o['ms']))
            strip = fixed_strip(P, r['name'], frames, anchor, point, loop, w, h, dx, dy, n)
        else:
            cut = P.effect_strip(r['name'], frames, anchor, point, loop)
            if cut is None:
                sys.exit('%s: larger than %d tiles' % (r['name'], P.MAX_TILES))
            strip, w, h, n, dx, dy = cut
        r.update(w=w, h=h, phases=n, ms=ms, dx=dx, dy=dy)
        out.append((r, strip))
    return out


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def sums_text(pairs):
    return ''.join('%s  %s\n' % (digest(s), r['name']) for r, s in pairs)


def read_spec():
    with open(SPEC, newline='') as fh:
        return list(csv.DictReader(fh))


def read_sums():
    return dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))


# -------------------------------------------------------------------------------------------------------- the pair
def is_blank(t):
    return (t.w, t.h, t.phases) == (1, 1, 1) and tuple(t.sprites) == (0,)


def pad_plan(effects):
    """(first pad id, pad count) for an input pair with `effects` effects, or None when the pair cannot take the step"""
    if not MIN_EFFECTS <= effects < FIRST:
        return None
    return effects + 1, FIRST - 1 - effects


def padded_dat(dat):
    """the dat bytes with blank effects after the last one, up to FIRST - 1 (items, outfits, missiles byte for byte)"""
    plan = pad_plan(len(dat.effects))
    assert plan, 'the pair cannot be padded'
    d = dat.data
    e_end = dat.effects[-1].raw[1]
    assert dat.missiles[0].raw[0] == e_end
    out = bytearray(d[:e_end]) + BLANK * plan[1] + d[e_end:]
    struct.pack_into('<HH', out, 8, len(dat.effects) + plan[1], len(dat.missiles))
    return bytes(out)


def build(dat_path, spr_path, out, srcs, write):
    import numpy as np
    from PIL import Image
    sys.path.insert(0, HERE)
    from datspr import Dat
    d = Dat(dat_path)
    if pad_plan(len(d.effects)) is None or len(d.missiles) != NEED_MISSILES:
        sys.exit('refused: the input pair has %d effects and %d missiles; this step needs %d to %d effects and %d missiles '
                 '(pair 72 or later, the ids from %d not taken)' % (len(d.effects), len(d.missiles), MIN_EFFECTS, FIRST - 1,
                                                                   NEED_MISSILES, FIRST))
    errs = table_errors(pieces())
    if errs:
        sys.exit('\n'.join(errs))
    for r in pieces():
        if r['kind'] == 'refill' and not is_blank(d.effects[r['id'] - 1]):
            sys.exit('refused: effect %d (%s) is not blank in the input pair' % (r['id'], r['name']))
    pairs = build_rows(srcs)
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
    out = os.path.abspath(out)
    strips = os.path.join(out, 'strips')
    padded = os.path.join(out, 'padded')
    os.makedirs(strips, exist_ok=True)
    os.makedirs(padded, exist_ok=True)
    first_pad, pads = pad_plan(len(d.effects))
    open(os.path.join(padded, 'Tibia.dat'), 'wb').write(padded_dat(d))
    pd = Dat(os.path.join(padded, 'Tibia.dat'))
    assert len(pd.effects) == FIRST - 1 and all(is_blank(t) for t in pd.effects[first_pad - 1:]), 'padding'
    assert all(pd.data[a.raw[0]:a.raw[1]] == d.data[b.raw[0]:b.raw[1]] for a, b in zip(pd.effects, d.effects)), 'an effect moved'
    print('padded: %d blank effects %d..%d' % (pads, first_pad, FIRST - 1) if pads else 'padded: nothing to pad')
    spec = os.path.join(strips, 'import.csv')
    with open(spec, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note'])
        for r, s in sorted(pairs, key=lambda p: (p[0]['kind'] != 'refill', p[0]['id'])):
            f = os.path.join(strips, r['name'] + '.png')
            Image.fromarray(np.ascontiguousarray(s)).save(f, optimize=False)
            w.writerow([r['id'] if r['kind'] == 'refill' else '', 'effect', r['name'], f, r['w'], r['h'], r['phases'], r['ms'],
                        r['dx'], r['dy'], r['note']])
    cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', os.path.join(padded, 'Tibia.dat'),
           '--ours-spr', spr_path, '--out-dir', out, '--spec', spec, '--expect-first-effect', str(FIRST)]
    if subprocess.run(cmd).returncode:
        sys.exit('import_fx_art.py failed')
    for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv', os.path.join('padded', 'Tibia.dat')):   # the ids come from the table
        p = os.path.join(out, f)
        if os.path.exists(p):
            os.remove(p)
    os.rmdir(padded)
    return live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))


def live(dat_path, spr_path):
    """the pair holds each row at its id: size, phases, durations and the pixels of the sums"""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_vfx import render_back
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_spec()
    sums = read_sums()
    errs = []
    last = max(int(r['id']) for r in rows)
    if len(dat.effects) < last or len(dat.missiles) != NEED_MISSILES:
        errs.append('the pair has %d effects and %d missiles' % (len(dat.effects), len(dat.missiles)))
    for r in rows if not errs else []:
        t = dat.effects[int(r['id']) - 1]
        ph, w, h = int(r['phases']), int(r['w']), int(r['h'])
        if (t.w, t.h, t.phases) != (w, h, ph):
            errs.append('%s: size or phases differ at %s' % (r['name'], r['id']))
            continue
        if t.anim and set(t.anim[3]) != {int(r['ms'])}:
            errs.append('%s: durations differ' % r['name'])
        back = render_back(t, spr, 1)
        strip = np.concatenate([back[(f, 0, 0, 0)] for f in range(ph)], axis=1).copy()
        strip[strip[..., 3] == 0] = 0
        if digest(strip) != sums.get(r['name']):
            errs.append('%s: pixels differ from the sum' % r['name'])
    for e in errs:
        print(e)
    print('area fx live: %d effects (%d refilled in place, %d new at %d..%d), %s' % (
        len(rows), sum(r['kind'] == 'refill' for r in rows), sum(r['kind'] == 'new' for r in rows), FIRST, last,
        'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


# ------------------------------------------------------------------------------------------------- server files
def reach(r):
    """tiles a beam's canvas reaches from the caster's tile along its heading (a diagonal: the shorter side)"""
    w, h, dx, dy = (int(r[k]) for k in ('w', 'h', 'dx', 'dy'))
    sx, sy = STEP[r['dir']]
    side = []
    if sx:
        side.append(dx if sx > 0 else w - 1 - dx)
    if sy:
        side.append(dy if sy > 0 else h - 1 - dy)
    return max(1, min(side))


def lua_text(rows):
    new = [r for r in rows if r['kind'] == 'new']
    L = ['-- GENERATED by client/tools/sprites/gen_area_fx.py from art_import/area_fx.csv (O607). Do not edit by hand.',
         '-- Area bursts, beams and markers of the purchased effect packs (docs/CREDITS.md), drawn by client pair %d:' % PAIR,
         '-- %d effects refilled at their pair 36 ids (pair 51 had blanked them; the names, sizes and send offsets are the ones' % (
             len(rows) - len(new)),
         '-- of chaos_pack36_fx_ids.lua) and %d new ones at %d..%d. A plain table: data/lib/chaos_area_fx.lua merges it into' % (
             len(new), FIRST, FIRST + len(new) - 1),
         '-- ChaosVfx when config.lua chaosClientPair is %d or more, so a server on an older pair never sends one.' % PAIR,
         '-- beams: the tiles a beam reaches from the caster along each heading (its canvas), for the beam segments.',
         'ChaosAreaFxIds = {',
         '\tpair = %d, first = %d, count = %d,' % (PAIR, FIRST, len(new)),
         '\teffects = {']
    for r in rows:
        L.append('\t\t%s = {id = %s, dx = %s, dy = %s, ms = %d, w = %s, h = %s, element = "%s", role = "%s", refill = %s},  -- %s' % (
            r['name'], r['id'], r['dx'], r['dy'], int(r['ms']) * int(r['phases']), r['w'], r['h'], r['element'], r['role'],
            'true' if r['kind'] == 'refill' else 'false', r['note']))
    L += ['\t},', '\tbeams = {']
    bases = []
    for r in rows:
        if r['role'] == 'beam' and r['name'][:-len(r['dir']) - 1] not in bases:
            bases.append(r['name'][:-len(r['dir']) - 1])
    for b in bases:
        rs = {r['dir']: reach(r) for r in rows if r['role'] == 'beam' and r['name'] == b + '_' + r['dir']}
        L.append('\t\t%s = {%s},' % (b, ', '.join('%s = %d' % (d, rs[d]) for d in DIRS)))
    L += ['\t},', '}']
    return '\n'.join(L) + '\n'


def catalog_text(rows):
    """the area bursts as a catalogue of gen_ground_fx.py: they lie under the creatures like the bursts they stand in for"""
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(['kind', 'id', 'name', 'size', 'send_offset', 'patterns', 'frames', 'ms', 'note'])
    for r in rows:
        if r['role'] == 'area':
            w.writerow(['effect', r['id'], r['name'], '%sx%s' % (r['w'], r['h']), '%s,%s' % (r['dx'], r['dy']), '1x1', r['phases'],
                        r['ms'], r['note']])
    return buf.getvalue()


def tags_text(rows):
    """spell_fx_elements.csv with this step's rows (id, name, element) in id order, the other rows as they are"""
    mine = {r['id'] for r in rows}
    with open(TAGS, encoding='utf-8', newline='') as fh:
        lines = fh.read().splitlines()
    keep = [l for l in lines[1:] if l.split(',')[0] not in mine]
    new = ['%s,%s,%s' % (r['id'], r['name'], r['element']) for r in rows]
    return '\n'.join(lines[:1] + sorted(keep + new, key=lambda l: int(l.split(',')[0]))) + '\n'


def ids(check):
    rows = read_spec()
    want = {LUA: lua_text(rows), CATALOG: catalog_text(rows), TAGS: tags_text(rows)}
    if check:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_area_fx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


def pair51_errors(rows):
    """a refilled id is no longer on the removed list of pair 51 and is on its keep list"""
    errs = []
    with open(REMOVED, newline='') as fh:
        removed = {r['id'] for r in csv.DictReader(fh) if r['kind'] == 'effect'}
    with open(KEEP, newline='') as fh:
        keep = {r['id']: r['name'] for r in csv.DictReader(fh) if r['kind'] == 'effect'}
    for r in rows:
        if r['kind'] != 'refill':
            continue
        if r['id'] in removed:
            errs.append('%s: effect %s is still in pair51_removed.csv' % (r['name'], r['id']))
        if keep.get(r['id']) != r['name']:
            errs.append('%s: effect %s is not in pair51_keep.csv under that name' % (r['name'], r['id']))
    return errs


def check():
    errs = table_errors(pieces())
    rows = read_spec() if os.path.exists(SPEC) else []
    static = [k for k in FIELDS if k not in ('w', 'h', 'phases', 'ms', 'dx', 'dy')]
    if [[str(r[k]) for k in static] for r in pieces()] != [[r[k] for k in static] for r in rows]:
        errs.append('art_import/area_fx.csv does not list the rows of the script in order')
    old, names = pack36_rows(), pack36_ids()
    for r in rows:
        w, h, dx, dy, ph, ms = (int(r[k]) for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'))
        if not (0 <= dx < w and 0 <= dy < h and 1 <= w <= 9 and 1 <= h <= 9 and ph >= 2 and ms > 0):
            errs.append('%s: size, offset or phases' % r['name'])
        if r['kind'] == 'refill':
            o = old.get(r['name'])
            if not o or [r[k] for k in ('w', 'h', 'phases', 'ms', 'dx', 'dy')] != [o[k] for k in ('w', 'h', 'phases', 'ms', 'dx', 'dy')]:
                errs.append('%s: not the size, phases and send offset of its pair 36 spec' % r['name'])
            if names.get(r['name']) != (int(r['id']), dx, dy):
                errs.append('%s: not the id and send offset of chaos_pack36_fx_ids.lua' % r['name'])
        elif r['name'] in names:
            errs.append('%s: a new effect takes a pair 36 name' % r['name'])
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS)] if os.path.exists(SUMS) else []
    if sums != [r['name'] for r in rows]:
        errs.append('area_fx.sums does not list the table names in order')
    errs += pair51_errors(rows)
    for p in (SPEC, SUMS, LUA, CATALOG):                               # no pack name outside docs/CREDITS.md
        text = open(p, encoding='utf-8').read().lower() if os.path.exists(p) else ''
        for word in PACK_WORDS:
            if word in text:
                errs.append('%s names a pack' % os.path.relpath(p, ROOT))
    for e in errs:
        print(e)
    bad = ids(True) if rows else 1
    n = sum(r['kind'] == 'new' for r in rows)
    print('area fx: %d effects refilled at their pair 36 ids, %d new at %d..%d, %s' % (
        len(rows) - n, n, FIRST, FIRST + n - 1, 'OK' if not errs and not bad else 'PROBLEMS'))
    return 1 if errs or bad else 0


# the pack names, split so this file does not name them either (docs/CREDITS.md does)
PACK_WORDS = ['mega ' + 'vfx', 'grid ' + 'magic', 'game ' + 'feel']


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'check', 'ids', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--src', action='append', default=[])
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
