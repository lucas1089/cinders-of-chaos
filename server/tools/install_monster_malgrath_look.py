#!/usr/bin/env python3
"""The outfit of Malgrath, the Drowned Crown, once the client has pair 74 (O637). install_all.py step `monstermalgrathlook`.

usage: python3 -I install_monster_malgrath_look.py DATA_DIR [--dry-run] [--map CSV]

Client pair 74 holds outfit 3530, the boss of a purchased pack drawn on 7x7 tiles that always faces the front
(client/tools/sprites/gen_malgrath_boss.py, README "Malgrath, the Drowned Crown (O637)"). server/data/monster/monster_malgrath_looks.csv
names its old look (the one its file in the repository has) and its new look. Its lair opens only from pair 74 (bosslair_config.lua), so
a client without the outfit never meets it; the old look is the file's valid fallback and is never drawn on a live server.

The repository file keeps the old look. This step runs after `monsterswaplooks` and does, only when config.lua chaosClientPair is 74 or
more (client_pair.py, README "Client pair guard"): the `<look type="OLD">` of the monster's XML file anywhere under DATA_DIR/monster
becomes NEW; colour fields stay. The boss has no row of the bounty pool. A monster with no file, or with a look that is neither the
old one nor the new one, stops the step (exit 1). Below pair 74 the step prints a WARNING line and changes nothing; a second run
changes nothing. --dry-run writes nothing.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_monster_donor_looks as D  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import install_monster_wst_looks as P  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_malgrath_looks.csv')
MONSTERS = 'monster'


def read_map(path=MAP):
    """[(monster, old look, new look)]"""
    return R.read_map(path)


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
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_MALGRATH, 'monstermalgrathlook')
    print(why)
    if not ok:
        return 0
    rows = read_map(path)
    files = D.definitions(os.path.join(data_dir, MONSTERS), {r[0] for r in rows})
    bad, moved, done, writes = [], 0, 0, []
    for name, old, new in rows:
        if name not in files:
            bad.append('%s: no monster file under %s' % (name, MONSTERS))
            continue
        for p, kind in files[name]:
            with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
                text = f.read()
            out, state = (P.retype_xml if kind == 'xml' else P.retype_lua)(text, {old}, new)
            if state == 'other':
                m = (R.LOOK_TAG if kind == 'xml' else D.LUA_OUTFIT).search(text)
                bad.append('%s: %s has look %s, the map knows %d and %d' % (name, os.path.relpath(p, data_dir), m.group(2), old, new))
            elif state == 'moved':
                moved += 1
                writes.append((p, out))
            else:
                done += 1
    print('monster files: %d moved to their new look, %d already there' % (moved, done))
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
