#!/usr/bin/env python3
"""Three hunt monster outfits 3744-3746 of pair 86 and two stock looks (O768; client/MANIFEST.md "Monster looks that match the name
(O768)"): owner 2026-11-25 "banshee, white lion, hellhound, werelion, leaf golem ficaram ruins ou nao condizentes com o nome".

    python3 -I gen_relook_monsters.py check                       # the table, the sums, the words, the pictures, the monsters and the map
    python3 -I gen_relook_monsters.py looks [--check]             # server/data/monster/monster_relook_looks.csv from the files and the table
    python3 -I gen_relook_monsters.py drop-import DIR [NAME=KEY...]   # PixelLab v3 downloads DIR/<key>/ -> art_import/relook_monsters/<key>/
    python3 -I gen_relook_monsters.py table [--write]             # measure the rows from the committed pictures, print (or write) table and sums
    python3 -I gen_relook_monsters.py build DAT SPR OUT_DIR       # pair 85 in (3,743 outfits, its dat md5), 3 outfits more out (OUT_DIR new)
    python3 -I gen_relook_monsters.py live DAT SPR                # the pair holds every outfit at its id, as the sums say
    python3 -I gen_relook_monsters.py quality DAT SPR             # sprite_quality.py check --kind creature of every outfit
    python3 -I gen_relook_monsters.py preview OUT.mp4 --dat D --spr S   # the looks in game at true size (never committed)

The owner's picks (2026-11-25), out of the options of V5b: Banshee a PixelLab ghost, Werelion a PixelLab lion-headed beast-man, Leaf Golem a
PixelLab bark and leaf golem (the three new outfits); White Lion the stock look 1041 and Hellhound the stock look 3280 (no art, only the
map: STOCK). Talath, drawn 1.75 times in the client, is game_monsterbar's (monsterbarmath.lua LOOK_SCALE), not this tool's.

Art. Words only: each monster is drawn by PixelLab from a description of ours, never from a picture. art_import/relook_monsters_words.csv
holds key, monster, PixelLab character id and the description (`words_problems`). Recipe: create_character mode v3 (the standard
oblique mode drew people in costume for these words), view low top-down, 4 directions, size 80, high detail; animate_character template
walking-8-frames and breathing-idle, the four directions each. The v3 view is upright, so `drop-import` shears every picture to the
game's angle (O728: oblique_lean.shear, k 0.25, the feet line of the standing picture of the direction) before it writes them; the
committed pictures are at the angle and the build never shears (lean 0.00). The idle is PixelLab's breath of 4, colours pulled to the
standing pictures and moved onto them by the feet, as read_drop does for the walk.

Everything else is gen_drive_monsters.py's (the redraw rows of O726 / O729): the 3x3 canvas, the O585 / O640 standing point, hard alpha,
idle 4 phases of 300 ms, walk 8 of 100 ms, the lean rule of O728 (9-26 px in south or east), the append of gen_wst_outfits.build. The
outfits go after the 3,743 outfits of pair 85 (O763 ends at 3743): the row at line n (0-based) is outfit 3744 + n. `build` takes pair
85 only (its outfit count and the dat md5 of client_pair.PAIR_ASSETS_DAT_MD5 at 85).

Monsters. The monster files keep their committed looks; the install step `monsterrelooklooks` (server/tools/install_monster_relook_looks.py)
moves them, behind chaosClientPair >= 86 (client_pair.PAIR_RELOOK_MONSTERS). Needs numpy and Pillow (the fx venv) for everything but
`check` without pictures; `preview` needs ffmpeg.
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_drive_monsters as D  # noqa: E402
import gen_wst_outfits as W  # noqa: E402
import oblique_lean as L  # noqa: E402

ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'relook_monsters.csv')
SUMS = os.path.join(ART, 'relook_monsters.sums')
ROOT = os.path.join(ART, 'relook_monsters')
WORDS = os.path.join(ART, 'relook_monsters_words.csv')
REPO = W.REPO
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_relook_looks.csv')
MAP_HEADER = ['monster', 'look', 'new_look']
PAIR = 86
OUTFITS_BEFORE = 3743               # pair 85: pair 84's 3,743 (O763 ten hunt monsters 3734-3743), effects changed in place by O766
FIRST_NEW = OUTFITS_BEFORE + 1
PAIR85_DAT_MD5 = '83b070b2b22d57336470aa0911488fde'   # client_pair.PAIR_ASSETS_DAT_MD5 at PAIR_ASSETS 85
# key -> monster (base server monsters: their committed look is the bounty pool's); in outfit order
MONSTERS = (
    ('banshee', 'Banshee'),
    ('werelion', 'Werelion'),
    ('leafgolem', 'Leaf Golem'),
)
# the owner's stock picks: monster, the stock look it wears from pair 86 (a look of the base pair, no art here)
STOCK = (
    ('White Lion', 1041),
    ('Hellhound', 3280),
)
ROWS = tuple((None, k, 'redraw') for k, _m in MONSTERS)
KEYS = tuple(k for k, _m in MONSTERS)
HEADER = D.HEADER
SHEAR_K = L.K
# a key sheared more: the werelion stands with its legs wide apart, so k 0.25 leaves its south at 8.2 px after the fit (under the 9 of
# O728); 0.30 puts it at 12.2
SHEAR_K_OF = {'werelion': 0.30}
MARGIN = 8                          # clear px round the drop's canvas: the figures fill their 80 px canvas (oblique_lean.read_drop margin)


def rows(path=TABLE):
    return D.rows(path)


def read_sums(path=SUMS):
    return W.read_sums(path)


def _here(x):
    return (x.replace('gen_drive_monsters.py', 'gen_relook_monsters.py').replace('drive_monsters.sums', 'relook_monsters.sums')
            .replace('drive_redraw_words', 'relook_monsters_words').replace('O729_KEYS', 'MONSTERS').replace('drive_redraw', 'relook_monsters')
            .replace('O726', 'O768'))


def problems(table=None, sums=None, root=None):
    """the table: the rows of ROWS in order from outfit 3744, every rule of gen_drive_monsters.problems, the pictures (redraw_problems),
    the sums naming the same outfits"""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out = [_here(x) for x in D.problems(t, s, FIRST_NEW, ROWS)]
    out += [_here(x) for x in D.redraw_problems(t, ROOT if root is None else root)]
    return out


def words_problems(path=None, keys=KEYS):
    """art_import/relook_monsters_words.csv: one row per key of MONSTERS in order, its monster, a PixelLab id, a description that ends
    with "dark fantasy" (gen_drive_monsters.words_problems)"""
    path = WORDS if path is None else path
    return [_here(x) for x in D.words_problems(path, keys, MONSTERS)]


def map_rows(table=None, old=None):
    """[(monster, the look the repository gives it, the look of pair 86)]: the three new outfits, then the stock picks"""
    t = rows() if table is None else table
    have = D.G.old_looks() if old is None else old
    by = {r['key']: int(r['new']) for r in t}
    return [(m, have.get(m), by.get(k)) for k, m in MONSTERS] + [(m, have.get(m), look) for m, look in STOCK]


def map_text(rows_):
    return ','.join(MAP_HEADER) + '\n' + ''.join('%s,%s,%s\n' % r for r in rows_)


def write_map(check=False, path=MAP):
    """write monster_relook_looks.csv, or with check compare it; returns the problem lines"""
    text = map_text(map_rows())
    old = open(path, encoding='utf-8', newline='').read() if os.path.exists(path) else None
    if old == text:
        return []
    if check:
        return ['server/data/monster/monster_relook_looks.csv is not up to date (run gen_relook_monsters.py looks)']
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return []


def monster_problems(old=None, levels=None):
    """every monster of MONSTERS and STOCK: known (a file of ours or a row of the committed bounty pool, whose look is one of pair 85),
    a hunt monster of the pool (no boss), once; every stock look is a look of pair 85"""
    have = D.G.old_looks() if old is None else old
    lv = D.P.pool_levels() if levels is None else levels
    out, seen = [], set()
    for m in [m for _k, m in MONSTERS] + [m for m, _l in STOCK]:
        if m in seen:
            out.append('%s is picked twice' % m)
        seen.add(m)
        if m not in have:
            out.append('%s has no monster file of ours and no row of the bounty pool' % m)
        elif not 1 <= int(have[m]) <= OUTFITS_BEFORE:
            out.append('%s: committed look %s, a look of pair 85 (1-%d)' % (m, have[m], OUTFITS_BEFORE))
        if m not in lv:
            out.append('%s is not a hunt monster of the bounty pool' % m)
    for m, look in STOCK:
        if not 1 <= look <= OUTFITS_BEFORE:
            out.append('%s: stock look %d is no look of pair 85' % (m, look))
    return out


def built_problems(table=None, sums=None, root=None):
    """the rows built from the committed pictures: every frame rule, the row as the table has it, the outfit as the sums have it"""
    return [_here(x) for x in D.redraw_built_problems(rows() if table is None else table, read_sums() if sums is None else sums,
                                                      ROOT if root is None else root)]


def measured(root=None, want=ROWS, first=FIRST_NEW):
    return D.measured([], want, first, ROOT if root is None else root)


def table_text(rs):
    return D.table_text(rs)


def sums_text(sums):
    return D.sums_text(sums).replace('gen_drive_monsters.py', 'gen_relook_monsters.py').replace('(O726)', '(O768)')


def _md5(path):
    import hashlib
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def build(dat, spr, out_dir, root=None, want=ROWS, first=FIRST_NEW, dat_md5=PAIR85_DAT_MD5, log=print):
    """pair 85 in (its outfits end at first - 1, its dat md5 `dat_md5`; None skips the md5, the test's synthetic pair) -> pair 86 in
    OUT_DIR: one outfit per row. Returns the new ids."""
    from datspr import Dat
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    n = len(Dat(dat).outfits)
    if n != first - 1:
        raise SystemExit('refused: the input pair has %d outfits, this step needs %d (pair 85)' % (n, first - 1))
    if dat_md5 is not None and _md5(dat) != dat_md5:
        raise SystemExit('refused: the input dat md5 is %s, pair 85 is %s' % (_md5(dat), dat_md5))
    return D.build(dat, spr, out_dir, [], want=want, first=first, log=log, redraw=ROOT if root is None else root)


def live(dat, spr, table=None, sums=None, first=FIRST_NEW, log=print):
    t = rows() if table is None else table
    return D.live(dat, spr, table=t, sums=read_sums() if sums is None else sums, first=first, log=log)


# ---------------------------------------------------------------- the drop: PixelLab v3 (upright) -> pictures at the game's angle

def _idle_dir(state, d):
    """the PixelLab idle frames of direction d (animations/idle*/d or breathing*/d), [] when there are none"""
    base = os.path.join(state, 'animations')
    for n in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        if (n.lower().startswith('idle') or n.lower().startswith('breath')) and os.path.isdir(os.path.join(base, n, d)):
            p = os.path.join(base, n, d)
            return [os.path.join(p, f) for f in sorted(os.listdir(p)) if f.lower().endswith('.png')]
    return []


def read_upright(path):
    """oblique_lean.read_drop of a v3 download, with PixelLab's own idle of 4 (when every direction has one) in place of the script
    breath: hard alpha, the drop's canvas, colours pulled to the standing pictures, moved onto the standing picture by the feet"""
    import numpy as np
    from PIL import Image
    from fun_costume_motion import find_state, lock_palette
    d = L.read_drop(path, margin=MARGIN)
    st = find_state(path)
    side = d['stand']['south'].shape[0]
    found = {dn: _idle_dir(st, dn) for dn in L.DROP_DIRS}
    if all(len(v) == L.DROP_IDLE for v in found.values()):
        refs = list(d['stand'].values())
        for dn in L.DROP_DIRS:
            fr = [L._on(L.hard(np.array(Image.open(f).convert('RGBA'))), side) for f in found[dn]]
            d['idle'][dn] = L.align_to_standing(d['stand'][dn], lock_palette(fr, refs, 1))[0]
        d['idle_src'] = 'pixellab'
    else:
        d['idle_src'] = 'breath'
    return d


STRAY_MAX = 3                       # px: an 8-connected island this small, apart from the body, is a stray of the drop (hair and mist tips)


def drop_strays(a, most=STRAY_MAX):
    """(picture without its 8-connected opaque islands of `most` pixels or fewer, pixels removed)"""
    op = a[..., 3] > 0
    seen = set()
    h, w = op.shape
    out = a.copy()
    gone = 0
    for y0, x0 in zip(*op.nonzero()):
        if (y0, x0) in seen:
            continue
        part, todo = [], [(int(y0), int(x0))]
        seen.add((int(y0), int(x0)))
        while todo:
            y, x = todo.pop()
            part.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    v = (y + dy, x + dx)
                    if 0 <= v[0] < h and 0 <= v[1] < w and op[v] and v not in seen:
                        seen.add(v)
                        todo.append(v)
        if len(part) <= most:
            for y, x in part:
                out[y, x] = 0
            gone += len(part)
    return out, gone


def shear_drop(d, k=SHEAR_K):
    """every picture of read_upright's result without its strays (drop_strays), on a canvas grown by room for the shear (left and top,
    so it stays square) and sheared by oblique_lean.shear at k, the feet line of the direction's standing picture"""
    side = d['stand']['south'].shape[0]
    room = int(k * side) + 2
    import numpy as np

    def grow(a):
        c = np.zeros((side + room, side + room, 4), np.uint8)
        c[room:, room:] = a
        return c
    out = {'stand': {}, 'idle': {}, 'walk': {}, 'id': d.get('id', ''), 'idle_src': d.get('idle_src', ''), 'strays': 0}

    def clean(a):
        b, n = drop_strays(a)
        out['strays'] += n
        return b
    for dn in L.DROP_DIRS:
        s = grow(clean(d['stand'][dn]))
        fy = L.feet_row(s)
        out['stand'][dn] = clean(L.shear(s, k, fy))           # again after the shear: it can part a diagonal step
        for g in ('idle', 'walk'):
            out[g][dn] = [clean(L.shear(grow(clean(a)), k, fy)) for a in d[g][dn]]
    return out


def drop_import(drop, names=None, root=None, log=print):
    """DROP/<name>/ (an unzipped PixelLab v3 download; names {folder: key}, default the keys) -> art_import/relook_monsters/<key>/:
    the four standing pictures, idle/<dir>/frame_000..003.png, walk/<dir>/frame_000..007.png, sheared to the game's angle (the old
    pictures of the key go). Returns the keys written."""
    from PIL import Image
    root = ROOT if root is None else root
    names = {k: k for k in KEYS} if names is None else names
    done = []
    for name, key in sorted(names.items()):
        src = os.path.join(drop, name)
        if not os.path.isdir(src):
            continue
        try:
            d = shear_drop(read_upright(src), SHEAR_K_OF.get(key, SHEAR_K))
        except (ValueError, L.LostPixel) as e:
            raise SystemExit('refused %s: %s' % (name, e))
        dst = os.path.join(root, key)
        shutil.rmtree(dst, ignore_errors=True)
        os.makedirs(dst)
        for dn, f in zip(D.DIRS, D.STANDING):
            Image.fromarray(d['stand'][dn], 'RGBA').save(os.path.join(dst, f))
            for g in ('idle', 'walk'):
                os.makedirs(os.path.join(dst, g, dn))
                for i, a in enumerate(d[g][dn]):
                    Image.fromarray(a, 'RGBA').save(os.path.join(dst, g, dn, 'frame_%03d.png' % i))
        fr = L.drop_frames(d)
        fr.update({('idle', i): [d['stand'][dn]] + fr[('idle', i)] for i, dn in enumerate(L.DROP_DIRS)})
        log('%s -> art_import/relook_monsters/%s: %d px canvas, idle %s, %d stray px dropped, lean %s px%s' % (
            name, key, d['stand']['south'].shape[0], d['idle_src'], d['strays'], L.lean_text(fr),
            '' if L.lean_ok(fr) else ' (OUTSIDE %g to %g in south and east)' % L.LEAN))
        done.append(key)
    return done


def main(argv):
    a = list(argv)
    cmd = a.pop(0) if a else ''
    if cmd == 'check':
        p = problems() + words_problems() + monster_problems() + write_map(check=True)
        if not p:
            p += built_problems()
        for line in p:
            print('PROBLEM', line)
        print('relook_monsters: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if cmd == 'looks':
        p = monster_problems() + write_map(check='--check' in a)
        for line in p:
            print('PROBLEM', line)
        print('monster_relook_looks: %d rows, %d problems' % (len(MONSTERS) + len(STOCK), len(p)))
        return 1 if p else 0
    if cmd == 'drop-import' and len(a) >= 1:
        names = dict(x.split('=', 1) for x in a[1:]) or None
        keys = drop_import(a[0], names)
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
