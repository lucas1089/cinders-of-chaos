#!/usr/bin/env python3
"""Client module sanity: every module folder has one .otmod, its `name:` matches the folder, and every
entry of `scripts: [...]` exists as a .lua file in the folder."""
import os, re, sys

bad = 0
for base in ('client/overlay/modules', 'client/alternates'):
    if not os.path.isdir(base):
        continue
    for mod in sorted(os.listdir(base)):
        d = os.path.join(base, mod)
        if not os.path.isdir(d):
            continue
        otmods = [f for f in os.listdir(d) if f.endswith('.otmod')]
        if len(otmods) != 1:
            print(f'{d}: expected exactly one .otmod, found {len(otmods)}'); bad += 1; continue
        t = open(os.path.join(d, otmods[0]), encoding='utf-8', errors='ignore').read()
        name = re.search(r'^\s*name:\s*(\S+)', t, re.M)
        if not name or name.group(1) != mod:
            print(f'{d}: module name {name.group(1) if name else None!r} does not match the folder'); bad += 1
        m = re.search(r'scripts:\s*\[([^\]]*)\]', t)
        for s in (x.strip() for x in (m.group(1).split(',') if m else [])):
            if s and not os.path.exists(os.path.join(d, s + '.lua')) and not os.path.exists(os.path.join(d, s)):
                print(f'{d}: script {s!r} not found'); bad += 1
print('module check:', 'OK' if not bad else f'{bad} problem(s)')
sys.exit(1 if bad else 0)
