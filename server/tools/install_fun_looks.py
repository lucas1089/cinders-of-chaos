#!/usr/bin/env python3
"""The new Dusk Moth look of the Dusk Moth pet (O566): the pet moves to it once the client has pair 72. install_all.py step `funlooks`.

usage: python3 -I install_fun_looks.py DATA_DIR [--dry-run]

Client pair 72 holds a new Dusk Moth outfit (id 3523, client/tools/sprites/gen_fun_costumes.py, README "Fun costumes (O566)"): a purple
moth with a smooth wing flap and a hover bob, in place of the stock butterfly look 213 (4 phases at 300 ms). The pet is the monster
"Dusk Moth" (data/monster/monsters/chaos/pets/dusk_moth.xml, species `dusk_moth` of pets_config.lua; its pet id, owners and store offer
stay). Its repository file keeps look 213, so a server whose client is on an older pair draws what it always did. This step runs
after `files` and does, only when config.lua chaosClientPair is 72 or more (client_pair.py, README "Client pair guard"): the
`<look type="213">` of every installed file of the monster named Dusk Moth becomes 3523. The pets window and the store offer read the same
id from data/lib/chaos_fun_costumes.lua (ChaosFunCostumes.mothLook), which reads the same record. A file whose look is neither 213 nor
3523 stops the step (exit 1). Below pair 72 the step prints a WARNING line and changes nothing; a second run changes nothing.
--dry-run writes nothing.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_monster_donor_looks as D  # noqa: E402
import install_monster_recolour as R  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
LIB = os.path.join(REPO, 'server', 'data', 'lib', 'chaos_fun_costumes.lua')
MONSTER = 'Dusk Moth'


def moth_looks(path=LIB):
    """(old look, new look) of the Dusk Moth from chaos_fun_costumes.lua `M.moth = {old = N, look = N}`"""
    m = re.search(r'^M\.moth\s*=\s*\{old\s*=\s*(\d+),\s*look\s*=\s*(\d+)\}', open(path, encoding='utf-8').read(), re.M)
    if not m:
        raise SystemExit('%s: no M.moth line' % path)
    return int(m.group(1)), int(m.group(2))


def retype(text, old, new):
    """(new text, state): 'moved' (old -> new), 'done' (already new) or 'other' (text unchanged)"""
    m = R.LOOK_TAG.search(text)
    if not m:
        return text, 'other'
    cur = int(m.group(2))
    if cur == new:
        return text, 'done'
    if cur != old:
        return text, 'other'
    return text[:m.start(2)] + str(new) + text[m.end(2):], 'moved'


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    lib = LIB
    if '--lib' in args:
        i = args.index('--lib')
        lib = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_FUN, 'funlooks')
    print(why)
    if not ok:
        return 0
    old, new = moth_looks(lib)
    files = D.definitions(os.path.join(data_dir, 'monster'), {MONSTER}).get(MONSTER, [])
    if not files:
        print('no monster file of %s under monster' % MONSTER)
        return 1
    bad, moved, done = [], 0, 0
    for p, _kind in files:
        with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        out, state = retype(text, old, new)
        if state == 'other':
            bad.append('%s: look %s, expected %d or %d' % (os.path.relpath(p, data_dir), R.LOOK_TAG.search(text).group(2), old, new))
        elif state == 'moved':
            moved += 1
            if not dry:
                with open(p, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                    f.write(out)
        else:
            done += 1
    for line in bad:
        print(line)
    print('Dusk Moth files: %d moved to look %d, %d already there%s' % (moved, new, done, ' (dry run)' if dry else ''))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
