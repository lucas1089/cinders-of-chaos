#!/usr/bin/env python3
"""The base scripts that hand out prizes give them into the backpack, never into an inventory slot (idempotent).
install_all.py step `prizes`.

usage: python3 -I patch_prizes.py DATA_DIR [--dry-run] [--check]

server/README.md "Prizes into the backpack". User report 2026-10-21: the Boss Roulette said "you won The Awakener" (a
ship) and the ship was in no bag and not in the inbox. The base gives prizes with player:addItem(id, count), and the
engine puts a new item into an empty inventory slot that takes it before any container: the ship went into the ship
slot (14), which no client draws. Engine patch 0058 refuses those slots now; this tool makes the base scripts give
their prizes through data/scripts/chaos/prizes.lua (ChaosPrizes): the backpack (or a container in it), else the store
inbox ("Purse"), else the ground under the player. The base scripts are found by their content:

1. the roulettes (each script with `local function rewardPlayer(playerId, leverPosition)` and a `prizePool`):
   - rewardPlayer asks ChaosPrizes.rouletteReward first: the prize on the winning tile goes to the player as above; a
     tile that holds no prize any more (nil, a creature, the ground) gives nothing and keeps the free spin; the rare
     prize broadcast reads the pool's chance of that item (the base read chancedItems[#chancedItems - 3], the chance
     of another spin's item, nil after fewer than four spins).
   - the prize pool lines of the decks, ships, belts and gloves (tools/patch_badges.py; nothing can wear them) are
     commented out. The other entries keep their chances; the README lists the new odds.
   - the base body stays as the fallback without the Chaos scripts, with the two nil guards (the winning tile's thing,
     the broadcast lookup); initiateReward reads the winning tile the same guarded way.
2. the task rewards (the script with `self:addItem(reward.Id, reward.Amount)`): ChaosPrizes.give first.
3. the base crafting script after tools/patch_base_crafting.py (`CraftGuard.added(player:addItemEx(item))`):
   ChaosPrizes.stow first (the backpack or a container in it), then the base addItemEx.
4. the NPC that builds the first ship (the NPC script with `player:addItem(27799, 1)`): ChaosPrizes.give first.

Every changed line carries the mark; without the Chaos scripts loaded the scripts work as before. A second run changes
nothing. --check changes nothing and exits 1 when something is still to do. Line endings (LF or CRLF) are kept.
"""
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_badges  # noqa: E402

RETIRED = frozenset(patch_badges.DECKS) | frozenset(patch_badges.SHIPS) | frozenset(patch_badges.BELTGLOVES)
MARK = 'Chaos: prizes into the backpack (patch_prizes.py)'

REWARD_HEAD = re.compile(r'^local function rewardPlayer\(playerId, leverPosition\)[ \t]*\n', re.M)
POOL_LINE = re.compile(r'^([ \t]*)(\{[ \t]*itemId[ \t]*=[ \t]*(\d+)[ \t]*,[^\n]*?)[ \t]*$', re.M)
WIN_TILE = re.compile(r'^([ \t]*)local item = Tile\(config\.roulettePositions\[([^\]\n]+)\]\):getTopVisibleThing\(\)'
                      r'[ \t]*$', re.M)
LABEL = re.compile(r'from the (\w+) roulette!')
INIT_INFO = re.compile(r'^([ \t]*)local newItemInfo = \{itemId = item:getId\(\), count = item:getCount\(\)\}[ \t]*$',
                       re.M)
INIT_INFO_NEW = (r'\1local newItemInfo = item and item.isItem and item:isItem() and '
                 r'{itemId = item:getId(), count = item:getCount()} or nil -- ' + MARK)
BROADCAST_OLD = 'chancedItems[#chancedItems - 3] <='
BROADCAST_NEW = '(chancedItems[#chancedItems - 3] or math.huge) <='
TASK_LINE = re.compile(r'^([ \t]*)self:addItem\(reward\.Id, reward\.Amount\)[ \t]*$', re.M)
TASK_NEW = (r'\1if not (ChaosPrizes and ChaosPrizes.give and ChaosPrizes.give(self, reward.Id, reward.Amount)) then '
            r'self:addItem(reward.Id, reward.Amount) end -- ' + MARK)
CRAFT_LINE = re.compile(r'^([ \t]*if not CraftGuard\.added\()player:addItemEx\(item\)(\) then)[ \t]*$', re.M)
CRAFT_NEW = (r'\1ChaosPrizes and ChaosPrizes.stow and ChaosPrizes.stow(player, item) or player:addItemEx(item)\2 -- '
             + MARK)
SHIP_LINE = re.compile(r'^([ \t]*)player:addItem\(27799, 1\)[ \t]*$', re.M)
SHIP_NEW = (r'\1if not (ChaosPrizes and ChaosPrizes.give and ChaosPrizes.give(player, 27799, 1)) then '
            r'player:addItem(27799, 1) end -- ' + MARK)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def function_span(text, head):
    """(start, end) of the function whose header matched: up to and including its closing `end` at column 0"""
    m = re.compile(r'^end[ \t]*$', re.M).search(text, head.end())
    return head.start(), (m.end() if m else len(text))


def roulette(text):
    """(new text, changes); changes is -1 when the script is a roulette this tool can't read (left alone)"""
    n = 0
    head = REWARD_HEAD.search(text)
    if not head:
        return text, 0
    start, end = function_span(text, head)
    body = text[head.end():end]
    if MARK not in body:
        tile = WIN_TILE.search(body)
        label = LABEL.search(body)
        if not (tile and label):
            return text, -1
        indent, where = tile.group(1), tile.group(2).strip()
        inner = indent + ('\t' if indent.startswith('\t') else '    ')
        hook = ('{i}-- {mark}: the prize into the backpack, else the Purse, else the ground\n'
                '{i}if ChaosPrizes and ChaosPrizes.rouletteReward then\n'
                '{j}ChaosPrizes.rouletteReward(playerId, config, config.roulettePositions[{w}], "{label}")\n'
                '{j}return\n'
                '{i}end\n').format(i=indent, j=inner, mark=MARK, w=where, label=label.group(1))
        guard = '\n%sif not (item and item.isItem and item:isItem()) then return end -- %s' % (indent, MARK)
        body = body[:tile.end()] + guard + body[tile.end():]
        body = hook + body
        text = text[:head.end()] + body + text[end:]
        n += 2

    def pool(m):
        nonlocal n
        if int(m.group(3)) not in RETIRED:
            return m.group(0)
        n += 1
        return '%s-- %s -- %s: nothing can wear it' % (m.group(1), m.group(2), MARK)
    text = POOL_LINE.sub(pool, text)
    text, k = INIT_INFO.subn(INIT_INFO_NEW, text)
    n += k
    k = text.count(BROADCAST_OLD)
    text = text.replace(BROADCAST_OLD, BROADCAST_NEW)
    return text, n + k


def task_rewards(text):
    return TASK_LINE.subn(TASK_NEW, text)


def crafting(text):
    return CRAFT_LINE.subn(CRAFT_NEW, text)


def ship_npc(text):
    return SHIP_LINE.subn(SHIP_NEW, text)


def files(root):
    for d, _sub, fs in sorted(os.walk(root)):
        for f in sorted(fs):
            if f.endswith('.lua'):
                yield os.path.join(d, f)


def run(data, dry=False):
    """-> (lines of the report, how many files change)"""
    report, changed = [], 0
    found = {}

    def apply(path, fn, what):
        nonlocal changed
        raw = read(path)
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        new, n = fn(text)
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        if n < 0:
            report.append('%s: a roulette this tool cannot read (left alone)' % rel)
            return
        if n or MARK in text:
            found[what] = found.get(what, 0) + 1
        if not n:
            return
        if fn(new)[1]:
            raise SystemExit('%s: not idempotent' % path)
        if crlf:
            new = new.replace('\n', '\r\n')
        changed += 1
        report.append('%s: %d change(s)' % (rel, n))
        if not dry:
            write(path, new)

    scripts = os.path.join(data, 'scripts')
    for path in files(scripts):
        if os.sep + 'chaos' + os.sep in path:
            continue
        text = read(path).replace('\r\n', '\n')
        if REWARD_HEAD.search(text) and 'prizePool' in text:
            apply(path, roulette, 'roulette')
        if TASK_LINE.search(text) or MARK in text and 'reward.Id' in text:
            apply(path, task_rewards, 'tasks')
        if CRAFT_LINE.search(text) or MARK in text and 'CraftGuard.added' in text:
            apply(path, crafting, 'crafting')
    npc_dir = os.path.join(data, 'npc', 'scripts')
    if os.path.isdir(npc_dir):
        for path in files(npc_dir):
            if 'addItem(27799' in read(path):
                apply(path, ship_npc, 'ship')
    if not dry:
        for what, where in (('roulette', 'the roulettes'), ('tasks', 'the task rewards'),
                            ('crafting', 'the crafting script (run patch_base_crafting.py first)'),
                            ('ship', 'the ship NPC')):
            if what not in found:
                report.append('%s not found (skipped)' % where)
    return report, changed


def main(argv):
    dry = '--dry-run' in argv or '--check' in argv
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    report, changed = run(args[0], dry)
    for line in report:
        print(line)
    verb = 'would change' if dry else 'changed'
    print('prizes: %d file(s) %s' % (changed, verb) if changed else 'prizes: nothing to change')
    return 1 if ('--check' in argv and changed) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
