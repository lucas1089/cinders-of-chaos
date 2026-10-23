#!/usr/bin/env python3
"""Client module sanity: every module folder has one .otmod, its `name:` matches the folder, and every
entry of `scripts: [...]` exists as a .lua file in the folder.
A module script may not read `window.<id>` when <id> sits deeper than a direct child in every .otui of the module:
the engine sets only direct children as fields, so the lookup gives nil (the Candlemarks list once stayed empty)."""
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
        direct, nested = set(), set()
        for f in os.listdir(d):
            if not f.endswith('.otui'):
                continue
            for line in open(os.path.join(d, f), encoding='utf-8', errors='ignore'):
                m = re.match(r'( *)id:\s*(\w+)', line)
                if m and len(m.group(1)) >= 4:
                    (direct if len(m.group(1)) == 4 else nested).add(m.group(2))
        for f in sorted(os.listdir(d)):
            if not f.endswith('.lua') or f.endswith('_test.lua'):
                continue
            src = open(os.path.join(d, f), encoding='utf-8', errors='ignore').read()
            for m in re.finditer(r'\bwindow\.(\w+)', src):
                if m.group(1) in nested - direct:
                    line = src.count('\n', 0, m.start()) + 1
                    print(f'{d}/{f}:{line}: window.{m.group(1)} is not a direct child; use its parent or recursiveGetChildById')
                    bad += 1
print('module check:', 'OK' if not bad else f'{bad} problem(s)')
sys.exit(1 if bad else 0)
