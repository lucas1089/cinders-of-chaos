#!/usr/bin/env python3
"""The base server's dungeon entry tile opens the Chaos dungeon window instead of its modal window (server/README.md
"Instance limits", "Base modal dungeon entry").

usage: python3 -I patch_base_dungeon.py DATA_DIR [--dry-run]

The base server has a second way into the dungeons next to the Chaos queue (scripts/chaos/dungeons.lua): a step-in tile
(data/movements/movements.xml, a StepIn movevent, stock item 26702, script dungeon.lua) opens a modal window over
DUNGEON_SYSTEM.Dungeons, and its answer (creaturescripts dungeon_mod.lua) teleports the group in itself. Both use the
same dungeon boxes and neither knows about the other. The modal run's weak spots: "a team is already inside" scans
every tile of the box on each use (37,074 and 61,325 tiles for the two big ones), its exit timer captures the player
userdata (stale after a logout), its fixed time (DungeonTime, 60 min) has no warning and no cap, and at the end it
removes every monster in the box, also those of a queue run that started there in the meantime.

The step-in script gets one line (with a marker), the body is untouched: first line of onStepIn,
  `if ChaosDungeonsOpen and ChaosDungeonsOpen(player) then return true end`:
the Chaos side sends the dungeon list and opens the window (opcode ChaosOpcodes.dungeons), so every entry goes through
the queue (one run per box, the time cap and warnings of "Instance limits", difficulty, records). The modal window is
never sent, so the modal scripts never run. Without the Chaos scripts loaded (ChaosDungeonsOpen nil) the tile works
exactly as before.

A script is recognised when it is the script of a StepIn movevent, has `function onStepIn(` exactly once and sends the
DUNGEON_SYSTEM modal window (`ModalWindow(DUNGEON_SYSTEM.Modal.ID`). Every change is made once (a second run changes
nothing). Line endings (LF or CRLF) are kept.
"""
import os
import re
import sys

MARK = 'Chaos (patch_base_dungeon.py)'
SHAPE = 'ModalWindow(DUNGEON_SYSTEM.Modal.ID'
STEPIN_RE = re.compile(r'^function onStepIn\(([A-Za-z_]\w*)[^)\n]*\)[ \t]*\r?$', re.M)
MOVEVENT_RE = re.compile(r'<movevent\b[^>]*>', re.I)
SCRIPT_RE = re.compile(r'\bscript\s*=\s*"([^"]+)"')
EVENT_RE = re.compile(r'\bevent\s*=\s*"([^"]+)"', re.I)


def patch(text):
    """-> (new text, status): 'patched', 'already patched', 'none' (not the dungeon entry), 'unrecognised <why>'"""
    if SHAPE not in text:
        return text, 'none'
    if MARK in text:
        return text, 'already patched'
    found = STEPIN_RE.findall(text)
    if len(found) != 1:
        return text, 'unrecognised (onStepIn x%d)' % len(found)
    m = STEPIN_RE.search(text)
    nl = '\r\n' if '\r\n' in text else '\n'
    eol = text.find('\n', m.end())
    eol = len(text) if eol < 0 else eol + 1
    line = '\tif ChaosDungeonsOpen and ChaosDungeonsOpen(%s) then return true end -- %s%s' % (m.group(1), MARK, nl)
    return text[:eol] + line + text[eol:], 'patched'


def files(data):
    """the scripts of the StepIn movevents in movements.xml (each once, in file order)"""
    xml = os.path.join(data, 'movements', 'movements.xml')
    if not os.path.isfile(xml):
        return
    with open(xml, encoding='utf-8', errors='surrogateescape') as f:
        text = re.sub(r'<!--.*?-->', '', f.read(), flags=re.S)
    seen = set()
    for tag in MOVEVENT_RE.findall(text):
        ev, sc = EVENT_RE.search(tag), SCRIPT_RE.search(tag)
        if not ev or not sc or ev.group(1).lower() != 'stepin':
            continue
        path = os.path.normpath(os.path.join(data, 'movements', 'scripts', sc.group(1)))
        if path in seen or not os.path.isfile(path):
            continue
        seen.add(path)
        yield path


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    found = 0
    for path in files(data):
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, st = patch(text)
        if st == 'none':
            continue
        found += 1
        if st == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('data/%s: %s%s' % (rel, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    if not found:
        print('no step-in script with the DUNGEON_SYSTEM modal window found (nothing to do)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
