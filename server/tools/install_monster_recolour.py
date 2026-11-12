#!/usr/bin/env python3
"""Hue shifted copies of 52 monster outfits (O531): the monsters move to them once the client has pair 69. install_all.py step
`monsterrecolour`.

usage: python3 -I install_monster_recolour.py DATA_DIR [--dry-run] [--map CSV]

Client pair 69 holds a hue shifted copy of 35 monster outfits that have no colour mask, one copy per monster that shared the
outfit with another (client/tools/sprites/gen_monster_recolour.py, README "Monster recolours (O531)"). server/data/monster/
monster_recolour_looks.csv names, for each of the 52 monsters, its old look and its new look (the copy's outfit id, 3371 to 3422).

The repository files keep the old look, so a server whose client is on an older pair draws what it always did. This step runs
after `monsters` (which copies the files) and does, only when config.lua chaosClientPair is 69 or more (client_pair.py, README
"Client pair guard"):
  * <look type="OLD"> of the monster's file under DATA_DIR/monster/monsters/chaos becomes type="NEW" (colours stay);
  * the row of the monster in DATA_DIR/scripts/chaos/bounty_pool.lua (`look = OLD`) becomes `look = NEW` (the bounty board shows the
    outfit); gen_bounty_pool.py turns a copy back to the old look, so the committed pool stays the same.
A monster file that is missing, or whose look is neither the old nor the new one, stops the step (exit 1): the map names the
monsters by their files, and a changed look needs a new row (the CI check `gen_monster_recolour.py check` holds the map to the
repository files). Below pair 69 the step prints a WARNING line and changes nothing; a second run changes nothing.
--dry-run writes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_recolour_looks.csv')
POOL = os.path.join('scripts', 'chaos', 'bounty_pool.lua')
OURS = os.path.join('monster', 'monsters', 'chaos')


def read_map(path=MAP):
    """[(monster, old look, new look)]"""
    with open(path, newline='', encoding='utf-8') as f:
        return [(r['monster'], int(r['look']), int(r['new_look'])) for r in csv.DictReader(f)]


def monster_files(root):
    """{monster name: path} of every XML under root"""
    out = {}
    for dp, _dn, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith('.xml'):
                p = os.path.join(dp, f)
                with open(p, encoding='utf-8', errors='surrogateescape') as fh:
                    m = re.search(r'<monster\s[^>]*name="([^"]+)"', fh.read(4096))
                if m:
                    out[m.group(1)] = p
    return out


LOOK_TAG = re.compile(r'(<look\s[^>]*?\btype\s*=\s*")(\d+)(")')


def retype_xml(text, old, new):
    """(new text, state): state is 'moved' (old -> new), 'done' (already new) or 'other' (neither; text unchanged)"""
    m = LOOK_TAG.search(text)
    if not m:
        return text, 'other'
    cur = int(m.group(2))
    if cur == new:
        return text, 'done'
    if cur != old:
        return text, 'other'
    return text[:m.start(2)] + str(new) + text[m.end(2):], 'moved'


def retype_pool(text, rows):
    """(new text, rows moved, rows done): `look = OLD` of every pool row of a monster of the map becomes `look = NEW`"""
    moved = done = 0
    for name, old, new in rows:
        rx = re.compile(r'(\{name = "%s",[^}]*?\blook = )(\d+)\b' % re.escape(name))
        m = rx.search(text)
        if not m:
            continue
        cur = int(m.group(2))
        if cur == new:
            done += 1
        elif cur == old:
            text = text[:m.start(2)] + str(new) + text[m.end(2):]
            moved += 1
    return text, moved, done


def write(path, text):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)
    os.replace(tmp, path)


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
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_RECOLOUR, 'monsterrecolour')
    print(why)
    if not ok:
        return 0
    rows = read_map(path)
    files = monster_files(os.path.join(data_dir, OURS))
    bad, moved, done, writes = [], 0, 0, []
    for name, old, new in rows:
        p = files.get(name)
        if p is None:
            bad.append('%s: no file under %s' % (name, OURS))
            continue
        with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        out, state = retype_xml(text, old, new)
        if state == 'other':
            m = LOOK_TAG.search(text)
            bad.append('%s: %s has look %s, the map knows %d and %d' % (
                name, os.path.relpath(p, data_dir), m.group(2) if m else 'none', old, new))
        elif state == 'moved':
            moved += 1
            writes.append((p, out))
        else:
            done += 1
    print('monster files: %d moved to their copy, %d already there' % (moved, done))
    pool = os.path.join(data_dir, POOL)
    if os.path.exists(pool):
        with open(pool, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        out, pm, pd = retype_pool(text, rows)
        print('bounty_pool.lua: %d rows moved to their copy, %d already there' % (pm, pd))
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
        write(p, text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
