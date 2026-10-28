#!/usr/bin/env python3
"""Install the ascension quest's base server parts (idempotent). Called by install_all.py as a class hook
(every tools/install_class_*.py, step "spells"); it can also run on its own.

usage: python3 -I install_class_ascension.py DATA_DIR [--dry-run]

1. copies the Ascendant Oracle (server/data/npc/Ascendant Oracle.xml and npc/scripts/ascendant_oracle.lua) into
   DATA_DIR/npc (only new or different files are written). ascension_quest.lua places it at startup (its stall in the hub).
2. runs patch_promotion.py DATA_DIR: the stock promotion NPCs (King Tibianus, ...) refuse and point to the Oracle, the
   premium login no longer promotes.
The quest scripts (data/scripts/chaos/ascension_quest*.lua) and the guardian monsters
(data/monster/monsters/chaos/ascension/) come with the "files" and "monsters" steps of install_all.py.
"""
import filecmp
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_NPC = os.path.join(os.path.dirname(HERE), 'data', 'npc')


def copy_npcs(data, dry):
    """copy every NPC file of server/data/npc (the Ascendant Oracle, Keeper of Trials, Archivist Maelis, Archivist Odrenna ...
    and their scripts) that is new or different; returns the relative paths written (or that a dry run would write)"""
    written = []
    for root, dirs, files in os.walk(REPO_NPC):
        dirs.sort()
        rel = os.path.relpath(root, REPO_NPC)
        for name in sorted(files):
            if not name.endswith(('.xml', '.lua')):
                continue
            src = os.path.join(root, name)
            dst = os.path.join(data, 'npc', rel, name) if rel != '.' else os.path.join(data, 'npc', name)
            if os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=False):
                print('npc/%s: up to date' % os.path.relpath(dst, os.path.join(data, 'npc')), flush=True)
                continue
            if not dry:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(src, dst)
            written.append(os.path.relpath(dst, os.path.join(data, 'npc')))
            print('npc/%s: copied%s' % (os.path.relpath(dst, os.path.join(data, 'npc')), ' (dry run)' if dry else ''), flush=True)
    return written


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    data = args[0]
    dry = '--dry-run' in sys.argv
    if not os.path.isdir(os.path.join(data, 'npc')):
        print('%s: no npc folder (is this a server data folder?)' % data)
        return 1
    copy_npcs(data, dry)
    cmd = [sys.executable, '-I', os.path.join(HERE, 'patch_promotion.py'), data] + (['--dry-run'] if dry else [])
    return subprocess.call(cmd)


if __name__ == '__main__':
    sys.exit(main())
