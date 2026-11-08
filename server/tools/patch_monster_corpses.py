#!/usr/bin/env python3
"""The loot bag item in items.xml (idempotent): server/README.md "Loot bag instead of corpses" (O435).

usage: python3 -I patch_monster_corpses.py DATA_DIR [--dry-run] [--config FILE] [--check]

Every monster that has a corpse leaves the bag item (engine src-patch 0089 + data/scripts/chaos/corpse_bag.lua; the
numbers are in data/scripts/chaos/corpse_config.lua). The bag is the stock item 6068, a container with a corpse type.
Its stock entry is the first stage of a three stage chain (6068 -> 5527 -> 5528, 24 slots, a body that remains after
the loot), so this tool gives the entry the bag's own life: the name, the slots of the config (the biggest stock corpse
holds 60), `decayTo 0` (the bag vanishes with what is left in it, no body remains) and `duration` seconds. The
corpseType attribute stays (every script that asks ItemType:isCorpse keeps working); other attributes of the entry
stay. Nothing else in items.xml and no monster file is touched: the rule that picks the bag is in the engine, so the
base monsters need no rewrite. A second run changes nothing. --check only compares (exit 1 when the file differs).

Stock skinning off (owner 2026-11-08: "o esfolar nem é usado. pode remover"): the stock skinning script (the one
actions.xml names for the obsidian knife 5908) works by corpse id and has nothing left to skin once every monster leaves
the bag. Its onUse gets one marked line `do return false end` (marker SKIN_MARK) right after the line that opens it, or
after the professions hook line when install_professions.py put one there, so the professions' Flaying (that hook) still
runs and the stock body never does. A professions run after this one puts its hook first, which is the same order. No
such script or no onUse: reported, nothing written. The file keeps its line ends.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'corpse_config.lua')


def read_config(text):
    """bagId, name, article, slots, seconds from corpse_config.lua (plain `key = value` lines)"""
    out = {}
    for key in ('bagId', 'slots', 'seconds'):
        m = re.search(r'^\s*%s\s*=\s*(\d+)' % key, text, re.M)
        if not m:
            raise ValueError('corpse_config.lua has no %s' % key)
        out[key] = int(m.group(1))
    for key in ('name', 'article'):
        m = re.search(r'^\s*%s\s*=\s*"([^"]*)"' % key, text, re.M)
        if not m:
            raise ValueError('corpse_config.lua has no %s' % key)
        out[key] = m.group(1)
    return out


def set_attr(body, key, value):
    pat = re.compile(r'(<attribute\s+key="%s"\s+value=")[^"]*("\s*/>)' % re.escape(key), re.I)
    if pat.search(body):
        return pat.sub(lambda m: m.group(1) + str(value) + m.group(2), body, count=1)
    stripped = body.rstrip()
    return stripped + '\n\t\t<attribute key="%s" value="%s" />' % (key, value) + (body[len(stripped):] or '\n\t')


def patch_text(text, conf):
    """(new text, changed) with the entry of conf['bagId'] set; ValueError when the item is not there"""
    m = re.search(r'<item\s+id="%d"([^>]*)>(.*?)</item>' % conf['bagId'], text, re.S)
    if not m:
        raise ValueError('items.xml has no single <item id="%d"> entry' % conf['bagId'])
    head, body = m.group(1), m.group(2)
    if not re.search(r'key="corpseType"', body, re.I):
        raise ValueError('item %d has no corpseType: it is no corpse container' % conf['bagId'])
    if not re.search(r'key="containerSize"', body, re.I):
        raise ValueError('item %d is no container' % conf['bagId'])
    head = re.sub(r'\s+(article|name)="[^"]*"', '', head)
    new_head = ' article="%s" name="%s"%s' % (conf['article'], conf['name'], head)
    for key, value in (('containerSize', conf['slots']), ('decayTo', 0), ('duration', conf['seconds'])):
        body = set_attr(body, key, value)
    new = '<item id="%d"%s>%s</item>' % (conf['bagId'], new_head, body)
    out = text[:m.start()] + new + text[m.end():]
    return out, out != text


SKIN_MARK = '-- Chaos: stock skinning off, monsters leave the loot bag (patch_monster_corpses.py)'
SKIN_LINE = '\tdo return false end ' + SKIN_MARK
KNIFE = 5908
PROF_MARK = '-- Chaos professions (tools/install_professions.py)'


def skinning_script(data_dir):
    """path of the script actions.xml names for the obsidian knife, or None"""
    path = os.path.join(data_dir, 'actions', 'actions.xml')
    if not os.path.isfile(path):
        return None
    for tag in re.findall(r'<action\s[^>]*>', open(path, encoding='utf-8', errors='replace').read()):
        iid = re.search(r'\bitemid="(\d+)"', tag)
        script = re.search(r'\bscript="([^"]+)"', tag)
        if iid and script and int(iid.group(1)) == KNIFE:
            return os.path.join(data_dir, 'actions', 'scripts', script.group(1))
    return None


def patch_skinning(text):
    """returns (new text, changed); raises ValueError without an onUse"""
    if SKIN_MARK in text:
        return text, False
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = text.splitlines(True)
    at = None
    for i, l in enumerate(lines):
        if re.match(r'\s*function\s+onUse\s*\(', l):
            at = i + 1
            break
    if at is None:
        raise ValueError('no onUse in the skinning script')
    if at < len(lines) and PROF_MARK in lines[at]:
        at += 1
    lines.insert(at, SKIN_LINE + nl)
    return ''.join(lines), True


def skinning_off(data_dir, dry):
    path = skinning_script(data_dir)
    if not path or not os.path.isfile(path):
        return 'stock skinning: no script for item %d in actions.xml, nothing to do' % KNIFE
    raw = open(path, 'rb').read().decode('latin-1')
    try:
        new, changed = patch_skinning(raw)
    except ValueError as e:
        return 'stock skinning: %s, skipped' % e
    if changed and not dry:
        open(path, 'wb').write(new.encode('latin-1'))
    return 'stock skinning: off in %s%s' % (os.path.basename(path), (' (changed)' if changed else ' (already off)')
                                            + (' (dry run)' if dry and changed else ''))


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    check = '--check' in argv
    cfg_path = CONFIG
    if '--config' in argv:
        cfg_path = argv[argv.index('--config') + 1]
        args = [a for a in args if a != cfg_path]
    if len(args) != 1:
        print(__doc__)
        return 2
    path = os.path.join(args[0], 'items', 'items.xml')
    if not os.path.isfile(path):
        print('no items.xml: %s' % path)
        return 1
    try:
        conf = read_config(open(cfg_path, encoding='utf-8').read())
        text = open(path, encoding='latin-1').read()
        new, changed = patch_text(text, conf)
    except ValueError as e:
        print('loot bag: %s' % e)
        return 1
    if check:
        print('loot bag: items.xml %s' % ('differs' if changed else 'matches'))
        return 1 if changed else 0
    if changed and not dry:
        open(path, 'w', encoding='latin-1', newline='').write(new)
    print('loot bag: item %d is "%s", %d slots, lasts %d s, no remains%s'
          % (conf['bagId'], conf['name'], conf['slots'], conf['seconds'],
             ' (changed)' if changed else ' (already set)') + (' (dry run)' if dry and changed else ''))
    print(skinning_off(args[0], dry))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
