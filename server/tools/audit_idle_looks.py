#!/usr/bin/env python3
"""Audit: does a hunt monster move when it stands still? (O533)

usage: python3 -I audit_idle_looks.py MONSTER_DIR [--spawn SPAWN_XML] [--dat TIBIA.DAT | --idle CSV] [--csv OUT.csv] [--allow CSV] [--walk LUA] [--check]
       python3 -I audit_idle_looks.py --write-idle TIBIA.DAT      # server/data/monster/look_idle.csv
       python3 -I audit_idle_looks.py --write-player-looks DATA_DIR   # server/data/monster/player_looks.csv (outfits, mounts, wings, auras)
       python3 -I audit_idle_looks.py --write-walk-idle [--check]  # client/overlay/modules/game_bossanimate/idle_walk_looks.lua (O534)

Owner 2026-11-12, after the recolour preview of O529: "these monsters standing still have no idle animation? If so, change them
to one that has". A monster draws an idle animation in our client (protocol 10.98, outfit frame groups) when its outfit
  - has an idle frame group with more than one phase ("idle group": the dat's first group of two, drawn while the creature stands), or
  - has the dat attribute animateAlways and more than one phase ("animateAlways": the wings, the idle pulse of pair 61,
    outfit.cpp plays the phases on a clock), or
  - is on the client list of game_bossanimate (`ThingType:setAnimateAlways`, base patch 0189), or
  - is on the generated walk-in-place list of game_bossanimate (O534, idle_walk_looks.lua): one idle phase, walk phases, no player use.
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
WALKLIST = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_bossanimate', 'idle_walk_looks.lua')
PLAYER = os.path.join(REPO, 'server', 'data', 'monster', 'player_looks.csv')
PLAYER_HEADER = ['look', 'source']
# Lua files whose `lookType / male / female = N` fields are outfits a player can wear (gated ones are not in outfits.xml while off)
PLAYER_LUA = ['server/data/scripts/chaos/chaos_constants.lua', 'server/data/scripts/chaos/exclusives_config.lua',
              'server/data/lib/chaos_pack37_looks.lua']
HEADER = ['look', 'idle', 'phases', 'frames', 'how', 'walk', 'walk_frames']
ALLOW_HEADER = ['name', 'look', 'reason']


def client_list(path=BOSSANIMATE):
    """The looks game_bossanimate sets animateAlways on at every game start (L.LOOKS)."""
    if not os.path.exists(path):
        return set()
    m = re.search(r'L\.LOOKS\s*=\s*\{([^}]*)\}', open(path, encoding='utf-8').read())
    return {int(x) for x in re.findall(r'\d+', m.group(1))} if m else set()


def picture(group, ph, direction=2):
    """The sprite ids (every layer and tile, one direction) of phase ph of one frame group."""
    w, h, _exact, layers, px, py, pz, phases, sprites = group[:9]
    x = direction if px >= 4 else 0
    pic = []
    for l in range(layers):
        for hh in range(h):
            for ww in range(w):
                pic.append(sprites[((((((ph * pz) * py) * px + x) * layers + l) * h + hh) * w + ww)])
    return tuple(pic)


def distinct_frames(group, direction=2):
    """Number of different pictures among the phases of one frame group (sprite ids of every layer and tile, one direction)."""
    return len({picture(group, ph, direction) for ph in range(group[7])})


def walk_info(thing):
    """(phases, pictures) a creature of this outfit cycles while it stands with animateAlways set (O534).

    The client (outfit.cpp, not ui, no idle animator) draws phase (millis % 1000) / (1000 / N) with N the phases of the walk group's
    animator (a walk group of one phase has none: N is then the total), counted over the groups in file order: phase 0 is the idle
    picture, 1 and up the walk phases. So N pictures at 1000 / N ms each, a whole turn in one second, and the last walk phase is
    skipped. Returns (0, 0) where it cannot work: an idle group of 2 or more phases (the idle animator wins) or a single phase."""
    g = thing.groups
    if len(g) == 2:
        if g[0][7] > 1:
            return 0, 0
        n = g[1][7] if g[1][7] > 1 else g[0][7] + g[1][7]
        pics = []
        for i in range(n):
            pics.append(picture(g[0], i) if i < g[0][7] else picture(g[1], i - g[0][7]))
    else:
        n = g[0][7]
        pics = [picture(g[0], i) for i in range(n)]
    if n < 2:
        return 0, 0
    return n, len(set(pics))


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


def dat_facts(dat_path, looks, walk=None):
    """{look: (idle, phases, frames, how)} for looks, read from the live dat. walk, a dict, gets {look: (walk phases, walk pictures)}."""
    sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
    from datspr import Dat
    d = Dat(dat_path)
    listed = client_list()
    out = {}
    for l in sorted(set(looks)):
        t = d.outfit(l)
        if t is not None:
            out[l] = idle_info(t, listed)
            if walk is not None:
                walk[l] = walk_info(t)
    return out


def write_idle(dat, pool=POOL, path=IDLE, allow_path=ALLOW):
    """Write look_idle.csv: one row per look of the pool (hunt list and bosses) and of the allow list (met monsters with 3 to 5
    spawn points are not in the pool). Returns the number of rows."""
    text = open(pool, encoding='utf-8').read()
    looks = {int(x) for x in re.findall(r'\blook = (\d+)', text)}
    looks |= {l for l, _ in load_allow(allow_path).values()}
    looks |= {new for _old, new in S.load_donor().values()}   # the donor looks of pair 70 (O538) are worn above it
    looks |= {new for _old, new in S.load_purchased().values()}     # and the purchased looks of pair 71 (O540)
    walk = {}
    facts = dat_facts(dat, looks, walk)
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(HEADER)
        for l, (idle, phases, frames, how) in sorted(facts.items()):
            w.writerow([l, 'yes' if idle else 'no', phases, frames, how, walk[l][0], walk[l][1]])
    return len(facts)


def load_walk(path=IDLE):
    """{look: (walk phases, walk pictures)} of look_idle.csv: what walk-in-place would draw (0, 0: it cannot)."""
    out = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
            out[int(r['look'])] = (int(r.get('walk') or 0), int(r.get('walk_frames') or 0))
    return out


def load_player(path=PLAYER):
    """{look: source} of player_looks.csv: every look a player can wear (outfit, mount, wings, aura)."""
    out = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
            out[int(r['look'])] = r['source']
    return out


def player_looks(data_dir):
    """{look: source} read from an installed server's data folder (XML/outfits.xml, mounts.xml, wings.xml, auras.xml) and from the
    Lua files of the repository that name outfits behind a switch (PLAYER_LUA)."""
    out = {}
    for fn, attr in (('outfits', 'looktype'), ('mounts', 'clientid'), ('wings', 'clientid'), ('auras', 'clientid')):
        p = os.path.join(data_dir, 'XML', fn + '.xml')
        if os.path.exists(p):
            for m in re.findall(r'\b%s="(\d+)"' % attr, open(p, encoding='utf-8').read(), flags=re.I):
                out.setdefault(int(m), fn + '.xml')
    for rel in PLAYER_LUA:
        p = os.path.join(REPO, rel)
        if os.path.exists(p):
            for m in re.findall(r'\b(?:lookType|male|female)\s*=\s*(\d+)', open(p, encoding='utf-8').read()):
                out.setdefault(int(m), os.path.basename(rel))
    return out


def write_player(data_dir, path=PLAYER):
    out = player_looks(data_dir)
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(PLAYER_HEADER)
        for l, s in sorted(out.items()):
            w.writerow([l, s])
    return len(out)


def walk_idle_looks(idle, walk, player):
    """Sorted looks that walk in place while they stand (O534): no idle animation of their own, one idle phase and a walk group that
    draws 2 or more pictures (walk_info), and no player can wear the look."""
    return sorted(l for l, (yes, _p, _f, _how) in idle.items()
                  if not yes and walk.get(l, (0, 0))[1] >= 2 and l not in player)


def with_copies(looks, recolour=None):
    """The list plus the hue shifted copy (O531, pair 69) of every look on it: a monster that wears its copy walks in place like the
    original. Each id once, sorted."""
    rec = S.load_recolour() if recolour is None else recolour
    have = set(looks)
    return sorted(have | {new for (old, new) in rec.values() if old in have})


def render_walk(looks):
    """The text of idle_walk_looks.lua: deterministic, sorted, 16 ids a line."""
    rows = ['\t' + ', '.join(str(l) for l in looks[i:i + 16]) + ',' for i in range(0, len(looks), 16)]
    return ('-- Generated by server/tools/audit_idle_looks.py --write-walk-idle from server/data/monster/look_idle.csv and\n'
            '-- player_looks.csv (O534). Do not edit. Monster looks with one idle phase and a walk group that play their walk\n'
            '-- phases in place while the creature stands (game_bossanimate, ThingType:setAnimateAlways, base patch 0189).\n'
            '-- Never a look a player can wear (outfits.xml, mounts, wings, auras).\n'
            'IdleWalkLooks = {\n' + '\n'.join(rows) + '\n}\n')


def load_walklist(path=WALKLIST):
    """The set of looks of idle_walk_looks.lua."""
    if not os.path.exists(path):
        return set()
    m = re.search(r'IdleWalkLooks\s*=\s*\{([^}]*)\}', open(path, encoding='utf-8').read())
    return {int(x) for x in re.findall(r'\d+', re.sub(r'--[^\n]*', '', m.group(1)))} if m else set()


def write_walk(path=WALKLIST):
    looks = with_copies(walk_idle_looks(load_idle(), load_walk(), load_player()))
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(render_walk(looks))
    return len(looks)


def check_walk(path=WALKLIST):
    """CI rule: the generated list is up to date. Returns the problem lines."""
    want = render_walk(with_copies(walk_idle_looks(load_idle(), load_walk(), load_player())))
    have = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
    return [] if have == want else ['%s is not up to date (run server/tools/audit_idle_looks.py --write-walk-idle)'
                                    % os.path.relpath(path, REPO)]


def load_allow(path=ALLOW):
    """{monster name: (look, reason)} of no_idle_allow.csv."""
    out = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, newline='', encoding='utf-8')):
            out[r['name']] = (int(r['look']), r['reason'])
    return out


def donor_rows(rows, pair, donor=None, purchased=None):
    """(rows, names): the pool rows as a server on client `pair` wears them. From pair 70 a monster of the donor map (O538,
    monster_donor_looks.csv) wears its new look, from pair 71 a monster of the purchased map (O540, monster_wst_looks.csv) its new look
    (over its donor look: Bonepicker, Wan Sentry); names is the set of those monsters (their rows of the allow lists are for the old look)."""
    import client_pair
    donor = S.load_donor() if donor is None else donor
    purchased = S.load_purchased() if purchased is None else purchased
    if pair is None or pair < client_pair.PAIR_DONOR:
        return rows, set()
    names = set()
    out = []
    for r in rows:
        chain = [m[r['name']] for m, need in ((donor, client_pair.PAIR_DONOR), (purchased, client_pair.PAIR_PURCHASED)) if r['name'] in m and pair >= need]
        if chain and r['look'] in {x for d in chain for x in d} | {d[0] for d in chain}:
            r = dict(r, look=chain[-1][1])
            names.add(r['name'])
        out.append(r)
    return out, names


def check_pool(pool=POOL, allow_path=ALLOW, idle=None, walk=None, pair=None, donor=None, purchased=None):
    """CI rule: every monster of the bounty pool hunt list wears a look with an idle animation (or one on the generated walk in
    place list, O534), or is a row of the allow list with the look it wears. Returns the problem lines.

    `pair` None reads the committed pool as it is (the looks below pair 70); a pair of 70 or more reads it as that pair draws it: a
    monster of the donor map (from 70) or of the purchased map (from 71) wears its new look, must move on it, and its allow row (for the
    old look) is not asked for."""
    idle = load_idle() if idle is None else idle
    walk = load_walklist() if walk is None else walk
    allow = load_allow(allow_path)
    out, seen = [], set()
    prow, moved = donor_rows(S.pool_rows(pool), pair, donor, purchased)
    for r in prow:
        name, look = r['name'], r['look']
        if not look:
            continue    # an item look (lookTypeEx) is not an outfit
        seen.add(name)
        if name in moved:
            if look not in idle:
                out.append('look %d of %s is not in server/data/monster/look_idle.csv (run tools/audit_idle_looks.py --write-idle Tibia.dat)'
                           % (look, name))
            elif not (idle[look][0] or look in walk):
                out.append('%s wears the new look %d at pair %d, which has no idle animation (%s): it must move while it stands'
                           % (name, look, pair, idle[look][3]))
            continue
        if look not in idle:
            out.append('look %d of %s is not in server/data/monster/look_idle.csv (run tools/audit_idle_looks.py --write-idle Tibia.dat)'
                       % (look, name))
        elif idle[look][0] or look in walk:
            if name in allow:
                out.append('%s wears look %d, which moves while it stands: remove its row of server/data/monster/no_idle_allow.csv'
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


def check_crowded(pool=POOL, allow_path=CROWDED, pair=None, donor=None, purchased=None):
    """CI rule on the bounty pool hunt list (read at `pair` as check_pool does)."""
    by = {}
    for r in donor_rows(S.pool_rows(pool), pair, donor, purchased)[0]:
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
    if '--write-player-looks' in args:
        print('player_looks.csv: %d looks' % write_player(opt('--write-player-looks')))
        return 0
    if '--write-walk-idle' in args:
        if '--check' in args:
            probs = check_walk()
            for p in probs:
                print(p)
            return 1 if probs else 0
        print('idle_walk_looks.lua: %d looks' % write_walk())
        return 0
    spawn, dat, outcsv, allow_path, idle_path = opt('--spawn'), opt('--dat'), opt('--csv'), opt('--allow'), opt('--idle')
    walk_path = opt('--walk')
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
    walked = load_walklist(walk_path or WALKLIST)
    rows, bad = [], 0
    for m in sorted(met, key=lambda m: -sp[m['name']]):
        f = facts.get(m['look'])
        if f is None:
            rows.append([m['name'], m['look'], sp[m['name']], '', 'UNKNOWN', 'the look is not in the dat'])
            bad += 1
        elif not f[0] and m['look'] not in walked:
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
