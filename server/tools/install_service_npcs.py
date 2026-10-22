#!/usr/bin/env python3
"""Install the service NPCs of the hub's stalls (server/data/scripts/chaos/service_npcs*.lua; README "Service NPCs").

usage: python3 -I install_service_npcs.py DATA_DIR [--dry-run]

The NPCs come from server/data/scripts/chaos/service_npcs_config.lua (`C.npcs`: name and script per NPC), the same file the
Lua side uses: the stash keeper, the pocket boss NPC, the banker, the house broker and the services clerk.

1. data/npc: each NPC's XML (server/data/npc/<name>.xml), the script it names and the shared dialogue
   npc/scripts/chaos_service_npc.lua; only new or different files are written. service_npcs.lua places them at startup,
   in their stalls of the hub (npc_booths_config.lua names them) else next to the temple.

Nothing else: no items, no hooks, no tables, no opcode. The windows they open belong to the stash, Boss Spawns, bank and
Info & Services modules. Idempotent: a second run changes nothing.
"""
import filecmp
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'service_npcs_config.lua')
REPO_NPC = os.path.join(SERVER, 'data', 'npc')
SHARED = 'chaos_service_npc.lua'


def read_npcs(path=CONFIG):
    """[(name, script)] of C.npcs, in file order"""
    text = open(path, encoding='utf-8').read()
    block = re.search(r'\nC\.npcs = \{(.*?)\n\}\n', text, re.S)
    if not block:
        raise SystemExit('service_npcs_config.lua: no C.npcs')
    out = re.findall(r'\bname = "([^"]+)",\s*script = "([^"]+)"', block.group(1))
    if not out:
        raise SystemExit('service_npcs_config.lua: C.npcs lists no NPC')
    return out


def npc_files(npcs):
    """(source, path below npc/) of every NPC: its XML, the script it names, and the shared dialogue"""
    out = []
    for name, script in npcs:
        xml = os.path.join(REPO_NPC, name + '.xml')
        if not os.path.isfile(xml):
            raise SystemExit('server/data/npc/%s.xml is missing' % name)
        m = re.search(r'script="([^"]+)"', open(xml, encoding='utf-8').read())
        if not m or m.group(1) != script:
            raise SystemExit('server/data/npc/%s.xml names script %s, the config %s' % (name, m and m.group(1), script))
        src = os.path.join(REPO_NPC, 'scripts', script)
        if not os.path.isfile(src):
            raise SystemExit('server/data/npc/scripts/%s is missing' % script)
        out.append((xml, name + '.xml'))
        out.append((src, os.path.join('scripts', script)))
    shared = os.path.join(REPO_NPC, 'scripts', SHARED)
    if not os.path.isfile(shared):
        raise SystemExit('server/data/npc/scripts/%s is missing' % SHARED)
    out.append((shared, os.path.join('scripts', SHARED)))
    return out


def copy_npcs(data_dir, npcs, dry):
    notes = []
    for src, rel in npc_files(npcs):
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
    for note in copy_npcs(data_dir, read_npcs(), dry):
        print(note)
    if dry:
        print('dry run: nothing written')
    return 0


if __name__ == '__main__':
    sys.exit(main())
