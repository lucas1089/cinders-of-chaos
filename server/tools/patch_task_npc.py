#!/usr/bin/env python3
"""Task NPC names and task kills (idempotent). install_all.py step `tasknpc`.

usage: python3 -I patch_task_npc.py DATA_DIR [--dry-run]

Beta report 2026-10-22 (server/README.md "Task NPC names"): at the base task NPC (Mermod) saying most task names did
nothing, so no task started and no kill counted. The base scripts:

1. The NPC script (data/npc/scripts, the one with the task_monsters / task_daily dialogue) took a name only after the
   word "normal" or "daily" in a line of its own, and compared it letter for letter (`if msg == l.name then`): a bare
   name, "normal <name>", the name in brackets as the list shows it, a hyphen or a missing apostrophe got no answer.
   After `local msg = msg:lower()` a bare name or "normal / daily <name>" now starts that task the stock way
   (ChaosTaskNames.route; a daily name on the daily cooldown gets the stock cooldown reply), and both name loops also
   accept ChaosTaskNames.same.
2. The kill script (data/scripts, the one with updateTaskProgress) compared the shown name only, case sensitive (a list
   entry with a capital letter never counted; a renamed or prefixed monster neither) and gave every party member the
   killer's task instead of their own. A kill now also counts by ChaosTaskNames.killCounts (shown name and type name,
   any case) and each member gets their own task.

The pure rules are data/lib/chaos_task_names.lua (tests/task_names_test.lua); the patched lines load it when the server
has not. Files are found by their stock lines, not by name. Exact match on the stock lines; anything else is reported and
left alone. Marker: `Chaos: task names (patch_task_npc.py)`. A second run changes nothing.
"""
import os
import re
import sys

MARK = 'Chaos: task names (patch_task_npc.py)'
LOAD = "if not ChaosTaskNames then pcall(dofile, 'data/lib/chaos_task_names.lua') end"

# ---------------------------------------------------------------- 1. the NPC script
NPC_LOWER = re.compile(r'^([ \t]*)local msg = msg:lower\(\)[ \t]*$', re.M)
NPC_ROUTE = '''{i}-- {mark}: a bare task name, "normal <name>" or "daily <name>" starts the task
{i}{load}
{i}if ChaosTaskNames and (npcHandler.topic[cid] or 0) == 0 then
{i}    local chaosKind, chaosIndex = ChaosTaskNames.route(msg, task_monsters, task_daily)
{i}    if chaosKind == 'normal' then
{i}        npcHandler.topic[cid] = 1
{i}        msg = task_monsters[chaosIndex].name
{i}    elseif chaosKind == 'daily' then
{i}        if player:getStorageValue(time_daySto) < os.time() then
{i}            npcHandler.topic[cid] = 2
{i}            msg = task_daily[chaosIndex].name
{i}        else
{i}            msg = 'daily'
{i}        end
{i}    end
{i}end
'''
NPC_MATCH_OLD = re.compile(r'^([ \t]*)if msg == l\.name then[ \t]*$', re.M)
NPC_MATCH_NEW = r'\1if msg == l.name or (ChaosTaskNames and ChaosTaskNames.same(msg, l.name)) then -- Chaos: any case'

# ---------------------------------------------------------------- 2. the kill script
KILL_NAME = re.compile(r'^([ \t]*)local mon_name = target:getName\(\):lower\(\)[ \t]*$', re.M)
KILL_NAME_NEW = '''\\g<0>
\\1-- {mark}: kills by shown or type name, any case; each party member their own task
\\1{load}
\\1local chaosTypeName = Chaos and Chaos.monsterTypeName and Chaos.monsterTypeName(target) or nil
\\1local chaosShownName = target:getName()'''
KILL_COND_OLD = 'if taskInfo and (mon_name == taskInfo.name or isInArray(taskInfo.mons_list, mon_name)) then'
KILL_COND_NEW = ('if taskInfo and (mon_name == taskInfo.name or isInArray(taskInfo.mons_list, mon_name) or '
                 '(ChaosTaskNames and ChaosTaskNames.killCounts(taskInfo, chaosShownName, chaosTypeName))) then')
PARTY = [('updateTaskProgress(member, getTaskInfos(player))', 'updateTaskProgress(member, getTaskInfos(member))'),
         ('updateTaskProgress(member, getTaskDailyInfo(player))', 'updateTaskProgress(member, getTaskDailyInfo(member))')]


def is_npc_script(text):
    return 'task_monsters' in text and 'task_daily' in text and 'creatureSayCallback' in text and \
        NPC_MATCH_OLD.search(text) is not None


def is_kill_script(text):
    return 'updateTaskProgress' in text and 'onKill' in text


def patch_npc(text):
    """(new text, [change, ...]); a first change starting with REFUSED is an error"""
    if MARK in text:
        return text, []
    lowers = NPC_LOWER.findall(text)
    matches = NPC_MATCH_OLD.findall(text)
    if len(lowers) != 1 or len(matches) != 2:
        return text, ['REFUSED: expected one "local msg = msg:lower()" and two name loops, found %d and %d'
                      % (len(lowers), len(matches))]

    def route(m):
        return m.group(0) + '\n' + NPC_ROUTE.format(i=m.group(1), mark=MARK, load=LOAD).rstrip('\n')
    text = NPC_LOWER.sub(route, text, count=1)
    text = NPC_MATCH_OLD.sub(NPC_MATCH_NEW, text)
    return text, ['bare task names and "normal / daily <name>" start a task', 'name loops match any case']


def patch_kill(text):
    if MARK in text:
        return text, []
    if len(KILL_NAME.findall(text)) != 1 or text.count(KILL_COND_OLD) != 1 or \
            any(text.count(old) != 1 for old, _ in PARTY):
        return text, ['REFUSED: expected stock kill lines not found']
    text = KILL_NAME.sub(KILL_NAME_NEW.format(mark=MARK, load=LOAD), text, count=1)
    text = text.replace(KILL_COND_OLD, KILL_COND_NEW)
    for old, new in PARTY:
        text = text.replace(old, new)
    return text, ['kills count by shown or type name, any case', 'party members get their own task']


def lua_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn.endswith('.lua'):
                yield os.path.join(dirpath, fn)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    data = args[0]
    found = {'npc': 0, 'kill': 0}
    changed, bad = 0, 0
    jobs = [('npc', os.path.join(data, 'npc', 'scripts'), is_npc_script, patch_npc),
            ('kill', os.path.join(data, 'scripts'), is_kill_script, patch_kill)]
    for kind, root, test, patch in jobs:
        for path in lua_files(root):
            text = read(path)
            if MARK not in text and not test(text.replace('\r\n', '\n')):
                continue
            found[kind] += 1
            crlf = '\r\n' in text
            new, changes = patch(text.replace('\r\n', '\n'))
            rel = os.path.relpath(path, data).replace(os.sep, '/')
            if changes and changes[0].startswith('REFUSED'):
                print('%s: %s' % (rel, changes[0]))
                bad += 1
                continue
            if not changes:
                continue
            if crlf:
                new = new.replace('\n', '\r\n')
            if not dry:
                with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                    f.write(new)
            print('%s: %s' % (rel, ', '.join(changes)))
            changed += 1
    for kind in ('npc', 'kill'):
        if not found[kind]:
            print('task %s script: not found (skipped)' % kind)
    print('task names: %d file(s) %s' % (changed, 'would change' if dry else 'changed') if changed
          else 'task names: nothing to change')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
