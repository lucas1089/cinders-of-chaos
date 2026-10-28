#!/usr/bin/env python3
"""Test of patch_roulette.py (run: python3 -I server/tools/patch_roulette_test.py): the real configs parse
(every pool line, none retired by tools/patch_badges.py, every id known to the committed item lists, or to an installed
items.xml when CHAOS_ITEMS_XML points at it), a small data folder with the boss, exercise, premium and the two crystal
roulettes (each gets its own pool by its actionId; a script without a known actionId and a script with another token are
left alone), the pool lines and the broadcast threshold, the crystal scripts renamed from their copied "Premium" /
"Exercise" names, CRLF kept, a second run that changes nothing, a changed config written again, a config with a retired
id refused, a boss roulette it cannot read left alone, --check, and the patched Lua parses (luac5.3 / luajit when
installed)."""
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

OTHERS = {}
for name in ('exercise', 'premium', 'crystal'):
    text_ = read(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'roulette_%s_config.lua' % name))
    ents, thr, ret = R.parse_config(text_)
    ids, title, token = R.parse_meta(text_)
    OTHERS[name] = (ents, thr, ret, ids, title, token)
    check(len(ents) == len(re.findall(r'^\s*\{id = \d+,', text_, re.M)), '%s: every pool line of the config is read' % name)
    check(R.check_entries(ents, ret) == [], '%s: the real pool has no problem: %s' % (name, R.check_entries(ents, ret)))
    check(title == name and ids and token, '%s: title, actionIds and token are read (%s %s %s)' % (name, title, ids, token))
    check(not [e for e in ents if e[0] in all_retired], '%s: no deck, ship, belt or gloves in the pool' % name)
    check(not [e for e in ents if 28373 <= e[0] <= 28393], '%s: none of the fixed Moist gear' % name)
    check(not [e for e in ents if e[0] in (27763, 27770, 27777)], '%s: no retired club chest' % name)
    if name == 'exercise':
        # the old axe chests hand out the Monk line's fist weapon since 2026-10-28 (O287)
        check({27762, 27769, 27776} <= {e[0] for e in ents}, 'exercise: the three fist weapon chests are in the pool')
    else:
        check(not [e for e in ents if e[0] in (27762, 27769, 27776)], '%s: no exercise fist chest' % name)
check(OTHERS['crystal'][3] == [18565, 18566] and OTHERS['exercise'][3] == [18563] and OTHERS['premium'][3] == [18564],
      'the actionIds of the base roulettes')
check(R.parse_meta(config_text) == ([18562], 'boss', 28033), 'the boss config: actionId 18562, token 28033')

known = set()
for rel, pat in (('data/items/base_item_names.csv', r'^(\d+),'), ('data/items/base_item_values.csv', r'^(\d+),'),
                 ('data/items/chaos_items.xml', r'id="(\d+)"'), ('data/lib/chaos_item_prices_data.lua', r'\[(\d+)\]'),
                 ('data/lib/chaos_orbs_config.lua', r'id = (\d+)'), ('data/lib/chaos_crafting.lua', r'id = (\d+)'),
                 ('data/lib/chaos_gems_config.lua', r'id = (\d+)')):
    known |= set(int(x) for x in re.findall(pat, read(os.path.join(SERVER, rel)), re.M))
known |= set(patch_badges.BADGES)
# the ids only the base items.xml defines: auras and the Tower Defense units (the base use-scripts name them)
known |= {26649, 26650, 26651, 26652, 26653, 28369, 28370}
known |= set(int(x) for x in re.findall(r'\[(\d+)\]', read(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'sell_prices.lua'))))
dead = [e for e in entries if e[0] not in known]
check(not dead, 'every id is a known item: %s' % dead)
for name, tup in OTHERS.items():
    dead = [e for e in tup[0] if e[0] not in known]
    check(not dead, '%s: every id is a known item: %s' % (name, dead))
xml = os.environ.get('CHAOS_ITEMS_XML')
if xml and os.path.isfile(xml):
    live = set(int(x) for x in re.findall(r'<item id="(\d+)"', read(xml)))
    live |= set(int(a) for a, b in re.findall(r'<item fromid="(\d+)" toid="(\d+)"', read(xml)) for a in range(int(a), int(b) + 1))
    gone = [e for e in entries if e[0] not in live]
    check(not gone, 'every id is in the installed items.xml: %s' % gone)
    for name, tup in OTHERS.items():
        gone = [e for e in tup[0] if e[0] not in live]
        check(not gone, '%s: every id is in the installed items.xml: %s' % (name, gone))

# ----------------------------------------------------------------------------------------------- a small data folder
BOSS = '''local config = {
    actionId = 18562,
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
OTHER = BOSS.replace('Boss Roulette requires', 'Exercise Roulette requires').replace('    actionId = 18562,\n', '')
UNREADABLE = BOSS.replace('prizePool = {', 'prizePool = makePool(')


def copy_of(action, token, count, name, label, threshold=5000):
    """a base roulette copied from another one: the names and the label are the other roulette's"""
    return '''local config = {
    actionId = %d,
    playItem = {
        itemId = %d,
        count = %d
    },
    rouletteOptions = {
        rareItemChance_broadcastThreshold = %d,
        rouletteStorage = 48552
    },
    prizePool = {
        {itemId = 26649, count = {1, 1},   chance = 9000},
        {itemId = 27975, count = {1, 1}, chance = 6500 }
    },
    roulettePositions = {
    Position(1, 1, 7),
    }
}

local function rewardPlayer(playerId, leverPosition)
    if ChaosPrizes and ChaosPrizes.rouletteReward then
        ChaosPrizes.rouletteReward(playerId, config, config.roulettePositions[1], "%s")
        return
    end
    Game.broadcastMessage("The player " .. player:getName() .. " has won an item from the %s roulette!", MESSAGE_EVENT_ADVANCE)
end

local function onUse()
    player:sendTextMessage(MESSAGE_STATUS_SMALL, "%s Roulette is currently in progress. Please wait.")
    player:sendTextMessage(MESSAGE_STATUS_SMALL, "%s Roulette requires " .. config.playItem.count)
end
''' % (action, token, count, threshold, label, label, name, name)


EXERCISE = copy_of(18563, 28058, 1, 'Exercise', 'exercise')
PREMIUM = copy_of(18564, 28057, 1, 'Premium', 'premium', 10000)
CRYSTAL = copy_of(18565, 28372, 15, 'Premium', 'premium')
CRYSTAL2 = copy_of(18566, 28372, 15, 'Exercise', 'exercise')
WRONG_TOKEN = copy_of(18564, 28099, 1, 'Premium', 'premium')
NO_ACTION = copy_of(77777, 28058, 1, 'Exercise', 'exercise')


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
    for name in ('exercise', 'premium', 'crystal'):
        put(root, 'scripts/chaos/roulette_%s_config.lua' % name,
            read(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'roulette_%s_config.lua' % name)))
    boss = put(root, 'scripts/customs/roulette/roulette.lua', BOSS)
    other = put(root, 'scripts/customs/roulette/other.lua', OTHER)
    ex = put(root, 'scripts/customs/roulette/roulette2.lua', EXERCISE)
    prem = put(root, 'scripts/customs/roulette/roulette3.lua', PREMIUM)
    cry = put(root, 'scripts/customs/tower_defense/roulette_crystal_token.lua', CRYSTAL)
    cry2 = put(root, 'scripts/customs/tower_defense/roulette_crystal_token_2.lua', CRYSTAL2)
    wrong = put(root, 'scripts/customs/roulette/wrong_token.lua', WRONG_TOKEN)
    noact = put(root, 'scripts/customs/roulette/no_action.lua', NO_ACTION)
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
    check(read(other) == OTHER, 'a script of the text of another roulette and no actionId is not touched')
    check(read(wrong) == WRONG_TOKEN, 'a script whose token is not the config\'s is left alone')
    check(read(noact) == NO_ACTION, 'a script of an unknown actionId is left alone')
    for name, path, expect in (('exercise', ex, 'exercise'), ('premium', prem, 'premium'), ('crystal', cry, 'crystal'),
                               ('crystal 2', cry2, 'crystal')):
        t = read(path)
        ents, thr = OTHERS[expect][0], OTHERS[expect][1]
        got = re.findall(r'\{itemId = (\d+), count = \{(\d+), (\d+)\}, chance = (\d+)\}', t)
        check([int(a) for a, b, c, d in got] == [e[0] for e in ents], '%s: the pool of the config, in order (%d lines)' % (name, len(got)))
        check(R.mark(expect) in t, '%s: the pool carries its mark' % name)
        check('rareItemChance_broadcastThreshold = %d' % thr in t, '%s: the broadcast threshold %d' % (name, thr))
        check('rouletteStorage = 48552' in t and 'roulettePositions' in t, '%s: the rest of the config table is kept' % name)
        ok2, err2 = lua_parses(path)
        check(ok2, '%s: the patched script parses: %s' % (name, err2))
    for name, path in (('crystal', cry), ('crystal 2', cry2)):
        t = read(path)
        check('Premium Roulette' not in t and 'Exercise Roulette' not in t, '%s: no copied name is left' % name)
        check('Crystal Roulette is currently in progress' in t and 'Crystal Roulette requires' in t, '%s: named the Crystal Roulette' % name)
        check('from the crystal roulette!' in t and '"crystal")' in t, '%s: the broadcast and the label say crystal' % name)
    check('Premium Roulette' in read(prem) and 'from the premium roulette!' in read(prem), 'the premium roulette keeps its own names')
    check('Exercise Roulette' in read(ex) and '"exercise")' in read(ex), 'the exercise roulette keeps its own names')
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

    # the fixed base gear of the old crystal pool is refused too
    check(R.check_entries([(28373, 'Moist Sword', 1, 1, 100, 'orb')], []) != [], 'a Moist piece in a pool: refused')
    check(R.check_entries([(28382, 'Moist Helmet', 1, 1, 100, 'orb')], []) != [], 'the whole range 28373-28393 is refused')

    # no config: refused
    os.remove(os.path.join(root, 'scripts/chaos/boss_roulette_config.lua'))
    check(R.main([root]) == 1, 'no config: refused')
finally:
    shutil.rmtree(root, ignore_errors=True)

print('patch_roulette_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
