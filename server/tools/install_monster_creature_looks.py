#!/usr/bin/env python3
"""Creature pack looks for 11 monsters (O605): the monsters move to them once the client has pair 73. install_all.py step
`monstercreaturelooks`.

usage: python3 -I install_monster_creature_looks.py DATA_DIR [--dry-run] [--map CSV]

Client pair 73 holds 9 creature outfits, 2x2, made from eight creature packs of one author (client/tools/sprites/
gen_creature_outfits.py, README "Creature pack looks (O605)"). server/data/monster/monster_creature_looks.csv names, for each monster
that wears one, its old look (the one its file in the repository has, or for a base server monster the one the committed bounty pool
gives it) and its new look (the outfit id, 3527 to 3535). The rows are the `creature` rows of
client/tools/sprites/monster_looks/picks.csv: six hunt monsters (two of them base server monsters), three bosses and the two
Ascended forms of the Omen bosses. Rimecairn wears a hue shifted copy of its old look since pair 69 (monster_recolour_looks.csv,
step `monsterrecolour`): the new look replaces it, so its file may hold the old look or the copy.

The repository files keep the old look, so a server whose client is on an older pair draws what it always did. This step runs
after `funlooks` and does, only when config.lua chaosClientPair is 73 or more (client_pair.py, README "Client pair guard"):
  * the `<look type="OLD">` of the monster's XML file, or the `lookType = OLD` of its Lua file (`monster.outfit`), anywhere under
    DATA_DIR/monster (our files and the base server's) becomes NEW. The colour fields stay: the new outfits have no colour mask and
    ignore them, and gen_bounty_pool.py gives the committed pool back from them;
  * the row of the monster in DATA_DIR/scripts/chaos/bounty_pool.lua (`look = OLD`, or its copy) becomes `look = NEW`; a boss has
    no row there; gen_bounty_pool.py turns the new look back to the old one, so the committed pool stays the same.
A monster with no file, or whose look is none of the old one, its copy and the new one, stops the step (exit 1). Below pair 73 the
step prints a WARNING line and changes nothing; a second run changes nothing. --dry-run writes nothing.
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
import install_monster_wst_looks as P  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_creature_looks.csv')
POOL = R.POOL
MONSTERS = os.path.join('monster')
EARLIER = (R.MAP, D.MAP, P.MAP)   # the maps of the pairs before: a monster of one of them wears that look when this step meets it


def read_map(path=MAP):
    """[(monster, old look, new look)]"""
    return R.read_map(path)


def earlier_looks(paths=EARLIER):
    """{monster: {looks an earlier pair's step gave it}}"""
    out = {}
    for p in paths:
        if os.path.exists(p):
            with open(p, newline='', encoding='utf-8') as f:
                for r in csv.DictReader(f):
                    out.setdefault(r['monster'], set()).add(int(r['new_look']))
    return out


def retype_pool(text, rows, earlier):
    """(new text, rows moved, rows done): `look = OLD` (or an earlier pair's look) of every pool row of a monster of the map becomes
    `look = NEW`; a monster with no row (a boss) is passed over"""
    moved = done = 0
    for name, old, new in rows:
        rx = re.compile(r'(\{name = "%s",[^}]*?\blook = )(\d+)\b' % re.escape(name))
        m = rx.search(text)
        if not m:
            continue
        cur = int(m.group(2))
        if cur == new:
            done += 1
        elif cur in {old} | earlier.get(name, set()):
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
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_CREATURE, 'monstercreaturelooks')
    print(why)
    if not ok:
        return 0
    rows = read_map(path)
    earlier = earlier_looks()
    files = D.definitions(os.path.join(data_dir, MONSTERS), {r[0] for r in rows})
    bad, moved, done, writes = [], 0, 0, []
    for name, old, new in rows:
        if name not in files:
            bad.append('%s: no monster file under %s' % (name, MONSTERS))
            continue
        olds = {old} | earlier.get(name, set())
        for p, kind in files[name]:   # a name defined twice (ours and the base's) moves in both
            with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
                text = f.read()
            out, state = (P.retype_xml if kind == 'xml' else P.retype_lua)(text, olds, new)
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
        out, pm, pd = retype_pool(text, rows, earlier)
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
