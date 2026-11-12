#!/usr/bin/env python3
"""The 40 effects of the owner's donor client (O525 step 2): strips, spec, sums, send offsets, the id table.

    python3 -I gen_donor_fx.py build --src DIR      # DIR holds the donor client's Tibia.dat and Tibia.spr; writes the
                                                    # strips art_import/donor_fx/*.png (never committed), art_import/donor_fx.csv
                                                    # and donor_fx.sums
    python3 -I gen_donor_fx.py build --src DIR --check   # CI with the files: the strips, the spec and the sums are what
                                                    # the donor files give
    python3 -I gen_donor_fx.py --check              # CI without the files: the spec, the sums, the picks agree
    python3 -I gen_donor_fx.py ids                  # server/data/lib/chaos_donor_fx_ids.lua from server/data/spells/donor_fx_catalog.csv
    python3 -I gen_donor_fx.py ids --check          # the committed id table is up to date
    python3 -I gen_donor_fx.py live DAT SPR         # the pair holds the 40 effects at the catalog ids, as the spec says

The owner supplied the donor client's art (origin unknown, docs/CREDITS.md). The art never enters the repository: the
picks (PICKS: the donor effect id, our element and role, the rank the owner saw) and the numbers read from the files at
build time are all that is committed. Each effect keeps its whole frame group at native size: no halving, no dither, no
crop, the soft alpha of its frames, its phases and its per phase durations (min and max, as the donor has them). The
donor's light flag and loop fields are not copied (import_fx_art.py writes the pair's own: play once).

Send offset (dx, dy): the whole tiles past the target tile that put the alpha weighted centre of the art over all
phases nearest the middle of the target tile (the client draws the bottom right tile of an effect on the tile it is sent
to, so the canvas starts w - 1 - dx tiles up and left of the target). The art is not moved.

Then import_fx_art.py appends them after the effects of the input pair:
    python3 -I import_fx_art.py --ours-dat P/Tibia.dat --ours-spr P/Tibia.spr --out-dir OUT --spec art_import/donor_fx.csv \
        --catalog-out ../../../server/data/spells/donor_fx_catalog.csv
and `gen_donor_fx.py ids` writes the Lua table from the catalog. Needs numpy and Pillow (the fx venv of CI).
"""
import argparse
import csv
import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'donor_fx')
SPEC = os.path.join(ART, 'donor_fx.csv')
SUMS = os.path.join(ART, 'donor_fx.sums')
CATALOG = os.path.join(ROOT, 'server', 'data', 'spells', 'donor_fx_catalog.csv')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_donor_fx_ids.lua')
TAGS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_elements.csv')
ALLOWS = os.path.join(ROOT, 'server', 'data', 'spells', 'spell_fx_allow.csv')
# spells of another element than the donor picture they send (check_spell_fx.py): (spell id, spell, effect name, reason)
ALLOW = []
FIELDS = ['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs', 'donor', 'element', 'role', 'rank']

# (donor effect id, element, role) in the owner's ranking of 2026-11-12 (the sheet of step 1)
PICKS = [(489, 'ice', 'hit'), (475, 'ice', 'hit'), (279, 'ice', 'nova'), (531, 'ice', 'burst'), (632, 'energy', 'strike'),
         (528, 'energy', 'bolt'), (465, 'fire', 'hit'), (276, 'fire', 'nova'), (695, 'arcane', 'nova'), (641, 'arcane', 'field'),
         (492, 'ice', 'aura'), (494, 'arcane', 'aura'), (216, 'holy', 'aura'), (278, 'holy', 'nova'), (281, 'earth', 'nova'),
         (626, 'ice', 'nova'), (654, 'ice', 'burst'), (233, 'energy', 'hit'), (201, 'ice', 'hit'), (604, 'energy', 'bolt'),
         (602, 'arcane', 'bolt'), (598, 'ice', 'bolt'), (692, 'fire', 'burst'), (508, 'fire', 'comet'), (688, 'death', 'nova'),
         (686, 'death', 'nova'), (683, 'holy', 'nova'), (449, 'holy', 'ring'), (452, 'ice', 'ring'), (450, 'physical', 'ring'),
         (280, 'physical', 'nova'), (277, 'physical', 'nova'), (493, 'holy', 'aura'), (495, 'physical', 'aura'),
         (505, 'earth', 'field'), (636, 'earth', 'field'), (605, 'earth', 'bolt'), (655, 'physical', 'slash'),
         (223, 'physical', 'slash'), (209, 'physical', 'hit')]


def name_of(donor, element, role):
    return 'donor_%s_%s_%d' % (element, role, donor)


def digest(strip):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


def axis_error(c, n, d):
    """px from the target tile's middle to the art centre c (px from the canvas edge, n tiles) when sent d tiles past it"""
    return c - ((n - 1 - d) * 32 + 16)


def fit_axis(c, n):
    return min(range(n), key=lambda d: (abs(axis_error(c, n, d)), d))


def centre_of(frames):
    import numpy as np
    total = cx = cy = 0.0
    for fr in frames:
        a = fr[..., 3].astype(float) / 255.0
        ys, xs = np.indices(a.shape)
        total += a.sum()
        cx += (a * xs).sum()
        cy += (a * ys).sum()
    return (cx / total, cy / total)


def durs_text(anim, phases):
    if not anim:
        return '100'
    d = anim[3]
    return ';'.join(str(d[2 * i]) if d[2 * i] == d[2 * i + 1] else '%d:%d' % (d[2 * i], d[2 * i + 1]) for i in range(phases))


def rows_from(src):
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from fxlib import render_frame
    dat = Dat(os.path.join(src, 'Tibia.dat'))
    spr = Spr(os.path.join(src, 'Tibia.spr'))
    out = []
    for k, (eid, el, role) in enumerate(PICKS):
        t = dat.effects[eid - 1]
        assert (t.layers, t.px, t.py, t.pz) == (1, 1, 1, 1), (eid, 'layers or patterns')
        frames = [np.array(render_frame(t, spr, p)) for p in range(t.phases)]
        cx, cy = centre_of(frames)
        durs = durs_text(t.anim, t.phases)
        mean = [int(x.split(':')[0]) for x in durs.split(';')]
        strip = np.concatenate(frames, axis=1)
        strip[strip[..., 3] == 0] = 0
        name = name_of(eid, el, role)
        row = dict(replace='', kind='effect', name=name, file='donor_fx/%s.png' % name, w=t.w, h=t.h, phases=t.phases,
                   ms=round(sum(mean) / len(mean)), dx=fit_axis(cx, t.w), dy=fit_axis(cy, t.h),
                   note='%s %s of the owner\'s donor client, effect %d (rank %d)' % (el, role, eid, k + 1),
                   alpha='soft', durs=durs, donor=eid, element=el, role=role, rank=k + 1)
        out.append((row, strip))
    return out


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def build(src, check):
    from PIL import Image
    pairs = rows_from(src)
    rows = [r for r, _ in pairs]
    sums = ''.join('%s  %s\n' % (digest(s), r['file']) for r, s in pairs)
    texts = {SPEC: spec_text(rows), SUMS: sums}
    if check:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        for p in bad:
            print('differs:', os.path.relpath(p, HERE))
        for r, s in pairs:
            f = os.path.join(ART, r['file'])
            if os.path.exists(f):
                import numpy as np
                if digest(np.asarray(Image.open(f).convert('RGBA'))) != digest(s):
                    bad.append(f)
                    print('strip differs:', r['file'])
        print('donor fx: %d effects, %s' % (len(rows), 'OK' if not bad else 'DIFFERS'))
        return 1 if bad else 0
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, '.gitignore'), 'w') as fh:
        fh.write('# strips cut from the owner\'s donor client: never committed (gen_donor_fx.py)\n*\n!.gitignore\n')
    for r, s in pairs:
        Image.fromarray(s).save(os.path.join(ART, r['file']), optimize=False)
    for p, t in texts.items():
        open(p, 'w', newline='').write(t)
    print('wrote %d strips, %s, %s' % (len(rows), os.path.relpath(SPEC, ROOT), os.path.relpath(SUMS, ROOT)))
    return 0


def read_spec():
    with open(SPEC, newline='') as fh:
        return list(csv.DictReader(fh))


def check_without_art():
    errs = []
    rows = read_spec()
    if [(int(r['donor']), r['element'], r['role']) for r in rows] != PICKS:
        errs.append('donor_fx.csv does not list PICKS in order')
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names) or any(r['name'] != name_of(int(r['donor']), r['element'], r['role']) for r in rows):
        errs.append('names: not unique or not donor_<element>_<role>_<donor id>')
    for r in rows:
        w, h, dx, dy, n = (int(r[k]) for k in ('w', 'h', 'dx', 'dy', 'phases'))
        if not (0 <= dx < w and 0 <= dy < h):
            errs.append('%s: offset outside' % r['name'])
        if len(r['durs'].split(';')) != n:
            errs.append('%s: durs count' % r['name'])
        if r['replace'] or r['kind'] != 'effect' or r['alpha'] != 'soft':
            errs.append('%s: must be a new soft effect' % r['name'])
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS)] if os.path.exists(SUMS) else []
    if sums != [r['file'] for r in rows]:
        errs.append('donor_fx.sums does not list the spec files in order')
    for r in rows:
        f = os.path.join(ART, r['file'])
        if os.path.exists(f):
            import numpy as np
            from PIL import Image
            want = dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))
            if digest(np.asarray(Image.open(f).convert('RGBA'))) != want[r['file']]:
                errs.append('%s: differs from its sum' % r['file'])
    errs += catalog_errors(rows)
    for e in errs:
        print(e)
    print('donor fx: %d things, %s' % (len(rows), 'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


def catalog_rows():
    with open(CATALOG, newline='') as fh:
        return list(csv.DictReader(fh))


def catalog_errors(rows):
    """the catalog (written by import_fx_art.py) lists the spec's things, consecutive ids, same size / offset / frames"""
    if not os.path.exists(CATALOG):
        return ['server/data/spells/donor_fx_catalog.csv is missing']
    cat = catalog_rows()
    errs = []
    if [c['name'] for c in cat] != [r['name'] for r in rows]:
        return ['donor_fx_catalog.csv does not list the spec names in order']
    ids = [int(c['id']) for c in cat]
    if ids != list(range(ids[0], ids[0] + len(ids))):
        errs.append('catalog ids are not consecutive')
    for c, r in zip(cat, rows):
        if (c['size'], c['send_offset'], int(c['frames'])) != ('%sx%s' % (r['w'], r['h']), '%s,%s' % (r['dx'], r['dy']), int(r['phases'])):
            errs.append('%s: catalog differs from the spec' % r['name'])
    return errs


def total_ms(durs):
    return sum((int(a.split(':')[0]) + int(a.split(':')[-1])) // 2 for a in durs.split(';'))


def lua_text(rows, cat):
    L = ['-- GENERATED by client/tools/sprites/gen_donor_fx.py from art_import/donor_fx.csv and data/spells/donor_fx_catalog.csv:',
         '-- the 40 effects of the owner\'s donor client (O525, client pair 68, ids %s..%s), appended after the effects of pair 67.' % (
             cat[0]['id'], cat[-1]['id']),
         '-- Native size, soft alpha, the donor\'s frame durations.  Do not edit by hand.',
         '-- Merged into ChaosVfx, so Vfx(pos, name) sends one at its offset tile (an effect bigger than a tile is drawn with its',
         '-- bottom-right tile on the tile it is sent to).  They show only with a client on pair 68 or newer.',
         'if not ChaosVfx then',
         '\tpcall(dofile, "data/lib/chaos_vfx.lua")',
         'end',
         'ChaosVfx = ChaosVfx or {}']
    for r, c in zip(rows, cat):
        L.append('ChaosVfx.%s = {id = %s, dx = %s, dy = %s, ms = %d}  -- %s' % (
            r['name'], c['id'], r['dx'], r['dy'], total_ms(r['durs']), r['note']))
    return '\n'.join(L) + '\n'


def tags_text(rows, cat):
    """spell_fx_elements.csv with the 40 donor rows (id, name, element) at its end, the other rows as they are"""
    with open(TAGS, encoding='utf-8', newline='') as fh:
        keep = [l for l in fh.read().splitlines() if not l.split(',')[1:2] or not l.split(',')[1].startswith('donor_')]
    return '\n'.join(keep + ['%s,%s,%s' % (c['id'], r['name'], r['element']) for r, c in zip(rows, cat)]) + '\n'


def allow_text(rows, cat):
    with open(ALLOWS, encoding='utf-8', newline='') as fh:
        keep = [l for l in fh.read().splitlines() if '"' in l or 'donor_' not in l.split(',')[3:4][0:1].__str__()]
    by = {r['name']: c['id'] for r, c in zip(rows, cat)}
    return '\n'.join(keep + ['%d,%s,%s,%s,%s' % (sid, sp, by[nm], nm, why) for sid, sp, nm, why in ALLOW]) + '\n'


def ids(check):
    rows = read_spec()
    errs = catalog_errors(rows)
    if errs:
        print('\n'.join(errs))
        return 1
    cat = catalog_rows()
    want = {LUA: lua_text(rows, cat), TAGS: tags_text(rows, cat), ALLOWS: allow_text(rows, cat)}
    if check:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_donor_fx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


def live(dat_path, spr_path):
    """the pair holds each effect at its catalog id with the spec's size, phases, durations and the art's pixels"""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from fxlib import render_frame
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_spec()
    cat = catalog_rows()
    errs = []
    sums = dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))
    for r, c in zip(rows, cat):
        t = dat.effects[int(c['id']) - 1]
        if (t.w, t.h, t.phases) != (int(r['w']), int(r['h']), int(r['phases'])):
            errs.append('%s: size or phases differ at %s' % (r['name'], c['id']))
            continue
        d = t.anim[3] if t.anim else ()
        want = [v for x in r['durs'].split(';') for v in ((int(x.split(':')[0]), int(x.split(':')[-1])))]
        if list(d) != want:
            errs.append('%s: durations differ' % r['name'])
        strip = np.concatenate([np.array(render_frame(t, spr, p)) for p in range(t.phases)], axis=1)
        strip[strip[..., 3] == 0] = 0
        if digest(strip) != sums[r['file']]:
            errs.append('%s: pixels differ from the sum' % r['name'])
    for e in errs:
        print(e)
    print('donor fx live: %d effects at ids %s..%s, %s' % (len(rows), cat[0]['id'], cat[-1]['id'], 'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', nargs='?', default='', choices=['', 'build', 'ids', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--src')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'build':
        if not a.src:
            sys.exit('build needs --src DIR')
        return build(a.src, a.check)
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'live':
        return live(*a.rest)
    return check_without_art()


if __name__ == '__main__':
    sys.exit(main())
