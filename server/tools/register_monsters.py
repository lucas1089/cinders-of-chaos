#!/usr/bin/env python3
"""Add every XML monster in a folder to data/monster/monsters.xml (idempotent).

usage: python3 -I register_monsters.py data/monster/monsters.xml data/monster/monsters/chaos
Lua monsters (data/monster/lua/**) need no registration: the server loads the whole data/monster folder.
"""
import os, re, sys

def main():
    xml_path, folder = sys.argv[1], sys.argv[2]
    t = open(xml_path, encoding='utf-8', errors='ignore').read()
    have = {n.lower() for n in re.findall(r'<monster\s+name="([^"]+)"', t)}
    base = os.path.dirname(xml_path)
    add = []
    for f in sorted(os.listdir(folder)):
        if not f.endswith('.xml'): continue
        m = re.search(r'<monster\s+name="([^"]+)"', open(os.path.join(folder, f), errors='ignore').read())
        if m and m.group(1).lower() not in have:
            rel = os.path.relpath(os.path.join(folder, f), base).replace(os.sep, '/')
            add.append(f'\t<monster name="{m.group(1)}" file="{rel}" />\n'); have.add(m.group(1).lower())
    if add:
        t = t.replace('</monsters>', ''.join(add) + '</monsters>')
        open(xml_path, 'w', encoding='utf-8').write(t)
    print(f'{len(add)} monsters registered')

if __name__ == '__main__':
    main()
