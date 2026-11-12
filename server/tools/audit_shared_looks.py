#!/usr/bin/env python3
"""Audit: do two different monsters look the same in game? (O529)

usage: python3 -I audit_shared_looks.py MONSTER_DIR [--spawn SPAWN_XML] [--dat TIBIA.DAT] [--csv OUT.csv]
                                         [--allow CSV] [--pair N] [--check]
       python3 -I audit_shared_looks.py --write-masks TIBIA.DAT      # server/data/monster/look_masks.csv

MONSTER_DIR is the data/monster folder of an installed server (base files and ours). Every monster the server loads is
read: the XML files (monsters.xml registry, else every file) and the Lua monsters (Game.createMonsterType). The look is
lookType (or lookTypeEx for an item look) plus head, body, legs, feet and addons.

Two monsters with different names SHARE a look when they have the same lookType (or lookTypeEx) and the colours do not
tell them apart. How colours are judged: an outfit draws colour only through its mask layer (a sprite pattern with
layers >= 2, which --dat tells; without --dat every outfit is taken to have one, the strict side). Of head, body, legs
and feet only the parts the mask paints count. Two colours differ when their RGB in the 133 colour table is more than
COLOUR_DIST apart (0..1 per channel, Euclidean), the same distance the eye uses for "another hue or another
brightness". Addons differ when the outfit has addon frames (patterns > 4 in z) and the numbers differ; without --dat they
always count when different. A look without a mask layer ignores all colours: two such monsters with the same lookType
are always shared. Bosses and variants the design wants alike are on the allow list (server/data/monster/
shared_looks_allow.csv: look, names, status kept, reason); --check fails when a shared look is neither allowed nor absent.

Hue shifted copies (O531): 35 monsters wear a copy of their outfit from client pair 69 (server/data/monster/
monster_recolour_looks.csv: monster, look, new_look; table client/tools/sprites/art_import/monster_recolour.csv). The audit
reads each monster with the look it has at the pair of the server: --pair N, else the pair recorded in the config.lua beside
the data folder (client_pair.py), else the newest pair. At pair 69 or more a monster in the map has its new look. Below it a
group in which all but one monster have a row of that map is no failure: it is counted as waiting for pair 69 ("WAITS").

CI (tools/ci/check_content.py) has no dat: it reads the bounty pool (colours included) and look_masks.csv, the pool looks that have a
mask (written by --write-masks from the live dat). Monsters of a masked look whose pool colours tell them apart pass.

--csv writes one row per look group (look | monsters | spawns each | kept or changed | why). Spawns come from --spawn
(the map's spawn file: one entry per spawn point) and data/scripts/chaos/bounty_pool.lua (the hunt pool, same counts
the bounty board uses).
"""
import csv
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
RECOLOUR = os.path.join(REPO, 'server', 'data', 'monster', 'monster_recolour_looks.csv')
ALLOW = os.path.join(REPO, 'server', 'data', 'monster', 'shared_looks_allow.csv')
POOL = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'bounty_pool.lua')
COLOUR_DIST = 0.28


def pal(c):
    """RGB (0..1) of outfit colour index c, the client's 133 colour table."""
    import colorsys
    if c >= 133:
        c = 0
    if c % 19 != 0:
        h = (c % 19) / 18.0
        k = c // 19
        sv = [(0.25, 1.0), (0.25, 0.75), (0.5, 0.75), (0.667, 0.75), (1.0, 1.0), (1.0, 0.75), (1.0, 0.5)][k]
        return colorsys.hsv_to_rgb(h * (1 - 1 / 19), sv[0], sv[1])
    v = 1 - (c // 19) / 7.0
    return (v, v, v)


def colour_differs(a, b):
    pa, pb = pal(a), pal(b)
    return sum((x - y) ** 2 for x, y in zip(pa, pb)) ** 0.5 > COLOUR_DIST


def read(p):
    with open(p, encoding='utf-8', errors='replace') as f:
        return f.read()


def load_monsters(mdir):
    """[{name, file, look, ex, head, body, legs, feet, addons}] of every monster the server loads."""
    out, seen = [], set()
    reg = os.path.join(mdir, 'monsters.xml')
    files = []
    if os.path.exists(reg):
        for tag in re.findall(r'<monster\s[^>]*>', read(reg)):   # name and file in either order (the base writes some the other way round)
            n, f = re.search(r'\bname="([^"]+)"', tag), re.search(r'\bfile="([^"]+)"', tag)
            if n and f:
                files.append((n.group(1), os.path.join(mdir, f.group(1))))
    else:
        for root, _, fs in os.walk(mdir):
            for f in sorted(fs):
                if f.endswith('.xml'):
                    files.append((None, os.path.join(root, f)))
    for n, p in files:
        if not os.path.exists(p):
            continue
        t = read(p)
        m = re.search(r'<monster\s+name="([^"]+)"', t)
        lk = re.search(r'<look\s[^>]*>', t)
        if not m or not lk:
            continue
        name = m.group(1)
        if name in seen:
            continue
        seen.add(name)

        def a(k, tag=lk.group(0)):
            v = re.search(r'\b%s\s*=\s*"(\d+)"' % k, tag)
            return int(v.group(1)) if v else 0
        out.append(dict(name=name, file=os.path.relpath(p, mdir), look=a('type'), ex=a('typeex'), head=a('head'),
                        body=a('body'), legs=a('legs'), feet=a('feet'), addons=a('addons')))
    for root, _, fs in os.walk(os.path.join(mdir, 'lua')):
        for f in sorted(fs):
            if not f.endswith('.lua'):
                continue
            t = read(os.path.join(root, f))
            m = re.search(r'Game\.createMonsterType\("([^"]+)"\)', t)
            o = re.search(r'monster\.outfit\s*=\s*\{(.*?)\}', t, re.S)
            if not m or not o or m.group(1) in seen:
                continue
            seen.add(m.group(1))

            def b(k, body=o.group(1)):
                v = re.search(r'\b%s\s*=\s*(\d+)' % k, body)
                return int(v.group(1)) if v else 0
            out.append(dict(name=m.group(1), file=os.path.relpath(os.path.join(root, f), mdir), look=b('lookType'),
                            ex=b('lookTypeEx'), head=b('lookHead'), body=b('lookBody'), legs=b('lookLegs'),
                            feet=b('lookFeet'), addons=b('lookAddons')))
    return out


def spawn_counts(spawn_xml=None, pool=POOL):
    c = defaultdict(int)
    if spawn_xml and os.path.exists(spawn_xml):
        for n in re.findall(r'<monster\s+name="([^"]+)"', read(spawn_xml)):
            c[n] += 1
    if pool and os.path.exists(pool):
        for n, s in re.findall(r'\{name = "([^"]+)",[^}]*?spawns = (\d+)', read(pool)):
            c[n] = max(c[n], int(s))
    return c


def pool_rows(pool=POOL):
    """[{name, spawns, look, head, body, legs, feet, addons}] of the bounty pool hunt list (monsters with >= 6 spawns on the map);
    the pool is generated from the installed files, colours included."""
    out = []
    for m in re.finditer(r'\{name = "([^"]+)",[^}]*?spawns = (\d+), look = (\d+)([^}]*)\}', read(pool).split('bosses = {')[0]):
        def a(k, tail=m.group(4)):
            v = re.search(r'\b%s = (\d+)' % k, tail)
            return int(v.group(1)) if v else 0
        out.append(dict(name=m.group(1), spawns=int(m.group(2)), look=int(m.group(3)), ex=0, head=a('head'), body=a('body'),
                        legs=a('legs'), feet=a('feet'), addons=a('addons')))
    return out


def pool_looks(pool=POOL):
    """[(name, spawns, look)] of the pool hunt list."""
    return [(r['name'], r['spawns'], r['look']) for r in pool_rows(pool)]


def mask_info(dat_path):
    """{outfit id: (mask colour parts used as set of 'head','body','legs','feet' or None for no mask, has_addons)}.

    Needs client/tools/sprites/datspr.py and the sprite file next to the dat; used only when --dat is given."""
    sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
    from datspr import Dat, Spr
    d = Dat(dat_path)
    s = Spr(os.path.splitext(dat_path)[0] + '.spr')
    from datspr import sprite_index
    info = {}

    def get(look):
        if look in info:
            return info[look]
        t = d.outfit(look)
        if t is None:
            info[look] = (None, False)
            return info[look]
        if t.layers < 2:
            info[look] = (None, t.pz > 1 if hasattr(t, 'pz') else False)
            return info[look]
        used = set()
        import numpy as np
        for ph in range(max(1, t.phases)):
            for dr in range(t.px if t.px >= 4 else 1):
                for hh in range(t.h):
                    for ww in range(t.w):
                        idx = sprite_index(t, dr, 0, 0, 1, ph, ww, hh)
                        if idx >= len(t.sprites):
                            continue
                        a = s.sprite(t.sprites[idx])
                        if a is None:
                            continue
                        m = np.asarray(a).astype(float) / 255
                        ok = m[..., 3] > 0.5
                        for part, (cr, cg, cb) in (('head', (1, 1, 0)), ('body', (1, 0, 0)), ('legs', (0, 1, 0)),
                                                   ('feet', (0, 0, 1))):
                            sel = ok & (abs(m[..., 0] - cr) < 0.5) & (abs(m[..., 1] - cg) < 0.5) & (abs(m[..., 2] - cb) < 0.5)
                            if sel.any():
                                used.add(part)
        info[look] = (used, t.pz > 1 if hasattr(t, 'pz') else False)
        return info[look]
    return get


def same_look(a, b, mask=None):
    """True when two monster rows look the same in game."""
    if (a['look'], a['ex']) != (b['look'], b['ex']):
        return False
    if a['ex']:
        return True
    if mask is None:
        parts, addons = {'head', 'body', 'legs', 'feet'}, True
    else:
        parts, addons = mask(a['look'])
    if parts is None:
        return True
    for p in parts:
        if colour_differs(a[p], b[p]):
            return False
    if addons and a['addons'] != b['addons']:
        return False
    return True


def groups(mons, mask=None):
    """Lists of >= 2 monsters pairwise... joined by same_look (single link per look type)."""
    by = defaultdict(list)
    for m in mons:
        if m['look'] or m['ex']:
            by[(m['look'], m['ex'])].append(m)
    out = []
    for k, ms in sorted(by.items()):
        if len(ms) < 2:
            continue
        # clusters: monsters of one look type, joined when they look the same
        left, clusters = list(ms), []
        while left:
            c = [left.pop(0)]
            grew = True
            while grew:
                grew = False
                for o in list(left):
                    if any(same_look(x, o, mask) for x in c):
                        c.append(o)
                        left.remove(o)
                        grew = True
            if len(c) > 1:
                clusters.append(c)
        out.extend(clusters)
    return out


MASKS = os.path.join(REPO, 'server', 'data', 'monster', 'look_masks.csv')
OURS = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
MIN_MET = 3   # a monster is "met" when it has this many spawn points on the map (bosses and uniques have 1 or 2)


def load_recolour(path=RECOLOUR):
    """{monster name: (look, new_look)} of monster_recolour_looks.csv (O531)"""
    out = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
            out[r['monster']] = (int(r['look']), int(r['new_look']))
    return out


def look_at_pair(name, look, pair, recolour):
    """the lookType of a monster at a client pair: its copy from pair 69 on, the old look below (a file or a pool row written
    for the other state is read for this one too, so a server mid update gives the same answer)"""
    if name in recolour:
        old, new = recolour[name]
        if look in (old, new):
            return new if pair >= client_pair.PAIR_RECOLOUR else old
    return look


def waits(names, look, recolour):
    """a group that waits for pair 69: all but one monster of it have a row of the recolour map for this look"""
    return len(names) > 1 and sum(1 for n in names if n in recolour and recolour[n][0] == look) >= len(names) - 1


def load_allow(path=ALLOW):
    """[(look, frozenset of names, status, reason)] of shared_looks_allow.csv (status kept)."""
    out = []
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
            out.append((r['look'], frozenset(x.strip() for x in r['names'].split('|')), r['status'], r['reason']))
    return out


def allowed(look, names, allow):
    """A shared look is allowed when one row of the list names the same look and covers every name."""
    names = set(names)
    return any(str(look) == l and names <= s for l, s, _, _ in allow)


def load_masks(path=MASKS):
    """{look: set of mask parts} of look_masks.csv (the pool looks whose outfit has a colour mask, from the dat)."""
    out = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='')):
            out[int(r['look'])] = set(r['parts'].split('|'))
    return out


def write_masks(dat, pool=POOL, path=MASKS):
    """Write look_masks.csv for every look of the pool hunt list (needs the live dat). Returns the number of rows."""
    get = mask_info(dat)
    rows = []
    for l in sorted({l for _, _, l in pool_looks(pool)}):
        parts, _ = get(l)
        if parts:
            rows.append([l, '|'.join(sorted(parts))])
    with open(path, 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['look', 'parts'])
        w.writerows(rows)
    return len(rows)


def check_pool(pool=POOL, allow_path=ALLOW, masks=None, pair=None, recolour=None):
    """CI rule (no installed server needed): two different monsters of the bounty pool hunt list (>= 6 spawns on the map) with
    one lookType must be on the allow list, or the look has a colour mask (look_masks.csv) and the pool colours of the monsters
    tell every two apart (same_look, the colour rule of the audit). Returns the problem lines.

    `pair` is the client pair the monsters are read at (default: the newest, client_pair.PAIR_ASSETS): from pair 69 a monster of the
    recolour map wears its copy; below it the groups the map will separate are not a problem (they wait for the pair)."""
    allow = load_allow(allow_path)
    masks = load_masks() if masks is None else masks
    pair = client_pair.PAIR_ASSETS if pair is None else pair
    recolour = load_recolour() if recolour is None else recolour
    by, rec = defaultdict(list), {}
    for r in pool_rows(pool):
        r['look'] = look_at_pair(r['name'], r['look'], pair, recolour)
        rec[r['name']] = r
        if r['name'] not in by[r['look']]:
            by[r['look']].append(r['name'])
    out = []
    for l, ns in sorted(by.items()):
        if len(ns) < 2:
            continue
        clusters = [ns]
        if l in masks:   # monsters of one masked look whose colours tell them apart are no duplicates
            clusters = [[m['name'] for m in c] for c in groups([rec[n] for n in ns], lambda _l, mk=masks[l]: (mk, False))]
        for c in clusters:
            if len(c) > 1 and not allowed(l, c, allow) and not (pair < client_pair.PAIR_RECOLOUR and waits(c, l, recolour)):
                out.append('look %d is shared by %s and is not on server/data/monster/shared_looks_allow.csv' % (l, ', '.join(c)))
    return out


def main():
    args = sys.argv[1:]

    def opt(k):
        if k in args:
            i = args.index(k)
            v = args[i + 1]
            del args[i:i + 2]
            return v
        return None
    spawn, dat, outcsv, allow_path = opt('--spawn'), opt('--dat'), opt('--csv'), opt('--allow')
    pair_arg = opt('--pair')
    check = '--check' in args
    if check:
        args.remove('--check')
    if '--write-masks' in args:
        i = args.index('--write-masks')
        print('look_masks.csv: %d looks' % write_masks(args[i + 1]))
        return
    mdir = args[0]
    mons = load_monsters(mdir)
    pair = int(pair_arg) if pair_arg else client_pair.recorded(os.path.dirname(os.path.abspath(mdir)))
    pair = client_pair.PAIR_ASSETS if pair is None else pair
    recolour = load_recolour()
    for m in mons:
        m['look'] = look_at_pair(m['name'], m['look'], pair, recolour)
    sp = spawn_counts(spawn)
    mask = mask_info(dat) if dat else None
    allow = load_allow(allow_path or ALLOW)
    gs = groups(mons, mask)
    bad = waiting = 0
    rows = []
    for g in gs:
        names = [m['name'] for m in g]
        met = [n for n in names if sp.get(n, 0) >= MIN_MET]
        look = g[0]['ex'] or g[0]['look']
        if len(met) < 2:
            status, why = 'kept', 'at most one monster of the look is met (>= %d spawn points)' % MIN_MET
        elif allowed(look, met, allow):
            status = 'kept'
            why = next(r for l, s, st, r in allow if l == str(look) and set(met) <= s)
        elif pair < client_pair.PAIR_RECOLOUR and waits(met, look, recolour):
            status, why = 'WAITS', 'all but one have a hue shifted copy from client pair %d (recorded pair %d)' % (client_pair.PAIR_RECOLOUR, pair)
            waiting += 1
        else:
            status, why = 'SHARED', ''
            bad += 1
        rows.append([look, ' | '.join(names), ' | '.join(str(sp.get(n, 0)) for n in names), status, why])
    if outcsv:
        with open(outcsv, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(['look', 'monsters', 'spawns each', 'kept or changed', 'why'])
            w.writerows(rows)
    print('%d monsters, %d shared look groups, %d not allowed%s (client pair %d)'
          % (len(mons), len(gs), bad, ', %d waiting for pair %d' % (waiting, client_pair.PAIR_RECOLOUR) if waiting else '', pair))
    for r in rows:
        if r[3] == 'SHARED':
            print('  look %s: %s (spawns %s)' % (r[0], r[1], r[2]))
    if check and bad:
        sys.exit(1)


if __name__ == '__main__':
    main()
