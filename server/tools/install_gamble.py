#!/usr/bin/env python3
"""Install the base server parts of the Gambler (server/data/scripts/chaos/gamble*.lua; README "The Gambler").

usage: python3 -I install_gamble.py DATA_DIR [--dry-run]

The NPC's name comes from server/data/scripts/chaos/gamble_config.lua (`C.npc` name), the same file the Lua side uses.

1. data/npc: the Gambler's XML (server/data/npc/<name>.xml) and the script it names (server/data/npc/scripts/); only new or
   different files are written. gamble.lua places him next to the main temple at startup.

Nothing else: no items, no hooks, no tables (the stock lives in five player storages, 7101900 - 7101904).
Idempotent: a second run changes nothing.
"""
import filecmp
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'gamble_config.lua')
REPO_NPC = os.path.join(SERVER, 'data', 'npc')


def npc_name(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    m = re.search(r'C\.npc\s*=\s*\{[^}]*?\bname\s*=\s*"([^"]+)"', text, re.S)
    if not m:
        raise SystemExit('gamble_config.lua: no C.npc name')
    return m.group(1)


def npc_files(name):
    xml = os.path.join(REPO_NPC, name + '.xml')
    if not os.path.isfile(xml):
        raise SystemExit('server/data/npc/%s.xml is missing' % name)
    m = re.search(r'script="([^"]+)"', open(xml, encoding='utf-8').read())
    if not m:
        raise SystemExit('server/data/npc/%s.xml names no script' % name)
    script = os.path.join(REPO_NPC, 'scripts', m.group(1))
    if not os.path.isfile(script):
        raise SystemExit('server/data/npc/scripts/%s is missing' % m.group(1))
    return [(xml, name + '.xml'), (script, os.path.join('scripts', m.group(1)))]


def copy_npc(data_dir, name, dry):
    notes = []
    for src, rel in npc_files(name):
        dst = os.path.join(data_dir, 'npc', rel)
        if os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=False):
            notes.append('npc/%s: up to date' % rel)
            continue
        if not dry:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
        notes.append('npc/%s: copied%s' % (rel, ' (dry run)' if dry else ''))
    return notes


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    if not os.path.isdir(os.path.join(data_dir, 'npc')):
        print('%s: no npc folder (is this a server data folder?)' % data_dir)
        return 1
    for note in copy_npc(data_dir, npc_name(), dry):
        print(note)
    if dry:
        print('dry run: nothing written')
    return 0


if __name__ == '__main__':
    sys.exit(main())
