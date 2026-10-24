#!/usr/bin/env python3
"""python3 -I tools/ci/check_assembled.py <assembled-client-dir>: the assembled client (client/tools/assemble_client.sh)
has no two modules of one name (the engine merges them into one, and the /mods copy, discovered last, overwrites the
/modules one) and its game_helper is ours: modules/game_helper with the overlay's .otmod, no mods/game_helper.
Owner report 2026-10-24: the helper had no general Auto setup and no Support tab, as if the base helper still ran."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OVERLAY_OTMOD = os.path.join(HERE, '..', '..', 'client', 'overlay', 'modules', 'game_helper', 'game_helper.otmod')


def modules_of(root):
    """{name: [otmod path, ...]} over modules/*/ and mods/*/ (one folder level, like the engine's discoverModules)."""
    found = {}
    for top in ('modules', 'mods'):
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for d in sorted(os.listdir(base)):
            dd = os.path.join(base, d)
            if not os.path.isdir(dd):
                continue
            for f in sorted(os.listdir(dd)):
                if f.endswith('.otmod'):
                    t = open(os.path.join(dd, f), encoding='utf-8', errors='ignore').read()
                    m = re.search(r'^\s*name:\s*(\S+)', t, re.M)
                    if m:
                        found.setdefault(m.group(1), []).append(top + '/' + d + '/' + f)
    return found


def check(root, overlay_otmod=OVERLAY_OTMOD):
    errors = []
    found = modules_of(root)
    for name, paths in sorted(found.items()):
        if len(paths) > 1:
            errors.append(f'module {name!r} is defined {len(paths)} times: {", ".join(paths)}')
    helper = found.get('game_helper', [])
    if helper != ['modules/game_helper/game_helper.otmod']:
        if len(helper) <= 1:
            errors.append(f'game_helper must be modules/game_helper/game_helper.otmod only, found {helper}')
    elif os.path.isfile(overlay_otmod):
        ours = open(overlay_otmod, encoding='utf-8').read()
        live = open(os.path.join(root, helper[0]), encoding='utf-8').read()
        if ours != live:
            errors.append('assembled game_helper.otmod is not the overlay one')
    if os.path.isdir(os.path.join(root, 'mods', 'game_helper')):
        errors.append('mods/game_helper (the base helper) is still in the tree')
    return errors


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    errors = check(argv[1])
    for e in errors:
        print('assembled client:', e)
    if not errors:
        print('assembled client: one game_helper, the overlay one')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
