#!/usr/bin/env python3
"""Test of patch_roulette.py (run: python3 -I server/tools/patch_roulette_test.py): the real config parses (every pool
line, none retired by tools/patch_badges.py, every id known to the committed item lists, or to an installed items.xml when
CHAOS_ITEMS_XML points at it), a small data folder with a boss roulette and an exercise roulette (only the boss one
changes), the pool lines and the broadcast threshold, CRLF kept, a second run that changes nothing, a changed config
written again, a config with a retired id refused, a boss roulette it can't read left alone, --check, and the patched Lua
parses (luac5.3 / luajit when installed)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.normpath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_roulette as R  # noqa: E402
import patch_badges  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: ' + what)


def read(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()


CONFIG_PATH = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'boss_roulette_config.lua')
config_text = read(CONFIG_PATH)
entries, threshold, retired = R.parse_config(config_text)

# ----------------------------------------------------------------------------------------------- the real config
check(len(entries) == len(re.findall(r'^\s*\{id = \d+,', config_text, re.M)), 'every pool line of the config is read')
check(len(entries) >= 30, 'a pool with variety (%d entries)' % len(entries))
check(threshold == 120, 'the broadcast threshold is read (%s)' % threshold)
check(R.check_entries(entries, retired) == [], 'the real pool has no problem: %s' % R.check_entries(entries, retired))
all_retired = (set(patch_badges.DECKS) | set(patch_badges.SHIPS) | set(patch_badges.BELTGLOVES) | set(retired))
check(not [e for e in entries if e[0] in all_retired], 'no deck, ship, belt or gloves in the pool')
check({27632, 27633, 27634, 27797} <= set(retired), 'the config lists the decks and the Awakener')
cards = [e for e in entries if e[5] == 'card']
check(0 < len(cards) <= 2, 'at most two cards (%d)' % len(cards))

known = set()
for rel, pat in (('data/items/base_item_names.csv', r'^(\d+),'), ('data/items/base_item_values.csv', r'^(\d+),'),
                 ('data/items/chaos_items.xml', r'id="(\d+)"'), ('data/lib/chaos_item_prices_data.lua', r'\[(\d+)\]'),
                 ('data/lib/chaos_orbs_config.lua', r'id = (\d+)'), ('data/lib/chaos_crafting.lua', r'id = (\d+)'),
                 ('data/lib/chaos_gems_config.lua', r'id = (\d+)')):
    known |= set(int(x) for x in re.findall(pat, read(os.path.join(SERVER, rel)), re.M))
known |= set(patch_badges.BADGES)
dead = [e for e in entries if e[0] not in known]
check(not dead, 'every id is a known item: %s' % dead)
xml = os.environ.get('CHAOS_ITEMS_XML')
if xml and os.path.isfile(xml):
    live = set(int(x) for x in re.findall(r'<item id="(\d+)"', read(xml)))
    live |= set(int(a) for a, b in re.findall(r'<item fromid="(\d+)" toid="(\d+)"', read(xml)) for a in range(int(a), int(b) + 1))
    gone = [e for e in entries if e[0] not in live]
    check(not gone, 'every id is in the installed items.xml: %s' % gone)

# ----------------------------------------------------------------------------------------------- a small data folder
BOSS = '''local config = {
    playItem = {
        itemId = 28033,
        count = 1
    },
    rouletteOptions = {
        rareItemChance_broadcastThreshold = 5000,
        rouletteStorage = 48550
    },
    prizePool = {
        {itemId = 27633, count = {1, 1},    chance = 7000},
        {itemId = 27822, count = {1, 1},    chance = 6800 },
        -- {itemId = 27797, count = {1, 1},    chance = 4400 }, -- Chaos: prizes into the backpack (patch_prizes.py)
        {itemId = 27547, count = {1, 1},    chance = 800  },

    },
    roulettePositions = {
    Position(1, 1, 7),
    }
}

local function rewardPlayer(playerId, leverPosition)
    local player = Player(playerId)
end

local function onUse()
    player:sendTextMessage(MESSAGE_STATUS_SMALL, "Boss Roulette requires " .. config.playItem.count)
end
'''
OTHER = BOSS.replace('Boss Roulette requires', 'Exercise Roulette requires')
UNREADABLE = BOSS.replace('prizePool = {', 'prizePool = makePool(')


def put(root, rel, text, crlf=False):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text.replace('\n', '\r\n') if crlf else text)
    return path


def lua_parses(path):
    for exe, args in (('luac5.3', ['-p']), ('luajit', ['-bl'])):
        if shutil.which(exe):
            r = subprocess.run([exe] + args + [path], capture_output=True, text=True)
            if exe == 'luajit':
                r = subprocess.run([exe, '-b', path, os.devnull], capture_output=True, text=True)
            if r.returncode != 0:
                return False, exe + ': ' + r.stderr.strip()
    return True, ''


root = tempfile.mkdtemp(prefix='patch_roulette_test_')
try:
    put(root, 'scripts/chaos/boss_roulette_config.lua', config_text)
    boss = put(root, 'scripts/customs/roulette/roulette.lua', BOSS)
    other = put(root, 'scripts/customs/roulette/roulette2.lua', OTHER)
    bad = put(root, 'scripts/customs/other/odd.lua', UNREADABLE)

    check(R.main([root, '--check']) == 1, '--check exits 1 while there is something to do')
    check(read(boss) == BOSS, '--check changes nothing')
    check(R.main([root, '--dry-run']) == 0 and read(boss) == BOSS, '--dry-run changes nothing')
    check(R.main([root]) == 0, 'a run')
    text = read(boss)
    lines = re.findall(r'\{itemId = (\d+), count = \{(\d+), (\d+)\}, chance = (\d+)\}', text)
    check(len(lines) == len(entries), 'the pool has the config lines (%d of %d)' % (len(lines), len(entries)))
    check([int(a) for a, b, c, d in lines] == [e[0] for e in entries], 'in the order of the config')
    check(R.MARK in text, 'the pool carries the mark')
    check('27633' not in text and '27797' not in text, 'the deck and the ship are out of the script')
    check('rareItemChance_broadcastThreshold = 120' in text, 'the broadcast threshold follows the config')
    check('rouletteStorage = 48550' in text and 'roulettePositions' in text, 'the rest of the config table is kept')
    check('local function rewardPlayer' in text, 'the rest of the script is kept')
    check(read(other) == OTHER, 'the exercise roulette is not touched')
    check(read(bad) == UNREADABLE, 'a script with no pool block is left alone')
    ok, err = lua_parses(boss)
    check(ok, 'the patched script parses: ' + err)
    before = text
    check(R.main([root]) == 0 and read(boss) == before, 'a second run changes nothing')
    check(R.main([root, '--check']) == 0, '--check is quiet after the run')

    # a changed config is written again
    changed = read(os.path.join(root, 'scripts/chaos/boss_roulette_config.lua')).replace('chance = 5200', 'chance = 5100', 1)
    put(root, 'scripts/chaos/boss_roulette_config.lua', changed)
    check(R.main([root, '--check']) == 1, 'a changed config is something to do')
    R.main([root])
    check('chance = 5100' in read(boss), 'the new chance is written')

    # CRLF kept
    crlf = put(root, 'scripts/customs/roulette/crlf.lua', BOSS, crlf=True)
    R.main([root])
    raw = open(crlf, 'rb').read()
    check(b'\r\n' in raw and raw.count(b'\n') == raw.count(b'\r\n'), 'CRLF kept')
    check(b'27633' not in raw, 'the CRLF script is patched')

    # a retired id in the config is refused and nothing changes
    bad_cfg = read(os.path.join(root, 'scripts/chaos/boss_roulette_config.lua')).replace(
        'id = 29851,', 'id = 27634,', 1)
    put(root, 'scripts/chaos/boss_roulette_config.lua', bad_cfg)
    snapshot = read(boss)
    check(R.main([root]) == 1, 'a retired id in the config: refused')
    check(read(boss) == snapshot, 'and nothing is written')

    # no config: refused
    os.remove(os.path.join(root, 'scripts/chaos/boss_roulette_config.lua'))
    check(R.main([root]) == 1, 'no config: refused')
finally:
    shutil.rmtree(root, ignore_errors=True)

print('patch_roulette_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
