#!/usr/bin/env python3
"""Write the hashed list of the monster types a fresh base server defines.

usage: python3 -I hash_base_monsters.py BASE_DATA_DIR [--out PATH] [--check]

BASE_DATA_DIR is the data folder of an untouched base server (before install_all.py). A type is a name registered in
data/monster/monsters.xml or created by Game.createMonsterType in a Lua file under data/monster. Each name is written
as the SHA-256 of its lower-case form (the same key as data/monster/base_monster_names.csv), one per line, sorted, so
the repository holds no base name. Default output: server/data/monster/base_monster_hashes.txt.
tools/ci/check_content.py reads the list: a Chaos monster must not take the name of a base type (a second
registration of a name is skipped by register_monsters.py, and a Lua type of the same name refills ours at load),
and a summon must name a type that exists.
--check changes nothing and exits 1 when the file differs from what the data gives.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
from patch_base_monster_names import digest, SKIP_DIRS

OUT = os.path.join(os.path.dirname(HERE), 'data', 'monster', 'base_monster_hashes.txt')


def base_types(data):
    names = set()
    mxml = os.path.join(data, 'monster', 'monsters.xml')
    if not os.path.isfile(mxml):
        raise SystemExit('missing ' + mxml)
    with open(mxml, encoding='utf-8', errors='ignore') as f:
        names |= {n.lower() for n in re.findall(r'<monster\s+name="([^"]+)"', f.read())}
    for dirpath, dirs, files in os.walk(os.path.join(data, 'monster')):
        dirs.sort()
        rel = os.path.relpath(dirpath, data)
        if any(rel == d or rel.startswith(d + os.sep) for d in SKIP_DIRS) or rel.split(os.sep)[-1] == 'chaos':
            dirs[:] = []
            continue
        for fn in sorted(files):
            if fn.endswith('.lua'):
                with open(os.path.join(dirpath, fn), encoding='utf-8', errors='ignore') as f:
                    names |= {(a or b).lower() for a, b in
                              re.findall(r'createMonsterType\(\s*(?:"([^"]+)"|\'([^\']+)\')', f.read())}
    return names


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    out = OUT
    if '--out' in argv:
        out = argv[argv.index('--out') + 1]
        args.remove(out)
    if len(args) != 1:
        raise SystemExit(__doc__)
    text = ''.join(h + '\n' for h in sorted({digest(n) for n in base_types(args[0])}))
    old = open(out, encoding='utf-8').read() if os.path.exists(out) else None
    if '--check' in argv:
        print('base monster hashes:', 'up to date' if old == text else 'OUT OF DATE')
        return 0 if old == text else 1
    if old != text:
        with open(out, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    print('%d base monster types -> %s' % (text.count('\n'), out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
