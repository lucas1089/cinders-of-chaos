#!/usr/bin/env python3
"""The base server's lever boss rooms get a lock, a time limit with warnings, a kick and a clean-up (server/README.md
"Instance limits", "Base lever boss rooms").

usage: python3 -I patch_base_bossrooms.py DATA_DIR [--dry-run]

The base server has about fifty boss rooms written from one template (data/scripts/**, outside scripts/chaos): a
`local config = {...}` with actionId, bossName, bossArea {fromPos, toPos, entrancePos, exitPosition}, participantsPos,
kickParticipantAfterSeconds; a lever Action whose onUse checks the participants and that nobody is in the room, makes
the boss, teleports the group in and starts a kick timer; a boss death that opens a teleport out. Its weak spots: the
kick timer is never stopped when the room empties, so it also hits the next group; there is no warning before it; a
character who logs out inside comes back into the room after the group is gone; monsters stay in the room after a kick.

Each recognised script gets three lines (with a marker), the body is untouched:
  1. before `local function getSpectators()`: the room's config goes into ChaosBossRoomsPending["aid<actionId>"], so
     the Chaos side knows the room (its area, exit, lever) from the start;
  2. first line of the lever's onUse: `if ChaosBossRooms and not ChaosBossRooms.leverUse(player, key, config) then
     return true end`: the lever is locked while a group's session runs (the message says when it frees up);
  3. after the script starts its kick timer: `ChaosBossRooms.started(key, config, participants)`: the session takes over
     the kick (the script's timer is stopped) with the time limit, the warnings, the countdown bars, the idle rule and
     the clean-up of instance_limits.lua.
Without the Chaos scripts loaded (ChaosBossRooms nil) every room works exactly as before.

A script is recognised when it has each anchor exactly once and an `actionId = <number>`. Scripts with the template's
words but not its shape (several rooms in one file, rooms entered by a tile) are listed and left alone. Every change is
made once (a second run changes nothing). Line endings (LF or CRLF) are kept.
"""
import os
import re
import sys

MARK = 'Chaos (patch_base_bossrooms.py)'
SKIP_DIRS = ('chaos',)  # data/scripts/chaos is ours

ACTION_RE = re.compile(r'^[ \t]*actionId[ \t]*=[ \t]*(\d+)[ \t]*,', re.M)
CONFIG_RE = re.compile(r'^local config = \{', re.M)
SPECT_RE = re.compile(r'^local function getSpectators\(\)[ \t]*\r?$', re.M)
USE_RE = re.compile(r'^function [A-Za-z_]\w*\.onUse\(player, item, fromPos, target, toPos, isHotkey\)[ \t]*(\r?)$', re.M)
KICK_START_RE = re.compile(r'config\.kickEventId = addEvent\(function')
KICK_END_RE = re.compile(r'^([ \t]*)end, config\.kickParticipantAfterSeconds \* 1000\)[ \t]*(\r?)$', re.M)
SHAPE_WORDS = ('kickParticipantAfterSeconds', 'bossArea')


def patch(text):
    """-> (new text, status): 'patched <key>', 'already patched', 'none' (not a room), 'unrecognised <why>'"""
    if not all(w in text for w in SHAPE_WORDS):
        return text, 'none'
    if MARK in text:
        return text, 'already patched'
    counts = {
        'config': len(CONFIG_RE.findall(text)),
        'getSpectators': len(SPECT_RE.findall(text)),
        'onUse': len(USE_RE.findall(text)),
        'kick timer': len(KICK_START_RE.findall(text)),
        'kick end': len(KICK_END_RE.findall(text)),
        'actionId': len(ACTION_RE.findall(text)),
    }
    bad = ['%s x%d' % (k, v) for k, v in counts.items() if v != 1]
    if bad:
        return text, 'unrecognised (%s)' % ', '.join(bad)
    if text.find('participants') < 0:
        return text, 'unrecognised (no participants list)'
    key = 'aid' + ACTION_RE.search(text).group(1)
    nl = '\r\n' if '\r\n' in text else '\n'
    # 3 first (it is the furthest down), then 2, then 1, so the earlier offsets stay right
    m = KICK_END_RE.search(text)
    if m.start() < USE_RE.search(text).end():
        return text, 'unrecognised (kick timer outside onUse)'
    ind = m.group(1)
    line3 = '%sif ChaosBossRooms then ChaosBossRooms.started("%s", config, participants) end -- %s%s' % (ind, key, MARK, nl)
    eol = text.find('\n', m.end())
    eol = len(text) if eol < 0 else eol + 1
    text = text[:eol] + line3 + text[eol:]
    m = USE_RE.search(text)
    eol = text.find('\n', m.end())
    eol = len(text) if eol < 0 else eol + 1
    body = re.match(r'[ \t]*', text[eol:]).group(0) or '\t'
    line2 = '%sif ChaosBossRooms and not ChaosBossRooms.leverUse(player, "%s", config) then return true end -- %s%s' % (
        body, key, MARK, nl)
    text = text[:eol] + line2 + text[eol:]
    m = SPECT_RE.search(text)
    line1 = ('ChaosBossRoomsPending = ChaosBossRoomsPending or {} -- %s%s'
             'ChaosBossRoomsPending["%s"] = config -- %s%s%s') % (MARK, nl, key, MARK, nl, nl)
    text = text[:m.start()] + line1 + text[m.start():]
    return text, 'patched ' + key


def files(data):
    root = os.path.join(data, 'scripts')
    if not os.path.isdir(root):
        return
    for dirpath, dirnames, filenames in os.walk(root):
        if os.path.relpath(dirpath, root) == '.':
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        dirnames.sort()
        for name in sorted(filenames):
            if name.endswith('.lua'):
                yield os.path.join(dirpath, name)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[3])
        return 2
    data = args[0]
    rooms, keys, skipped = 0, {}, 0
    for path in files(data):
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, st = patch(text)
        if st == 'none':
            continue
        if st.startswith('patched') or st == 'already patched':
            rooms += 1
            key = st.split(' ', 1)[1] if st.startswith('patched') else (
                'aid' + ACTION_RE.search(text).group(1) if ACTION_RE.search(text) else '?')
            if key in keys:
                print('data/%s: lever %s also used by data/%s (both locked as one room)' % (rel, key, keys[key]))
            keys.setdefault(key, rel)
        else:
            skipped += 1
        if st.startswith('patched') and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('data/%s: %s%s' % (rel, st, ' (dry run, not written)' if dry and st.startswith('patched') else ''))
    print('%d boss room(s) with the Chaos lock and time limit, %d left alone' % (rooms, skipped))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
