#!/usr/bin/env python3
"""Polished creature outfits of the owner's donor client (O538; client/MANIFEST.md "Pair 70").

    python3 -I gen_donor_outfits.py check                       # the table against its own rules (no pair, no donor files)
    python3 -I gen_donor_outfits.py looks [--check]             # server/data/monster/monster_donor_looks.csv from the `donor` rows of monster_looks/picks.csv
    python3 -I gen_donor_outfits.py select --donor DIR [--pair DAT SPR] [--write]
                                                                # apply the pick rule to the donor files, print (or write) the table
    python3 -I gen_donor_outfits.py sums --donor DIR [--check]  # write (or compare) art_import/donor_outfits.sums from the donor files
    python3 -I gen_donor_outfits.py build DAT SPR OUT_DIR --donor DIR
                                                                # pair 69 in, pair 70 out (OUT_DIR must not exist; written beside, then renamed)
    python3 -I gen_donor_outfits.py live DAT SPR                # the pair holds every outfit at its id, as the sums say (CI job "Live sprite pair")

The owner approved (2026-11-12, O537 survey) importing the polished creature looks of the donor client and moving the blocky hunt
monsters of the same kind onto them. The art never enters the repository: committed are this tool, the table
art_import/donor_outfits.csv (donor id, new id, kind, size, walk frames, colours) and art_import/donor_outfits.sums (a digest of
every outfit's pictures, to check a built pair and the donor files against).

Pick rule (`select`), all of it measured on the donor files:
  * polished: 500 or more colours (every opaque RGB over all frames facing south, all frame groups);
  * one colour layer, 4 directions, 3 or more walk frames (the phases of the last frame group), at most 2x2 tiles (MAX_TILES);
  * a creature (KINDS: the kind of each candidate, looked at by eye in the O537 catalog; wings, crystals, rings, costumes are no kind);
  * not identical (every group, direction, phase, sprite pixel) to an outfit of the input pair, and not identical to a pick of lower id.

Pair 70 (`build`) appends the picks as new outfits after the 3,405 outfits of pair 69, one per row, in table order: the row at
line n (0-based) becomes outfit 3406 + n. An outfit keeps its flag bytes (re-encoded by name, import_outfits.encode_flags), frame
groups (idle and walk), sizes, patterns, phases and animator durations. Sprites are the donor's pictures, byte for byte (record
copied when the donor spr has our layout, else re-encoded): a picture that is already a record of the input pair takes that
sprite id, a new one is appended once. Nothing but outfits and sprite records is appended (check_pair.py --old pair 69: 0 errors).
Needs numpy and Pillow (the fx venv of CI) for build, select, sums and live; `check` needs neither.
"""
import csv
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art_import')
TABLE = os.path.join(ART, 'donor_outfits.csv')
SUMS = os.path.join(ART, 'donor_outfits.sums')
HEADER = ['donor', 'new', 'kind', 'size', 'walk', 'colours']
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
PICKS = os.path.join(HERE, 'monster_looks', 'picks.csv')
POOL = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'bounty_pool.lua')
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_donor_looks.csv')
MAP_HEADER = ['monster', 'look', 'new_look']
PAIR = 70
MIN_PAIR = 69
OUTFITS_69 = 3405
FIRST_NEW = OUTFITS_69 + 1
DAT_69_MD5 = '2bc03dde6fa919a9055d20991721ffd4'
MIN_COLOURS = 500
MIN_WALK = 3
MAX_TILES = 2
KIND_NAMES = ('angel/spirit', 'beast', 'bird/bat', 'demon', 'dragon/drake', 'gazer/eye', 'golem/construct', 'hydra/serpent',
              'reptile', 'slime/blob', 'spider/insect', 'troll/ogre/orc', 'undead')
# the kind of every polished candidate of the donor client that is a creature (looked at in the O537 catalog sheet); an outfit
# that is no creature (wings, crystals, rings, orbs, costumes, player style humans) has no entry and is never picked (2410 is a
# Santa Claus costume: no hunt monster is one, so it has no kind)
KINDS = {
    1216: 'angel/spirit', 1302: 'angel/spirit', 1315: 'angel/spirit', 1316: 'angel/spirit', 1380: 'angel/spirit',
    1400: 'angel/spirit', 1413: 'angel/spirit', 1417: 'angel/spirit', 1434: 'angel/spirit', 2185: 'angel/spirit',
    2202: 'angel/spirit',
    395: 'beast', 919: 'beast', 1305: 'beast', 1524: 'beast', 1878: 'beast', 2030: 'beast', 2149: 'beast',
    2157: 'beast', 2227: 'beast', 2228: 'beast', 2229: 'beast', 2230: 'beast', 2231: 'beast', 2255: 'beast',
    2345: 'beast', 2354: 'beast', 2575: 'beast',
    1936: 'bird/bat', 2351: 'bird/bat', 2750: 'bird/bat', 2751: 'bird/bat', 2752: 'bird/bat', 2753: 'bird/bat',
    2754: 'bird/bat',
    1210: 'demon', 1226: 'demon', 1340: 'demon', 1371: 'demon', 1601: 'demon', 1898: 'demon', 1938: 'demon',
    2012: 'demon', 2017: 'demon', 2148: 'demon', 2160: 'demon', 2368: 'demon', 2371: 'demon',
    1211: 'dragon/drake', 1349: 'dragon/drake', 1350: 'dragon/drake', 1351: 'dragon/drake', 1375: 'dragon/drake',
    1657: 'dragon/drake', 1850: 'dragon/drake', 1858: 'dragon/drake', 2162: 'dragon/drake', 2667: 'dragon/drake',
    2687: 'dragon/drake', 2756: 'dragon/drake', 2771: 'dragon/drake', 2772: 'dragon/drake', 2773: 'dragon/drake',
    2774: 'dragon/drake', 2775: 'dragon/drake',
    924: 'gazer/eye',
    1142: 'golem/construct', 1225: 'golem/construct', 1348: 'golem/construct', 1381: 'golem/construct',
    1383: 'golem/construct', 1433: 'golem/construct', 1520: 'golem/construct', 1839: 'golem/construct',
    1840: 'golem/construct', 1841: 'golem/construct', 2015: 'golem/construct', 2033: 'golem/construct',
    2150: 'golem/construct', 2156: 'golem/construct', 2187: 'golem/construct', 2313: 'golem/construct',
    2734: 'golem/construct', 2757: 'golem/construct', 2758: 'golem/construct', 2759: 'golem/construct',
    2760: 'golem/construct', 2761: 'golem/construct',
    121: 'hydra/serpent',
    119: 'reptile', 1605: 'reptile', 1862: 'reptile',
    2429: 'slime/blob',
    1214: 'spider/insect', 1313: 'spider/insect', 1314: 'spider/insect', 1431: 'spider/insect', 1528: 'spider/insect',
    1529: 'spider/insect', 1727: 'spider/insect', 2407: 'spider/insect',
    470: 'troll/ogre/orc', 1363: 'troll/ogre/orc', 1378: 'troll/ogre/orc', 1386: 'troll/ogre/orc',
    1387: 'troll/ogre/orc', 1779: 'troll/ogre/orc', 1838: 'troll/ogre/orc',
    939: 'undead', 1312: 'undead', 2146: 'undead', 2155: 'undead', 2166: 'undead', 2188: 'undead', 2385: 'undead',
    2591: 'undead', 2764: 'undead', 2766: 'undead', 2768: 'undead',
}


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def read_sums(path=SUMS):
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding='utf-8'):
            line = line.strip()
            if line and not line.startswith('#'):
                k, v = line.split()
                out[int(k)] = v
    return out


def problems(table=None, sums=None, first=FIRST_NEW):
    """What is wrong with the table: header, ids in a row from the first new outfit, a donor id once, kinds, sizes and the sums rows."""
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    out, seen = [], set()
    for i, r in enumerate(t):
        d, n = int(r['donor']), int(r['new'])
        if n != first + i:
            out.append('donor %d: new id %d, the row at line %d must be %d' % (d, n, i, first + i))
        if d in seen:
            out.append('donor %d is on two rows' % d)
        seen.add(d)
        if r['kind'] not in KIND_NAMES:
            out.append('donor %d: kind %s is not one of %s' % (d, r['kind'], ', '.join(KIND_NAMES)))
        if KINDS.get(d) != r['kind']:
            out.append('donor %d: kind %s, KINDS says %s' % (d, r['kind'], KINDS.get(d)))
        try:
            w, h = (int(x) for x in r['size'].split('x'))
        except ValueError:
            out.append('donor %d: size %s is not WxH' % (d, r['size']))
            continue
        if w > MAX_TILES or h > MAX_TILES:
            out.append('donor %d: size %s is above %dx%d (a monster that is no boss stays 2x2 at most)' % (d, r['size'], MAX_TILES, MAX_TILES))
        if int(r['walk']) < MIN_WALK:
            out.append('donor %d: %s walk frames, at least %d' % (d, r['walk'], MIN_WALK))
        if int(r['colours']) < MIN_COLOURS:
            out.append('donor %d: %s colours, polished is %d or more' % (d, r['colours'], MIN_COLOURS))
    if set(s) != seen:
        out.append('donor_outfits.sums and the table name other outfits (%s)' % ', '.join(str(x) for x in sorted(set(s) ^ seen)))
    return out


def write_table(picks, path=TABLE):
    """picks: [(donor id, kind, size 'WxH', walk, colours)] -> the csv (new ids follow the order)"""
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(HEADER)
        for i, (d, kind, size, walk, colours) in enumerate(picks):
            w.writerow([d, FIRST_NEW + i, kind, size, walk, colours])


# ---------------------------------------------------------------- the monsters

def picks_rows(path=PICKS):
    """[(monster, new look, donor id)] of the rows of family `donor` of monster_looks/picks.csv, in file order"""
    with open(path, newline='', encoding='utf-8') as f:
        return [(r['monsters'], int(r['look']), int(r['lib_id'])) for r in csv.DictReader(f) if r['family'] == 'donor']


def pool_looks(path=POOL):
    """{monster name: look} of the committed bounty pool (the look every monster wears below pair 70)"""
    import re
    text = open(path, encoding='utf-8').read()
    return {m.group(1).replace('\\"', '"'): int(m.group(2))
            for m in re.finditer(r'\{name = "((?:[^"\\]|\\.)*)",[^}]*?\blook = (\d+)', text)}


def map_rows(picks=None, pool=None):
    """[(monster, old look, new look)]: the donor rows of picks.csv with the look the committed pool gives each monster today"""
    p = picks_rows() if picks is None else picks
    have = pool_looks() if pool is None else pool
    return [(m, have[m], new) for m, new, _d in p]


def map_text(rows_):
    return ','.join(MAP_HEADER) + '\n' + ''.join('%s,%d,%d\n' % r for r in rows_)


def map_problems(table=None, picks=None, pool=None):
    """The `donor` rows of picks.csv against the outfit table and the pool: each look is a table outfit (and its donor id), used by one
    monster, each monster once and in the pool."""
    t = rows() if table is None else table
    p = picks_rows() if picks is None else picks
    have = pool_looks() if pool is None else pool
    by = {int(r['new']): int(r['donor']) for r in t}
    out, seen, used = [], set(), set()
    for m, new, d in p:
        if by.get(new) != d:
            out.append('%s: look %d / donor %d is not a row of donor_outfits.csv' % (m, new, d))
        if new in used:
            out.append('look %d is on two monsters' % new)
        used.add(new)
        if m in seen:
            out.append('%s is on two rows of picks.csv' % m)
        seen.add(m)
        if m not in have:
            out.append('%s is not in the bounty pool' % m)
    for new in sorted(set(by) - used):
        out.append("outfit %d (donor %d) is no monster's look" % (new, by[new]))
    return out


def write_map(check=False):
    """write monster_donor_looks.csv (monster, look, new_look), or with check compare it; returns the problem lines"""
    text = map_text(map_rows())
    old = open(MAP, encoding='utf-8', newline='').read() if os.path.exists(MAP) else None
    if old == text:
        return []
    if check:
        return ['server/data/monster/monster_donor_looks.csv is not up to date (run gen_donor_outfits.py looks)']
    with open(MAP, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return []


# ---------------------------------------------------------------- measuring

def digest(dat, spr, look):
    """sha256 over the whole outfit: group shapes and animator, then every sprite slot (empty slots alike) of every group"""
    import numpy as np  # noqa: F401
    sys.path.insert(0, HERE)
    from import_outfits import parse_body
    h = hashlib.sha256()
    for g in parse_body(dat, dat.outfit(look)):
        h.update(repr((g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim)).encode())
        for sid in g.sprites:
            a = spr.sprite(sid)
            h.update(b'\0' if a is None or not a[:, :, 3].any() else a.tobytes())
    return h.hexdigest()


def measure(dat, spr, look):
    """facts of an outfit: tiles, layers, directions, walk frames (phases of the last group), colours (south, all groups)"""
    import numpy as np
    sys.path.insert(0, HERE)
    from import_outfits import parse_body, frame, frames_of
    groups = parse_body(dat, dat.outfit(look))
    g = groups[-1]
    cols = set()
    for gg in groups:
        for (x, y, z, ph) in frames_of(gg):
            if x != (2 if gg.px >= 4 else 0) or y != 0 or z != 0:
                continue
            a = frame(gg, spr, x, y, z, ph)
            v = a[..., 3] > 0
            if v.any():
                cols.update(map(tuple, np.unique(a[v][:, :3], axis=0)))
    return {'w': g.w, 'h': g.h, 'layers': max(x.layers for x in groups), 'dirs': g.px, 'walk': g.phases, 'colours': len(cols)}


def passes(m):
    return (m['colours'] >= MIN_COLOURS and m['layers'] == 1 and m['dirs'] == 4 and m['walk'] >= MIN_WALK
            and m['w'] <= MAX_TILES and m['h'] <= MAX_TILES)


def select(donor_dat, donor_spr, pair=None, log=print):
    """[(donor id, kind, size, walk, colours)] ordered by kind then id: the pick rule on the donor files. pair: (dat, spr) of the input
    pair, a pick identical to one of its outfits is dropped; a pick identical to an earlier pick is dropped too."""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    d, s = Dat(donor_dat), Spr(donor_spr)
    ours = None
    if pair:
        od, osp = Dat(pair[0]), Spr(pair[1])
        ours = {}
        for o in od.outfits:
            t = od.outfit(o.id)
            g = t.groups[-1] if t.groups else None
            if g and g[0] <= MAX_TILES and g[1] <= MAX_TILES:
                try:
                    ours[digest(od, osp, o.id)] = o.id
                except Exception:   # a blank or odd stock outfit cannot equal a pick
                    pass
    picks, seen = [], {}
    for look in sorted(KINDS):
        if d.outfit(look) is None:
            raise SystemExit('donor has no outfit %d' % look)
        m = measure(d, s, look)
        if not passes(m):
            log('drop %d: %s' % (look, m))
            continue
        h = digest(d, s, look)
        if ours is not None and h in ours:
            log('drop %d: identical to outfit %d of the pair' % (look, ours[h]))
            continue
        if h in seen:
            log('drop %d: identical to the pick %d' % (look, seen[h]))
            continue
        seen[h] = look
        picks.append((look, KINDS[look], '%dx%d' % (m['w'], m['h']), m['walk'], m['colours']))
    picks.sort(key=lambda p: (p[1], p[0]))
    return picks


def donor_sums(donor_dat, donor_spr, ids):
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    d, s = Dat(donor_dat), Spr(donor_spr)
    return {i: digest(d, s, i) for i in ids}


def sums_text(sums):
    return ('# sha256 of each donor outfit (shapes, animator, every sprite slot), written by gen_donor_outfits.py sums (O538)\n'
            + ''.join('%d %s\n' % (k, sums[k]) for k in sorted(sums)))


# ---------------------------------------------------------------- the pair

def record_index(spr):
    """{md5 of a record: sprite id} of every record of a spr (the first id of equal records)"""
    import struct
    m, idx = spr.m, {}
    for sid in range(1, spr.count + 1):
        o = int(spr.offs[sid - 1])
        if o:
            ln = struct.unpack_from('<H', m, o + 3)[0]
            idx.setdefault(hashlib.md5(m[o:o + 5 + ln]).digest(), sid)
    return idx


def build(dat, spr, out_dir, donor_dat, donor_spr, table=None, first=FIRST_NEW, expect_md5=None, log=print):
    """pair in (DAT, SPR; its outfits end at first - 1) -> pair out in OUT_DIR (not there yet): every row of the table is one new
    outfit, the donor outfit of the row. Verified before the rename; returns the new ids."""
    import random
    import shutil
    import struct
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_outfits import parse_body, build_entry, encode_flags, record_bytes, frame, frames_of
    from gen_effects import encode_sprite
    t = rows() if table is None else table
    if os.path.exists(out_dir):
        raise SystemExit('%s exists: remove it or name another folder' % out_dir)
    if expect_md5:
        with open(dat, 'rb') as f:
            got = hashlib.md5(f.read()).hexdigest()
        if got != expect_md5:
            raise SystemExit('input dat md5 %s, expected %s (pair %d): wrong input pair' % (got, expect_md5, MIN_PAIR))
    od, ospr = Dat(dat), Spr(spr)
    sd, sspr = Dat(donor_dat), Spr(donor_spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]), 'expected our 10.98 dat: %s' % (od.variant,)
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    nours = len(od.outfits)
    if nours + 1 != first:
        raise SystemExit('the input has %d outfits, the first new outfit would be %d, not %d: wrong input pair (or already built)'
                         % (nours, nours + 1, first))
    tmp = out_dir.rstrip('/') + '.tmp'
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    cnt = ospr.count
    index = record_index(ospr)
    same_layout = sspr.alpha == ospr.alpha
    src, sid_map, newrecs, recs, reused, copied, reenc = [], {0: 0}, [], {}, 0, 0, 0
    for i, r in enumerate(t):
        look = int(r['donor'])
        th = sd.outfit(look)
        if th is None:
            raise SystemExit('donor has no outfit %d' % look)
        groups = parse_body(sd, th)
        if not any(s for g in groups for s in g.sprites):
            raise SystemExit('donor outfit %d has no sprites' % look)
        flags, stripped = encode_flags(th, od.extra)
        for g in groups:
            for sid in g.sprites:
                if sid in sid_map:
                    continue
                a = sspr.sprite(sid) if 0 < sid <= sspr.count and sspr.offs[sid - 1] else None
                if a is None or not a[:, :, 3].any():
                    sid_map[sid] = 0
                    continue
                if same_layout and sspr._record_ok(sid, sspr.alpha):
                    rec = record_bytes(sspr, sid)
                    copied += 1
                else:
                    rec = encode_sprite(a)
                    reenc += 1
                key = hashlib.md5(rec).digest()
                if key in index:
                    sid_map[sid] = index[key]
                    reused += 1
                else:
                    if rec not in recs:
                        newrecs.append(rec)
                        recs[rec] = cnt + len(newrecs)
                    sid_map[sid] = recs[rec]
        src.append((first + i, r, th, groups, flags, stripped))
    entries = [build_entry(flags, groups, sid_map) for _n, _r, _t, groups, flags, _s in src]
    d = od.data
    ins = od.effects[0].raw[0]
    assert od.outfits[-1].raw[1] == ins
    out = bytearray(d[:ins]) + b''.join(entries) + d[ins:]
    struct.pack_into('<H', out, 6, nours + len(entries))
    with open(os.path.join(tmp, 'Tibia.dat'), 'wb') as f:
        f.write(out)
    m, nn = ospr.m, len(newrecs)
    toffs = ospr.offs.astype('<u8').copy()
    toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur)
        cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table_b = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(tmp, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn))
        f.write(table_b.tobytes())
        pos = 8 + 4 * cnt
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)])
            pos += 1 << 24
        for rec in newrecs:
            f.write(rec)
    # verify: re-parse, old things byte identical, every slot and frame of every new outfit is the donor's
    md, ms = Dat(os.path.join(tmp, 'Tibia.dat')), Spr(os.path.join(tmp, 'Tibia.spr'))
    assert md.variant == od.variant and ms.alpha == ospr.alpha and ms.signature == ospr.signature
    assert md.counts == (od.counts[0], nours + len(entries), od.counts[2], od.counts[3]), md.counts
    assert ms.count == cnt + nn and md.max_sprite <= ms.count
    assert md.data[:6] == d[:6] and md.data[8:ins] == d[8:ins], 'items or old outfits changed'
    assert md.data[ins + sum(map(len, entries)):] == d[ins:], 'effects or missiles changed'
    nslots = nframes = 0
    for nid, r, th, groups, flags, stripped in src:
        tm = md.outfit(nid)
        mg = parse_body(md, tm)
        assert {k: v for k, v in tm.flags.items()} == {k: v for k, v in th.flags.items() if k not in stripped}, (nid, 'flags')
        assert len(mg) == len(groups), nid
        for g, h in zip(groups, mg):
            assert (g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim) == \
                   (h.gtype, h.w, h.h, h.exact, h.layers, h.px, h.py, h.pz, h.phases, h.anim), (nid, 'group')
            for s0, s1 in zip(g.sprites, h.sprites):
                x, y = sspr.sprite(s0), ms.sprite(s1)
                if x is not None and not x[:, :, 3].any():
                    x = None
                assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), (nid, s0, s1)
                nslots += 1
            for (xx, yy, zz, ph) in frames_of(g):
                for layer in range(g.layers):
                    assert np.array_equal(frame(g, sspr, xx, yy, zz, ph, layer), frame(h, ms, xx, yy, zz, ph, layer)), \
                        (nid, 'frame', xx, yy, zz, ph, layer)
                nframes += 1
    random.seed(1)
    for sid in random.sample(range(1, cnt + 1), min(3000, cnt)) + [1, cnt]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log('verified: %d outfits %d to %d, %d sprite slots and %d frames equal the donor, %d slots reuse a sprite of the input pair, '
        '%d records appended (%d -> %d; %d copied, %d re-encoded), every old outfit, item, effect, missile and 3000 sampled old sprites unchanged'
        % (len(entries), first, first + len(entries) - 1, nslots, nframes, reused, nn, cnt, cnt + nn, copied, reenc))
    from check_pair import check_append_only
    check_append_only(dat, spr, os.path.join(tmp, 'Tibia.dat'), os.path.join(tmp, 'Tibia.spr'), log=log)
    os.rename(tmp, out_dir)
    return [first + i for i in range(len(entries))]


def live(dat, spr, table=None, sums=None, first=FIRST_NEW, log=print):
    """the pair holds every outfit at its id, its digest the one of the sums file, one colour layer and the table's size.
    Returns the problem lines."""
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    t = rows() if table is None else table
    s = read_sums() if sums is None else sums
    d, sp = Dat(dat), Spr(spr)
    if len(d.outfits) < first + len(t) - 1:
        return ['the pair has %d outfits, the donor outfits end at %d' % (len(d.outfits), first + len(t) - 1)]
    out = []
    for r in t:
        nid, don = int(r['new']), int(r['donor'])
        if digest(d, sp, nid) != s.get(don):
            out.append('outfit %d (donor %d, %s): the pictures are not the ones of donor_outfits.sums' % (nid, don, r['kind']))
    log('live: %d outfits %d to %d checked, %d problems' % (len(t), first, first + len(t) - 1, len(out)))
    return out


def opt(args, key):
    if key in args:
        i = args.index(key)
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return None


def main(argv):
    args = list(argv)
    if args[:1] == ['check']:
        p = problems() + map_problems() + write_map(check=True)
        for line in p:
            print('PROBLEM', line)
        print('donor_outfits: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if args[:1] == ['looks']:
        p = map_problems() + write_map(check='--check' in args)
        for line in p:
            print('PROBLEM', line)
        print('monster_donor_looks: %d rows, %d problems' % (len(picks_rows()), len(p)))
        return 1 if p else 0
    cmd = args.pop(0) if args else ''
    donor = opt(args, '--donor')
    if cmd == 'select' and donor:
        pair = None
        if '--pair' in args:
            i = args.index('--pair')
            pair = (args[i + 1], args[i + 2])
            del args[i:i + 3]
        picks = select(os.path.join(donor, 'Tibia.dat'), os.path.join(donor, 'Tibia.spr'), pair)
        for d, kind, size, walk, colours in picks:
            print('%5d  %-16s %s  walk %2d  colours %6d' % (d, kind, size, walk, colours))
        print('%d picks' % len(picks))
        if '--write' in args:
            write_table(picks)
        return 0
    if cmd == 'sums' and donor:
        text = sums_text(donor_sums(os.path.join(donor, 'Tibia.dat'), os.path.join(donor, 'Tibia.spr'), [int(r['donor']) for r in rows()]))
        if '--check' in args:
            old = open(SUMS, encoding='utf-8').read() if os.path.exists(SUMS) else None
            if old != text:
                print('PROBLEM donor_outfits.sums is not what the donor files give')
                return 1
            print('donor_outfits.sums: up to date')
            return 0
        with open(SUMS, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        return 0
    if cmd == 'build' and donor and len(args) == 3:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(args[0], args[1], args[2], os.path.join(donor, 'Tibia.dat'), os.path.join(donor, 'Tibia.spr'), expect_md5=DAT_69_MD5)
        print('built %d outfits %d to %d' % (len(ids), ids[0], ids[-1]))
        return 0
    if cmd == 'live' and len(args) == 2:
        p = live(args[0], args[1])
        for line in p:
            print('PROBLEM', line)
        return 1 if p else 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
