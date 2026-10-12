#!/usr/bin/env python3
"""Turn off every stock promotion path of the base server (idempotent). Ascension is a quest now (docs/CLASSES.md
"Ascension quest", data/scripts/chaos/ascension_quest.lua): the stock promotion picked Vocation:getPromotion(), one of the
two ascended classes more or less at random, and skipped the class system.

usage: python3 -I patch_promotion.py DATA_DIR [--dry-run]

1. data/npc/lib/npcsystem/modules.lua: StdModule.promotePlayer (King Tibianus, Queen Eloise, the emperors, Ishebad,
   The Forgotten King, ... all call it) refuses: the NPC says TEXT and resets. Nothing is charged, nothing changes.
2. data/npc/scripts/*.lua: every script that promotes (StdModule.promotePlayer, or a direct
   player:setVocation(<promotion or demotion>)) answers "promotion" with TEXT first: a keyword added right after
   NpcSystem.parseParameters (the keyword handler takes the first match), and, for scripts with their own
   creatureSayCallback that promote directly, a check at the top of the callback. The direct setVocation calls are
   commented out.
3. data/creaturescripts/scripts/login.lua: the premium branch of the stock login set the vocation to its promotion
   when the promotion storage (30018) was 1; that line is commented out (the demotion branch is handled by
   patch_base_events.py step 4).

Then the whole data folder (except scripts/chaos) is scanned for other setVocation calls with a promotion or demotion;
they are listed for a manual check (none in the base server this was written for: the Oracle on the starting island sets
the first vocation, which is not a promotion). The base server's store has no promotion offer.

Idempotent: every change carries the marker "patch_promotion.py" and is not made twice.
"""
import os
import re
import sys

LEVEL = 100
TEXT = ("The old rites of promotion are broken; no king can grant what must be earned. At level %d, seek the "
        "Ascendant Oracle in the temple and walk the road of ascension." % LEVEL)
MARK = 'Chaos: no stock promotion, ascension is a quest (patch_promotion.py)'
DIRECT = re.compile(r'^([ \t]*)((?:player|p|target|creature)\s*:\s*setVocation\s*\(\s*'
                    r'(?:promotion|[\w.]*:getPromotion\(\)|[\w.]*:getDemotion\(\)|Vocation\(\s*[\w.]*:getPromotion\(\)\s*\))\s*\))',
                    re.M)


def lua_str(text):
    return "'" + text.replace('\\', '\\\\').replace("'", "\\'") + "'"


def patch_modules(text):
    """StdModule.promotePlayer refuses"""
    if MARK in text:
        return text, 'already'
    start = text.find('function StdModule.promotePlayer(')
    if start < 0:
        return text, 'StdModule.promotePlayer not found'
    m = re.compile(r'\n([ \t]*)if not npcHandler:isFocused\(cid\) then\s*\n\s*return false\s*\n[ \t]*end[ \t]*\n').search(text, start)
    nxt = text.find('function StdModule.', start + 10)
    if not m or (nxt >= 0 and m.start() > nxt):
        return text, 'no focus check in StdModule.promotePlayer'
    ind = m.group(1)
    block = (ind + '-- ' + MARK + '\n' +
             ind + 'npcHandler:say(' + lua_str(TEXT) + ', cid)\n' +
             ind + 'npcHandler:resetNpc(cid)\n' +
             ind + 'do return true end\n')
    return text[:m.end()] + block + text[m.end():], 'patched'


def promotes(text):
    return 'StdModule.promotePlayer' in text or DIRECT.search(text) is not None


def patch_npc_script(text):
    """returns (new text, status) for one NPC script"""
    if MARK in text:
        return text, 'already'
    if not promotes(text):
        return text, 'skip'
    out = text
    changed = []
    # 1. the keyword, first in the handler
    m = re.search(r'^([ \t]*)NpcSystem\.parseParameters\(npcHandler\)[ \t]*\r?\n', out, re.M)
    if m and 'keywordHandler' in out:
        line = ("keywordHandler:addKeyword({'promot'}, StdModule.say, {npcHandler = npcHandler, text = %s}) -- %s\n"
                % (lua_str(TEXT), MARK))
        out = out[:m.end()] + line + out[m.end():]
        changed.append('keyword')
    # 2. direct promotions: intercept "promot" at the top of the callback and comment the calls out
    if DIRECT.search(out):
        cb = re.search(r'^([ \t]*)local function creatureSayCallback\(cid, type, msg\)[ \t]*\r?\n', out, re.M)
        if cb:
            ind = cb.group(1) + '\t'
            block = (ind + '-- ' + MARK + '\n' +
                     ind + 'if npcHandler:isFocused(cid) and msgcontains(msg, "promot") then\n' +
                     ind + '\tnpcHandler:say(' + lua_str(TEXT) + ', cid)\n' +
                     ind + '\tnpcHandler.topic[cid] = 0\n' +
                     ind + '\treturn true\n' +
                     ind + 'end\n')
            out = out[:cb.end()] + block + out[cb.end():]
            changed.append('callback')
        out, n = DIRECT.subn(lambda mm: mm.group(1) + '-- ' + mm.group(2) + ' -- ' + MARK, out)
        if n:
            changed.append('%d setVocation' % n)
    if not changed:
        return text, 'promotes, but no place to patch (check by hand)'
    if MARK not in out:
        out = '-- ' + MARK + '\n' + out
    return out, 'patched (' + ', '.join(changed) + ')'


def patch_login(text):
    """the premium branch's setVocation(promotion)"""
    if MARK in text:
        return text, 'already'
    out, n = DIRECT.subn(lambda mm: mm.group(1) + '-- ' + mm.group(2) + ' -- ' + MARK, text)
    if not n:
        return text, 'no promotion at login (nothing to do)'
    return out, 'patched (%d setVocation)' % n


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def apply(path, fn, dry, quiet_skip=False):
    if not os.path.isfile(path):
        print('%s: missing' % path)
        return False
    text = read(path)
    new, status = fn(text)
    if status == 'skip' and quiet_skip:
        return True
    if new != text and not dry:
        write(path, new)
    print('%s: %s%s' % (path, status, ' (dry run)' if dry and new != text else ''))
    return status in ('already', 'skip', 'no promotion at login (nothing to do)') or status.startswith('patched')


def scan(data):
    """other setVocation calls with a promotion or demotion outside the NPCs and the Chaos scripts"""
    found = []
    for root, dirs, files in os.walk(data):
        dirs.sort()
        rel = os.path.relpath(root, data).replace(os.sep, '/')
        if rel.startswith('scripts/chaos') or rel.startswith('npc'):
            continue
        for name in sorted(files):
            if not name.endswith('.lua'):
                continue
            path = os.path.join(root, name)
            if os.path.relpath(path, data).replace(os.sep, '/') == 'creaturescripts/scripts/login.lua':
                continue  # step 3
            for i, line in enumerate(read(path).split('\n'), 1):
                if MARK in line or line.lstrip().startswith('--'):
                    continue
                if DIRECT.search(line):
                    found.append('%s:%d: %s' % (os.path.relpath(path, data), i, line.strip()))
    return found


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    data = args[0]
    dry = '--dry-run' in sys.argv
    ok = apply(os.path.join(data, 'npc', 'lib', 'npcsystem', 'modules.lua'), patch_modules, dry)
    scripts = os.path.join(data, 'npc', 'scripts')
    if os.path.isdir(scripts):
        for name in sorted(os.listdir(scripts)):
            if name.endswith('.lua'):
                ok = apply(os.path.join(scripts, name), patch_npc_script, dry, quiet_skip=True) and ok
    ok = apply(os.path.join(data, 'creaturescripts', 'scripts', 'login.lua'), patch_login, dry) and ok
    rest = scan(data)
    for line in rest:
        print('check by hand: ' + line)
    print('promotion: %s' % ('ok' if ok else 'FAILED'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
