#!/usr/bin/env python3
"""The base server's soul pit and tower defence get the boss room lock, a time limit with warnings, an exit and a
clean-up (server/README.md "Instance limits", "Soul pit and tower defence").

usage: python3 -I patch_base_eventrooms.py DATA_DIR [--dry-run]

Both are places a group goes into, written outside the boss room template, without a time limit or a lock:
  soul pit        data/scripts/customs/soulpit_system/soulpit.lua: a soul core used on the pit (action id in its
                  `config`) teleports the group in after 5 s and runs 5 waves. The state of a run is one table of the
                  script (`event`): a group that leaves early leaves the run (and its 1 s loops) going, nothing ends it.
  tower defence   data/scripts/customs/tower_defense/tower_defense.lua: a lever in the arena starts the waves;
                  tower_defense/entrance_teleport.lua lets anyone in at any time; a lever pull after the spawning ended
                  restarts the run (a new Base Core, the counters reset) while the old monsters still walk.
The scripts get marked lines (the bodies are untouched) that hand both places to ChaosBossRooms (instance_limits.lua),
as tools/patch_base_bossrooms.py does for the lever boss rooms:
  - a room config at load (ChaosBossRoomsPending["aid<id>"]): the box, where the group goes in and out (the soul pit:
    the lobby spot its entrance teleport (soulpit_system/teleport.lua) leads to, so nobody is left on the start tiles of
    the next group; the tower defence: the spot its own exit tile leads to), the place's own
    time (config.chaosRoom -> bossRooms.ownSeconds), and chaosOnClose, which resets the script's own state at the end
    (the soul pit's `event`; the tower defence stops spawning and clears the players' summon counters as its exit does);
  - the lock first in the entry (the soul core on the pit; the tower defence's lever and entrance tile, which sends a
    refused player back where they came from): refused while a run is on, with the time it frees up;
  - ChaosBossRooms.started when the run starts, ChaosBossRooms.finished when it ends by the script's own rule (the pit
    completed; the tower defence won or lost).
Without the Chaos scripts loaded (ChaosBossRooms nil) both work exactly as before.

A file is patched only when each of its anchors is there exactly as often as in the stock script; otherwise it is
listed and left alone. Every change is made once (a second run changes nothing). Line endings (LF or CRLF) are kept.
"""
import os
import re
import sys

MARK = 'Chaos (patch_base_eventrooms.py)'

SOULPIT = ('scripts', 'customs', 'soulpit_system', 'soulpit.lua')
TOWER = ('scripts', 'customs', 'tower_defense', 'tower_defense.lua')
ENTRANCE = ('scripts', 'customs', 'tower_defense', 'entrance_teleport.lua')

SOULPIT_AID_RE = re.compile(r'^local config = \{[ \t]*\r?\n[ \t]*actionId[ \t]*=[ \t]*(\d+)[ \t]*,', re.M)
TOWER_AID_RE = re.compile(r'^\[(\d+)\] = \{names = ', re.M)


def anchor(pattern):
    return re.compile(pattern, re.M)


# (anchor, expected count, 'before' | 'after', lines with {key}; {i} = the indentation of the anchor line, {b} = the
# indentation of the line after it)
SOULPIT_STEPS = [
    (anchor(r'^local function getSpectators\(\)[ \t]*\r?$'), 1, 'before', [
        'local chaosRoom = {bossName = "Soulpit", chaosRoom = "soulpit", participantsPos = config.participantsPos,',
        '    bossArea = {fromPos = Position(math.min(config.spawnArea.fromPos.x, event.spawnArea[1].x),',
        '        math.min(config.spawnArea.fromPos.y, event.spawnArea[1].y), config.spawnArea.fromPos.z),',
        '    toPos = Position(math.max(config.spawnArea.toPos.x, event.spawnArea[2].x),',
        '        math.max(config.spawnArea.toPos.y, event.spawnArea[2].y), config.spawnArea.toPos.z),',
        '    entrancePos = config.entranceArea, exitPosition = Position(31589, 32281, 8)},',
        '    chaosOnClose = function()',
        '        event.creatures = {}',
        '        event.currentWave = 0',
        '        event.participants = {}',
        '        event.currentItem = nil',
        '    end}',
        'ChaosBossRoomsPending = ChaosBossRoomsPending or {}',
        'ChaosBossRoomsPending["{key}"] = chaosRoom',
        '',
    ]),
    (anchor(r'^function soulPit\.onUse\(player, item, fromPos, target, toPos, isHotkey\)[ \t]*\r?$'), 1, 'after', [
        '{b}if ChaosBossRooms and target and target.getActionId and target:getActionId() == config.actionId',
        '{b}    and not ChaosBossRooms.leverUse(player, "{key}", chaosRoom) then return true end',
    ]),
    (anchor(r'^([ \t]*)if checkAndStartWave\(player, item\) then[ \t]*\r?$'), 1, 'after', [
        '{b}if ChaosBossRooms then ChaosBossRooms.started("{key}", chaosRoom, participants) end',
    ]),
    (anchor(r'^([ \t]*)local eventName = event\.waves\[event\.currentItem\]\.name or "Soulpit"[ \t]*\r?$'), 1, 'after', [
        '{i}if ChaosBossRooms then ChaosBossRooms.finished("{key}") end',
    ]),
]

TOWER_STEPS = [
    (anchor(r'^local toPos = \{x = \d+, y = \d+, z = \d+\}[ \t]*\r?$'), 1, 'after', [
        '',
        'local chaosRoom = {bossName = "Tower Defense", chaosRoom = "towerdefense",',
        '    bossArea = {fromPos = Position(fromPos.x, fromPos.y, fromPos.z), toPos = Position(toPos.x, toPos.y, toPos.z),',
        '    entrancePos = Position(31205, 32270, 8), exitPosition = Position(31206, 32295, 8)},',
        '    participantsPos = {Position(31206, 32295, 8)},',
        '    chaosOnClose = function(players)',
        '        stopSpawning = true',
        '        spawningWave = false',
        '        for _, p in ipairs(players or {}) do',
        '            for k = 86704, 86715 do p:setStorageValue(k, 0) end',
        '            p:setStorageValue(88708, 0)',
        '            p:setStorageValue(88709, 0)',
        '        end',
        '    end}',
        'ChaosBossRoomsPending = ChaosBossRoomsPending or {}',
        'ChaosBossRoomsPending["{key}"] = chaosRoom',
    ]),
    (anchor(r'^local function rewardPlayers\(\)[ \t]*\r?$'), 1, 'after', [
        '{b}if ChaosBossRooms then ChaosBossRooms.finished("{key}") end',
    ]),
    (anchor(r'^([ \t]*)local playersTeleported = false[ \t]*\r?$'), 2, 'after', [
        '{i}if ChaosBossRooms then ChaosBossRooms.finished("{key}") end',
    ]),
    (anchor(r'^function towerDefense\.onUse\(cid, item, fromPosition, itemEx, toPosition\)[ \t]*\r?$'), 1, 'after', [
        '{b}if ChaosBossRooms and not ChaosBossRooms.leverUse(cid, "{key}", chaosRoom) then return true end',
    ]),
    (anchor(r'^([ \t]*)spawningWave = true[ \t]*\r?$'), 1, 'after', [
        '{i}if ChaosBossRooms then ChaosBossRooms.started("{key}", chaosRoom) end',
    ]),
]

ENTRANCE_STEPS = [
    (anchor(r'^function entranceTower\.onStepIn\(player, item, position, fromPosition\)[ \t]*\r?$'), 1, 'after', [
        '{b}if ChaosBossRooms and not ChaosBossRooms.leverUse(player, "{key}") then',
        '{b}    player:teleportTo(fromPosition)',
        '{b}    return true',
        '{b}end',
    ]),
]


def apply(text, steps, key):
    """-> (new text, status) for one file: 'patched', 'already patched', 'unrecognised <why>'"""
    if MARK in text:
        return text, 'already patched'
    bad = []
    for rx, n, _, _ in steps:
        found = len(rx.findall(text))
        if found != n:
            bad.append('%s x%d (want %d)' % (rx.pattern.split('\\(')[0].strip('^').strip()[:40], found, n))
    if bad:
        return text, 'unrecognised (%s)' % ', '.join(bad)
    nl = '\r\n' if '\r\n' in text else '\n'
    inserts = []  # (offset, text)
    for rx, _, where, lines in steps:
        for m in rx.finditer(text):
            sol = text.rfind('\n', 0, m.start()) + 1
            eol = text.find('\n', m.end())
            eol = len(text) if eol < 0 else eol + 1
            ind = re.match(r'[ \t]*', text[sol:]).group(0)
            body = re.match(r'[ \t]*', text[eol:]).group(0) or ind + '    '
            out = ''
            for line in lines:
                line = line.replace('{key}', key).replace('{i}', ind).replace('{b}', body)
                out += (line + ' -- ' + MARK if line.strip() else '') + nl
            inserts.append((sol if where == 'before' else eol, out))
    for off, add in sorted(inserts, key=lambda t: t[0], reverse=True):
        text = text[:off] + add + text[off:]
    return text, 'patched'


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[3])
        return 2
    data = args[0]
    jobs = []
    soulpit = os.path.join(data, *SOULPIT)
    if os.path.isfile(soulpit):
        m = SOULPIT_AID_RE.search(read(soulpit))
        jobs.append((soulpit, SOULPIT_STEPS, 'aid' + m.group(1) if m else None))
    tower = os.path.join(data, *TOWER)
    tower_key = None
    if os.path.isfile(tower):
        m = TOWER_AID_RE.search(re.sub(r'^[ \t]+', '', read(tower), flags=re.M))
        tower_key = 'aid' + m.group(1) if m else None
        jobs.append((tower, TOWER_STEPS, tower_key))
    entrance = os.path.join(data, *ENTRANCE)
    if os.path.isfile(entrance) and tower_key:
        jobs.append((entrance, ENTRANCE_STEPS, tower_key))
    if not jobs:
        print('no soul pit and no tower defence script found (nothing to do)')
        return 0
    for path, steps, key in jobs:
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        text = read(path)
        if key is None:
            new, st = text, 'unrecognised (no action id)'
        else:
            new, st = apply(text, steps, key)
        if st == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('data/%s: %s%s%s' % (rel, st, ' ' + key if st == 'patched' else '',
                                   ' (dry run, not written)' if dry and st == 'patched' else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
