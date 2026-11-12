#!/usr/bin/env python3
"""Audit: does a hunt monster move when it stands still? (O533)

usage: python3 -I audit_idle_looks.py MONSTER_DIR [--spawn SPAWN_XML] [--dat TIBIA.DAT | --idle CSV] [--csv OUT.csv] [--allow CSV] [--check]
       python3 -I audit_idle_looks.py --write-idle TIBIA.DAT      # server/data/monster/look_idle.csv

Owner 2026-11-12, after the recolour preview of O529: "these monsters standing still have no idle animation? If so, change them
to one that has". A monster draws an idle animation in our client (protocol 10.98, outfit frame groups) when its outfit
  - has an idle frame group with more than one phase ("idle group": the dat's first group of two, drawn while the creature stands), or
  - has the dat attribute animateAlways and more than one phase ("animateAlways": the wings, the idle pulse of pair 61,
    outfit.cpp plays the phases on a clock), or
  - is on the client list of game_bossanimate (`ThingType:setAnimateAlways`, base patch 0189).
A look with one idle phase draws one picture while the creature stands, however many walk phases it has. The phases must also
differ: `frames` counts the distinct idle pictures (by sprite ids, facing south) and must be 2 or more.

MONSTER_DIR is the data/monster folder of an installed server (base files and ours); the monsters, the spawn counts (--spawn: the
map's spawn file, and the bounty pool) and the met rule (3 or more spawn points) are those of audit_shared_looks.py. --dat reads
the facts from the live dat (needs client/tools/sprites/datspr.py); without it look_idle.csv (or --idle CSV) is used. --csv writes one row per
met monster without an idle look. --check fails when such a monster is not on server/data/monster/no_idle_allow.csv.

CI (tools/ci/check_content.py) has no dat and no map: it reads the bounty pool (hunt list, 6 or more spawn points) and
look_idle.csv, one row per pool look written by --write-idle from the live dat. A pool monster whose look has no idle animation
must be a row of no_idle_allow.csv (name, look, reason), the row must name the look the monster wears, and a row of a monster that
has an idle look now is stale. The list may only shrink: a new hunt monster gets a look with an idle animation or a reason.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import audit_shared_looks as S  # noqa: E402

ALLOW = os.path.join(REPO, 'server', 'data', 'monster', 'no_idle_allow.csv')
IDLE = os.path.join(REPO, 'server', 'data', 'monster', 'look_idle.csv')
CROWDED = os.path.join(REPO, 'server', 'data', 'monster', 'crowded_looks_allow.csv')
MAX_ON_LOOK = 2   # owner 2026-11-12 ("strange to reuse the same sprite 5 times"): the original and one recolour
POOL = S.POOL
BOSSANIMATE = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_bossanimate', 'bossanimatelogic.lua')
MIN_MET = S.MIN_MET
HEADER = ['look', 'idle', 'phases', 'frames', 'how']
ALLOW_HEADER = ['name', 'look', 'reason']


def client_list(path=BOSSANIMATE):
    """The looks game_bossanimate sets animateAlways on at every game start (L.LOOKS)."""
    if not os.path.exists(path):
        return set()
    m = re.search(r'L\.LOOKS\s*=\s*\{([^}]*)\}', open(path, encoding='utf-8').read())
    return {int(x) for x in re.findall(r'\d+', m.group(1))} if m else set()


def distinct_frames(group, direction=2):
    """Number of different pictures among the phases of one frame group (sprite ids of every layer and tile, one direction)."""
    w, h, _exact, layers, px, py, pz, phases, sprites = group[:9]
    x = direction if px >= 4 else 0
    seen = set()
    for ph in range(phases):
        pic = []
        for l in range(layers):
            for hh in range(h):
                for ww in range(w):
                    pic.append(sprites[((((((ph * pz) * py) * px + x) * layers + l) * h + hh) * w + ww)])
        seen.add(tuple(pic))
    return len(seen)


def idle_info(thing, listed=()):
    """(idle, phases, frames, how) of an outfit of the dat (datspr.Thing: .groups, .flags, .id).

    how: "idle group", "animateAlways", "client list" or "none"."""
    g = thing.groups
    always = bool(thing.flags.get('animateAlways'))
    if len(g) == 2 and g[0][7] > 1:
        return distinct_frames(g[0]) > 1, g[0][7], distinct_frames(g[0]), 'idle group'
    played = g[1] if len(g) == 2 else g[0]
    if (always or thing.id in listed) and played[7] > 1:
        n = distinct_frames(played)
        return n > 1, played[7], n, 'animateAlways' if always else 'client list'
    return False, g[0][7], 1, 'none'


def load_idle(path=IDLE):
    """{look: (idle, phases, frames, how)} of look_idle.csv."""
    out = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
            out[int(r['look'])] = (r['idle'] == 'yes', int(r['phases']), int(r['frames']), r['how'])
    return out


def dat_facts(dat_path, looks):
    """{look: (idle, phases, frames, how)} for looks, read from the live dat."""
    sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
    from datspr import Dat
    d = Dat(dat_path)
    listed = client_list()
    out = {}
    for l in sorted(set(looks)):
        t = d.outfit(l)
        if t is not None:
            out[l] = idle_info(t, listed)
    return out


def write_idle(dat, pool=POOL, path=IDLE):
    """Write look_idle.csv: one row per look of the pool (hunt list and bosses). Returns the number of rows."""
    text = open(pool, encoding='utf-8').read()
    looks = {int(x) for x in re.findall(r'\blook = (\d+)', text)}
    facts = dat_facts(dat, looks)
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(HEADER)
        for l, (idle, phases, frames, how) in sorted(facts.items()):
            w.writerow([l, 'yes' if idle else 'no', phases, frames, how])
    return len(facts)


def load_allow(path=ALLOW):
    """{monster name: (look, reason)} of no_idle_allow.csv."""
    out = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
            out[r['name']] = (int(r['look']), r['reason'])
    return out


def check_pool(pool=POOL, allow_path=ALLOW, idle=None):
    """CI rule: every monster of the bounty pool hunt list wears a look with an idle animation, or is a row of the allow list
    with the look it wears. Returns the problem lines."""
    idle = load_idle() if idle is None else idle
    allow = load_allow(allow_path)
    out, seen = [], set()
    for r in S.pool_rows(pool):
        name, look = r['name'], r['look']
        if not look:
            continue    # an item look (lookTypeEx) is not an outfit
        seen.add(name)
        if look not in idle:
            out.append('look %d of %s is not in server/data/monster/look_idle.csv (run tools/audit_idle_looks.py --write-idle Tibia.dat)'
                       % (look, name))
        elif idle[look][0]:
            if name in allow:
                out.append('%s wears look %d, which has an idle animation: remove its row of server/data/monster/no_idle_allow.csv'
                           % (name, look))
        elif name not in allow:
            out.append('%s wears look %d, which has no idle animation (%s) and is not on server/data/monster/no_idle_allow.csv; '
                       'give it a look that moves while it stands (O533) or a row with its reason' % (name, look, idle[look][3]))
        elif allow[name][0] != look:
            out.append('%s: no_idle_allow.csv names look %d, the monster wears look %d' % (name, allow[name][0], look))
    return out


def load_crowded(path=CROWDED):
    """[(look, set of names, reason)] of crowded_looks_allow.csv."""
    out = []
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
            out.append((int(r['look']), {n.strip() for n in r['names'].split('|')}, r['reason']))
    return out


def crowded_problems(groups, allow_path=CROWDED):
    """groups: {look: [monster names]}. A look worn by more than MAX_ON_LOOK met hunt monsters needs a row of
    crowded_looks_allow.csv that names every one of them (with a reason)."""
    rows = load_crowded(allow_path)
    out = []
    for look, names in sorted(groups.items()):
        if len(names) > MAX_ON_LOOK and not any(l == look and set(names) <= n for l, n, _ in rows):
            out.append('look %d is worn by %d monsters (%s), at most %d: give the extra ones other looks (with an idle animation) or '
                       'put the look on server/data/monster/crowded_looks_allow.csv with a reason' % (look, len(names), ', '.join(sorted(names)), MAX_ON_LOOK))
    return out


def check_crowded(pool=POOL, allow_path=CROWDED):
    """CI rule on the bounty pool hunt list."""
    by = {}
    for r in S.pool_rows(pool):
        if r['look']:
            by.setdefault(r['look'], []).append(r['name'])
    return crowded_problems(by, allow_path)


def main():
    args = sys.argv[1:]

    def opt(k):
        if k in args:
            i = args.index(k)
            v = args[i + 1]
            del args[i:i + 2]
            return v
        return None
    if '--write-idle' in args:
        print('look_idle.csv: %d looks' % write_idle(opt('--write-idle')))
        return 0
    spawn, dat, outcsv, allow_path, idle_path = opt('--spawn'), opt('--dat'), opt('--csv'), opt('--allow'), opt('--idle')
    check = '--check' in args
    if check:
        args.remove('--check')
    if len(args) != 1:
        print(__doc__)
        return 2
    mons = S.load_monsters(args[0])
    sp = S.spawn_counts(spawn)
    met = [m for m in mons if sp.get(m['name'], 0) >= MIN_MET and m['look'] and not m['ex']]
    facts = dat_facts(dat, {m['look'] for m in met}) if dat else load_idle(idle_path or IDLE)
    allow = load_allow(allow_path or ALLOW)
    rows, bad = [], 0
    for m in sorted(met, key=lambda m: -sp[m['name']]):
        f = facts.get(m['look'])
        if f is None:
            rows.append([m['name'], m['look'], sp[m['name']], '', 'UNKNOWN', 'the look is not in the dat'])
            bad += 1
        elif not f[0]:
            ok = m['name'] in allow and allow[m['name']][0] == m['look']
            bad += 0 if ok else 1
            rows.append([m['name'], m['look'], sp[m['name']], f[1], 'kept' if ok else 'NO IDLE',
                         allow[m['name']][1] if ok else ''])
    if outcsv:
        with open(outcsv, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(['monster', 'look', 'spawns', 'idle phases', 'kept or changed', 'why'])
            w.writerows(rows)
    groups = {}
    for m in met:
        groups.setdefault(m['look'], []).append(m['name'])
    crowded = crowded_problems(groups)
    bad += len(crowded)
    print('%d met monsters, %d without an idle animation, %d not allowed' % (len(met), len(rows), bad))
    for line in crowded:
        print('  ' + line)
    for r in rows:
        if r[4] in ('NO IDLE', 'UNKNOWN'):
            print('  %s (look %s, spawns %s): %s' % (r[0], r[1], r[2], r[4]))
    return 1 if check and bad else 0


if __name__ == '__main__':
    sys.exit(main())
