#!/usr/bin/env python3
"""Give the base map's houses Cinders of Chaos names, by house id (server/README.md "Base houses").

usage: python3 -I patch_base_houses.py DATA_DIR [--names CSV] [--dry-run]

The names come from server/tools/base_house_names.csv (columns id,name). The house file is
DATA_DIR/world/<mapName>-house.xml (mapName of the config.lua next to DATA_DIR), else the only *-house.xml there.
Every <house ... houseid="N" .../> with a row gets the new name; ids, entries, rents, towns and sizes stay, so the
houses table of the database (owners, rent) is unaffected. The server writes the names it loaded from this file into
the houses table at its next save, which is what the website's house pages read.

A house id of the file without a row keeps its name and is listed; a row whose id is not in the file is listed too.
Idempotent: a second run changes nothing. --dry-run writes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(HERE, 'base_house_names.csv')
HOUSE = re.compile(r'<house\b[^>]*>')


def read_names(path=CSV_PATH):
    names = {}
    with open(path, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            hid, name = (row.get('id') or '').strip(), (row.get('name') or '').strip()
            if not hid or hid.startswith('#'):
                continue
            if not hid.isdigit() or not name or re.search(r'["<>&]', name):
                raise SystemExit('%s: bad row %r' % (path, row))
            if int(hid) in names:
                raise SystemExit('%s: house id %s twice' % (path, hid))
            names[int(hid)] = name
    return names


def house_file(data_dir):
    world = os.path.join(data_dir, 'world')
    cfg = os.path.join(os.path.dirname(os.path.abspath(data_dir)), 'config.lua')
    if os.path.isfile(cfg):
        m = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', open(cfg, encoding='utf-8', errors='replace').read(), re.M)
        if m:
            p = os.path.join(world, m.group(1) + '-house.xml')
            if os.path.isfile(p):
                return p
    files = sorted(n for n in os.listdir(world) if n.endswith('-house.xml')) if os.path.isdir(world) else []
    return os.path.join(world, files[0]) if len(files) == 1 else None


def patch(text, names):
    """-> (new text, renamed, total, [ids without a row], [rows not in the file])"""
    seen, missing = set(), []
    n = [0]

    def sub(m):
        tag = m.group(0)
        hid = re.search(r'\bhouseid="(\d+)"', tag)
        if not hid:
            return tag
        hid = int(hid.group(1))
        seen.add(hid)
        want = names.get(hid)
        if want is None:
            missing.append(hid)
            return tag
        new = re.sub(r'(\bname=")[^"]*(")', lambda k: k.group(1) + want + k.group(2), tag, count=1)
        if new != tag:
            n[0] += 1
        return new
    out = HOUSE.sub(sub, text)
    return out, n[0], len(seen), missing, sorted(set(names) - seen)


def main(argv):
    dry = '--dry-run' in argv
    path = CSV_PATH
    if '--names' in argv:
        k = argv.index('--names')
        if k + 1 >= len(argv):
            print(__doc__)
            return 2
        path = argv[k + 1]
        argv = argv[:k] + argv[k + 2:]
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    hf = house_file(args[0])
    if not hf:
        print('no house file found (DATA_DIR/world/<mapName>-house.xml)')
        return 1
    with open(hf, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    out, n, total, missing, unknown = patch(text, read_names(path))
    if missing:
        print('houses without a row (name kept): %s' % ', '.join(map(str, missing[:40])))
    if unknown:
        print('rows whose house is not in %s: %s' % (os.path.basename(hf), ', '.join(map(str, unknown[:40]))))
    print('houses: %d renamed of %d' % (n, total))
    if out == text:
        print('nothing to change')
        return 0
    if dry:
        print('dry run: %s would change' % os.path.basename(hf))
        return 0
    with open(hf, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(out)
    print('%s written' % os.path.basename(hf))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
