#!/usr/bin/env python3
"""Looks of the five relic sets: PixelLab pictures, 32 x 32, become client items 44446-44510 (appended to pair 57, client/MANIFEST.md
"Pair 58"). Owner approved the art and asked for the import on 2026-10-30 ("Aprovo, pode importar os sets como itens"). Five sets of
13 pieces: a helmet, a chest armour, legs, boots, a shield, a spellbook, a sword, a two-handed axe, a war hammer, a bow, a wand or a rod,
a ring and an amulet. Server ids = client id + 4000 (48446-48510, the pair 50 rule; server/data/items/relic_sets.csv,
server/tools/install_relic_sets.py, server/README.md "Relic sets (pair 58)").

    python3 -I gen_relic_sets_art.py build [--from-dir DIR | --src KEY=FILE ...] [--check] [--preview DIR --dat P/Tibia.dat --spr P/Tibia.spr]

PixelLab results (create_image_pro, 32 x 32 RGBA, alpha 0 / 255; docs/CREDITS.md "Tools"). The pixels are PixelLab's, owner approved:
nothing is repainted, snapped, mirrored or recoloured here (only the colour under fully transparent pixels is cleared).
`build --from-dir DIR` takes DIR/<ember|gilded|rime|abyssal|venom>/NN_<slot>.png (the owner-approved pictures of the 2026-10-30 review),
`--src KEY=FILE` (repeatable) one picture; both check it and copy it to art_import/relic_sets/KEY.png (the committed source). Without
either the committed copies are used (CI).

Outputs (committed): art_import/relic_sets.png (the atlas, 32 px cells side by side in LOOKS order), art_import/relic_sets.csv (the things file
of import_art_things.py: 1 x 1, one phase, the dat flags copied from a stock item of the kind like gen_gear_sets_art.py, mode new; `extra`
carries what the server needs: set, kind, fit, level, description), art_import/relic_sets.sums (sha256 of the decoded pixels of each
source and of the atlas) and art_import/relic_sets_sources.csv (credits). `--check` (CI) rebuilds from the committed sources and
compares, writes nothing. The server manifest server/data/items/relic_sets.csv is import_art_things.py's --manifest-out of the things
file (--server-offset 4000).

Style: docs/SPRITE_STYLE.md wants one theme palette. These looks use their own colours and the owner approved the pixels, so they are not
snapped. `build` runs the style check on each canvas against its own colours: every rule but the theme palette must pass or `build`
refuses; the light rule is a warning; the rules a look misses by a little (owner approved as drawn) are in WAIVED, printed, never silent.
Deterministic: numpy and Pillow only.

The weights: the helmets, chest armours and legs are fit A (anyone wears them, as the later tiers' legs of install_gear_sets.py): one of a
kind per set cannot dress three armour weights, and a class that wears no heavy, medium or cloth piece of a band should still find one.
"""
import argparse, csv, hashlib, io, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
NAME = 'relic_sets'
FIRST_ITEM = 44446          # right after the last item of pair 57 (44445, the weapons above level 800)
SERVER_OFFSET = 4000

# set key, display name, folder of the review pictures, level, damage element, theme words (the look), staff type
SETS = [
    ('venomcoil', 'Venomcoil', 'venom', 640, 'earth', 'dark green scales with gold trim and poison-green gems', 'wand'),
    ('hoarglass', 'Hoarglass', 'rime', 860, 'ice', 'pale ice-blue steel with frost crystals and silver edges', 'wand'),
    ('kilnforged', 'Kilnforged', 'ember', 1400, 'fire', 'blackened iron with red trim and glowing ember seams', 'wand'),
    ('halogild', 'Halogild', 'gilded', 1700, 'holy', 'polished gold with blue and red gems', 'rod'),
    ('deepdirge', 'Deepdirge', 'abyssal', 2050, 'death', 'dark steel lit by teal abyssal gems', 'rod'),
]
# slot: number in the review folder, file word, things kind, fit, noun of the name, description frame (the set's look fills %s)
SLOTS = [
    (1, 'helmet', 'helmet', 'A', 'helm', 'A helm of %s.'),
    (2, 'chest', 'armor', 'A', 'cuirass', 'A cuirass of %s.'),
    (3, 'legs', 'legs', 'A', 'greaves', 'Greaves of %s.'),
    (4, 'boots', 'boots', '', 'boots', 'Boots of %s.'),
    (5, 'shield', 'shield', '', 'shield', 'A shield of %s.'),
    (6, 'spellbook', 'spellbook', '', 'tome', 'A spellbook bound in %s.'),
    (7, 'sword', 'sword', '1', 'blade', 'A one-handed sword of %s.'),
    (8, 'axe', 'axe', '2', 'greataxe', 'A two-handed axe of %s.'),
    (9, 'hammer', 'club', '1', 'warhammer', 'A one-handed war hammer of %s.'),
    (10, 'bow', 'bow', '', 'bow', 'A bow of %s.'),
    (11, 'staff', None, '', None, None),    # a wand or a rod by the set (the noun: scepter or staff)
    (12, 'ring', 'ring', '', 'ring', 'A ring of %s.'),
    (13, 'amulet', 'amulet', '', 'amulet', 'An amulet of %s.'),
]
COPY = {   # dat flags of a stock item per kind (client ids of the 10.98 pair; the same as gen_gear_sets_art.py)
    'sword': 3264, 'axe': 3274, 'club': 3270, 'bow': 3350, 'crossbow': 3349, 'wand': 3066, 'rod': 3066,
    'shield': 3409, 'spellbook': 3059, 'helmet': 3351, 'armor': 3357, 'legs': 3557, 'boots': 3552, 'amulet': 3572,
    'ring': 3063,
}


def _looks():
    out, cid = [], FIRST_ITEM
    for skey, sname, folder, level, element, theme, staff in SETS:
        for num, word, kind, fit, noun, frame in SLOTS:
            if word == 'staff':
                kind, noun = staff, 'scepter' if staff == 'wand' else 'staff'
                frame = 'A %s topped with a gem of %%s.' % ('wand' if staff == 'wand' else 'staff')
            key = '%s_%s' % (skey, word)
            desc = '%s Part of the %s set (level %d).' % (frame % theme, sname, level)
            out.append((key, skey, kind, fit, '%s %s' % (sname.lower(), noun), cid, cid + SERVER_OFFSET, level, desc, folder, num, word))
            cid += 1
    return out


# (key, set, kind, fit, name, client id, server id, level, description, review folder, review number, review word)
LOOKS = _looks()
KEYS = [l[0] for l in LOOKS]
# PixelLab job of the first pick of each picture (the review folders' jobs.txt). The pictures marked REPLACED were re-rolled or fixed
# afterwards: the final picture is not that job. The ember set's jobs were not kept.
JOBS = {
    'gilded': '241f6400 11648959 cc2ef33d 93e00a9d 610aa1b0 9149a588 fdbd90db 018e12fc 600c42b6 40d127d0 71115b18 bed5e5e9 38d2062d',
    'rime': 'b578b865 fb195762 81be007d bf79f0be 0c032574 6b5a1fb1 70d8d4da c13cd4b8 d31feb6b 8d1189c2 12e76fc9 59ec1615 5dc169fb',
    'abyssal': '11e31b4e a195ce08 fbe9615c 94d4f85f a8fb0b5a 1e28e48e 836e7ecc 553f4c89 36935266 0285507f 59f5a6bf e4c0e3e3 4d095ecc',
    'venom': '142b7574 0d7727e7 fe9cda75 86d0231b 0b058046 be01c833 5b31ecb7 cb3b8662 2b9ed585 ddb93d16 6c1f6c86 04afc9be 64695750',
}
REPLACED = {'abyssal_axe', 'abyssal_bow', 'gilded_chest', 'gilded_bow', 'rime_legs', 'rime_staff', 'venom_axe', 'venom_hammer',
            'venom_bow', 'venom_ring'}
REPLACED = {'%s_%s' % ({'abyssal': 'deepdirge', 'gilded': 'halogild', 'rime': 'hoarglass', 'venom': 'venomcoil'}[k.split('_')[0]], k.split('_')[1])
            for k in REPLACED}
# style rules a look misses by a little but the owner approved as drawn (key -> {rule word: why}); printed, never silent
def _rim(pct):
    return {'outline': '%d%% near-black rim (min 30%%): PixelLab draws a dark coloured rim, navy, teal or brown' % pct}


def _flat(n, what):
    return {'colours': '%d colours (min 11): %s' % (n, what)}


WAIVED = {
    'venomcoil_bow': _flat(9, 'a thin bow of two greens and a string'),
    'hoarglass_chest': _rim(0), 'hoarglass_shield': _rim(0), 'hoarglass_spellbook': _rim(0), 'hoarglass_axe': _rim(0),
    'hoarglass_amulet': _rim(0),
    'kilnforged_boots': _rim(14), 'kilnforged_spellbook': _rim(0),
    'kilnforged_amulet': dict(_rim(0), **_flat(8, 'a small red gem on a chain')),
    'halogild_legs': dict(_rim(0), **_flat(9, 'plain gold plates')),
    'halogild_boots': _rim(0), 'halogild_shield': _rim(0), 'halogild_spellbook': _rim(17), 'halogild_ring': _rim(0),
    'halogild_amulet': dict(_rim(0), noise='two lone pixels and two specks (max 1 and 2): the chain'),
    'deepdirge_legs': _rim(0), 'deepdirge_boots': _rim(0), 'deepdirge_bow': _flat(8, 'a thin bow of two teals and a string'),
    'deepdirge_amulet': _rim(0),
}
SRC_DIR = os.path.join(ART, NAME)
ATLAS = os.path.join(ART, NAME + '.png')
THINGS = os.path.join(ART, NAME + '.csv')
SUMS = os.path.join(ART, NAME + '.sums')
SOURCES_CSV = os.path.join(ART, NAME + '_sources.csv')
CELL = 32
HEADER = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode',
          'server_id', 'extra']


def src_path(key):
    return os.path.join(SRC_DIR, key + '.png')


def extra_of(look):
    key, skey, kind, fit, _name, _cid, _sid, level, desc = look[:9]
    return 'set=%s|kind=%s|fit=%s|level=%d|description=%s' % (skey, kind, fit, level, desc)


def read_rgba(path):
    """the picture as RGBA; the colour under fully transparent pixels is cleared (PixelLab leaves noise there, nothing
    visible changes: the importer treats alpha 0 as empty)"""
    a = np.array(Image.open(path).convert('RGBA'))
    a[a[..., 3] == 0] = 0
    return a


def problems_of(a):
    """why a picture cannot be a 32 x 32 item canvas ([] = fine)"""
    if a.shape[:2] != (CELL, CELL):
        return ['size %d x %d, not %d x %d' % (a.shape[1], a.shape[0], CELL, CELL)]
    out = []
    al = a[..., 3]
    if ((al != 0) & (al != 255)).any():
        out.append('semi-transparent pixels (alpha must be 0 or 255)')
    if not (al == 255).any():
        out.append('empty')
    else:
        ys, xs = np.nonzero(al)
        if max(ys.max() - ys.min(), xs.max() - xs.min()) < 12:
            out.append('the art does not fill the canvas (an item is at least 13 px wide or high)')
    if (a[al == 0][:, :3] != 0).any():
        out.append('colour under transparent pixels')
    return out


def style_report(a):
    """(reasons that stop the build, warnings, colour count); the palette rule is judged against the canvas's own colours"""
    data = sc.load_palettes()
    own = np.unique(a[a[..., 3] > 0][:, :3], axis=0)
    bad, warn = sc.judge(sc.measure(a), own, data['light']['global'], data['thresholds'])
    return bad, warn, own.shape[0]


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def build(srcs):
    """srcs: {key: path}. (atlas RGBA or None, things text, sums text, {key: (errors, style bad, warnings, colours)})"""
    cells, reports = [], {}
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(HEADER)
    sums = ''
    for i, look in enumerate(LOOKS):
        key, kind, name, sid = look[0], look[2], look[4], look[6]
        a = read_rgba(srcs[key])
        errs = problems_of(a)
        bad, warn, ncol = style_report(a) if not errs else ([], [], 0)
        waived = WAIVED.get(key, {})
        warn = warn + ['waived (owner approved): ' + b for b in bad if b.split(':')[0] in waived]
        bad = [b for b in bad if b.split(':')[0] not in waived]
        reports[key] = (errs, bad, warn, ncol)
        cells.append(a)
        w.writerow([key, 'item', kind, name, NAME, i * CELL, 0, 1, 1, 1, 1, 'copy:%d' % COPY[kind], 'new', sid, extra_of(look)])
        sums += '%s  %s/%s.png\n' % (digest(a), NAME, key)
    ok = not any(r[0] for r in reports.values())
    atlas = np.concatenate(cells, axis=1) if ok else None
    if ok:
        sums += '%s  %s.png\n' % (digest(atlas), NAME)
    return atlas, out.getvalue(), sums, reports


def png_bytes(a):
    buf = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(buf, format='PNG', optimize=False)
    return buf.getvalue()


def preview(outdir, dat, spr, name='relic_sets_looks.png'):
    """the items as the client draws them from the pair, 4x and 1x, on a dark and a light ground (rows of 13: one set a row)"""
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    pad, z, per = 8, 4, 13
    nrow = (len(LOOKS) + per - 1) // per
    cw = CELL * z + pad
    ch = CELL * z + CELL + 3 * pad
    W, H = per * cw + pad, nrow * ch + pad
    im = Image.new('RGBA', (W, 2 * H))
    for side, bg in enumerate(((40, 36, 34, 255), (214, 200, 170, 255))):
        im.paste(Image.new('RGBA', (W, H), bg), (0, side * H))
        for i, look in enumerate(LOOKS):
            f = render_item(d, s, look[5]).convert('RGBA')
            assert f.size == (CELL, CELL), (look[5], f.size)
            x = pad + (i % per) * cw
            y = side * H + (i // per) * ch + pad
            im.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (x, y))
            im.alpha_composite(f, (x + (CELL * z - CELL) // 2, y + CELL * z + 2 * pad))
    p = os.path.join(outdir, name)
    im.convert('RGB').save(p)
    print('preview', p)


def sources_text():
    """art_import/relic_sets_sources.csv: the credit rows of the importer's sources file"""
    jobs = {f: v.split() for f, v in JOBS.items()}
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(['name', 'kind', 'pack', 'source', 'licence'])
    for look in LOOKS:
        key, name, folder, num, word = look[0], look[4], look[9], look[10], look[11]
        if folder in jobs and key not in REPLACED:
            job = 'PixelLab job %s' % jobs[folder][num - 1]
        elif folder in jobs:
            job = 'a re-roll or fix of PixelLab job %s, the job id of the final picture was not kept' % jobs[folder][num - 1]
        else:
            job = 'PixelLab job id not kept'
        w.writerow([key, 'item', 'PixelLab',
                    'create image pro 32x32, our own prompt (relic sets, %s %s, review folder %s/%02d_%s), %s, owner approved 2026-10-30; '
                    'art_import/%s/%s.png' % (look[1], word, folder, num, word, job, NAME, key),
                    'made with our PixelLab subscription; docs/CREDITS.md'])
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--from-dir', default=None, metavar='DIR',
                    help='the review pictures: DIR/<ember|gilded|rime|abyssal|venom>/NN_<slot>.png, copied to art_import/%s/' % NAME)
    ap.add_argument('--src', action='append', default=[], metavar='KEY=FILE',
                    help='a PixelLab picture for one look; copied to art_import/%s/KEY.png' % NAME)
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for relic_sets_looks.png (needs --dat and --spr of the new pair)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    a = ap.parse_args()
    if (a.src or a.from_dir) and a.check:
        sys.exit('--check reads the committed sources only; leave --src and --from-dir out')
    given = {}
    if a.from_dir:
        for look in LOOKS:
            given[look[0]] = os.path.join(a.from_dir, look[9], '%02d_%s.png' % (look[10], look[11]))
    for s_ in a.src:
        k, _, f = s_.partition('=')
        if k not in KEYS or not f:
            sys.exit('--src KEY=FILE with KEY one of the %d looks of LOOKS' % len(KEYS))
        given[k] = f
    srcs = {k: src_path(k) for k in KEYS}
    tmp = None
    if given:
        import tempfile
        tmp = tempfile.mkdtemp()
        for k, f in given.items():
            srcs[k] = os.path.join(tmp, k + '.png')
            Image.fromarray(read_rgba(f), 'RGBA').save(srcs[k], format='PNG', optimize=False)
    try:
        missing = [k for k in KEYS if not os.path.exists(srcs[k])]
        if missing:
            print('missing:', ', '.join(os.path.relpath(src_path(k), HERE) for k in missing))
            return 1
        atlas, things, sums, reports = build(srcs)
        failed = False
        for key in KEYS:
            errs, bad, warn, ncol = reports[key]
            reasons = errs + bad
            print('%s: %s (%d colours)' % (key, 'style PASS (own palette)' if not reasons else 'FAIL', ncol))
            for r in reasons:
                print('  ' + r)
            for w_ in warn:
                print('  warn ' + w_)
            failed = failed or bool(reasons)
        if failed:
            return 1
        if a.check:
            ok = True
            if not os.path.exists(ATLAS) or not np.array_equal(read_rgba(ATLAS), atlas):
                print('stale:', os.path.relpath(ATLAS, HERE)); ok = False
            for path, want in ((THINGS, things), (SUMS, sums), (SOURCES_CSV, sources_text())):
                if not os.path.exists(path) or open(path, encoding='utf-8').read() != want:
                    print('stale:', os.path.relpath(path, HERE)); ok = False
            print('relic set art up to date' if ok else 'run: python3 -I gen_relic_sets_art.py build')
            return 0 if ok else 1
        os.makedirs(SRC_DIR, exist_ok=True)
        for k in given:
            shutil.copyfile(srcs[k], src_path(k))
        with open(ATLAS, 'wb') as f:
            f.write(png_bytes(atlas))
        for path, text in ((THINGS, things), (SUMS, sums), (SOURCES_CSV, sources_text())):
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(text)
        print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client ids %d-%d' % (LOOKS[0][5], LOOKS[-1][5]))
        if a.preview:
            if not (a.dat and a.spr):
                sys.exit('--preview needs --dat and --spr (the new pair)')
            preview(a.preview, a.dat, a.spr)
        return 0
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
