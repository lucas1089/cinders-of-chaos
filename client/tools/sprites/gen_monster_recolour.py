#!/usr/bin/env python3
"""Monster recolour outfits: hue shifted copies of outfits that have no colour mask (O529, O531; client/MANIFEST.md "Pair 69").

    python3 -I gen_monster_recolour.py check                  # the table against the monster files and the id files (no pair needed)
    python3 -I gen_monster_recolour.py ids [--check]          # write (or compare) the two id files below
    python3 -I gen_monster_recolour.py build DAT SPR OUT_DIR  # pair 68 in, pair 69 out (OUT_DIR must not exist; written beside, then renamed)
    python3 -I gen_monster_recolour.py live DAT SPR           # the pair holds every copy at its id (the CI job "Live sprite pair")

Owner 2026-11-12 (translated): no two hunt monsters may share a look, and the way is a recolour. An outfit with a colour mask
(dat layers >= 2) is recoloured in the monster file (head, body, legs, feet; server/tools/tune_monsters.py). An outfit with no
mask cannot take a colour, so the second monster needs its own copy of the outfit with the hue shifted. The table
art_import/monster_recolour.csv names one row per such monster:

  look        the outfit the monster wears now (lookType in its XML)
  hue_shift   degrees added to the hue of every pixel (mode hue), or the target hue itself (mode tint)
  monster     the exact <monster name>
  mode        hue  = rotate the hue of each pixel, keep its saturation and value
              tint = the outfit is nearly grey (source_sat < 0.22): set the hue to hue_shift, lift the saturation to TINT_SAT
  theme       why the colour: fire, ice, poison, shadow, iron, gold, blood, arcane (the monster's name and element)
  source_hue  the outfit's dominant hue in degrees (saturation weighted), source_sat its mean saturation (informative)

Pair 69 (O531) appends one copy per row as a new outfit after the 3,370 outfits of pair 68: the row at line n (0-based) of
the table becomes outfit 3371 + n. The copy has the source's flag bytes, frame groups, sizes, directions, phases, animator
(durations) and sprite layout; every sprite is the source sprite through recolour(). Two rows of one look are two copies of it.
Nothing but outfits and sprite records is appended (check_pair.py --old pair 68: 0 errors).

The ids are written by `ids` to two files, so nothing waits for the pair to know them:
  art_import/monster_recolour_ids.csv                  monster, look, new_look, hue_shift, mode (the client side record)
  server/data/monster/monster_recolour_looks.csv       monster, look, new_look (read by the install step `monsterrecolour`, the
                                                       shared look audit and tools/ci/check_content.py)
The monster files keep the old look: the install step moves a monster to its copy only once config.lua chaosClientPair is 69
or more (server/README.md "Monster recolours (O531)").
`recolour()` is the one pixel transform (numpy only); the O529 preview uses it too. Deterministic.
"""
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
TABLE = os.path.join(HERE, 'art_import', 'monster_recolour.csv')
IDS = os.path.join(HERE, 'art_import', 'monster_recolour_ids.csv')
SERVER_IDS = os.path.join(REPO, 'server', 'data', 'monster', 'monster_recolour_looks.csv')
MONSTERS = os.path.join(REPO, 'server', 'data', 'monster', 'monsters', 'chaos')
HEADER = ['look', 'hue_shift', 'monster', 'mode', 'theme', 'source_hue', 'source_sat']
TINT_SAT = 0.45
PAIR = 69            # the pair that holds the copies
MIN_PAIR = 68        # the copies go after the last outfit of this pair
OUTFITS_68 = 3370    # outfits of pair 68; the first copy is the next id
FIRST_NEW = OUTFITS_68 + 1
DAT_68_MD5 = '6b5638b4057f86f484bc506b00079f19'
MIN_APART = 40       # degrees between two colours of one look


def recolour(rgba, hue_shift, mode='hue'):
    """RGBA uint8 array (H, W, 4) -> a new array with the hue moved. Alpha stays; a grey pixel has no hue and stays (mode hue)."""
    import numpy as np
    a = np.asarray(rgba)
    f = a[..., :3].astype(np.float64) / 255.0
    mx, mn = f.max(-1), f.min(-1)
    v, c = mx, mx - mn
    s = np.where(mx > 0, c / np.where(mx > 0, mx, 1), 0.0)
    safe = np.where(c > 0, c, 1)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    h = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) / 6.0
    h = np.where(c > 0, h, 0.0)
    if mode == 'tint':
        h = np.full_like(h, (hue_shift % 360) / 360.0)
        s = np.maximum(s, TINT_SAT)
    else:
        h = (h + hue_shift / 360.0) % 1.0
    i = np.floor(h * 6).astype(int) % 6
    ff = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - ff * s), v * (1 - (1 - ff) * s)
    out = np.stack([np.choose(i, [v, q, p, p, t, v]), np.choose(i, [t, v, v, q, p, p]), np.choose(i, [p, p, t, v, v, q])], -1)
    res = a.copy()
    res[..., :3] = np.clip(np.rint(out * 255), 0, 255).astype(np.uint8)
    return res


def rows(path=TABLE):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def monster_looks(root=MONSTERS):
    """{monster name: lookType} of the XML files under server/data/monster/monsters/chaos"""
    import re
    out = {}
    for dp, _dn, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith('.xml'):
                with open(os.path.join(dp, f), encoding='utf-8') as fh:
                    t = fh.read()
                m = re.search(r'<monster\s[^>]*name="([^"]+)"', t)
                lk = re.search(r'<look\s[^>]*type="(\d+)"', t)
                if m and lk:
                    out[m.group(1)] = int(lk.group(1))
    return out


def problems(table=None, monsters=None):
    """What is wrong with the table: shift range, mode, one row per monster, the colours of one look MIN_APART degrees apart
    (the source hue counts as one of them in mode hue), and (committed table, or `monsters` given) the row's look is the one
    the monster's file names today."""
    t = rows() if table is None else table
    out, seen, by = [], set(), {}
    for r in t:
        sh = int(r['hue_shift'])
        if not 0 <= sh < 360:
            out.append('%s: hue_shift %d outside 0..359' % (r['monster'], sh))
        if r['mode'] not in ('hue', 'tint'):
            out.append('%s: mode %s' % (r['monster'], r['mode']))
        if r['monster'] in seen:
            out.append('%s is on two rows' % r['monster'])
        seen.add(r['monster'])
        by.setdefault(r['look'], []).append(r)
    for look, rs in by.items():
        hs = [(int(r['hue_shift']) + (int(r['source_hue']) if r['mode'] == 'hue' else 0)) % 360 for r in rs]
        if rs[0]['mode'] == 'hue':
            hs.append(int(rs[0]['source_hue']))
        for i, a in enumerate(hs):
            for b in hs[i + 1:]:
                d = abs(a - b) % 360
                if min(d, 360 - d) < MIN_APART:
                    out.append('look %s: two colours are less than %d degrees apart (%s)'
                               % (look, MIN_APART, ', '.join(r['monster'] for r in rs)))
                    break
    if table is None or monsters is not None:
        have = monster_looks() if monsters is None else monsters
        for r in t:
            if have.get(r['monster']) != int(r['look']):
                out.append('%s: the table says look %s, its monster file says %s' % (r['monster'], r['look'], have.get(r['monster'])))
    return out


def id_rows(table=None, first=FIRST_NEW):
    """[(monster, look, new_look, hue_shift, mode)] in table order: the row at line n becomes outfit first + n"""
    t = rows() if table is None else table
    return [(r['monster'], int(r['look']), first + i, int(r['hue_shift']), r['mode']) for i, r in enumerate(t)]


def id_texts(table=None, first=FIRST_NEW):
    """(client text, server text) of the two generated id files"""
    ids = id_rows(table, first)
    a = 'monster,look,new_look,hue_shift,mode\n' + ''.join('%s,%d,%d,%d,%s\n' % r for r in ids)
    b = 'monster,look,new_look\n' + ''.join('%s,%d,%d\n' % r[:3] for r in ids)
    return a, b


def write_ids(check=False):
    """write the two id files, or with check compare them; returns the problem lines"""
    a, b = id_texts()
    out = []
    for path, text in ((IDS, a), (SERVER_IDS, b)):
        old = open(path, encoding='utf-8', newline='').read() if os.path.exists(path) else None
        if old != text:
            if check:
                out.append('%s is not up to date (run gen_monster_recolour.py ids)' % os.path.relpath(path, REPO))
            else:
                with open(path, 'w', encoding='utf-8', newline='') as f:
                    f.write(text)
    return out


# ---------------------------------------------------------------- the pair

def build(dat, spr, out_dir, table=None, first=FIRST_NEW, expect_md5=None, log=print):
    """pair in (DAT, SPR; its outfits end at first - 1) -> pair out in OUT_DIR (not there yet): every row of the table is one new
    outfit, a copy of the row's look with recolour() on every sprite. Verified before the rename; returns the new ids."""
    import hashlib
    import random
    import shutil
    import struct
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_outfits import parse_body, build_entry, frame, frames_of
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
    assert od.variant[0] == 'new' and all(od.variant[1:]), 'expected our 10.98 dat: %s' % (od.variant,)
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    nours = len(od.outfits)
    if nours + 1 != first:
        raise SystemExit('the input has %d outfits, the first copy would be %d, not %d: wrong input pair (or already built)'
                         % (nours, nours + 1, first))
    tmp = out_dir.rstrip('/') + '.tmp'
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    cnt = ospr.count
    # the copies: sprites through recolour(), records appended once (identical records share an id)
    recs, newrecs, entries, src = {}, [], [], []
    for i, r in enumerate(t):
        look, shift, mode = int(r['look']), int(r['hue_shift']), r['mode']
        th = od.outfit(look)
        if th is None:
            raise SystemExit('%s: pair has no outfit %d' % (r['monster'], look))
        groups = parse_body(od, th)
        assert all(g.layers == 1 for g in groups), '%s: outfit %d has a colour mask layer, it is no table look' % (r['monster'], look)
        sid_map = {0: 0}
        for g in groups:
            for sid in g.sprites:
                if sid in sid_map:
                    continue
                a = ospr.sprite(sid)
                if a is None or not a[:, :, 3].any():
                    sid_map[sid] = 0
                    continue
                rec = encode_sprite(recolour(a, shift, mode))
                if rec not in recs:
                    newrecs.append(rec)
                    recs[rec] = cnt + len(newrecs)
                sid_map[sid] = recs[rec]
        flags = bytes(od.data[th.raw[0]:th.attr_end])
        entries.append(build_entry(flags, groups, sid_map))
        src.append((first + i, r, th, groups))
    # dat: the copies go after the last outfit
    d = od.data
    ins = od.effects[0].raw[0]
    assert od.outfits[-1].raw[1] == ins
    out = bytearray(d[:ins]) + b''.join(entries) + d[ins:]
    struct.pack_into('<H', out, 6, nours + len(entries))
    with open(os.path.join(tmp, 'Tibia.dat'), 'wb') as f:
        f.write(out)
    # spr: bigger offset table, old records shifted by 4 * new, new records appended
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
    # verify: re-parse, old things byte identical, every slot and frame of every copy is the recoloured source
    md, ms = Dat(os.path.join(tmp, 'Tibia.dat')), Spr(os.path.join(tmp, 'Tibia.spr'))
    assert md.variant == od.variant and ms.alpha == ospr.alpha and ms.signature == ospr.signature
    assert md.counts == (od.counts[0], nours + len(entries), od.counts[2], od.counts[3]), md.counts
    assert ms.count == cnt + nn and md.max_sprite <= ms.count
    assert md.data[:6] == d[:6] and md.data[8:ins] == d[8:ins], 'items or old outfits changed'
    assert md.data[ins + sum(map(len, entries)):] == d[ins:], 'effects or missiles changed'
    nslots = nframes = 0
    for nid, r, th, groups in src:
        tm = md.outfit(nid)
        mg = parse_body(md, tm)
        assert md.data[tm.raw[0]:tm.attr_end] == d[th.raw[0]:th.attr_end], (nid, 'flags')
        assert len(mg) == len(groups), nid
        for g, h in zip(groups, mg):
            assert (g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim) == \
                   (h.gtype, h.w, h.h, h.exact, h.layers, h.px, h.py, h.pz, h.phases, h.anim), (nid, 'group')
            for s0, s1 in zip(g.sprites, h.sprites):
                x, y = ospr.sprite(s0), ms.sprite(s1)
                x = None if x is None or not x[:, :, 3].any() else recolour(x, int(r['hue_shift']), r['mode'])
                assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), (nid, s0, s1)
                nslots += 1
            for (xx, yy, zz, ph) in frames_of(g):
                a, b = frame(g, ospr, xx, yy, zz, ph), frame(h, ms, xx, yy, zz, ph)
                assert a.shape == b.shape and np.array_equal(a[..., 3], b[..., 3]), (nid, 'frame alpha', xx, yy, zz, ph)
                nframes += 1
    random.seed(1)
    for sid in random.sample(range(1, cnt + 1), min(3000, cnt)) + [1, cnt]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    log('verified: %d outfits %d to %d, %d sprite slots and %d frames equal the recoloured source, %d records appended (%d -> %d), '
        'every old outfit, item, effect, missile and 3000 sampled old sprites unchanged'
        % (len(entries), first, first + len(entries) - 1, nslots, nframes, nn, cnt, cnt + nn))
    from check_pair import check_append_only
    check_append_only(dat, spr, os.path.join(tmp, 'Tibia.dat'), os.path.join(tmp, 'Tibia.spr'), log=log)
    os.rename(tmp, out_dir)
    return [first + i for i in range(len(entries))]


def live(dat, spr, table=None, first=FIRST_NEW, log=print):
    """the pair holds every copy at its id: same flags, groups and animator as its source look, every sprite the recoloured
    source sprite. Returns the problem lines."""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from import_outfits import parse_body
    t = rows() if table is None else table
    d, s = Dat(dat), Spr(spr)
    if len(d.outfits) < first + len(t) - 1:
        return ['the pair has %d outfits, the copies end at %d' % (len(d.outfits), first + len(t) - 1)]
    out = []
    for i, r in enumerate(t):
        nid = first + i
        src, new = d.outfit(int(r['look'])), d.outfit(nid)
        a, b = parse_body(d, src), parse_body(d, new)
        if d.data[src.raw[0]:src.attr_end] != d.data[new.raw[0]:new.attr_end]:
            out.append('outfit %d (%s): flags differ from outfit %s' % (nid, r['monster'], r['look']))
        if len(a) != len(b) or any((g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim) !=
                                   (h.gtype, h.w, h.h, h.exact, h.layers, h.px, h.py, h.pz, h.phases, h.anim) for g, h in zip(a, b)):
            out.append('outfit %d (%s): frame groups differ from outfit %s' % (nid, r['monster'], r['look']))
            continue
        bad = 0
        for g, h in zip(a, b):
            for s0, s1 in zip(g.sprites, h.sprites):
                x, y = s.sprite(s0), s.sprite(s1)
                x = None if x is None or not x[:, :, 3].any() else recolour(x, int(r['hue_shift']), r['mode'])
                if (x is None) != (y is None) or (x is not None and not np.array_equal(x, y)):
                    bad += 1
        if bad:
            out.append('outfit %d (%s): %d sprites are not the recoloured outfit %s' % (nid, r['monster'], bad, r['look']))
    log('live: %d outfits %d to %d checked, %d problems' % (len(t), first, first + len(t) - 1, len(out)))
    return out


def main(argv):
    if argv[:1] == ['check']:
        p = problems() + write_ids(check=True)
        for line in p:
            print('PROBLEM', line)
        print('monster_recolour: %d rows, %d problems' % (len(rows()), len(p)))
        return 1 if p else 0
    if argv[:1] == ['ids']:
        if '--check' in argv:
            p = write_ids(check=True)
            for line in p:
                print('PROBLEM', line)
            return 1 if p else 0
        write_ids()
        print('monster_recolour: %d ids %d to %d written' % (len(rows()), FIRST_NEW, FIRST_NEW + len(rows()) - 1))
        return 0
    if argv[:1] == ['build'] and len(argv) == 4:
        p = problems()
        if p:
            print('\n'.join(p))
            return 1
        ids = build(argv[1], argv[2], argv[3], expect_md5=DAT_68_MD5)
        print('built %d outfits %d to %d' % (len(ids), ids[0], ids[-1]))
        return 0
    if argv[:1] == ['live'] and len(argv) == 3:
        p = live(argv[1], argv[2])
        for line in p:
            print('PROBLEM', line)
        return 1 if p else 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
