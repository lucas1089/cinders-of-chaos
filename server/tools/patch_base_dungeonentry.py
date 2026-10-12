#!/usr/bin/env python3
"""The base server's dungeon window (the modal entry) goes through the Chaos dungeon runs (server/README.md "Dungeon
queue", "Instance limits").

usage: python3 -I patch_base_dungeonentry.py DATA_DIR [--dry-run]

The base server has a dungeon window: stepping on the dungeon tile opens a modal window with the dungeons of
DUNGEON_SYSTEM (data/lib/core/dungeon.lua), and its "Confirm" button (data/creaturescripts/scripts/dungeon_mod.lua,
onModalWindow) checks level, party, leader, safe zone, cooldown and distance, then teleports the group in. Its weak
spots:
  - "A team is already inside" came from a scan of every tile of the dungeon box (37,074 tiles for the first dungeon,
    61,325 for the second) at each click, a stall of the game loop; the leader's distance check scanned 1,681 tiles;
  - each player got a fixed DungeonTime timer (60 or 30 minutes) that held the Player object across the whole run (a
    player who logged out left a stale object behind) and pulled the player back to the entry even after leaving; the
    leader's timer scanned the whole box again to remove the monsters;
  - none of the Chaos instance limits: no time cap, no warnings, no idle end, the queue did not know the dungeon was in
    use, and the cooldown storage read was nil (Storages.TimerCooldown; the table has timerCooldown).

Changes (each line carries a marker; the rest of the script is untouched):
  1. two local helpers at the top of the file;
  2. after `local sto = DUNGEON_SYSTEM.Storages`: the cooldown storage is the one the queue uses
     (ChaosDungeons.modalStorages);
  3. the box scan becomes `local players = chaosDungeonInside(choiceId)`: the guids of the dungeon's run (queue or
     window) and of the players online in the box (ChaosDungeons.modalInside), no Player object, no tile;
  4. "A team is already inside." gets the wait of the run inside (" It frees up in ~12 min at the latest.");
  5. the distance check loops over the positions near the leader that hold a player (from Game.getPlayers()), the
     body untouched;
  6. each of the three timers `addEvent(function() <who>:teleportTo(<from>) ... end, dg[choiceId].DungeonTime*1000)`
     is wrapped: with the Chaos scripts loaded, ChaosDungeons.modalJoin(choiceId, <who>:getGuid(), <from>,
     player:getGuid()) puts the player in the group's run of dungeons.lua (one run per dungeon, DungeonTime capped at
     45 minutes, warnings, the exit to the entry position, the window's ToFail text and cooldown, the monsters removed,
     logout and login rules, /instances); without them the stock timer runs as before.
Without the Chaos scripts (ChaosDungeons nil) the window works as before (helpers 3 and 5 still avoid the scans).

The file is recognised when every anchor is found exactly as often as the stock script has it; otherwise it is listed
and left alone. Every change is made once (a second run changes nothing). Line endings (LF or CRLF) are kept. A server
without the script has nothing to do (exit status 0).
"""
import os
import re
import sys

MARK = 'Chaos (patch_base_dungeonentry.py)'
SHAPE_WORDS = ('DUNGEON_SYSTEM', 'onModalWindow', 'PlayerInside')
SKIP_DIRS = ('chaos',)

FUNC_RE = re.compile(r'^function onModalWindow\(', re.M)
STO_RE = re.compile(r'^([ \t]*)local sto = DUNGEON_SYSTEM\.Storages[ \t]*(\r?)\n', re.M)
# the scan of the dungeon box: `local players = {}` and the three loops up to the `end` of the x loop
SCAN_RE = re.compile(
    r'^(?P<i>[ \t]*)local players = \{\}[ \t]*\r?\n'
    r'(?P=i)for x = dg\[choiceId\]\.FromPos\.x, dg\[choiceId\]\.ToPos\.x do[ \t]*\r?\n'
    r'(?P<body>(?:[ \t]+[^\n]*\n)*?)'
    r'(?P=i)end[ \t]*\r?\n', re.M)
INSIDE_RE = re.compile(r'player:sendTextMessage\(MESSAGE_STATUS_SMALL, msg\.PlayerInside\)')
NEAR_RE = re.compile(
    r'^(?P<i>[ \t]*)for x = (?P<c>[A-Za-z_]\w*)\.x - (?P<d>[A-Za-z_]\w*), (?P=c)\.x \+ (?P=d) do[ \t]*\r?\n'
    r'(?P<i2>[ \t]*)for y = (?P=c)\.y - (?P=d), (?P=c)\.y \+ (?P=d) do[ \t]*\r?\n'
    r'(?P<i3>[ \t]*)for z = (?P=c)\.z, (?P=c)\.z do[ \t]*\r?\n'
    r'(?=[ \t]*local (?P<t>[A-Za-z_]\w*) = Tile\(x, y, z\)[ \t]*\r?\n'
    r'[ \t]*local (?P<cr>[A-Za-z_]\w*) = (?P=t):getTopCreature\(\)[ \t]*\r?\n'
    r'[ \t]*if (?P=cr) and (?P=cr):isPlayer\(\) then)', re.M)
TIMER_RE = re.compile(
    r'^(?P<i>[ \t]*)addEvent\(function\(\)[ \t]*\r?\n'
    r'[ \t]*(?P<who>[A-Za-z_]\w*):teleportTo\((?P<from>[A-Za-z_]\w*)\)[ \t]*\r?\n'
    r'(?P<body>(?:[^\n]*\n)*?)'
    r'(?P=i)end, dg\[choiceId\]\.DungeonTime\*1000\)[ \t]*(?:\r?\n|$)', re.M)
EXPECT = {'onModalWindow': 1, 'Storages line': 1, 'box scan': 1, 'PlayerInside text': 1, 'distance scan': 1,
          'timers': 3}

HELPERS = (
    '-- %s: the players who hold a dungeon, as guids (no Player object kept, no\n'
    '-- tile scan): the run of dungeons.lua and the players online in the box; without the Chaos scripts the players\n'
    '-- online in the box (the stock code looked at every tile of the box).\n'
    'local function chaosDungeonInside(id)\n'
    '\tif ChaosDungeons and ChaosDungeons.modalInside then\n'
    '\t\treturn ChaosDungeons.modalInside(id)\n'
    '\tend\n'
    '\tlocal dg, list = DUNGEON_SYSTEM.Dungeons[id], {}\n'
    '\tfor _, p in ipairs(Game.getPlayers()) do\n'
    '\t\tlocal q = p:getPosition()\n'
    '\t\tif q.x >= dg.FromPos.x and q.x <= dg.ToPos.x and q.y >= dg.FromPos.y and q.y <= dg.ToPos.y\n'
    '\t\t\t\tand q.z >= dg.FromPos.z and q.z <= dg.ToPos.z then\n'
    '\t\t\tlist[#list + 1] = p:getGuid()\n'
    '\t\tend\n'
    '\tend\n'
    '\treturn list\n'
    'end\n'
    '\n'
    '-- %s: the positions on the floor of `center`, at most `d` away on x and y,\n'
    '-- that hold a player. A tile without a player cannot have a player as its top creature, so the check below sees the\n'
    '-- same players as the stock loop over all (2d+1)^2 tiles.\n'
    'local function chaosPlayerTilesNear(center, d)\n'
    '\tlocal list, seen = {}, {}\n'
    '\tfor _, p in ipairs(Game.getPlayers()) do\n'
    '\t\tlocal q = p:getPosition()\n'
    '\t\tif q.z == center.z and math.abs(q.x - center.x) <= d and math.abs(q.y - center.y) <= d then\n'
    '\t\t\tlocal key = q.x * 65536 + q.y\n'
    '\t\t\tif not seen[key] then\n'
    '\t\t\t\tseen[key] = true\n'
    '\t\t\t\tlist[#list + 1] = Position(q.x, q.y, q.z)\n'
    '\t\t\tend\n'
    '\t\tend\n'
    '\tend\n'
    '\treturn list\n'
    'end\n'
    '\n'
    '-- %s: the wait of the run inside, after "A team is already inside."\n'
    'local function chaosDungeonWait(id)\n'
    '\tif ChaosDungeons and ChaosDungeons.modalWait then\n'
    '\t\treturn ChaosDungeons.modalWait(id)\n'
    '\tend\n'
    '\treturn ""\n'
    'end\n'
    '\n') % (MARK, MARK, MARK)


def crlf(text, new):
    return new.replace('\n', '\r\n') if '\r\n' in text else new


def counts(text):
    return {
        'onModalWindow': len(FUNC_RE.findall(text)),
        'Storages line': len(STO_RE.findall(text)),
        'box scan': sum(1 for m in SCAN_RE.finditer(text)
                        if 'getTopCreature()' in m.group('body') and 'players[#players+1]' in m.group('body')),
        'PlayerInside text': len(INSIDE_RE.findall(text)),
        'distance scan': len(NEAR_RE.findall(text)),
        'timers': len(TIMER_RE.findall(text)),
    }


def patch(text):
    """-> (new text, status): 'patched', 'already patched', 'none' (not the dungeon window), 'unrecognised (...)'"""
    if not all(w in text for w in SHAPE_WORDS):
        return text, 'none'
    if MARK in text:
        return text, 'already patched'
    c = counts(text)
    bad = ['%s x%d' % (k, v) for k, v in c.items() if v != EXPECT[k]]
    if bad:
        return text, 'unrecognised (%s)' % ', '.join(bad)

    # 6. the timers (from the bottom up, so the earlier offsets stay right)
    for m in reversed(list(TIMER_RE.finditer(text))):
        i, nl = m.group('i'), ('\r\n' if '\r\n' in text else '\n')
        block = m.group(0)
        if not block.endswith('\n'):
            block += nl
        new = ('%sif ChaosDungeons and ChaosDungeons.modalJoin then -- %s: the run of dungeons.lua%s'
               '%s\tChaosDungeons.modalJoin(choiceId, %s:getGuid(), %s, player:getGuid())%s'
               '%selse%s'
               '%s'
               '%send -- %s%s') % (i, MARK, nl, i, m.group('who'), m.group('from'), nl, i, nl, block, i, MARK, nl)
        text = text[:m.start()] + new + text[m.end():]
    # 5. the distance check
    m = NEAR_RE.search(text)
    new = ('{i}for _, chaosPos in ipairs(chaosPlayerTilesNear({c}, {d})) do -- %s: no map scan\n'
           '{i2}do\n'
           '{i3}do local x, y, z = chaosPos.x, chaosPos.y, chaosPos.z\n' % MARK).format(
        i=m.group('i'), i2=m.group('i2'), i3=m.group('i3'), c=m.group('c'), d=m.group('d'))
    text = text[:m.start()] + crlf(text, new) + text[m.end():]
    # 4. the wait after "A team is already inside."
    text = INSIDE_RE.sub('player:sendTextMessage(MESSAGE_STATUS_SMALL, msg.PlayerInside .. chaosDungeonWait(choiceId))'
                         ' --[[ %s ]]' % MARK, text, count=1)
    # 3. the box scan
    m = next(m for m in SCAN_RE.finditer(text) if 'getTopCreature()' in m.group('body'))
    new = '%slocal players = chaosDungeonInside(choiceId) -- %s: no scan of the dungeon box\n' % (m.group('i'), MARK)
    text = text[:m.start()] + crlf(text, new) + text[m.end():]
    # 2. the cooldown storage
    m = STO_RE.search(text)
    new = ('%sif ChaosDungeons and ChaosDungeons.modalStorages then sto = ChaosDungeons.modalStorages(sto) end'
           ' -- %s\n') % (m.group(1), MARK)
    text = text[:m.end()] + crlf(text, new) + text[m.end():]
    # 1. the helpers
    m = FUNC_RE.search(text)
    text = text[:m.start()] + crlf(text, HELPERS) + text[m.start():]
    return text, 'patched'


def files(data):
    for sub in ('creaturescripts', 'scripts'):
        root = os.path.join(data, sub)
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            if sub == 'scripts' and os.path.relpath(dirpath, root) == '.':
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
        print('no base dungeon window script found (nothing to do)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
