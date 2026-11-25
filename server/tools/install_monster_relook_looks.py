#!/usr/bin/env python3
"""Looks that match the name for five hunt monsters (O768): the monsters move to them once the client has pair 86.
install_all.py step `monsterrelooklooks`.

usage: python3 -I install_monster_relook_looks.py DATA_DIR [--dry-run] [--map CSV]

Owner 2026-11-25: "banshee, white lion, hellhound, werelion, leaf golem ficaram ruins ou nao condizentes com o nome". The owner's picks:
Banshee, Werelion and Leaf Golem wear the outfits 3744-3746 of client pair 86 (our own PixelLab drawings from words,
client/tools/sprites/gen_relook_monsters.py), White Lion the stock look 1041 and Hellhound the stock look 3280 (looks of every pair).
server/data/monster/monster_relook_looks.csv names, for each, its old look (the one the committed bounty pool gives a base server monster)
and its new look; White Lion's old look is 1041 too (the donor look 3414 of pair 70 it wears today goes). The step knows a monster that
wears the look an earlier pair's step gave it (a row of monster_recolour_looks.csv, monster_donor_looks.csv, monster_wst_looks.csv,
monster_creature_looks.csv, monster_o619_looks.csv, monster_pixellab_looks.csv or monster_drive_looks.csv): the new look replaces it.
Banshee and White Lion wear donor looks today (3408, 3414), Hellhound, Werelion and Leaf Golem purchased ones (3441, 3444, 3472).

The repository and base files keep the old look, so a server whose client is on an older pair draws what it always did. This step runs
after `monsterdrivelooks` (the last look step: a step after it would meet a look it does not know) and does, only when config.lua
chaosClientPair is 86 or more (client_pair.py PAIR_RELOOK_MONSTERS, README "Client pair guard"):
  * the `<look type="OLD">` of the monster's XML file, or the `lookType = OLD` of its Lua file (`monster.outfit`), anywhere under
    DATA_DIR/monster becomes NEW. The colour fields stay: the new outfits have no colour mask and ignore them; the stock looks
    1041 and 3280 have none either;
  * the row of the monster in DATA_DIR/scripts/chaos/bounty_pool.lua (`look = OLD`, or its copy) becomes `look = NEW`.
A monster with no file, or whose look is none of the old one, an earlier pair's look and the new one, stops the step (exit 1). Below pair 86 the
step prints a WARNING line and changes nothing; a second run changes nothing. --dry-run writes nothing.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_monster_creature_looks as C  # noqa: E402
import install_monster_donor_looks as D  # noqa: E402
import install_monster_drive_looks as V  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import install_monster_wst_looks as P  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_relook_looks.csv')
POOL = R.POOL
MONSTERS = os.path.join('monster')
EARLIER = V.EARLIER + (V.MAP,)   # the maps of the pairs before: a monster of one of them wears that look when this step meets it


def read_map(path=MAP):
    """[(monster, old look, new look)]"""
    return R.read_map(path)


def earlier_looks(paths=EARLIER):
    """{monster: {looks an earlier pair's step gave it}}"""
    return C.earlier_looks(paths)


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
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_RELOOK_MONSTERS, 'monsterrelooklooks')
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
                bad.append('%s: %s has look %s, the map knows %d and %d' % (name, os.path.relpath(p, data_dir),
                                                                           m.group(2) if m else None, old, new))
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
        out, pm, pd = C.retype_pool(text, rows, earlier)
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
