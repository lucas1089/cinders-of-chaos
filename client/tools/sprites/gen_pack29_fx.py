#!/usr/bin/env python3
"""Pair 29: Mystic line spell effects and missiles (Tier B of the 2026-10-16 Mystic effect pass), cut from the owner's
oblique effect sets.

    python3 -I gen_pack29_fx.py build --src DIR [--src DIR ...]   # -> art_import/pack29_fx/<name>.png
                                                                  #    + art_import/pack29_fx.csv + pack29_fx.sums
                                                                  #    + art_import/pack29_sources.csv
    python3 -I gen_pack29_fx.py build --src DIR ... --check       # rebuild in memory, compare with spec, sums, strips
    python3 -I gen_pack29_fx.py build --check                     # without the sets (CI): spec and sums match PICKS;
                                                                  #    strips on disk match the sums
    python3 -I gen_pack29_fx.py preview --out DIR                 # every strip 3x on a ground with the tile grid + GIFs

Sources (Google Drive "ots", 2026-10-15/16; pack names and licences in docs/CREDITS.md, per pick in
art_import/pack29_sources.csv):
  * the oblique spell impact, aura and buff, game feel, projectile and field sets: loose files, a variant's .json and
    its flattened `full` sheet, found at `sheets/32px/<category>/<effect>/<variant>/<effect>_<variant>.json` in any
    --src (read exactly like gen_pack27_fx.py, whose conversion this script reuses);
  * the 500 effect set (source names `mega:<id>`): its `metadata.json` and the `all` sheet of each effect at
    `oblique/32px/<category>/<id>.png` in any --src. Its effects are placed by their anchor tile (the unit's feet point,
    a quarter tile right and down of the tile centre, like the other sets); its projectiles by their frame centre, with
    the flat ground shadow under the projectile (near-black, half transparent) removed before the cut. That set may be
    imported into the game; it is never a style reference or an input to an AI tool (docs/SPRITE_STYLE.md).

Conversion: gen_pack27_fx.py (layers merged, alpha cut to 0 / 255 with a 4x4 ordered dither, `loop` cuts dissolve in
their last three frames, an empty last frame for effects, missiles in the client's 3 x 3 direction patterns). No pick
is recoloured: every Mystic pick has a variant in its theme colour, and the Druid-kit spells keep the nature green.

Licence (owner, 2026-10-15): use in games, modified or not, no attribution needed; no resale or redistribution of the
assets themselves. So neither the sets nor these strips are committed: art_import/pack29_fx/ is ignored by git;
art_import/pack29_fx.sums holds the sha256 of every strip's decoded RGBA pixels. Deterministic: no randomness.

Pair 29 (client/MANIFEST.md "Mystic line effects, Tier B (pair 29)"); server side server/data/lib/chaos_pack29_fx.lua
behind the switch ChaosPack29Fx.PAIR29 (off until the pair is live).
"""
import argparse
import csv
import glob
import io
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_pack27_fx as G  # noqa: E402

ART = os.path.join(HERE, 'art_import')
OUT = os.path.join(ART, 'pack29_fx')
SPEC = os.path.join(ART, 'pack29_fx.csv')
SUMS = os.path.join(ART, 'pack29_fx.sums')
SOURCES = os.path.join(ART, 'pack29_sources.csv')
LICENCE = G.LICENCE
LICENCE_MEGA = G.LICENCE + '; never a style reference or AI input'
PACK_OF = G.PACK_OF + [('mega:', 'Mega VFX 500')]

# kind, name, source effect, variant, first and last frame, step, ms per frame, note (spec order = id order).
# Spell ids and the names they replace: server/data/lib/chaos_pack29_fx.lua.
PICKS = [
    ('loop', 'storm_shock', 'status_shocked', 'thunder', 0, 15, 1, 83,
     'Forked Storm: jagged arcs crackle over each struck foe'),
    ('loop', 'covenant_bloodlust', 'status_bloodlust', 'blood', 0, 15, 1, 83,
     'Crimson Covenant: veins throb on the floor, red vapour coils up the caster'),
    ('effect', 'pyre_rune', 'field_rune_trap', 'hellfire', 0, 31, 2, 83,
     'Falling Pyre: a burning rune circle marks where the meteor falls'),
    ('effect', 'crypt_ice_strike', 'impact_ultimate_ice_strike', 'frost', 0, 15, 1, 62,
     'Frozen Crypt: a cluster of ice spikes erupts and bursts into shards and frost mist'),
    ('effect', 'doom_skyfall', 'mega:skyfall_meteor', 'all', 0, 27, 1, 67,
     'Doomtide, last wave: a meteor falls from the sky and bursts'),
    ('effect', 'doom_tornado', 'impact_tornado', 'storm', 0, 19, 1, 62,
     'Doomtide, storm wave: a howling storm funnel spins up and unwinds'),
    ('loop', 'ironbark_skin', 'status_iron_skin', 'earth', 0, 15, 1, 83,
     'Ironbark Hide: bark-like plates shimmer over the body'),
    ('loop', 'briar_rooted', 'status_rooted', 'nature@loop', 0, 15, 1, 83,
     'Briar Prison: gnarled roots coil around the feet'),
    ('effect', 'squall_spore_cloud', 'impact_mushroom_cloud', 'poison', 0, 23, 1, 62,
     'Primordial Squall, venom waves: a toxic blast swells into a spore cloud'),
    ('loop', 'mirror_ring', 'mega:circle_mirror_ring', 'all', 0, 15, 1, 83,
     'Hall of Mirrors: a ring of mirror panes turns round the caster'),
    ('effect', 'mirror_glass_nova', 'mega:burst_glass_shardnova', 'all', 0, 13, 1, 83,
     'Hall of Mirrors: each clone steps out of a burst of glass shards'),
    ('effect', 'umbral_step', 'fx_shadow_step', 'void', 0, 15, 1, 62,
     'Umbral Stride: a void shadow step where the Illusionist leaves and arrives'),
    ('effect', 'psyche_fracture', 'mega:burst_prismatic_fracture', 'all', 0, 15, 1, 83,
     'Shattered Psyche: the mind cracks in a prismatic fracture'),
    ('loop', 'wraith_veil', 'aura_shadow_veil', 'void', 0, 23, 1, 83,
     'Wraithshroud: smoke tendrils and blinking eyes veil the caster'),
    ('effect', 'night_eyelid', 'mega:burst_void_eyelid', 'all', 0, 15, 1, 83,
     'Nightburst, the gather: a void eye opens on the floor'),
    ('effect', 'night_cataclysm', 'impact_void_cataclysm', 'void', 0, 23, 1, 62,
     'Nightburst: a black hole crushes to a point and detonates in a void shockwave'),
    ('effect', 'weave_crush', 'mega:burst_gravity_crush', 'all', 0, 15, 1, 83,
     'Tear in the Weave: each implosion collapses the space round the rift'),
    ('effect', 'mend_chime', 'mega:impact_crystal_chime', 'all', 0, 11, 1, 83,
     'Mirror Mend: a crystal chime rings on the mirror'),
    ('effect', 'reverie_pop', 'mega:burst_dreambubble_pop', 'all', 0, 15, 1, 83,
     'Lucid Reverie: dream bubbles pop on each member at every pulse'),
    ('effect', 'reverie_release', 'fx_soul_release', 'spirit', 0, 15, 1, 62,
     'Lucid Reverie: spirit lights rise round the Illusionist'),
    ('loop', 'hex_curse', 'status_cursed', 'void', 0, 15, 1, 83,
     'Bewitching Hex: a void curse sigil and tendrils on the hexed foe'),
    ('missile', 'witchfire_lance', 'proj_flame_lance', 'hellfire', 0, 7, 1, 83, 'Witchfire Bolt: a lance of witchfire'),
    ('missile', 'storm_bolt', 'proj_lightning_bolt', 'storm', 0, 7, 1, 83, 'Forked Storm: a forked lightning bolt'),
    ('missile', 'pyre_comet', 'proj_comet', 'fire', 0, 7, 1, 83, 'Falling Pyre: a blazing comet'),
    ('missile', 'crypt_lance', 'proj_ice_lance', 'crystal', 0, 7, 1, 83, 'Frozen Crypt: a crystal ice lance'),
    ('missile', 'hex_missile', 'proj_arcane_missile', 'lavender', 0, 7, 1, 83, 'Bewitching Hex: a lavender arcane missile'),
    ('missile', 'umbral_raven', 'mega:raven_shade', 'all', 0, 7, 1, 83, 'Umbral Stride: a raven of shadow'),
    ('missile', 'psyche_prism', 'mega:prism_bolt', 'all', 0, 7, 1, 83, 'Shattered Psyche: a bolt splitting into a prism'),
    ('missile', 'weave_marble', 'mega:singularity_marble', 'all', 0, 7, 1, 83,
     'Tear in the Weave: a singularity drags each pulled foe in'),
    ('missile', 'mend_shards', 'mega:mirror_shard_volley', 'all', 0, 7, 1, 83, 'Mirror Mend: a volley of mirror shards'),
]

SHADOW_RGB_MAX, SHADOW_ALPHA = 16, (90, 170)   # the 500 set's projectile ground shadow: near-black, half transparent


def _mega_meta(srcs):
    for s in srcs:
        p = os.path.join(s, 'metadata.json')
        if os.path.exists(p):
            return {e['id']: e for e in json.load(open(p))['effects']}
    sys.exit(f'no metadata.json of the 500 effect set under {srcs}')


def mega_load(srcs, eid):
    """-> (pivot, rows {row: [frames]}, missile?) of one effect of the 500 set (the `all` sheet)"""
    e = _mega_meta(srcs).get(eid)
    if not e:
        sys.exit(f'{eid}: not in the 500 set metadata')
    v = e['variants']['oblique/32']
    rel = v['files']['all']
    hits = [os.path.join(s, rel) for s in srcs if os.path.exists(os.path.join(s, rel))]
    hits += sorted(glob.glob(os.path.join(srcs[0], '**', os.path.basename(rel)), recursive=True)) if not hits else []
    if not hits:
        sys.exit(f'{eid}: {rel} not found under {srcs}')
    a = np.asarray(Image.open(hits[0]).convert('RGBA'))
    fw, fh, nr, nc = v['frame_w'], v['frame_h'], v['rows'], v['columns']
    assert v['tile'] == 32 and a.shape[0] == fh * nr and a.shape[1] == fw * nc, (eid, a.shape)
    missile = e['category'] == 'projectiles'
    rows = {r: [a[r * fh:(r + 1) * fh, i * fw:(i + 1) * fw].copy() for i in range(e['frames'])] for r in range(nr)}
    if missile:
        assert nr == 8 and e.get('directions') == ['E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE'], eid
        for r in rows:
            rows[r] = [drop_shadow(f) for f in rows[r]]
        return (fw // 2, fh // 2), rows, True
    ax, ay = v['anchor_tile']
    return (ax * 32 + 24, ay * 32 + 24), rows, False


def drop_shadow(f):
    """the projectile's flat ground shadow (near-black, half transparent) removed"""
    rgb_max = f[:, :, :3].max(axis=2)
    a = f[:, :, 3]
    sh = (rgb_max <= SHADOW_RGB_MAX) & (a > SHADOW_ALPHA[0]) & (a < SHADOW_ALPHA[1])
    out = f.copy()
    out[sh] = 0
    return out


def convert(srcs, pick):
    """-> [(spec row, strip)] like gen_pack27_fx.convert, files under pack29_fx/"""
    kind, name, sid, var, a, b, step, ms, note = pick
    src = f'{sid}/{var} {a}-{b}' + (f' step {step}' if step > 1 else '')
    if sid.startswith('mega:'):
        piv, rows, missile = mega_load(srcs, sid[5:])
        assert missile == (kind == 'missile'), (name, 'kind does not match the set')
        point = G.MISSILE_CENTRE if missile else G.FEET
    else:
        meta, rows = G.load(srcs, sid, var)
        piv, point = G.pivot_point(meta, 'missile' if kind == 'missile' else 'effect')
    out = []
    if kind in ('effect', 'loop'):
        fr = G.select(rows[0], a, b, step)
        if kind == 'loop':
            for j in range(G.FADE):
                fr[len(fr) - G.FADE + j] = G.dissolve(fr[len(fr) - G.FADE + j], (G.FADE - j) / (G.FADE + 1))
        strip, w, h, n, dx, dy = G.effect_strip(name, fr, piv, point)
        out.append((dict(kind='effect', name=name, file=f'pack29_fx/{name}.png', w=w, h=h, phases=n, ms=ms,
                         dx=dx, dy=dy, note=f'{note} (from {src})'), strip))
    else:
        assert len(rows) == 8, name
        pats = {pat: G.select(rows[G.DIRS8.index(d)], a, b, step) for pat, d in G.MISSILE_DIR.items()}
        n = len(pats[(0, 0)])
        left, top, right, bottom = G.bbox_tiles([f for v in pats.values() for f in v], piv, point)
        w, h = left + 1 + right, top + 1 + bottom
        assert w <= 3 and h <= 3, (name, w, h)
        W, H = w * 32, h * 32
        strip = np.zeros((3 * H, 3 * W * n, 4), np.uint8)
        for (x, y), fr in pats.items():
            for f, img in enumerate(fr):
                assert img[:, :, 3].any(), (name, 'empty missile frame')
                x0 = (x * n + f) * W
                strip[y * H:(y + 1) * H, x0:x0 + W] = G.place(img, piv, point, left, top, w, h, name)
        out.append((dict(kind='missile', name=name, file=f'pack29_fx/{name}.png', w=w, h=h, phases=n, ms=ms,
                         dx=right, dy=bottom, note=f'{note} (from {src})'), strip))
    return out


def pack_of(sid):
    for prefix, pack in PACK_OF:
        if sid.startswith(prefix):
            return pack
    sys.exit(f'{sid}: no pack for this source effect (PACK_OF)')


def sources_text():
    """one row per pick: our name, its kind, the art pack (a docs/CREDITS.md entry), the source and the licence line"""
    buf = io.StringIO()
    wr = csv.writer(buf, lineterminator='\n')
    wr.writerow(['name', 'kind', 'pack', 'source', 'licence'])
    for kind, name, sid, var, a, b, step, ms, note in PICKS:
        mega = sid.startswith('mega:')
        wr.writerow([name, kind, pack_of(sid), sid[5:] if mega else f'{sid}/{var}', LICENCE_MEGA if mega else LICENCE])
    return buf.getvalue()


def expected_names():
    out = []
    for kind, name, sid, var, a, b, step, ms, note in PICKS:
        src = f'{sid}/{var} {a}-{b}' + (f' step {step}' if step > 1 else '')
        out.append(('effect' if kind == 'loop' else kind, name, ms, f'{note} (from {src})'))
    return out


def read(path):
    return open(path, newline='').read() if os.path.exists(path) else None


def check_without_art():
    ok = True
    spec, sums = read(SPEC), read(SUMS)
    if spec is None or sums is None:
        print('missing', SPEC if spec is None else SUMS)
        return False
    rows = list(csv.DictReader(io.StringIO(spec)))
    if read(SOURCES) != sources_text():
        print(SOURCES, 'differs from PICKS (run build)')
        ok = False
    want = expected_names()
    if [(r['kind'], r['name']) for r in rows] != [(k, n) for k, n, _, _ in want]:
        print('spec names differ from PICKS')
        ok = False
    for r, (kind, name, ms, note) in zip(rows, want):
        exp = dict(file=f'pack29_fx/{name}.png', ms=str(ms), note=note)
        for k, v in exp.items():
            if r[k] != v:
                print(f'{name}: {k} = {r[k]!r}, PICKS says {v!r}')
                ok = False
        for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'):
            r[k] = int(r[k])
        lim = 3 if kind == 'missile' else G.MAX_TILES
        if not (1 <= r['w'] <= lim and 1 <= r['h'] <= lim and 0 <= r['dx'] < r['w'] and 0 <= r['dy'] < r['h']):
            print(f'{name}: bad size or offset')
            ok = False
    sum_of = dict(reversed(line.split('  ', 1)) for line in sums.splitlines())
    if sorted(sum_of) != sorted(r['file'] for r in rows):
        print('sums do not list exactly the spec files')
        ok = False
    found = 0
    for r in rows:
        p = os.path.join(ART, r['file'])
        if os.path.exists(p):
            found += 1
            s = np.asarray(Image.open(p).convert('RGBA'))
            errs = G.check_strip(r, s)
            if G.digest(s) != sum_of.get(r['file']):
                errs.append(f"{r['name']}: strip differs from pack29_fx.sums")
            for e in errs:
                print(e)
            ok = ok and not errs
    print(f'pack29 fx check (no art sets): {len(rows)} specs, {found} strips on disk checked:',
          'OK' if ok else 'FAILED')
    return ok


def build(srcs, check):
    if not srcs:
        if not check:
            sys.exit('build needs --src (the art sets); without it only --check runs')
        return check_without_art()
    rows, strips, errs = [], [], []
    for p in PICKS:
        for r, s in convert(srcs, p):
            errs += G.check_strip(r, s)
            rows.append(r)
            strips.append(s)
    for e in errs:
        print(e)
    if errs:
        return False
    spec = G.spec_text(rows)
    sums = ''.join(f"{G.digest(s)}  {r['file']}\n" for r, s in zip(rows, strips))
    if check:
        ok = read(SPEC) == spec and read(SUMS) == sums and read(SOURCES) == sources_text()
        if not ok:
            print('spec, sums or sources differ from a rebuild')
        for r, s in zip(rows, strips):
            p = os.path.join(ART, r['file'])
            if os.path.exists(p) and not np.array_equal(np.asarray(Image.open(p).convert('RGBA')), s):
                print(r['name'], 'strip differs from a rebuild')
                ok = False
        print('pack29 fx check:', 'OK' if ok else 'FAILED')
        return ok
    os.makedirs(OUT, exist_ok=True)
    for r, s in zip(rows, strips):
        Image.fromarray(s).save(os.path.join(ART, r['file']), optimize=True)
    open(SPEC, 'w', newline='').write(spec)
    open(SUMS, 'w', newline='').write(sums)
    open(SOURCES, 'w', newline='').write(sources_text())
    for r in rows:
        print(f"{r['kind']} {r['name']}: {r['w']}x{r['h']}, offset {r['dx']},{r['dy']}, {r['phases']} x {r['ms']} ms")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src', action='append', default=[])
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    a = ap.parse_args()
    if a.cmd == 'build':
        sys.exit(0 if build(a.src, a.check) else 1)
    G.SPEC, G.ART = SPEC, ART
    G.preview(a.out)


if __name__ == '__main__':
    main()
