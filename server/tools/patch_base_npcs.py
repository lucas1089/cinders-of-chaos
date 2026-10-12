#!/usr/bin/env python3
"""Small, idempotent fixes to the base server's NPC library (data/npc/lib, not part of this repository).

usage: python3 -I patch_base_npcs.py DATA_DIR [--dry-run]

The NPC scripts of the base server were written for a newer library than the one it ships (TFS 1.4 Jiddo system):

1. Replies given as a list of lines. 50 keyword replies in 20 scripts (every "twist of fate" priest such as Yberius,
   Chondur, A Bearded Woman, Myra, ...) and the greetings of Al Dee and Umar are tables of lines.
   NpcHandler:say already talks a table line by line (doNPCTalkALot), but NpcHandler:parseMessage ran string.gsub on
   it first: "npchandler.lua:311: bad argument #1 to 'gsub' (string expected, got table)" and no answer.
   parseMessage now fills the tags of every line of a table and hands anything that is not a string back unchanged;
   NpcHandler:say says nothing for a nil message (Seymour's "dead rat" and "destiny" nodes and Pydar's "heal" have no
   text: their reply comes from the node's action or is missing, which used to stop the dialogue with a gsub error).

2. Tags no parseInfo filled: |BLESSCOST| and |PVPBLESSCOST| (the blessing priests, 21 replies) and |TIME| (18 replies)
   were printed as they are. StdModule.say now fills them (the blessing cost for the player's level, the world time).

3. StdModule.bless got the cost as the string '|BLESSCOST|' / '|PVPBLESSCOST|' from those scripts and compared it with
   numbers in Player.removeTotalMoney ("attempt to compare string with number", no blessing). The tag is now turned
   into the cost for the player's level first (a number cost is unchanged).
   Costs (10.98 rules): a blessing 2000 gold up to level 30, then 200 per level above 20, at most 20000 (level 120);
   the twist of fate the same, at most 50000 (level 270). A base lib that defines getBlessingsCost /
   getPvpBlessingCost is used instead.

4. data/npc/lib/npc.lua: the delayed lines of a table reply (doCreatureSayWithDelay) indexed Player(pcid) without a
   check, so a player who logged out (or an NPC removed) during a long reply raised "attempt to index a nil value".

Exact match on the stock lines; anything else is reported and left alone. Idempotent: every change carries a marker.
"""
import os, sys

MARK = 'Chaos: (patch_base_npcs.py)'

# ---------------------------------------------------------------- 1. npchandler.lua
PARSE_OLD = (
    '\tfunction NpcHandler:parseMessage(msg, parseInfo)\n'
    '\t\tlocal ret = msg\n'
    '\t\tfor search, replace in pairs(parseInfo) do\n'
    '\t\t\tret = string.gsub(ret, search, replace)\n'
    '\t\tend\n'
    '\t\treturn ret\n'
    '\tend\n'
)
PARSE_MARK = '-- Chaos: a reply may be a table of lines; nil stays nil (patch_base_npcs.py)'
PARSE_NEW = (
    '\tfunction NpcHandler:parseMessage(msg, parseInfo)\n'
    '\t\t' + PARSE_MARK + '\n'
    '\t\tif type(msg) == "table" then\n'
    '\t\t\tlocal lines = {}\n'
    '\t\t\tfor i, line in ipairs(msg) do\n'
    '\t\t\t\tlines[i] = self:parseMessage(line, parseInfo)\n'
    '\t\t\tend\n'
    '\t\t\treturn lines\n'
    '\t\telseif type(msg) ~= "string" then\n'
    '\t\t\treturn msg\n'
    '\t\tend\n'
    '\t\tlocal ret = msg\n'
    '\t\tfor search, replace in pairs(parseInfo) do\n'
    '\t\t\tret = string.gsub(ret, search, (tostring(replace):gsub("%%", "%%%%")))\n'
    '\t\tend\n'
    '\t\treturn ret\n'
    '\tend\n'
)
SAY_OLD = (
    '\tfunction NpcHandler:say(message, focus, publicize, shallDelay, delay)\n'
    '\t\tif type(message) == "table" then\n'
)
SAY_MARK = '-- Chaos: nothing to say for a node without text (patch_base_npcs.py)'
SAY_NEW = (
    '\tfunction NpcHandler:say(message, focus, publicize, shallDelay, delay)\n'
    '\t\t' + SAY_MARK + '\n'
    '\t\tif message == nil then\n'
    '\t\t\treturn\n'
    '\t\tend\n'
    '\t\tif type(message) == "table" then\n'
)


def patch_npchandler(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    done = [PARSE_MARK in text, SAY_MARK in text]
    if all(done):
        return text, 'already'
    if not done[0] and text.count(PARSE_OLD) != 1:
        return text, 'unexpected npchandler.lua (the stock NpcHandler:parseMessage not found once)'
    if not done[1] and text.count(SAY_OLD) != 1:
        return text, 'unexpected npchandler.lua (the stock NpcHandler:say opening not found once)'
    if not done[0]:
        text = text.replace(PARSE_OLD, PARSE_NEW, 1)
    if not done[1]:
        text = text.replace(SAY_OLD, SAY_NEW, 1)
    return text, 'patched'


# ---------------------------------------------------------------- 2. + 3. modules.lua
HELPERS_MARK = '-- Chaos: blessing costs and the |TIME| tag for the base NPC scripts (patch_base_npcs.py)'
HELPERS = (
    '\t' + HELPERS_MARK + '\n'
    '\tfunction StdModule.chaosBlessCost(level, twist)\n'
    '\t\tlocal own = twist and getPvpBlessingCost or getBlessingsCost\n'
    '\t\tif type(own) == "function" then\n'
    '\t\t\treturn own(level)\n'
    '\t\tend\n'
    '\t\tlevel = tonumber(level) or 1\n'
    '\t\tif level <= 30 then\n'
    '\t\t\treturn 2000\n'
    '\t\tend\n'
    '\t\treturn math.min(twist and 50000 or 20000, (math.floor(level) - 20) * 200)\n'
    '\tend\n'
    '\n'
    '\tfunction StdModule.chaosTags(player, parseInfo)\n'
    '\t\tlocal level = player and player:getLevel() or 1\n'
    '\t\tparseInfo["|BLESSCOST|"] = StdModule.chaosBlessCost(level, false)\n'
    '\t\tparseInfo["|PVPBLESSCOST|"] = StdModule.chaosBlessCost(level, true)\n'
    '\t\tif type(getFormattedWorldTime) == "function" then\n'
    '\t\t\tparseInfo["|TIME|"] = getFormattedWorldTime()\n'
    '\t\tend\n'
    '\t\treturn parseInfo\n'
    '\tend\n'
    '\n'
    '\t-- a cost given as a tag (\'|BLESSCOST|\', \'|PVPBLESSCOST|\') for this player; a number stays as it is\n'
    '\tfunction StdModule.chaosCost(player, cost)\n'
    '\t\tif type(cost) ~= "string" then\n'
    '\t\t\treturn cost\n'
    '\t\tend\n'
    '\t\tlocal tags = StdModule.chaosTags(player, {})\n'
    '\t\treturn tonumber(tags[cost]) or tonumber(cost) or cost\n'
    '\tend\n'
    '\n'
)
STDSAY_HEAD = '\tfunction StdModule.say(cid, message, keywords, parameters, node)\n'
STDSAY_OLD = '\t\tlocal parseInfo = {[TAG_PLAYERNAME] = Player(cid):getName()}\n'
STDSAY_NEW = ('\t\tlocal parseInfo = StdModule.chaosTags(Player(cid), {[TAG_PLAYERNAME] = Player(cid):getName()}) '
              '-- Chaos: (patch_base_npcs.py)\n')
BLESS_HEAD = '\tfunction StdModule.bless(cid, message, keywords, parameters, node)\n'
BLESS_OLD = '\t\t\telseif not player:removeTotalMoney(parameters.cost) then\n'
BLESS_NEW = ('\t\t\telseif not player:removeTotalMoney(StdModule.chaosCost(player, parameters.cost)) then '
             '-- Chaos: (patch_base_npcs.py)\n')


def _in_function(text, head, old):
    """index of `old` inside the function that starts with `head` (up to the next top-level function), or -1"""
    start = text.find(head)
    if start < 0 or text.count(head) != 1:
        return -1
    end = text.find('\n\tfunction ', start + len(head))
    end = len(text) if end < 0 else end
    at = text.find(old, start, end)
    if at < 0 or text.find(old, at + 1, end) >= 0:
        return -1
    return at


def patch_modules(text):
    """returns (new text, status)"""
    done = [HELPERS_MARK in text, STDSAY_NEW in text, BLESS_NEW in text]
    if all(done):
        return text, 'already'
    say_at = -1 if done[1] else _in_function(text, STDSAY_HEAD, STDSAY_OLD)
    if not done[1] and say_at < 0:
        return text, 'unexpected modules.lua (the stock parseInfo line of StdModule.say not found once)'
    bless_at = -1 if done[2] else _in_function(text, BLESS_HEAD, BLESS_OLD)
    if not done[2] and bless_at < 0:
        return text, 'unexpected modules.lua (the stock cost line of StdModule.bless not found once)'
    if not done[0] and text.count(STDSAY_HEAD) != 1:
        return text, 'unexpected modules.lua (StdModule.say not found once)'
    # the later edits first so the earlier offsets stay valid
    edits = []
    if bless_at >= 0:
        edits.append((bless_at, len(BLESS_OLD), BLESS_NEW))
    if say_at >= 0:
        edits.append((say_at, len(STDSAY_OLD), STDSAY_NEW))
    if not done[0]:
        edits.append((text.find(STDSAY_HEAD), 0, HELPERS))
    for at, n, new in sorted(edits, key=lambda e: e[0], reverse=True):
        text = text[:at] + new + text[at + n:]
    return text, 'patched'


# ---------------------------------------------------------------- 4. npc.lua
DELAY_FUNC_OLD = (
    'local func = function(cid, text, type, e, pcid)\n'
    '\tif Player(pcid):isPlayer() then\n'
    '\t\tlocal creature = Creature(cid)\n'
    '\t\tcreature:say(text, type, false, pcid, creature:getPosition())\n'
)
DELAY_MARK = '-- Chaos: the player may have logged out, the NPC may be gone (patch_base_npcs.py)'
DELAY_FUNC_NEW = (
    'local func = function(cid, text, type, e, pcid)\n'
    '\t' + DELAY_MARK + '\n'
    '\tlocal creature = Creature(cid)\n'
    '\tif Player(pcid) and creature then\n'
    '\t\tcreature:say(text, type, false, pcid, creature:getPosition())\n'
)
DELAY_ADD_OLD = (
    'function doCreatureSayWithDelay(cid, text, type, delay, e, pcid)\n'
    '\tif Player(pcid):isPlayer() then\n'
)
DELAY_ADD_NEW = (
    'function doCreatureSayWithDelay(cid, text, type, delay, e, pcid)\n'
    '\tif Player(pcid) then -- Chaos: (patch_base_npcs.py)\n'
)


def patch_npc_lib(text):
    """returns (new text, status)"""
    done = [DELAY_MARK in text, DELAY_ADD_NEW in text]
    if all(done):
        return text, 'already'
    if not done[0] and text.count(DELAY_FUNC_OLD) != 1:
        return text, 'unexpected npc.lua (the stock delayed-say function not found once)'
    if not done[1] and text.count(DELAY_ADD_OLD) != 1:
        return text, 'unexpected npc.lua (the stock doCreatureSayWithDelay not found once)'
    if not done[0]:
        text = text.replace(DELAY_FUNC_OLD, DELAY_FUNC_NEW, 1)
    if not done[1]:
        text = text.replace(DELAY_ADD_OLD, DELAY_ADD_NEW, 1)
    return text, 'patched'


def apply(path, fn, dry):
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    new, status = fn(text)
    if status == 'patched' and not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    print(f'{path}: {status}')
    return status in ('patched', 'already')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    dry = '--dry-run' in sys.argv
    lib = os.path.join(args[0], 'npc', 'lib')
    ok = apply(os.path.join(lib, 'npcsystem', 'npchandler.lua'), patch_npchandler, dry)
    ok = apply(os.path.join(lib, 'npcsystem', 'modules.lua'), patch_modules, dry) and ok
    ok = apply(os.path.join(lib, 'npc.lua'), patch_npc_lib, dry) and ok
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
