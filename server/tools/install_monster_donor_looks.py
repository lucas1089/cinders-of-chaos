#!/usr/bin/env python3
"""Polished donor looks for 28 hunt monsters (O538): the monsters move to them once the client has pair 70. install_all.py step
`monsterdonorlooks`.

usage: python3 -I install_monster_donor_looks.py DATA_DIR [--dry-run] [--map CSV]

Client pair 70 holds 28 polished creature outfits (client/tools/sprites/gen_donor_outfits.py, README "Donor monster looks (O538)").
server/data/monster/monster_donor_looks.csv names, for each of the 28 monsters, its old look (the one the committed bounty pool
gives it) and its new look (the outfit id, 3406 to 3433). The rows are the `donor` rows of client/tools/sprites/monster_looks/picks.csv.

The repository files keep the old look, so a server whose client is on an older pair draws what it always did. This step runs
after `baselooks` and does, only when config.lua chaosClientPair is 70 or more (client_pair.py, README "Client pair guard"):
  * the `<look type="OLD">` of the monster's XML file, or the `lookType = OLD` of its Lua file (`monster.outfit`), anywhere under
    DATA_DIR/monster (our files and the base server's) becomes NEW. The colour fields stay: an outfit with no colour mask ignores them,
    and gen_bounty_pool.py gives the committed pool back from them;
  * the row of the monster in DATA_DIR/scripts/chaos/bounty_pool.lua (`look = OLD`) becomes `look = NEW` (the bounty board shows the
    outfit); gen_bounty_pool.py turns the new look back to the old one, so the committed pool stays the same.
A monster with no file, or whose look is neither the old nor the new one, stops the step (exit 1): the map names the monsters by
their files, and a changed look needs a new row (the CI checks hold the map to the pool and the files). Below pair 70 the step prints
a WARNING line and changes nothing; a second run changes nothing. --dry-run writes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_monster_recolour as R  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_donor_looks.csv')
PURCHASED_MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_wst_looks.csv')
POOL = R.POOL
MONSTERS = os.path.join('monster')
LUA_NAME = re.compile(r'Game\.createMonsterType\(\s*"([^"]+)"\s*\)')
LUA_OUTFIT = re.compile(r'(monster\.outfit\s*=\s*\{.*?\blookType\s*=\s*)(\d+)', re.S)


def read_map(path=MAP):
    """[(monster, old look, new look)]"""
    return R.read_map(path)


def purchased_looks(path=PURCHASED_MAP):
    """{monster: purchased look} of the pair 71 map (O540): a monster of both maps (Bonepicker, Wan Sentry) wears that look once step
    `monsterwstlooks` has run, which is past this step, not a look this step does not know"""
    if not os.path.exists(path):
        return {}
    with open(path, newline='', encoding='utf-8') as f:
        return {r['monster']: int(r['new_look']) for r in csv.DictReader(f)}


def retype_lua(text, old, new):
    """(new text, state) as retype_xml, for the `monster.outfit = { lookType = N }` of a Lua monster"""
    m = LUA_OUTFIT.search(text)
    if not m:
        return text, 'other'
    cur = int(m.group(2))
    if cur == new:
        return text, 'done'
    if cur != old:
        return text, 'other'
    return text[:m.start(2)] + str(new) + text[m.end(2):], 'moved'


def definitions(root, names):
    """{monster name: [(path, kind)]} of the XML (kind 'xml') and Lua (kind 'lua') monster files under root that define a name of names"""
    out = {}
    for dp, _dn, fs in os.walk(root):
        for f in sorted(fs):
            p = os.path.join(dp, f)
            if f.endswith('.xml'):
                with open(p, encoding='utf-8', errors='surrogateescape') as fh:
                    text = fh.read()
                m = re.search(r'<monster\s[^>]*?name="([^"]+)"', text)
                if m and m.group(1) in names and R.LOOK_TAG.search(text):
                    out.setdefault(m.group(1), []).append((p, 'xml'))
            elif f.endswith('.lua'):
                with open(p, encoding='utf-8', errors='surrogateescape') as fh:
                    text = fh.read()
                m = LUA_NAME.search(text)
                if m and m.group(1) in names and LUA_OUTFIT.search(text):
                    out.setdefault(m.group(1), []).append((p, 'lua'))
    return out


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    path = MAP
    if '--map' in args:
        i = args.index('--map')
        path = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_DONOR, 'monsterdonorlooks')
    print(why)
    if not ok:
        return 0
    rows = read_map(path)
    beyond = purchased_looks()
    files = definitions(os.path.join(data_dir, MONSTERS), {r[0] for r in rows})
    bad, moved, done, writes = [], 0, 0, []
    for name, old, new in rows:
        if name not in files:
            bad.append('%s: no monster file under %s' % (name, MONSTERS))
            continue
        for p, kind in files[name]:   # a name defined twice (ours and the base's) moves in both
            with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
                text = f.read()
            out, state = (R.retype_xml if kind == 'xml' else retype_lua)(text, old, new)
            if state == 'other' and int((R.LOOK_TAG if kind == 'xml' else LUA_OUTFIT).search(text).group(2)) == beyond.get(name):
                done += 1   # the purchased look (pair 71) is already on the monster: nothing to move
            elif state == 'other':
                m = (R.LOOK_TAG if kind == 'xml' else LUA_OUTFIT).search(text)
                bad.append('%s: %s has look %s, the map knows %d and %d' % (name, os.path.relpath(p, data_dir), m.group(2), old, new))
            elif state == 'moved':
                moved += 1
                writes.append((p, out))
            else:
                done += 1
    print('monster files: %d moved to their new look, %d already there' % (moved, done))
    pool = os.path.join(data_dir, POOL)
    if os.path.exists(pool):
        with open(pool, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        out, pm, pd = R.retype_pool(text, rows)
        print('bounty_pool.lua: %d rows moved to their new look, %d already there' % (pm, pd))
        if out != text:
            writes.append((pool, out))
    else:
        print('bounty_pool.lua: not installed, skipped')
    for line in bad:
        print('ERROR', line)
    if bad:
        return 1
    if dry:
        print('dry run: nothing written (%d files would change)' % len(writes))
        return 0
    for p, text in writes:
        R.write(p, text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
