#!/usr/bin/env python3
"""Looks of the 34 weapons above level 800: PixelLab pictures, 32 x 32, become client items 44412-44445 (appended to pair 56, client/MANIFEST.md
"Pair 56"). Owner approved all art 2026-10-28 ("pode criar mais armas pros levels acima de 800"), the top picks of the phase 1 sheets:
44412-44420 nine bows, 44421-44424 four crossbows, 44425-44433 nine wands, 44434-44442 nine rods, 44443-44445 three two-handed melee
weapons (a greatsword, a greataxe, a maul). Server ids = client id + 4000 (48412-48445, the pair 50 rule; server/data/items/weapons800.csv,
server/tools/install_weapons800.py, server/README.md "Weapons above level 800").

    python3 -I gen_weapons800_art.py build [--src KEY=FILE ...] [--check] [--preview DIR --dat P/Tibia.dat --spr P/Tibia.spr]

PixelLab results (create_image_pro, 8 x 8 sheets of 32 px tiles, the tile is re-cut over the cell seam; 32 x 32 RGBA, alpha 0 / 255;
docs/CREDITS.md "Tools"). The pixels are PixelLab's, owner approved: nothing is repainted, snapped, mirrored or recoloured here (only the
colour under fully transparent pixels is cleared). Candidate set and tile number of each look: SOURCES below and
art_import/weapons800_sources.csv (the 8 x 8 sheets live in the phase 1 scratchpad, not in the repo). `build --src KEY=FILE`
(repeatable) takes a picture, checks it and copies it to art_import/weapons800/KEY.png (the committed source); without --src the committed
copies are used (CI).

Outputs (committed): art_import/weapons800.png (the atlas, 32 px cells side by side in LOOKS order), art_import/weapons800.csv (the things file
of import_art_things.py: 1 x 1, one phase, the dat flags copied from a stock item of the kind like gen_gear_sets_art.py, mode new; `extra`
carries what the server needs: type, level, element, loot, description) and art_import/weapons800.sums (sha256 of the decoded pixels of each
source and of the atlas). `--check` (CI) rebuilds from the committed sources and compares, writes nothing. The server manifest
server/data/items/weapons800.csv is import_art_things.py's --manifest-out of the things file (--server-offset 4000).

Style: docs/SPRITE_STYLE.md wants one theme palette. These looks use their own colours and the owner approved the pixels, so they are not
snapped. `build` runs the style check on each canvas against its own colours: every rule but the theme palette must pass or `build` refuses;
the light rule is a warning; the rules a look misses by a little (owner approved as drawn) are in WAIVED, printed, never silent.
Deterministic: numpy and Pillow only.

Orientation: the two-handed melee looks have the grip bottom-left and the head top-right (the set art of pair 28 has the head top-left); they
are kept as approved.
"""
import argparse, csv, hashlib, io, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import style_check as sc

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
NAME = 'weapons800'
# (key, type, item name, client id, server id, required level, element, loot "Monster:chance per 100000;...", description)
# type: bow, crossbow, wand, rod, sword2, axe2, club2 (the things kind is the type without the 2). Client ids follow the last item of the pair
# before (44411, the fist looks).
LOOKS = [
    ('w800_gravesong_bow', 'bow', 'gravesong bow', 44412, 48412, 820, 'death',
     'Frost Maiden:150;Dawn Strayer:150',
     'A dark yew longbow with a bone grip, a pale green soul-glow along the limb, string of black sinew.'),
    ('w800_emberthorn_longbow', 'bow', 'emberthorn longbow', 44413, 48413, 885, 'fire',
     'Dawn Strayer:150;Ice Lich:150',
     'A longbow of blackened wood with thorn-like barbs on the limbs and glowing orange ember cracks.'),
    ('w800_hollowreed_recurve', 'bow', 'hollowreed recurve', 44414, 48414, 950, 'earth',
     'Dawn Strayer:150;Ice Lich:150',
     'A short recurve bow of pale hollow reed and moss, green vine wrapped, poison-green gem in the grip.'),
    ('w800_stormlace_bow', 'bow', 'stormlace bow', 44415, 48415, 1120, 'energy',
     'Ossivane the Gravecage:1200;Celestial Wyrm:150',
     'A slender bow of dark iron with a bright blue-white lightning string, gold fittings.'),
    ('w800_veilpiercer_bow', 'bow', 'veilpiercer bow', 44416, 48416, 1235, 'holy',
     'Winterstride:150',
     'A sleek ivory and gold bow with a radiant white-gold gem and feathered ornaments.'),
    ('w800_duskpetal_longbow', 'bow', 'duskpetal longbow', 44417, 48417, 1420, 'earth',
     'Bloodantler Fiend:150;Vaelith the Fallen Seraph:1200',
     'A longbow of dark purple wood shaped like curved petals, toxic green glow, thorns.'),
    ('w800_ashen_halo_bow', 'bow', 'ashen halo bow', 44418, 48418, 1580, 'holy',
     'Bloodantler Fiend:150;Vaelith the Fallen Seraph:1200',
     'A warbow of ash-grey wood with a floating golden halo ring at the grip, pale gold light.'),
    ('w800_throneseeker_bow', 'bow', 'throneseeker bow', 44419, 48419, 1850, 'energy',
     'Mirecoil Wyrm:150;Pyrewing Tyrant:150',
     'A great black-steel recurve bow with a crown motif, violet and electric blue crackle, gold trim.'),
    ('w800_last_ember_recurve', 'bow', 'last-ember recurve', 44420, 48420, 2150, 'fire',
     'Azhkarrath the Chained Wyrm:1200',
     'A huge recurve bow of obsidian and molten gold, burning orange embers along the limbs.'),
    ('w800_bonehinge_arbalest', 'crossbow', 'bonehinge arbalest', 44421, 48421, 840, 'death',
     'Frost Maiden:150;Dawn Strayer:150',
     'A heavy crossbow built from bleached bones and dark iron, green soul-fire in the stock.'),
    ('w800_cindergut_crossbow', 'crossbow', 'cindergut crossbow', 44422, 48422, 930, 'fire',
     'Dawn Strayer:150;Ice Lich:150',
     'A squat iron crossbow with a glowing lava-filled bolt channel, red and orange.'),
    ('w800_frostlatch_arbalest', 'crossbow', 'frostlatch arbalest', 44423, 48423, 1150, 'ice',
     'Ossivane the Gravecage:1200;Winterstride:150',
     'An icy blue steel crossbow with frost crystals and silver latches.'),
    ('w800_thornwarden_crossbow', 'crossbow', 'thornwarden crossbow', 44424, 48424, 1480, 'earth',
     'Bloodantler Fiend:150;Vaelith the Fallen Seraph:1200',
     'A dark wooden crossbow wrapped in thorny vines with green gems.'),
    ('w800_cinderbloom_wand', 'wand', 'cinderbloom wand', 44425, 48425, 830, 'fire',
     'Frost Maiden:150;Dawn Strayer:150',
     'A short wand of black iron topped by an open flower of orange flame crystal.'),
    ('w800_mirewhisper_spire', 'wand', 'mirewhisper spire', 44426, 48426, 890, 'earth',
     'Dawn Strayer:150;Ice Lich:150',
     'A twisted bog-wood wand with a swirling green-brown poison orb on top.'),
    ('w800_stormglass_scepter', 'wand', 'stormglass scepter', 44427, 48427, 960, 'energy',
     'Dawn Strayer:150;Ice Lich:150',
     'A scepter with a clear glass sphere containing blue lightning, silver shaft.'),
    ('w800_hoarwick_wand', 'wand', 'hoarwick wand', 44428, 48428, 1080, 'ice',
     'Celestial Wyrm:150;Ossivane the Gravecage:1200',
     'A pale blue wand shaped like a frozen candle wick with an icicle crystal tip.'),
    ('w800_sunscar_focus', 'wand', 'sunscar focus', 44429, 48429, 1200, 'holy',
     'Winterstride:150',
     'A gold wand with a sun-disc head with a scar crack of white light.'),
    ('w800_thunderwake_scepter', 'wand', 'thunderwake scepter', 44430, 48430, 1400, 'energy',
     'Bloodantler Fiend:150;Vaelith the Fallen Seraph:1200',
     'A long dark scepter with a spiral of yellow lightning around a violet crystal.'),
    ('w800_emberveil_spire', 'wand', 'emberveil spire', 44431, 48431, 1560, 'fire',
     'Bloodantler Fiend:150;Vaelith the Fallen Seraph:1200',
     'A tall slender wand with veiled flame wrapped around a ruby.'),
    ('w800_rotcrown_wand', 'wand', 'rotcrown wand', 44432, 48432, 1780, 'death',
     'Mirecoil Wyrm:150;Pyrewing Tyrant:150',
     'A bone wand topped with a small crown of rotted thorns and a green skull gem.'),
    ('w800_wyrmtongue_focus', 'wand', 'wyrmtongue focus', 44433, 48433, 2100, 'energy',
     'Azhkarrath the Chained Wyrm:1200',
     'A wand carved like a forked wyrm tongue, gold and violet, glowing tip.'),
    ('w800_hushwood_rod', 'rod', 'hushwood rod', 44434, 48434, 825, 'death',
     'Frost Maiden:150;Dawn Strayer:150',
     'A long rod of grey silent wood wrapped in pale cloth with a dim ghostly violet orb.'),
    ('w800_mirrorbark_staff', 'rod', 'mirrorbark staff', 44435, 48435, 885, 'ice',
     'Dawn Strayer:150;Ice Lich:150',
     'A staff of silver-white bark with a polished mirror disc, frosty blue.'),
    ('w800_dreamthorn_branch', 'rod', 'dreamthorn branch', 44436, 48436, 955, 'earth',
     'Dawn Strayer:150;Ice Lich:150',
     'A gnarled branch with thorns and a glowing teal dream-blossom.'),
    ('w800_veilhollow_crook', 'rod', 'veilhollow crook', 44437, 48437, 1100, 'death',
     'Ossivane the Gravecage:1200;Celestial Wyrm:150',
     'A shepherd crook of dark wood with a hanging violet lantern, ghostly.'),
    ('w800_glimmerbough_rod', 'rod', 'glimmerbough rod', 44438, 48438, 1210, 'holy',
     'Winterstride:150',
     'A pale gold bough rod with glittering white leaves and a star gem.'),
    ('w800_gloamroot_staff', 'rod', 'gloamroot staff', 44439, 48439, 1390, 'earth',
     'Bloodantler Fiend:150',
     'A staff of twisted dark root clutching a glowing green-yellow gem.'),
    ('w800_wraithwillow_rod', 'rod', 'wraithwillow rod', 44440, 48440, 1590, 'ice',
     'Bloodantler Fiend:150;Vaelith the Fallen Seraph:1200',
     'A willow rod of ghostly blue wood with trailing frost strands and a pale gem.'),
    ('w800_nightbloom_crook', 'rod', 'nightbloom crook', 44441, 48441, 1820, 'death',
     'Mirecoil Wyrm:150;Pyrewing Tyrant:150',
     'A black crook with a night-blooming purple flower, dark glow.'),
    ('w800_eventide_branch', 'rod', 'eventide branch', 44442, 48442, 2080, 'holy',
     'Azhkarrath the Chained Wyrm:1200',
     'A long branch of dusk-gold wood with a setting-sun orange-pink crystal.'),
    ('w800_gravewrought_greatsword', 'sword2', 'gravewrought greatsword', 44443, 48443, 850, 'death',
     'Frost Maiden:150;Dawn Strayer:150',
     'A huge two-handed black steel greatsword with a grave-green etched blade and bone crossguard.'),
    ('w800_ashmaw_greataxe', 'axe2', 'ashmaw greataxe', 44444, 48444, 910, 'fire',
     'Dawn Strayer:150;Ice Lich:150',
     'A two-handed double-bit axe of dark iron with a jaw-shaped blade and glowing ember edge.'),
    ('w800_dirgebell_maul', 'club2', 'dirgebell maul', 44445, 48445, 975, 'holy',
     'Dawn Strayer:150;Ice Lich:150',
     'A two-handed warhammer shaped like a tolling bell, dull bronze with pale gold runes.'),
]
KEYS = [l[0] for l in LOOKS]
FIRST_ID = LOOKS[0][3]
KIND = {'bow': 'bow', 'crossbow': 'crossbow', 'wand': 'wand', 'rod': 'rod', 'sword2': 'sword', 'axe2': 'axe', 'club2': 'club'}
COPY = {   # dat flags of a stock item per kind (client ids of the 10.98 pair; the same as gen_gear_sets_art.py)
    'sword': 3264, 'axe': 3274, 'club': 3270, 'bow': 3350, 'crossbow': 3349, 'wand': 3066, 'rod': 3066,
}
# candidate set and tile of each look in the phase 1 sheets (PixelLab create_image_pro jobs of 2026-10-28; the candidate sets W01b and
# W17b are the re-rolls of W01 and W17)
SOURCES = {
    'w800_gravesong_bow': ('W01b', 1),
    'w800_emberthorn_longbow': ('W02', 11),
    'w800_hollowreed_recurve': ('W03', 2),
    'w800_stormlace_bow': ('W04', 2),
    'w800_veilpiercer_bow': ('W05', 17),
    'w800_duskpetal_longbow': ('W06', 37),
    'w800_ashen_halo_bow': ('W07', 3),
    'w800_throneseeker_bow': ('W08', 13),
    'w800_last_ember_recurve': ('W09', 8),
    'w800_bonehinge_arbalest': ('W10', 15),
    'w800_cindergut_crossbow': ('W11', 0),
    'w800_frostlatch_arbalest': ('W12', 18),
    'w800_thornwarden_crossbow': ('W13', 28),
    'w800_cinderbloom_wand': ('W14', 0),
    'w800_mirewhisper_spire': ('W15', 0),
    'w800_stormglass_scepter': ('W16', 28),
    'w800_hoarwick_wand': ('W17b', 7),
    'w800_sunscar_focus': ('W18', 22),
    'w800_thunderwake_scepter': ('W19', 1),
    'w800_emberveil_spire': ('W20', 5),
    'w800_rotcrown_wand': ('W21', 0),
    'w800_wyrmtongue_focus': ('W22', 14),
    'w800_hushwood_rod': ('W23', 2),
    'w800_mirrorbark_staff': ('W24', 25),
    'w800_dreamthorn_branch': ('W25', 24),
    'w800_veilhollow_crook': ('W26', 1),
    'w800_glimmerbough_rod': ('W27', 2),
    'w800_gloamroot_staff': ('W28', 0),
    'w800_wraithwillow_rod': ('W29', 24),
    'w800_nightbloom_crook': ('W30', 10),
    'w800_eventide_branch': ('W31', 8),
    'w800_gravewrought_greatsword': ('W32', 12),
    'w800_ashmaw_greataxe': ('W33', 3),
    'w800_dirgebell_maul': ('W34', 5),
}
# style rules a look misses by a little but the owner approved as drawn (key -> {rule word: why}); printed, never silent
WAIVED = {'w800_mirrorbark_staff': {'outline': '28% near-black rim (min 30%): the frosted mirror disc has a pale blue edge'}}
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
    key, typ, _name, _cid, _sid, level, element, loot, desc = look
    return 'type=%s|level=%d|element=%s|loot=%s|description=%s' % (typ, level, element, loot, desc)


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
        if ys.max() - ys.min() < 12 or xs.max() - xs.min() < 12:
            out.append('the art does not fill the canvas (a weapon is at least 13 px wide and high)')
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
        key, typ, name, _cid, sid = look[:5]
        a = read_rgba(srcs[key])
        errs = problems_of(a)
        bad, warn, ncol = style_report(a) if not errs else ([], [], 0)
        waived = WAIVED.get(key, {})
        warn = warn + ['waived (owner approved): ' + b for b in bad if b.split(':')[0] in waived]
        bad = [b for b in bad if b.split(':')[0] not in waived]
        reports[key] = (errs, bad, warn, ncol)
        cells.append(a)
        kind = KIND[typ]
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


def preview(outdir, dat, spr):
    """weapons800_looks.png: the items as the client draws them from the pair, 4x and 1x, on a dark and a light ground (rows of 12)"""
    from datspr import Dat, Spr
    from fxlib import render_item
    d, s = Dat(dat), Spr(spr)
    os.makedirs(outdir, exist_ok=True)
    pad, z, per = 8, 4, 12
    nrow = (len(LOOKS) + per - 1) // per
    cw = CELL * z + pad
    ch = CELL * z + CELL + 3 * pad
    W, H = per * cw + pad, nrow * ch + pad
    im = Image.new('RGBA', (W, 2 * H))
    for side, bg in enumerate(((40, 36, 34, 255), (214, 200, 170, 255))):
        im.paste(Image.new('RGBA', (W, H), bg), (0, side * H))
        for i, look in enumerate(LOOKS):
            f = render_item(d, s, look[3]).convert('RGBA')
            assert f.size == (CELL, CELL), (look[3], f.size)
            x = pad + (i % per) * cw
            y = side * H + (i // per) * ch + pad
            im.alpha_composite(f.resize((CELL * z, CELL * z), Image.NEAREST), (x, y))
            im.alpha_composite(f, (x + (CELL * z - CELL) // 2, y + CELL * z + 2 * pad))
    p = os.path.join(outdir, 'weapons800_looks.png')
    im.convert('RGB').save(p)
    print('preview', p)


def sources_text():
    """art_import/weapons800_sources.csv: the credit rows of the importer's sources file"""
    out = io.StringIO()
    w = csv.writer(out, lineterminator='\n')
    w.writerow(['name', 'kind', 'pack', 'source', 'licence'])
    for look in LOOKS:
        key = look[0]
        cand, tile = SOURCES[key]
        w.writerow([key, 'item', 'PixelLab',
                    'create image pro 32x32 8x8 sheet, our own prompt (weapons above level 800 phase 1, candidate set %s, tile %d, '
                    're-cut over the cell seam), %s, owner approved 2026-10-28; art_import/%s/%s.png' % (cand, tile, look[2], NAME, key),
                    'made with our PixelLab subscription; docs/CREDITS.md'])
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build'])
    ap.add_argument('--src', action='append', default=[], metavar='KEY=FILE',
                    help='a PixelLab picture for one look; copied to art_import/%s/KEY.png' % NAME)
    ap.add_argument('--check', action='store_true', help='compare with the committed files, write nothing')
    ap.add_argument('--preview', default=None, help='a folder for weapons800_looks.png (needs --dat and --spr of the new pair)')
    ap.add_argument('--dat')
    ap.add_argument('--spr')
    a = ap.parse_args()
    if a.src and a.check:
        sys.exit('--check reads the committed sources only; leave --src out')
    given = {}
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
            print('weapon look art up to date' if ok else 'run: python3 -I gen_weapons800_art.py build')
            return 0 if ok else 1
        os.makedirs(SRC_DIR, exist_ok=True)
        for k in given:
            shutil.copyfile(srcs[k], src_path(k))
        with open(ATLAS, 'wb') as f:
            f.write(png_bytes(atlas))
        for path, text in ((THINGS, things), (SUMS, sums), (SOURCES_CSV, sources_text())):
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(text)
        print('atlas', ATLAS, atlas.shape[1], 'x', atlas.shape[0], '; client ids %d-%d' % (LOOKS[0][3], LOOKS[-1][3]))
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
