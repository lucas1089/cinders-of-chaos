#!/usr/bin/env python3
"""Test of patch_prizes.py (run: python3 -I server/tools/patch_prizes_test.py) on a small data folder: two roulettes
(the winning tile by index and by #positions, CRLF kept), the retired prize pool lines commented out and the others
kept, the rewardPlayer hook with the right tile and label, the nil guards (winning tile, broadcast lookup,
initiateReward), a roulette it can't read left alone, the task rewards, the crafting script after
patch_base_crafting.py, the ship NPC, scripts/chaos untouched, a second run that changes nothing, --check, and the
patched Lua parses (luac5.3 / luajit when installed)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_prizes as P  # noqa: E402

ROULETTE = '''local config = {
    rouletteOptions = {
        rareItemChance_broadcastThreshold = 5000,
        rouletteStorage = 48550
    },
    prizePool = {
        {itemId = 27633, count = {1, 1},    chance = 7000},
        {itemId = 27822, count = {1, 1},    chance = 6800 },
        {itemId = 27797, count = {1, 1},    chance = 4400 },
        {itemId = 27547, count = {1, 1},    chance = 800  },
    },
    roulettePositions = {
    Position(1, 1, 7),
    }
}

local chancedItems = {}

local function initiateReward(leverPosition, effectCounter)
        if effectCounter == 2 then
            local item = Tile(config.roulettePositions[7]):getTopVisibleThing()
            local newItemInfo = {itemId = item:getId(), count = item:getCount()}
            clearRoulette(newItemInfo)
        end
end

local function rewardPlayer(playerId, leverPosition)
    local player = Player(playerId)
    if not player then
        return
    end

    local item = Tile(config.roulettePositions[7]):getTopVisibleThing()

    if ItemType(item:getId()):hasShowCharges() then
        local addedItem = player:addItem(item:getId(), 1, true)
        addedItem:setAttribute("charges", item:getCharges())
    else
        player:addItem(item:getId(), item:getCount(), true)
    end

    player:setStorageValue(config.rouletteOptions.rouletteStorage, -1)
    if chancedItems[#chancedItems - 3] <= config.rouletteOptions.rareItemChance_broadcastThreshold then
        Game.broadcastMessage("The player " .. player:getName() .. " has won " .. item:getName() .. " from the boss roulette!", MESSAGE_EVENT_ADVANCE)
    end
end
'''
ROULETTE2 = (ROULETTE.replace('[7]', '[#config.roulettePositions]').replace('boss roulette', 'exercise roulette')
             .replace('27633', '28552').replace('27797', '28553'))
NOLABEL = ROULETTE.replace(' from the boss roulette!', '!')
TASKS = '''    elseif reward.Type == RewardType.Item then
      if playerCap >= itemWeight then
        self:addItem(reward.Id, reward.Amount)
      else
        self:getStoreInbox():addItem(reward.Id, reward.Amount)
      end
'''
CRAFT = '''    if not CraftGuard.added(player:addItemEx(item)) then
      CraftGuard.refund(player, craft.cost, craft.materials)
      return
    end
'''
NPC = '''	if x then
		player:addItem(29860, 1)
		player:addItem(27799, 1)
	end
'''

checks = failures = 0


def ok(cond, label):
    global checks, failures
    checks += 1
    if not cond:
        failures += 1
        print('FAIL ' + label)


def put(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


def get(root, rel):
    with open(os.path.join(root, rel), encoding='utf-8', newline='') as f:
        return f.read()


def fn_body(text, name):
    m = re.search(r'^local function %s\(.*?^end' % name, text, re.S | re.M)
    return m.group(0) if m else ''


def parses(path):
    """None when no Lua compiler is installed, else whether every one installed parses the file"""
    tools = [t for t in (['luac5.3', '-p'], ['luajit', '-bl']) if shutil.which(t[0])]
    if not tools:
        return None
    return all(subprocess.run(t + [path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
               for t in tools)


def main():
    tmp = tempfile.mkdtemp(prefix='prizes_test_')
    try:
        data = os.path.join(tmp, 'data')
        put(data, 'scripts/customs/roulette/roulette.lua', ROULETTE.replace('\n', '\r\n'))
        put(data, 'scripts/customs/roulette/roulette2.lua', ROULETTE2)
        put(data, 'scripts/customs/other/odd_roulette.lua', NOLABEL)
        put(data, 'scripts/customs/tasks/tasks.lua', TASKS)
        put(data, 'scripts/customs/crafting/craft.lua', CRAFT)
        put(data, 'scripts/chaos/mine.lua', TASKS)  # our own scripts are never touched
        put(data, 'npc/scripts/builder.lua', NPC)

        ok(P.main([data, '--check']) == 1, '--check before: work to do')
        ok(get(data, 'scripts/customs/tasks/tasks.lua') == TASKS, '--check changes nothing')
        report, changed = P.run(data)
        ok(changed == 5, 'five files change (%d): %s' % (changed, report))
        ok(any('odd_roulette.lua: a roulette this tool cannot read' in r for r in report), 'the odd roulette is listed')
        ok(get(data, 'scripts/customs/other/odd_roulette.lua') == NOLABEL, 'and left alone')

        raw = get(data, 'scripts/customs/roulette/roulette.lua')
        ok('\n' not in raw.replace('\r\n', ''), 'roulette.lua keeps CRLF')
        r1 = raw.replace('\r\n', '\n')
        ok(re.search(r'^\s*-- \{itemId = 27633,.*' + re.escape(P.MARK), r1, re.M) is not None, 'the deck is out of the pool')
        ok(re.search(r'^\s*-- \{itemId = 27797,', r1, re.M) is not None, 'the ship is out of the pool')
        ok(re.search(r'^\s*\{itemId = 27822,', r1, re.M) and re.search(r'^\s*\{itemId = 27547,', r1, re.M),
           'the badge and the other prize stay')
        reward = fn_body(r1, 'rewardPlayer')
        ok('ChaosPrizes.rouletteReward(playerId, config, config.roulettePositions[7], "boss")' in reward,
           'the hook reads tile 7 and the label "boss"')
        ok(reward.index('ChaosPrizes.rouletteReward') < reward.index('local player = Player(playerId)'),
           'the hook runs first')
        ok('        ChaosPrizes.rouletteReward' in reward and '\n        return\n' in reward, 'the hook is indented')
        ok('if not (item and item.isItem and item:isItem()) then return end' in reward, 'the fallback guards the tile')
        ok('(chancedItems[#chancedItems - 3] or math.huge) <=' in reward, 'the fallback broadcast lookup is guarded')
        ok('player:addItem(item:getId(), item:getCount(), true)' in reward, 'the base body stays as the fallback')
        init = fn_body(r1, 'initiateReward')
        ok('local newItemInfo = item and item.isItem and item:isItem() and {itemId' in init, 'initiateReward is guarded')

        r2 = get(data, 'scripts/customs/roulette/roulette2.lua')
        ok('config.roulettePositions[#config.roulettePositions], "exercise")' in r2,
           'the second roulette: the last tile and its label')
        ok(re.search(r'^\s*\{itemId = 28552,', r2, re.M) is not None, 'items that are not retired stay in its pool')

        tasks = get(data, 'scripts/customs/tasks/tasks.lua')
        ok('if not (ChaosPrizes and ChaosPrizes.give and ChaosPrizes.give(self, reward.Id, reward.Amount)) then '
           'self:addItem(reward.Id, reward.Amount) end' in tasks, 'the task reward gives through ChaosPrizes')
        ok('self:getStoreInbox():addItem(reward.Id, reward.Amount)' in tasks, 'the low capacity branch is untouched')
        ok(get(data, 'scripts/chaos/mine.lua') == TASKS, 'scripts/chaos is not touched')
        craft = get(data, 'scripts/customs/crafting/craft.lua')
        ok('CraftGuard.added(ChaosPrizes and ChaosPrizes.stow and ChaosPrizes.stow(player, item) or '
           'player:addItemEx(item)) then' in craft, 'crafting stows first')
        npc = get(data, 'npc/scripts/builder.lua')
        ok('ChaosPrizes.give(player, 27799, 1)) then player:addItem(27799, 1) end' in npc, 'the ship NPC gives the ship')
        ok('\t\tplayer:addItem(29860, 1)\n' in npc, 'its other item is untouched')

        for rel in ('scripts/customs/roulette/roulette.lua', 'scripts/customs/roulette/roulette2.lua',
                    'scripts/customs/tasks/tasks.lua', 'npc/scripts/builder.lua'):
            if rel.endswith('tasks.lua'):
                continue  # a fragment of a function
            res = parses(os.path.join(data, rel))
            ok(res is not False, '%s parses' % rel)

        before = {}
        for d, _s, fs in os.walk(data):
            for f in fs:
                before[os.path.join(d, f)] = get(d, f)
        report, changed = P.run(data)
        ok(changed == 0, 'a second run changes nothing (%s)' % report)
        ok(all(get(os.path.dirname(p), os.path.basename(p)) == t for p, t in before.items()), 'the files are the same')
        ok(P.main([data, '--check']) == 0, '--check after: nothing to do')

        # the retired ids are those of patch_badges.py
        import patch_badges
        ok(P.RETIRED == set(patch_badges.DECKS) | set(patch_badges.SHIPS) | set(patch_badges.BELTGLOVES),
           'the retired ids')
        ok(not any(b in P.RETIRED for b in patch_badges.BADGES), 'no badge is retired')
    finally:
        shutil.rmtree(tmp)
    print('patch_prizes_test: %d checks, %d failures' % (checks, failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
