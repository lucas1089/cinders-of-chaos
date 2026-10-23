#!/usr/bin/env python3
"""Install the Apothecary of the hub (server/data/scripts/chaos/apothecary*.lua; README "The Apothecary").

usage: python3 -I install_apothecary.py DATA_DIR [--dry-run]

The NPC's name comes from server/data/scripts/chaos/apothecary_config.lua (`C.npc`), the same file the Lua side uses.

1. data/npc: the XML (server/data/npc/<name>.xml, with the shop lists) and the script it names (server/data/npc/scripts/);
   only new or different files are written. apothecary.lua places her at startup, in her stall of the hub
   (npc_booths_config.lua) else next to the temple.

Run before the `runes` and `potions` steps (install_all.py step `apothecary`, right after `servicenpcs`): those two
read every NPC shop of data/npc, so the rune prices are the supply table's and she sells the Everfull potions too, and
`itemprices` raises any price below the no-arbitrage floor. Nothing else: no items, no hooks, no tables.
Idempotent: a second run changes nothing (the later steps rewrite the copy; running this step again copies the repo's
file over theirs, and they restore their changes on the same install run).
"""
import filecmp
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'apothecary_config.lua')
REPO_NPC = os.path.join(SERVER, 'data', 'npc')


def npc_name(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    m = re.search(r'^C\.npc\s*=\s*"([^"]+)"', text, re.M)
    if not m:
        raise SystemExit('apothecary_config.lua: no C.npc name')
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
