#!/usr/bin/env python3
"""Ground effects: the effect ids the client draws under the creatures (base patch 0055, g_map.setGroundEffect).

    python3 -I gen_ground_fx.py build            # ground_fx.csv + the server catalogues -> groundfx_data.lua
    python3 -I gen_ground_fx.py build --check    # CI: the rules hold and groundfx_data.lua is up to date
    python3 -I gen_ground_fx.py measure --dat D --spr S [--check]
                                                 # body cover of every effect of the pair -> ground_fx_cover.csv
    python3 -I gen_ground_fx.py suggest          # print the tagged effects that ground_fx.csv does not list yet

Owner (2026-10-16): spell effects drawn over the player or monster hid them. Floor shapes (rune circles, seals, glyphs,
novas, shockwave rings, rifts, warning areas) and every effect that covers the creature on its tile for long now lie
under the creatures; projectiles and short hits stay above.

One list, in `ground_fx.csv` (name, layer `ground` or `above`, reason). Names are resolved to ids through the server
catalogues (server/data/spells/*_catalog.csv), so no id is written by hand. A name ending in `_*` stands for the eight
directional effects `<name>_n` .. `<name>_nw`. The procedural effects (effects_catalog.csv, Lua ChaosFx) are named
`fx:<name>`, because ChaosFx and ChaosVfx share a few names (frost_nova, fire_explosion). Output: client/overlay/modules/game_groundfx/groundfx_data.lua.

Rules (the build stops when one fails). An effect is *tagged* as a ground or area shape when:
  1. it is a procedural effect (effects_catalog.csv) of style circle, nova or rings, or an aura whose note says ring,
     and not an engine hit (the engine sends those on the creature that is hit);
  2. it is a large effect (big_fx_catalog.csv): every one is a floor-sized shape around its centre tile;
  3. its name says it is a floor shape (seal, sigil, glyph, rune, ring, nova, telegraph, rift, pad, warning, quake,
     shock, dome, pentagram);
  4. it covers the body box of the creature on its target tile (32 x 32, 8 px up-left of the tile, the outfit
     displacement) at 35 % or more for 500 ms or longer (ground_fx_cover.csv, measured on the pair by `measure`).
Every effect tagged by 1, 2 or 4 must be `ground`. Rule 3 can be overruled by an `above` row with a reason (a ring
over the head). Rule 4 spares the status words (status_fx_catalog.csv): their words must stay readable over the body.
Every name of the csv must exist in a catalogue; no name twice.
"""
import argparse
import csv
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
CATS = os.path.join(REPO, 'server', 'data', 'spells')
SPEC = os.path.join(HERE, 'ground_fx.csv')
COVER = os.path.join(HERE, 'ground_fx_cover.csv')
OUT = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_groundfx', 'groundfx_data.lua')
CATALOGUES = ['effects_catalog.csv', 'vfx_catalog.csv', 'vfx_art_catalog.csv', 'class_fx_catalog.csv',
              'pack_fx_catalog.csv', 'big_fx_catalog.csv', 'status_fx_catalog.csv', 'pack27_fx_catalog.csv',
              'pack29_fx_catalog.csv']
DIRS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']
GROUND_STYLES = {'circle', 'nova', 'rings'}
NAME_WORDS = re.compile(r'(^|_)(seal|sigil|glyph|rune|ring|rings|nova|telegraph|rift|pad|warning|quake|shock|dome|'
                        r'pentagram)(_|$)')
COVER_MIN, COVER_MS = 0.35, 500
BODY = 8   # px: the body box sits this far up-left of the target tile (outfit displacement)


def catalogue():
    """[(name, row)]: row = id, size, offset, note, style, use, source catalogue; effects only. A name may stand for
    two ids (a vigil banner of the class set and of pair 27): a csv row covers both"""
    out = []
    for fn in CATALOGUES:
        for r in csv.DictReader(open(os.path.join(CATS, fn), encoding='utf-8')):
            if (r.get('kind') or r.get('category')) != 'effect':
                continue
            key = ('fx:' + r['name']) if fn == 'effects_catalog.csv' else r['name']
            out.append((key, dict(id=int(r['id']), size=r['size'], offset=r.get('send_offset') or '0,0',
                                  note=r.get('note', ''), style=r.get('style', ''), use=r.get('use', ''), cat=fn)))
    ids = [row['id'] for _, row in out]
    assert len(ids) == len(set(ids)), 'an effect id in two catalogues'
    return sorted(out, key=lambda kv: kv[1]['id'])


def read_spec():
    rows = list(csv.DictReader(open(SPEC, encoding='utf-8')))
    out = []
    for r in rows:
        names = [r['name'][:-1] + d for d in DIRS] if r['name'].endswith('_*') else [r['name']]
        for n in names:
            out.append(dict(name=n, layer=r['layer'].strip(), reason=r['reason'].strip()))
    return out


def read_cover():
    if not os.path.exists(COVER):
        return {}
    return {int(r['id']): dict(ms=int(r['cover_ms']), peak=float(r['peak']))
            for r in csv.DictReader(open(COVER, encoding='utf-8'))}


def tags(name, row, c):
    """the rules that tag an effect as a ground shape (numbers as in the docstring); c: its measured cover"""
    t = []
    if row['cat'] == 'effects_catalog.csv':
        aura_ring = row['style'] == 'aura' and 'ring' in row['note'].lower()
        if (row['style'] in GROUND_STYLES or aura_ring) and 'engine' not in row['note'].lower():
            t.append(1)
    if row['cat'] == 'big_fx_catalog.csv':
        t.append(2)
    if row['size'] != '1x1' and NAME_WORDS.search(name.split(':')[-1]):
        t.append(3)
    if c and c['ms'] >= COVER_MS and row['cat'] != 'status_fx_catalog.csv':
        t.append(4)
    return t


def check(cat, spec, cover):
    errors, seen = [], {}
    names = {n for n, _ in cat}
    for r in spec:
        if r['name'] in seen:
            errors.append('%s: listed twice' % r['name'])
        seen[r['name']] = r
        if r['name'] not in names:
            errors.append('%s: not in any catalogue (server/data/spells/*_catalog.csv)' % r['name'])
        if r['layer'] not in ('ground', 'above'):
            errors.append('%s: layer %r (ground or above)' % (r['name'], r['layer']))
        if not r['reason']:
            errors.append('%s: no reason' % r['name'])
    for name, row in cat:
        t = tags(name, row, cover.get(row['id']))
        r = seen.get(name)
        hard = [x for x in t if x in (1, 2, 4)]
        if hard and (not r or r['layer'] != 'ground'):
            errors.append('%s (%d): tagged by rule %s, must be listed as ground' % (name, row['id'], hard))
        elif 3 in t and not r:
            errors.append('%s (%d): its name says floor shape (rule 3): list it as ground, or above with a reason'
                          % (name, row['id']))
    return errors


def lua_text(cat, spec):
    want = {r['name'] for r in spec if r['layer'] == 'ground'}
    ground = sorted((row['id'], name) for name, row in cat if name in want)
    L = ['-- GENERATED by client/tools/sprites/gen_ground_fx.py from client/tools/sprites/ground_fx.csv and the server',
         '-- effect catalogues (server/data/spells/*_catalog.csv). Do not edit by hand.',
         '-- Effect ids drawn under the creatures (base patch 0055, g_map.setGroundEffect): floor shapes and the effects',
         '-- that would cover a creature for long. game_groundfx registers them.',
         'GroundFxData = {',
         '  ids = {']
    line = '   '
    for i, (tid, _) in enumerate(ground):
        piece = ' %d,' % tid
        if len(line) + len(piece) > 118:
            L.append(line)
            line = '   '
        line += piece
    L.append(line)
    L.append('  },')
    L.append('  names = {')
    for tid, name in ground:
        L.append('    [%d] = "%s",' % (tid, name))
    L.append('  },')
    L.append('}')
    return '\n'.join(L) + '\n'


def cmd_build(args):
    cat, spec, cover = catalogue(), read_spec(), read_cover()
    errors = check(cat, spec, cover)
    if not cover:
        errors.append('ground_fx_cover.csv missing: run `measure` on the pair first')
    if errors:
        print('\n'.join(errors))
        return 1
    text = lua_text(cat, spec)
    if args.check:
        have = open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else ''
        if have != text:
            print('%s is out of date: run gen_ground_fx.py build' % os.path.relpath(OUT, REPO))
            return 1
        print('ok: %d ground effects' % text.count('] = "'))
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote %s: %d ground effects' % (os.path.relpath(OUT, REPO), text.count('] = "')))
    return 0


def measure_rows(dat_path, spr_path, cat):
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_vfx import render_back
    dat, spr = Dat(dat_path), Spr(spr_path)
    out = []
    for name, row in cat:
        t = dat.effects[row['id'] - 1]
        dx, dy = (int(v) for v in row['offset'].split(','))
        fr = render_back(t, spr, 1)
        durs = [max(20, t.anim[3][2 * i]) for i in range(t.phases)] if t.anim else [100] * t.phases
        tx, ty = (t.w - 1 - dx) * 32 - BODY, (t.h - 1 - dy) * 32 - BODY
        ms, peak = 0, 0.0
        for ph in range(t.phases):
            a = fr[(ph, 0, 0, 0)][..., 3] > 0
            box = a[max(0, ty):ty + 32, max(0, tx):tx + 32]
            c = box.sum() / 1024.0
            peak = max(peak, c)
            if c >= COVER_MIN:
                ms += durs[ph]
        out.append((row['id'], name, t.w * t.h, round(peak, 2), ms))
    return out


def cover_text(rows):
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(['id', 'name', 'tiles', 'peak', 'cover_ms'])
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


def cmd_measure(args):
    text = cover_text(measure_rows(args.dat, args.spr, catalogue()))
    if args.check:
        have = open(COVER, encoding='utf-8').read() if os.path.exists(COVER) else ''
        print('ok' if have == text else 'ground_fx_cover.csv differs from the pair')
        return 0 if have == text else 1
    with open(COVER, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote %s' % os.path.relpath(COVER, REPO))
    return 0


def cmd_suggest(args):
    cat, cover = catalogue(), read_cover()
    spec = {r['name']: r for r in read_spec()} if os.path.exists(SPEC) else {}
    for name, row in cat:
        c = cover.get(row['id'], {})
        t = tags(name, row, c)
        if t and name not in spec:
            print(row['id'], name, row['size'], t, c.get('ms'), row['note'][:60])
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--check', action='store_true')
    m = sub.add_parser('measure')
    m.add_argument('--dat', required=True)
    m.add_argument('--spr', required=True)
    m.add_argument('--check', action='store_true')
    sub.add_parser('suggest')
    args = ap.parse_args(argv)
    return {'build': cmd_build, 'measure': cmd_measure, 'suggest': cmd_suggest}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
