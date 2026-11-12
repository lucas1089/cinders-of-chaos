#!/usr/bin/env python3
"""Purchased creature looks for hunt monsters (O540): the monsters move to them once the client has pair 71. install_all.py step
`monsterwstlooks`.

usage: python3 -I install_monster_wst_looks.py DATA_DIR [--dry-run] [--map CSV]

Client pair 71 holds 77 creature outfits made from the purchased packs (client/tools/sprites/gen_wst_outfits.py, README "Purchased
monster looks (O540)"). server/data/monster/monster_wst_looks.csv names, for each monster that wears one, its old look (the one the committed
bounty pool gives it) and its new look (the outfit id, 3434 to 3510). The rows are the `purchased` rows of
client/tools/sprites/monster_looks/picks.csv. Two monsters of the map (Bonepicker, Wan Sentry) wear a donor look at pair 70
(monster_donor_looks.csv, step `monsterdonorlooks`): the purchased look replaces it, so their file may hold the old look or the donor look.

The repository files keep the old look, so a server whose client is on an older pair draws what it always did. This step runs
after `monsterdonorlooks` and does, only when config.lua chaosClientPair is 71 or more (client_pair.py, README "Client pair guard"):
  * the `<look type="OLD">` of the monster's XML file, or the `lookType = OLD` of its Lua file (`monster.outfit`), anywhere under
    DATA_DIR/monster (our files and the base server's) becomes NEW (a monster that wears its donor look instead goes the same way). The
    colour fields stay: an outfit with no colour mask ignores them, and gen_bounty_pool.py gives the committed pool back from them;
  * the row of the monster in DATA_DIR/scripts/chaos/bounty_pool.lua (`look = OLD`, or the donor look) becomes `look = NEW`; the
    bounty board shows the outfit; gen_bounty_pool.py turns the new look back to the old one, so the committed pool stays the same.
A monster with no file, or whose look is none of the old, the donor and the new one, stops the step (exit 1). Below pair 71 the step
prints a WARNING line and changes nothing; a second run changes nothing. --dry-run writes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_monster_donor_looks as D  # noqa: E402
import install_monster_recolour as R  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_wst_looks.csv')
DONOR_MAP = D.MAP
POOL = R.POOL
MONSTERS = os.path.join('monster')


def read_map(path=MAP):
    """[(monster, old look, new look)]"""
    return R.read_map(path)


def donor_looks(path=DONOR_MAP):
    """{monster: donor look} of the donor map (the look a monster of both maps wears at pair 70)"""
    if not os.path.exists(path):
        return {}
    with open(path, newline='', encoding='utf-8') as f:
        return {r['monster']: int(r['new_look']) for r in csv.DictReader(f)}


def retype_xml(text, olds, new):
    """(new text, state): 'moved' (one of olds -> new), 'done' (already new) or 'other' (none of them; text unchanged)"""
    m = R.LOOK_TAG.search(text)
    if not m:
        return text, 'other'
    cur = int(m.group(2))
    if cur == new:
        return text, 'done'
    if cur not in olds:
        return text, 'other'
    return text[:m.start(2)] + str(new) + text[m.end(2):], 'moved'


def retype_lua(text, olds, new):
    """(new text, state) as retype_xml, for the `monster.outfit = { lookType = N }` of a Lua monster"""
    m = D.LUA_OUTFIT.search(text)
    if not m:
        return text, 'other'
    cur = int(m.group(2))
    if cur == new:
        return text, 'done'
    if cur not in olds:
        return text, 'other'
    return text[:m.start(2)] + str(new) + text[m.end(2):], 'moved'


def retype_pool(text, rows, donor):
    """(new text, rows moved, rows done): `look = OLD` (or the donor look) of every pool row of a monster of the map becomes `look = NEW`"""
    moved = done = 0
    for name, old, new in rows:
        rx = re.compile(r'(\{name = "%s",[^}]*?\blook = )(\d+)\b' % re.escape(name))
        m = rx.search(text)
        if not m:
            continue
        cur = int(m.group(2))
        if cur == new:
            done += 1
        elif cur in {old, donor.get(name)}:
            text = text[:m.start(2)] + str(new) + text[m.end(2):]
            moved += 1
    return text, moved, done


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
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_PURCHASED, 'monsterwstlooks')
    print(why)
    if not ok:
        return 0
    rows = read_map(path)
    donor = donor_looks()
    files = D.definitions(os.path.join(data_dir, MONSTERS), {r[0] for r in rows})
    bad, moved, done, writes = [], 0, 0, []
    for name, old, new in rows:
        if name not in files:
            bad.append('%s: no monster file under %s' % (name, MONSTERS))
            continue
        olds = {old, donor.get(name)}
        for p, kind in files[name]:   # a name defined twice (ours and the base's) moves in both
            with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
                text = f.read()
            out, state = (retype_xml if kind == 'xml' else retype_lua)(text, olds, new)
            if state == 'other':
                m = (R.LOOK_TAG if kind == 'xml' else D.LUA_OUTFIT).search(text)
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
        out, pm, pd = retype_pool(text, rows, donor)
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
