#!/usr/bin/env python3
"""Every base waypoint open for every character (owner 2026-11-03, O386; server/README.md "Waypoints for everyone (O386)").

usage: python3 -I patch_base_waypoints.py DATA_DIR [--dry-run]

DATA_DIR is the base server's data folder. The base waypoint script (scripts/customs/waypoints/waypoint.lua: a portal
next to every temple, action ids 7000-7017) opens a waypoint when a character first steps on it (the player storage of
the action id set to 1) and its menu lists only those. This tool makes the script ask
data/scripts/chaos/waypoints_core.lua (ChaosWaypointsCore.isUnlocked) instead, so the switch `unlockAll` of
data/scripts/chaos/waypoints_config.lua decides (on: every waypoint open, for new and old characters, nothing written
to them; off: the base rule again):
  1. a small block before the script's MoveEvent (marked "chaos-waypoints") loads the core and defines
     chaosWaypointOpen(player, aid);
  2. every `player:getStorageValue(<x>.actionId) == 1` becomes `chaosWaypointOpen(player, <x>.actionId)` and every
     `~= 1` becomes `not chaosWaypointOpen(...)`.
The rest of the file (the list, the menu, the cooldown, the strings the worldtexts step renames) is kept byte for byte,
line endings too. Idempotent: a second run finds the block and no storage test and changes nothing. A data folder
without the script is left alone (exit 0); a script without the block and without any storage test is left alone with
a line saying so (exit 0). --dry-run writes nothing. install_all.py step `waypoints`.
Test: tools/patch_base_waypoints_test.py (a synthetic script, run under luajit / lua5.3 with a mocked engine).
"""
import os
import re
import sys

SCRIPT = os.path.join('scripts', 'customs', 'waypoints', 'waypoint.lua')
MARK = '-- chaos-waypoints'
TEST = re.compile(r'player:getStorageValue\(\s*([A-Za-z_][\w.\[\]]*\.actionId)\s*\)\s*(==|~=)\s*1(?![\w.])')
ANCHOR = re.compile(r'^[^\r\n]*\bMoveEvent\(\)', re.M)
BLOCK = [
    '-- chaos-waypoints: tools/patch_base_waypoints.py (O386). Which waypoints are open is asked of',
    '-- data/scripts/chaos/waypoints_core.lua (switch unlockAll in waypoints_config.lua).',
    'if not ChaosWaypointsCore then',
    '\tdofile("data/scripts/chaos/waypoints_core.lua")',
    'end',
    'local function chaosWaypointOpen(player, aid)',
    '\treturn ChaosWaypointsCore.isUnlocked(player, aid)',
    'end',
    '-- chaos-waypoints end',
]


def patch(text):
    """(new text, number of storage tests replaced, block added: bool, note or None)"""
    eol = '\r\n' if '\r\n' in text else '\n'
    tests = [0]

    def repl(m):
        tests[0] += 1
        call = 'chaosWaypointOpen(player, %s)' % m.group(1)
        return call if m.group(2) == '==' else 'not ' + call
    new = TEST.sub(repl, text)
    added = False
    if MARK not in new:
        if not tests[0]:
            return text, 0, False, 'no waypoint storage test found: not the expected script, left alone'
        a = ANCHOR.search(new)
        if not a:
            return text, 0, False, 'no MoveEvent() line found: not the expected script, left alone'
        new = new[:a.start()] + eol.join(BLOCK) + eol + eol + new[a.start():]
        added = True
    return new, tests[0], added, None


def run(data_dir, dry=False, log=print):
    path = os.path.join(data_dir, SCRIPT)
    if not os.path.isfile(path):
        log('%s: not there, nothing to do' % SCRIPT)
        return 0
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, n, added, note = patch(text)
    if note:
        log('%s: %s' % (SCRIPT, note))
        return 0
    if new == text:
        log('%s: patched already' % SCRIPT)
        return 0
    if not dry:
        with open(path + '.tmp', 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
        os.replace(path + '.tmp', path)
    log('%s: %d storage test(s) now ask waypoints_core.lua%s%s' % (SCRIPT, n, ', block added' if added else '',
                                                                  ' (dry run)' if dry else ''))
    return 0


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    args = [a for a in args if a != '--dry-run']
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    if not os.path.isdir(args[0]):
        print('%s: no such folder' % args[0])
        return 1
    return run(args[0], dry)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
