#!/usr/bin/env python3
"""Ten hunt monster outfits 3734-3743 of pair 84 (O763; client/MANIFEST.md "Hunt monsters above level 2000 (O763)"): the monsters of
levels 2100-2500 for the six O759 hall hunts, our own PixelLab drawings from words (owner 2026-11-24: PixelLab allowed for this).

    python3 -I gen_apex_monsters.py check                       # the table, the sums keys, the words, the pictures and the monsters (no pair)
    python3 -I gen_apex_monsters.py looks [--check]             # server/data/monster/monster_apex_looks.csv from the files and the table
    python3 -I gen_apex_monsters.py drop-import DIR [KEY...]    # PixelLab oblique downloads DIR/<key>/ -> art_import/apex_monsters/<key>/
    python3 -I gen_apex_monsters.py table [--write]             # measure the rows from the committed pictures, print (or write) table and sums
    python3 -I gen_apex_monsters.py build DAT SPR OUT_DIR       # pair 83 in (3,733 outfits, its dat md5), 10 outfits more out (OUT_DIR new)
    python3 -I gen_apex_monsters.py live DAT SPR                # the pair holds every outfit at its id, as the sums say
    python3 -I gen_apex_monsters.py quality DAT SPR             # sprite_quality.py check --kind creature of every outfit
    python3 -I gen_apex_monsters.py preview OUT.mp4 --dat D --spr S   # the looks in game at true size (never committed)

Art. Words only: each monster is drawn by PixelLab from a description of ours (its name, element, hunt and the ember dark fantasy theme),
never from a picture. art_import/apex_monsters_words.csv holds key, monster, PixelLab character id and the description, so a look can be
drawn again (`words_problems`). Recipe (O618 / O728 / O729): create_character mode standard, view oblique (the game's angle, O728: never
sheared, lean 0.00), 4 directions, size 56 (80 px canvas), high detail, detailed shading; animate_character v3 "walking forward at a
calm steady pace", 8 frames, the four directions in one group (`walkv3`); the idle is the script breath of 4 (oblique_lean.read_drop).
art_import/apex_monsters/<key>/ holds the four standing pictures and the idle / walk frames, committed (our art), the layout of
art_import/drive_redraw.

Everything else is gen_drive_monsters.py's (the redraw rows of O726 / O729): the 3x3 canvas, the O585 / O640 standing point, hard alpha,
idle 4 phases of 300 ms, walk 8 of 100 ms, the lean rule of O728 (9-26 px in south or east), the append of gen_wst_outfits.build (old
things byte identical, every slot read back). The outfits go after the 3,733 outfits of pair 83 (O747 heads and capes end at 3733): the row
at line n (0-based) is outfit 3734 + n. `build` takes pair 83 only (its outfit count and the dat md5 of client_pair.PAIR_ASSETS_DAT_MD5 at 83).

Monsters. MONSTERS gives each key its monster; its file of ours (server/data/monster/monsters/chaos/) keeps a stand-in look of pair 83
(the look of a monster it replaces in its hunt), as the files of O726 keep their old looks: the monster spawns nowhere before pair 84,
and the install step `apexhunts` (server/tools/install_apex_hunts.py) moves the file and the pool row to the new look and gives it the
packs of server/data/monster/apex_hunt_swaps.csv. `looks [--check]` writes server/data/monster/monster_apex_looks.csv (monster, stand-in
look, new look) from the files and the table. Needs numpy and Pillow (the fx venv) for
everything but `check` without pictures; `preview` needs ffmpeg.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_drive_monsters as D  # noqa: E402
import gen_wst_outfits as W  # noqa: E402

ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'apex_monsters.csv')
SUMS = os.path.join(ART, 'apex_monsters.sums')
ROOT = os.path.join(ART, 'apex_monsters')
WORDS = os.path.join(ART, 'apex_monsters_words.csv')
REPO = W.REPO
MONSTER_DIR = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
SWAPS = os.path.join(REPO, 'server', 'data', 'monster', 'apex_hunt_swaps.csv')
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_apex_looks.csv')
MAP_HEADER = ['monster', 'look', 'new_look']
PAIR = 84
OUTFITS_BEFORE = 3733               # pair 83: 3,588 of pair 82, Plasma Fly Wings 3589, the O747 heads 3590-3655 and capes 3656-3733
FIRST_NEW = OUTFITS_BEFORE + 1
PAIR83_DAT_MD5 = '4169e2cf9b30499b79d3a3f8566f28a2'   # client_pair.PAIR_ASSETS_DAT_MD5 at PAIR_ASSETS 83
# key -> monster, level, the file under server/data/monster/monsters/chaos; in outfit order (by level, two a band)
MONSTERS = (
    ('rimehide', 'Rimehide Mauler', 2100, 'rimehide_mauler.xml'),
    ('sorrowweeper', 'Sorrowmere Weeper', 2100, 'sorrowmere_weeper.xml'),
    ('rimelancer', 'Rimewrath Lancer', 2200, 'rimewrath_lancer.xml'),
    ('bogwake', 'Bogwake Mourner', 2200, 'bogwake_mourner.xml'),
    ('penitent', 'Ashfall Penitent', 2300, 'ashfall_penitent.xml'),
    ('hangman', 'Soot Hangman', 2300, 'soot_hangman.xml'),
    ('behemoth', 'Emberlode Behemoth', 2400, 'emberlode_behemoth.xml'),
    ('warden', 'Gravelight Warden', 2400, 'gravelight_warden.xml'),
    ('matriarch', 'Ossuary Matriarch', 2500, 'ossuary_matriarch.xml'),
    ('devourer', 'Umbral Devourer', 2500, 'umbral_devourer.xml'),
)
ROWS = tuple((None, k, 'redraw') for k, _m, _l, _f in MONSTERS)
KEYS = tuple(k for k, _m, _l, _f in MONSTERS)
HEADER = D.HEADER


def rows(path=TABLE):
    return D.rows(path)


def read_sums(path=SUMS):
    return W.read_sums(path)


def problems(table=None, sums=None, root=None):
    """the table: the rows of ROWS in order from outfit 3734, every rule of gen_drive_monsters.problems, the pictures (redraw_problems),
    the sums naming the same outfits, the words"""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out = [x.replace('gen_drive_monsters.py', 'gen_apex_monsters.py').replace('drive_monsters.sums', 'apex_monsters.sums')
           for x in D.problems(t, s, FIRST_NEW, ROWS)]
    out += [x.replace('drive_redraw', 'apex_monsters') for x in D.redraw_problems(t, ROOT if root is None else root)]
    return out


def words_problems(path=None, keys=KEYS):
    """art_import/apex_monsters_words.csv: one row per key of MONSTERS in order, its monster, a PixelLab id, a description that ends
    with "dark fantasy" (gen_drive_monsters.words_problems)"""
    path = WORDS if path is None else path
    return [x.replace('drive_redraw_words', 'apex_monsters_words').replace('O729_KEYS', 'MONSTERS')
            for x in D.words_problems(path, keys, tuple((k, m) for k, m, _l, _f in MONSTERS))]


LOOK = re.compile(r'<look\s+type="(\d+)"')
LEVEL = re.compile(r'<level\s+min="(\d+)"\s+max="(\d+)"')
NAME = re.compile(r'<monster\s+name="([^"]+)"')


def file_look(f, folder=MONSTER_DIR):
    p = os.path.join(folder, f)
    if not os.path.isfile(p):
        return None
    m = LOOK.search(open(p, encoding='utf-8').read())
    return int(m.group(1)) if m else None


def map_rows(table=None, folder=MONSTER_DIR):
    t = rows() if table is None else table
    by = {r['key']: int(r['new']) for r in t}
    return [(m, file_look(f, folder), by.get(k)) for k, m, _l, f in MONSTERS]


def map_text(rows_):
    return ','.join(MAP_HEADER) + '\n' + ''.join('%s,%s,%s\n' % r for r in rows_)


def write_map(check=False, path=MAP):
    """write monster_apex_looks.csv, or with check compare it; returns the problem lines"""
    text = map_text(map_rows())
    old = open(path, encoding='utf-8', newline='').read() if os.path.exists(path) else None
    if old == text:
        return []
    if check:
        return ['server/data/monster/monster_apex_looks.csv is not up to date (run gen_apex_monsters.py looks)']
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return []


def monster_problems(table=None, folder=MONSTER_DIR, swaps=SWAPS):
    """every key's monster file of ours: the name of MONSTERS, a stand-in look of pair 83 (not the new one: the file spawns nowhere before
    pair 84), a <level> of the level +-20 (the late set's rule), no boss; every monster spawns in apex_hunt_swaps.csv"""
    t = rows() if table is None else table
    by = {r['key']: r['new'] for r in t}
    out = []
    for k, m, lv, f in MONSTERS:
        p = os.path.join(folder, f)
        if not os.path.isfile(p):
            out.append('%s: no monster file %s' % (m, f))
            continue
        text = open(p, encoding='utf-8').read()
        n, lk, le = NAME.search(text), LOOK.search(text), LEVEL.search(text)
        if not n or n.group(1) != m:
            out.append('%s: %s names %s' % (m, f, n.group(1) if n else None))
        if not lk or int(lk.group(1)) > OUTFITS_BEFORE or lk.group(1) == by.get(k):
            out.append('%s: look %s, the file keeps a stand-in look of pair 83 (1-%d); outfit %s comes with `apexhunts`'
                       % (m, lk.group(1) if lk else None, OUTFITS_BEFORE, by.get(k)))
        if not le or (int(le.group(1)), int(le.group(2))) != (lv - 20, lv + 20):
            out.append('%s: <level> %s, the rule is %d-%d' % (m, le.groups() if le else None, lv - 20, lv + 20))
        if re.search(r'<flag\s+(?:boss|rewardboss)="1"', text):
            out.append('%s: a hunt monster, no boss' % m)
    if os.path.exists(swaps):
        with open(swaps, newline='', encoding='utf-8') as fh:
            got = {r['new'] for r in csv.DictReader(fh)}
        for _k, m, _l, _f in MONSTERS:
            if m not in got:
                out.append('%s spawns in no hunt of apex_hunt_swaps.csv' % m)
    else:
        out.append('server/data/monster/apex_hunt_swaps.csv is missing')
    return out


def built_problems(table=None, sums=None, root=None):
    """the rows built from the committed pictures: every frame rule, the row as the table has it, the outfit as the sums have it"""
    return [x.replace('drive_monsters.sums', 'apex_monsters.sums')
            for x in D.redraw_built_problems(rows() if table is None else table, read_sums() if sums is None else sums,
                                            ROOT if root is None else root)]


def measured(root=None, want=ROWS, first=FIRST_NEW):
    return D.measured([], want, first, ROOT if root is None else root)


def table_text(rs):
    return D.table_text(rs)


def sums_text(sums):
    return D.sums_text(sums).replace('gen_drive_monsters.py', 'gen_apex_monsters.py').replace('(O726)', '(O763)')


def _md5(path):
    import hashlib
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def build(dat, spr, out_dir, root=None, want=ROWS, first=FIRST_NEW, dat_md5=PAIR83_DAT_MD5, log=print):
    """pair 83 in (its outfits end at first - 1, its dat md5 `dat_md5`; None skips the md5, the test's synthetic pair) -> pair 84 in
    OUT_DIR: one outfit per row. Returns the new ids."""
    from datspr import Dat
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    n = len(Dat(dat).outfits)
    if n != first - 1:
        raise SystemExit('refused: the input pair has %d outfits, this step needs %d (pair 83)' % (n, first - 1))
    if dat_md5 is not None and _md5(dat) != dat_md5:
        raise SystemExit('refused: the input dat md5 is %s, pair 83 is %s' % (_md5(dat), dat_md5))
    return D.build(dat, spr, out_dir, [], want=want, first=first, log=log, redraw=ROOT if root is None else root)


def live(dat, spr, table=None, sums=None, first=FIRST_NEW, log=print):
    t = rows() if table is None else table
    return D.live(dat, spr, table=t, sums=read_sums() if sums is None else sums, first=first, log=log)


def drop_import(drop, keys=KEYS, root=None, log=print):
    """DROP/<key>/ (an unzipped PixelLab download) -> art_import/apex_monsters/<key>/ (gen_drive_monsters.drop_import)"""
    return D.drop_import(drop, {k: k for k in keys}, ROOT if root is None else root, log=log)


def main(argv):
    a = list(argv)
    cmd = a.pop(0) if a else ''
    if cmd == 'check':
        p = problems() + words_problems() + monster_problems() + write_map(check=True)
        if not p:
            p += built_problems()
        for line in p:
            print('PROBLEM', line)
        print('apex_monsters: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if cmd == 'looks':
        p = monster_problems() + write_map(check='--check' in a)
        for line in p:
            print('PROBLEM', line)
        print('monster_apex_looks: %d rows, %d problems' % (len(MONSTERS), len(p)))
        return 1 if p else 0
    if cmd == 'drop-import' and len(a) >= 1:
        keys = drop_import(a[0], tuple(a[1:]) or KEYS)
        print('drop-import: %d characters (%s); now `table --write`' % (len(keys), ', '.join(keys)))
        return 0
    if cmd == 'table':
        ms = measured()
        rs = [r for r, _p in ms]
        print(table_text(rs), end='')
        if '--write' in a:
            open(TABLE, 'w', encoding='utf-8', newline='').write(table_text(rs))
            open(SUMS, 'w', encoding='utf-8', newline='').write(sums_text(D.pack_sums(ms)))
            print('wrote %s and %s' % (TABLE, SUMS))
        return 0
    if cmd == 'build' and len(a) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(*a)
        p = live(os.path.join(a[2], 'Tibia.dat'), os.path.join(a[2], 'Tibia.spr'))
        for line in p:
            print('PROBLEM', line)
        print('built %d outfits %d to %d' % (len(ids), ids[0], ids[-1]))
        return 1 if p else 0
    if cmd == 'live' and len(a) == 2:
        p = live(*a)
        for line in p:
            print('PROBLEM', line)
        return 1 if p else 0
    if cmd == 'quality' and len(a) == 2:
        for key, code, text in D.quality(*a, table=rows()):
            print('==== %s (exit %d)\n%s' % (key, code, text.rstrip()))
        return 0
    if cmd == 'preview' and len(a) >= 1:
        dat, spr = W.opt(a, '--dat'), W.opt(a, '--spr')
        if not (dat and spr and len(a) == 1):
            print(__doc__)
            return 2
        D.preview(a[0], dat, spr, table=rows(), with_look=None)
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
