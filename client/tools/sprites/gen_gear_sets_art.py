#!/usr/bin/env python3
"""Pair 28: seven equipment sets from the owner's item sheets, ready for import_art_things.py.

    python3 -I gen_gear_sets_art.py build --src DIR         # DIR holds sheet1.png .. sheet7.png (SOURCES, md5 checked)
                                                           #   -> art_import/gear_sets/<set>.png, gear_sets.csv, .sums
    python3 -I gen_gear_sets_art.py build --check           # CI: atlases match the sums, the things file the layout
    python3 -I gen_gear_sets_art.py build --src DIR --check # rebuild from the sources, compare pixel for pixel
    python3 -I gen_gear_sets_art.py preview --out DIR --dat P/Tibia.dat --spr P/Tibia.spr

Source and licence: seven 256 x 256 RGBA sheets the owner sent on 2026-10-15, "made for us": the owner's own art, free to
use without restriction (docs/CREDITS.md "Owner art"). Each sheet is an 8 x 8 grid of 32 px item icons of one theme. The
committed atlases art_import/gear_sets/<set>.png hold the very same pixels (an exact palette PNG, about a third of the
size); art_import/gear_sets.sums keeps the sha256 of each one's RGBA pixels.

The rows are roughly helmets, armours, legs and boots, shields and spellbooks, swords and axes, clubs and launchers,
amulets and rings, wands and rods; the order differs a little per sheet, so LAYOUT names every cell, read off the sheets
(two sheets draw eight leg pieces and no boots, one two legs and six boots). Armour pieces carry a fit: H heavy (Warrior
and Templar lines), M medium (Ranger, Thief and Monk lines), C cloth (Mystic and Necromancer lines), A anyone (a slot
with too few pieces for three fits). Melee weapons are one- or two-handed by size: within a sheet's kind, the larger half
by art pixels (ties: the later cell) is two-handed. Levels and stats are not decided here: server/tools/
install_gear_sets.py gives them from each set's level band (server/README.md "Equipment sets (pair 28)").

Outputs: gear_sets.csv, items from 33995 (after pair 27's 33994), 64 per set in sheet order (row by row), server id =
client id + 3000. Dat flags copied from a stock item of each kind (gen_theme_art.COPY).
Append to pair 27 (the output is pair 28):
    python3 -I import_art_things.py --ours-dat P27/Tibia.dat --ours-spr P27/Tibia.spr --out-dir P28 \\
        --things art_import/gear_sets.csv --first-item 33995 --expect-items 33994 \\
        --manifest-out ../../../server/data/items/gear_sets.csv
Deterministic: numpy and Pillow only.
"""
import argparse
import csv
import hashlib
import io
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
OUT_DIR = os.path.join(ART, 'gear_sets')
THINGS = os.path.join(ART, 'gear_sets.csv')
SUMS = os.path.join(ART, 'gear_sets.sums')

FIRST_ITEM = 33995          # after pair 27's 33994 items
SERVER_OFFSET = 3000
FIELDS = ['key', 'cat', 'kind', 'name', 'atlas', 'x', 'y', 'w', 'h', 'patterns', 'phases', 'flags', 'mode', 'server_id',
          'extra']
COPY = {   # dat flags of a stock item per kind (client ids of the 10.98 pair; gen_theme_art.py COPY)
    'sword': 3264, 'axe': 3274, 'club': 3270, 'bow': 3350, 'crossbow': 3349, 'wand': 3066, 'rod': 3066,
    'shield': 3409, 'spellbook': 3059, 'helmet': 3351, 'armor': 3357, 'legs': 3557, 'boots': 3552, 'amulet': 3572,
    'ring': 3063,
}
CODE = {'he': 'helmet', 'ar': 'armor', 'le': 'legs', 'bo': 'boots', 'sh': 'shield', 'sb': 'spellbook', 'sw': 'sword',
        'ax': 'axe', 'cl': 'club', 'bw': 'bow', 'xb': 'crossbow', 'am': 'amulet', 'ri': 'ring', 'wa': 'wand', 'ro': 'rod'}
MELEE = ('sword', 'axe', 'club')

# neutral source name -> md5 of the file as the owner sent it
SOURCES = {
    'sheet1.png': 'edbd9595a8fa12764e3eec7cb42b7b66',
    'sheet2.png': 'f456926fb643fa5dbc6686957ee0b797',
    'sheet3.png': '1d6ed863baef00925737b8eb93a9856d',
    'sheet4.png': 'c94f224456cede40bb15b1d49cff7655',
    'sheet5.png': '13e73220bb17e775902f5b1786806372',
    'sheet6.png': 'b3c49c3c03db0b33ca54cca018f459fb',
    'sheet7.png': 'ba918f1a47c41b46ad4064caabd388e2',
}
# the sets in id order: key, source, item name prefix, theme (the owner's words)
SETS = [
    ('cinderwrought', 'sheet1.png', 'cinderwrought', 'fire and ember'),
    ('wyrmscale', 'sheet2.png', 'wyrmscale', 'green dragon'),
    ('rimewraith', 'sheet3.png', 'rimewraith', 'teal frost, spectral'),
    ('azurevigil', 'sheet4.png', 'azure vigil', 'blue and gold paladin'),
    ('bloodmoon', 'sheet5.png', 'bloodmoon', 'crimson, blood'),
    ('gildcrown', 'sheet6.png', 'gildcrown', 'gold'),
    ('blightfang', 'sheet7.png', 'blightfang', 'dark green, venom'),
]
# every cell of every sheet, row by row (read off the sheets): kind code + the fit of armour pieces (H, M, C, A)
LAYOUT = {
    'cinderwrought': ['heH heH heM heH heC heC heM heM', 'arH arC arC arM arH arH arM arM',
                      'leH leC bo bo leH leM bo bo', 'sh sh sh sh sb sb sb sb', 'sw sw sw sw ax ax ax ax',
                      'cl cl bw bw bw bw xb xb', 'am am am ri ri ri ri ri', 'wa wa wa wa ro ro ro ro'],
    'wyrmscale': ['heH heM heM heH heC heH heM heC', 'arH arM arC arH arM arH arM arC',
                  'leH leM leC leH leM leH leM leC', 'sh sh sh sh sb sb sb sb', 'sw sw sw sw ax ax ax ax',
                  'cl cl cl bw bw bw xb xb', 'am am am am ri ri ri ri', 'wa wa wa wa ro ro ro ro'],
    'rimewraith': ['heH heM heH heM heM heH heC heC', 'arH arC arM arM arH arC arH arM',
                   'leH leM bo bo leC leH bo bo', 'sh sh sh sh sb sb sb sb', 'sw sw sw sw sw ax sw ax',
                   'cl cl bw bw ax bw xb xb', 'am am am ri ri ri ri ri', 'wa wa wa wa ro ro ro ro'],
    'azurevigil': ['heC heH heM heC heH heH heM heM', 'arM arC arH arC arH arM arH arM',
                   'leH leM leC bo leH leM bo bo', 'sh sh sh sh sb sb sb sb', 'sw sw sw sw ax ax ax ax',
                   'cl cl cl bw bw bw xb xb', 'am am am am ri ri ri ri', 'wa wa wa wa ro ro ro ro'],
    'bloodmoon': ['heH heM heC heM heH heH heM heC', 'arH arC arC arM arH arH arM arM',
                  'leH leM leC bo bo leH bo bo', 'sh sh sh sh sb sb sb sb', 'sw sw sw sw ax ax ax ax',
                  'cl cl cl bw bw bw xb xb', 'am am am ri am ri ri ri', 'wa wa wa wa ro ro ro ro'],
    'gildcrown': ['heH heM heM heC heH heH heM heC', 'arH arH arC arM arH arM arM arC',
                  'leA leA bo bo bo bo bo bo', 'sh sh sh sh sh sb sb sb', 'sw sw sw ax ax ax ax ax',
                  'cl cl cl bw bw bw xb xb', 'am am am ri am ri ri ri', 'wa wa wa wa ro ro ro ro'],
    'blightfang': ['heH heM heH heM heC heH heM heC', 'arH arM arC arH arM arC arM arH',
                   'leH leM leC leH leM leC leH leM', 'sh sh sh sh sb sb sb sb', 'sw sw sw sw ax ax ax ax',
                   'cl cl cl cl bw bw xb xb', 'am am am am ri ri ri ri', 'wa wa wa wa ro ro ro ro'],
}
# item nouns per kind (and fit or hands), used in order within a set
NOUNS = {
    ('helmet', 'H'): ['greathelm', 'warhelm', 'horned helm', 'visored helm', 'crested helm'],
    ('helmet', 'M'): ['helm', 'coif', 'casque', 'sallet', 'crest'],
    ('helmet', 'C'): ['hood', 'cowl', 'circlet', 'crown', 'mitre'],
    ('armor', 'H'): ['plate', 'cuirass', 'warplate', 'breastplate', 'battleplate'],
    ('armor', 'M'): ['mail', 'hauberk', 'brigandine', 'scale mail', 'jerkin'],
    ('armor', 'C'): ['robe', 'vestment', 'mantle', 'raiment', 'cassock'],
    ('legs', 'H'): ['legplates', 'tassets', 'cuisses', 'greaves'],
    ('legs', 'M'): ['leggings', 'chausses', 'breeches', 'legguards'],
    ('legs', 'C'): ['kilt', 'trousers', 'legwraps', 'skirt'],
    ('legs', 'A'): ['legplates', 'leggings', 'greaves', 'chausses'],
    ('boots', ''): ['boots', 'sabatons', 'treads', 'striders', 'sollerets', 'walkers', 'steps'],
    ('shield', ''): ['shield', 'aegis', 'bulwark', 'kite shield', 'buckler', 'tower shield'],
    ('spellbook', ''): ['grimoire', 'tome', 'codex', 'folio', 'libram'],
    ('sword', '1'): ['blade', 'sabre', 'longsword', 'edge'],
    ('sword', '2'): ['greatsword', 'claymore', 'great blade'],
    ('axe', '1'): ['axe', 'hatchet', 'cleaver', 'war axe'],
    ('axe', '2'): ['greataxe', 'battle axe', 'headsman axe', 'great cleaver'],
    ('club', '1'): ['mace', 'hammer', 'morning star', 'flail'],
    ('club', '2'): ['maul', 'warhammer', 'great hammer'],
    ('bow', ''): ['bow', 'longbow', 'recurve bow', 'warbow', 'shortbow'],
    ('crossbow', ''): ['crossbow', 'arbalest', 'repeater', 'heavy crossbow'],
    ('wand', ''): ['wand', 'scepter', 'spire', 'focus', 'baton'],
    ('rod', ''): ['rod', 'staff', 'branch', 'crook', 'stave'],
    ('amulet', ''): ['amulet', 'pendant', 'talisman', 'necklace', 'locket'],
    ('ring', ''): ['ring', 'band', 'signet', 'seal', 'loop'],
}


# ------------------------------------------------------------------------------------------------ the layout
def cells_of(key):
    """[(row, col, kind, fit)] of a set's sheet, row by row"""
    out = []
    for r, line in enumerate(LAYOUT[key]):
        toks = line.split()
        assert len(toks) == 8, (key, r, line)
        for c, t in enumerate(toks):
            out.append((r, c, CODE[t[:2]], t[2:]))
    assert len(out) == 64
    return out


def art_pixels(sheet, r, c):
    return int((sheet[r * 32:(r + 1) * 32, c * 32:(c + 1) * 32, 3] > 0).sum())


def hands_of(key, sheet):
    """(row, col) -> 1 or 2 for the melee weapons: the larger half of a kind by art pixels is two-handed"""
    out = {}
    cells = cells_of(key)
    for kind in MELEE:
        own = [(art_pixels(sheet, r, c), r * 8 + c, (r, c)) for r, c, k, _f in cells if k == kind]
        own.sort()
        two = len(own) // 2
        for i, (_n, _o, rc) in enumerate(own):
            out[rc] = 2 if i >= len(own) - two else 1
    return out


def piece_rows(key, sheet):
    """the 64 pieces of a set: dicts with key, kind, fit (H/M/C/A, '1'/'2' for melee, '' else), n, name, x, y"""
    _k, _src, prefix, _theme = SETS[[s[0] for s in SETS].index(key)]
    hands = hands_of(key, sheet)
    used = {}
    out = []
    for r, c, kind, fit in cells_of(key):
        if kind in MELEE:
            fit = str(hands[(r, c)])
        nouns = NOUNS[(kind, fit)]
        i = used.get((kind, fit), 0)
        used[(kind, fit)] = i + 1
        noun = nouns[i] if i < len(nouns) else '%s %d' % (nouns[-1], i - len(nouns) + 2)
        n = sum(1 for p in out if p['kind'] == kind) + 1
        out.append({'key': '%s_%s_%d' % (key, kind, n), 'kind': kind, 'fit': fit, 'n': n,
                    'name': '%s %s' % (prefix, noun), 'x': c * 32, 'y': r * 32, 'cell': r * 8 + c})
    names = [p['name'] for p in out]
    assert len(set(names)) == len(names), (key, 'duplicate names')
    return out


# ------------------------------------------------------------------------------------------------ sources and atlases
def load_source(src, name):
    path = os.path.join(src, name)
    data = open(path, 'rb').read()
    if hashlib.md5(data).hexdigest() != SOURCES[name]:
        sys.exit('%s: md5 %s, the spec has %s (another file?)' % (path, hashlib.md5(data).hexdigest(), SOURCES[name]))
    a = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))
    assert a.shape == (256, 256, 4), (name, a.shape)
    return a


def png_bytes(a):
    """an exact palette PNG of an RGBA array (every colour and alpha kept; at most 256 colours)"""
    flat = a.reshape(-1, 4)
    cols, inv = np.unique(flat, axis=0, return_inverse=True)
    assert len(cols) <= 256, 'more than 256 colours'
    p = Image.fromarray(inv.reshape(a.shape[:2]).astype(np.uint8), 'P')
    p.putpalette(cols[:, :3].astype(np.uint8).tobytes())
    b = io.BytesIO()
    p.save(b, 'PNG', optimize=True, transparency=cols[:, 3].astype(np.uint8).tobytes())
    return b.getvalue()


def decode(data_or_path):
    src = io.BytesIO(data_or_path) if isinstance(data_or_path, bytes) else data_or_path
    return np.asarray(Image.open(src).convert('RGBA'))


def digest(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes() + repr(a.shape).encode()).hexdigest()


def check_rules(key, a):
    bad = []
    if a.shape != (256, 256, 4):
        return ['%s: shape %s' % (key, a.shape)]
    al = a[..., 3]
    if (a[al == 0][:, :3] != 0).any():
        bad.append(key + ': colour under alpha 0')
    for r in range(8):
        for c in range(8):
            if not al[r * 32:(r + 1) * 32, c * 32:(c + 1) * 32].any():
                bad.append('%s: empty cell (%d, %d)' % (key, r, c))
    return bad


# ------------------------------------------------------------------------------------------------ tables
def things_rows(atlases):
    rows = []
    for key, *_r in SETS:
        for p in piece_rows(key, atlases[key]):
            extra = 'set=%s|kind=%s|fit=%s|n=%d|cell=%d' % (key, p['kind'], p['fit'], p['n'], p['cell'])
            rows.append([p['key'], 'item', p['kind'], p['name'], 'gear_sets/' + key, p['x'], p['y'], 1, 1, 1, 1,
                         'copy:%d' % COPY[p['kind']], 'new', '', extra])
    return rows


def csv_text(rows):
    s = io.StringIO()
    w = csv.writer(s, lineterminator='\n')
    w.writerow(FIELDS)
    w.writerows(rows)
    return s.getvalue()


def sums_text(atlases):
    return ''.join('%s  gear_sets/%s.png\n' % (digest(atlases[k]), k) for k, *_r in SETS)


def read(path):
    return open(path, newline='').read() if os.path.exists(path) else None


def read_atlases():
    out = {}
    for key, *_r in SETS:
        p = os.path.join(OUT_DIR, key + '.png')
        if os.path.exists(p):
            out[key] = decode(p)
    return out


def cmd_build(a):
    if a.src:
        atlases = {key: load_source(a.src, src) for key, src, *_r in SETS}
    elif a.check:
        atlases = read_atlases()
    else:
        sys.exit('build needs --src (the owner sheets); without it only --check runs')
    bad = []
    for key, *_r in SETS:
        if key not in atlases:
            bad.append('gear_sets/%s.png missing' % key)
        else:
            bad += check_rules(key, atlases[key])
    if bad:
        sys.exit('\n'.join(bad))
    files = {THINGS: csv_text(things_rows(atlases)), SUMS: sums_text(atlases)}
    if a.check:
        for path, text in files.items():
            if read(path) != text:
                bad.append(os.path.relpath(path, REPO) + ' differs from the spec (run build --src DIR)')
        for key, *_r in SETS:
            p = os.path.join(OUT_DIR, key + '.png')
            if a.src and (not os.path.exists(p) or not np.array_equal(decode(p), atlases[key])):
                bad.append('gear_sets/%s.png differs from its source' % key)
        if bad:
            sys.exit('\n'.join(bad))
        print('gear sets art: %d sets, %d items match the spec' % (len(SETS), 64 * len(SETS)))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    for key, *_r in SETS:
        p = os.path.join(OUT_DIR, key + '.png')
        data = png_bytes(atlases[key])
        assert np.array_equal(decode(data), atlases[key])
        if not os.path.exists(p) or open(p, 'rb').read() != data:
            open(p, 'wb').write(data)
            print('wrote', os.path.relpath(p, REPO))
    for path, text in files.items():
        open(path, 'w', newline='').write(text)
        print('wrote', os.path.relpath(path, REPO))


# ------------------------------------------------------------------------------------------------ previews
SLOT_BG, SLOT_EDGE, PANEL = (38, 34, 30, 255), (70, 62, 52, 255), (22, 20, 18, 255)
KITS = [('heavy', 'H', ('sword', '1'), 'shield'), ('medium', 'M', ('bow', ''), None),
        ('cloth', 'C', ('wand', ''), 'spellbook')]


def first_piece(pieces, kind, fit=None):
    for p in pieces:
        if p['kind'] == kind and (fit is None or p['fit'] == fit):
            return p
    return None


def kit_of(pieces, fit, weapon, offhand):
    """slot -> piece of one class kit: the first piece of each slot in the fit (else A, else any)"""
    out = {}
    for slot in ('helmet', 'armor', 'legs'):
        out[slot] = first_piece(pieces, slot, fit) or first_piece(pieces, slot, 'A') or first_piece(pieces, slot)
    out['boots'] = first_piece(pieces, 'boots')
    out['amulet'] = first_piece(pieces, 'amulet')
    rings = [p for p in pieces if p['kind'] == 'ring']
    out['ring'], out['ring2'] = rings[0], rings[1] if len(rings) > 1 else None
    out['weapon'] = first_piece(pieces, *weapon)
    out['offhand'] = first_piece(pieces, offhand) if offhand else None
    return out


def slot_box(img, x, y, size=36):
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + size - 1, y + size - 1], fill=SLOT_BG, outline=SLOT_EDGE)


KIT_LOOK = {'heavy': 131, 'medium': 129, 'cloth': 130}   # stock looks: knight, hunter, mage
TINTS = {   # head, body, legs, feet of the preview figure per set (RGB)
    'cinderwrought': ((230, 120, 40), (170, 50, 20), (120, 40, 20), (90, 50, 30)),
    'wyrmscale': ((60, 150, 70), (170, 60, 40), (60, 130, 60), (110, 90, 60)),
    'rimewraith': ((80, 190, 190), (40, 110, 120), (60, 70, 100), (40, 60, 70)),
    'azurevigil': ((220, 180, 70), (60, 120, 200), (220, 180, 70), (50, 90, 160)),
    'bloodmoon': ((210, 170, 80), (160, 20, 40), (110, 20, 30), (90, 60, 40)),
    'gildcrown': ((240, 200, 60), (220, 170, 40), (190, 140, 30), (150, 110, 30)),
    'blightfang': ((60, 200, 90), (40, 60, 45), (35, 50, 40), (30, 40, 30)),
}


def figure(dat, spr, look, tints):
    """a stock look facing south (website/tools/gen_sprite_images.py's composer: the client's template colours, the
    outfit colour nearest each tint for head, body, legs and feet) on a 64 px floor"""
    sys.path.insert(0, os.path.join(REPO, 'website', 'tools'))
    import gen_sprite_images as W
    from gen_owner_art import checker_ground
    near = [min(range(133), key=lambda c: sum((a - b) ** 2 for a, b in zip(W.outfit_colour(c), rgb))) for rgb in tints]
    t = dat.outfit(look)
    arr = W.compose(W.outfit_meta(t), W.outfit_sheet(t, spr), tuple(near))
    out = checker_ground(64, 64)
    img = Image.fromarray(arr, 'RGBA')
    out.alpha_composite(img, (64 - img.width, 64 - img.height))
    return out


def cmd_preview(a):
    """per set: the 64 pieces in a bag (8 x 8 slots, as the client's container window) and three class kits worn on a
    character in the equipment slots (heavy, medium, cloth), the character drawn in the middle"""
    sys.path.insert(0, HERE)
    from PIL import ImageDraw
    from datspr import Dat, Spr
    from gen_owner_art import draw_thing, groups_of, checker_ground
    dat, spr = Dat(a.dat), Spr(a.spr)
    os.makedirs(a.out, exist_ok=True)
    atlases = read_atlases()
    sc = 2
    for s, (key, _src, prefix, theme) in enumerate(SETS):
        pieces = piece_rows(key, atlases[key])
        cid = {p['key']: FIRST_ITEM + s * 64 + i for i, p in enumerate(pieces)}

        def icon(img, p, x, y):
            t = dat.items[cid[p['key']] - 100]
            sub = Image.new('RGBA', (32, 32))
            draw_thing(sub, t, spr, (0, 0), 0, 0)
            img.alpha_composite(sub, (x, y))
        # the bag
        bag = Image.new('RGBA', (8 * 36 + 16, 8 * 36 + 34), PANEL)
        ImageDraw.Draw(bag).text((8, 6), '%s (%s)  client %d-%d' % (prefix, theme, FIRST_ITEM + s * 64,
                                                                       FIRST_ITEM + s * 64 + 63), fill=(230, 210, 170))
        for i, p in enumerate(pieces):
            x, y = 8 + (i % 8) * 36, 26 + (i // 8) * 36
            slot_box(bag, x, y)
            icon(bag, p, x + 2, y + 2)
        bag.resize((bag.width * sc, bag.height * sc), Image.NEAREST).save(os.path.join(a.out, '%d_%s_bag.png' % (
            s + 1, key)))
        # worn: three kits side by side, each a character (a stock look of the kit's role, tinted in the set's
        # colours) beside its equipment slots
        pw, ph = 104 + 3 * 40, 4 * 40 + 34
        worn = Image.new('RGBA', (len(KITS) * (pw + 8) + 8, ph + 16), PANEL)
        dr = ImageDraw.Draw(worn)
        for k, (label, fit, weapon, off) in enumerate(KITS):
            kit = kit_of(pieces, fit, weapon, off)
            ox, oy = 8 + k * (pw + 8), 8
            dr.text((ox + 4, oy), '%s kit' % label, fill=(230, 210, 170))
            fig = figure(dat, spr, KIT_LOOK[label], TINTS[key])
            worn.alpha_composite(fig.resize((96, 96), Image.NEAREST), (ox + 4, oy + 50))
            pos = {'amulet': (0, 0), 'helmet': (1, 0), 'ring2': (2, 0), 'weapon': (0, 1), 'armor': (1, 1),
                   'offhand': (2, 1), 'ring': (0, 2), 'legs': (1, 2), 'boots': (1, 3)}
            for slot, (cx, cy) in pos.items():
                x, y = ox + 104 + cx * 40, oy + 16 + cy * 40
                slot_box(worn, x, y)
                if kit.get(slot):
                    icon(worn, kit[slot], x + 2, y + 2)
        worn.resize((worn.width * sc, worn.height * sc), Image.NEAREST).save(os.path.join(a.out, '%d_%s_worn.png' % (
            s + 1, key)))
    print('previews in', a.out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--src')
    b.add_argument('--check', action='store_true')
    p = sub.add_parser('preview')
    p.add_argument('--out', required=True)
    p.add_argument('--dat', required=True)
    p.add_argument('--spr', required=True)
    a = ap.parse_args()
    (cmd_build if a.cmd == 'build' else cmd_preview)(a)


if __name__ == '__main__':
    main()
