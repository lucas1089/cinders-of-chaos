#!/usr/bin/env python3
"""Guard for engine src-patch 0091: the bare-fist hit is rolled with the attack a script gives the player (O505).

Weapon::useFist (weapons.cpp) rolls the bare-fist hit with attack 7. The Monk line and Open Hand Creed rescale it in a later event, after the
monster's flat armour and defence took their part in the engine, so at attack 7 nearly all of a Monk's hit died in the flat armour. The
patch adds Player::setChaosFist (Lua player:setFistAttack(attack, multiplier), player:getFistAttack()) and rolls the hit with it when one is
set. This test reads the patch text and checks that
  * it is the only patch numbered 0091 and no later patch removes what it adds,
  * it touches exactly luascript.cpp, luascript.h, player.h, weapons.cpp and adds chaosfist.h (no enums.h, no config key, no SQL, no player.cpp),
  * Weapon::useFist keeps the stock roll (attackValue = 7 and Weapons::getMaxWeaponDamage) and only replaces maxDamage when the player's
    chaos fist attack is above 0, in the one place the fist is rolled; nothing else of weapons.cpp changes,
  * the Lua names the scripts detect the capability by exist (setFistAttack, getFistAttack) and are registered next to getFightMode,
  * the header cleans bad numbers (NaN, infinity, zero, negative, over the limits) to "none set" / 1 and its formula is the engine's,
  * the player's value is never saved (no database or save-code change) and starts at 0 / 1 (the stock hit).
It also computes the arithmetic the Lua side depends on: a Monk's maximum hit with and without the patch, in the engine's rounding.
Applying it on a copy of the patched source tree: patch -p1 --fuzz=0 --dry-run (server/README.md "Flat armour, weapon spells and the Monk's
fist (O505)"); with SRC_TREE=<source root with patches 0001-0090 applied> this test also runs that dry run.
Run: python3 -I server/tools/fist_attack_patch_test.py (standard library only)."""
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
NAME = '0091-fist-attack-from-script.patch'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def eq(a, b, what):
    check(a == b, '%s: %r != %r' % (what, a, b))


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
mine = [f for f in files if f.startswith('0091-')]
eq(mine, [NAME], 'one patch numbered 0091')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
body = text[text.index('diff --git'):]
touched = re.findall(r'^diff --git a/(\S+) b/\S+', body, re.M)
eq(touched, ['src/luascript.cpp', 'src/luascript.h', 'src/player.h', 'src/weapons.cpp', 'src/chaosfist.h'], 'the files the patch touches')
check('new file mode' in body and body.count('new file mode') == 1, 'chaosfist.h is the only new file')

# no later patch undoes it (0092, the Rune Bag in the purse, comes after it): a later patch removes no line of the fist attack
later = [f for f in files if f > NAME]
for f in later:
    gone = [l for l in open(os.path.join(PATCHES, f), encoding='utf-8').read().splitlines()
            if l.startswith('-') and not l.startswith('---')]
    check(not any('FistAttack' in l or 'chaosFist' in l or 'ChaosFist' in l or 'patch 0091' in l for l in gone),
          'no later patch removes what 0091 adds: ' + f)
for f in files:
    if f != NAME and f.startswith('00'):
        other = open(os.path.join(PATCHES, f), encoding='utf-8').read()
        check('chaosFistAttack' not in other and 'ChaosFist' not in other, f + ' does not touch the fist attack')

added = [l[1:] for l in body.splitlines() if l.startswith('+') and not l.startswith('+++')]
removed = [l[1:] for l in body.splitlines() if l.startswith('-') and not l.startswith('---')]
eq(removed, [], 'the patch removes no line of the engine (it only adds)')

# Weapon::useFist: the stock roll stays, the script's attack replaces the maximum only when set
weapons = body[body.index('diff --git a/src/weapons.cpp'):body.index('diff --git a/src/chaosfist.h')]
check('attackValue = 7' not in ''.join(added), 'the stock attackValue line is not changed (it is context)')
check(weapons.count('ChaosFist::maxDamage') == 1, 'weapons.cpp calls ChaosFist::maxDamage once')
check(re.search(r'if \(player->getChaosFistAttack\(\) > 0\.0f\) \{\s*//[^\n]*\n(//[^\n]*\n|\s*//[^\n]*\n)*\s*maxDamage = ChaosFist::maxDamage\(player->getLevel\(\), attackSkill, player->getChaosFistAttack\(\), player->getChaosFistMultiplier\(\), attackFactor\);', weapons.replace('\n+', '\n')) is not None,
      'maxDamage is replaced only inside if (the chaos fist attack > 0)')
check(re.search(r'^ \tint32_t maxDamage = Weapons::getMaxWeaponDamage\(player->getLevel\(\), attackSkill, attackValue, attackFactor\);', weapons, re.M) is not None,
      'the stock maxDamage line is context, unchanged, and runs first')
check(not any('normal_random' in l for l in added), 'the bell between 0 and the maximum is the stock one (the roll line is not touched)')
eq(weapons.count('@@'), 2, 'one hunk in weapons.cpp (two @@ marks)')
check('#include' not in ''.join(l for l in added if 'weapons' in l), 'no include added to weapons.cpp (player.h brings chaosfist.h)')

# the Lua side: the capability is the method
lua_cpp = body[body.index('diff --git a/src/luascript.cpp'):body.index('diff --git a/src/luascript.h')]
check('registerMethod("Player", "setFistAttack", LuaScriptInterface::luaPlayerSetFistAttack);' in lua_cpp, 'setFistAttack is registered')
check('registerMethod("Player", "getFistAttack", LuaScriptInterface::luaPlayerGetFistAttack);' in lua_cpp, 'getFistAttack is registered')
check('registerMethod("Player", "getFightMode", LuaScriptInterface::luaPlayerGetFightMode);' in lua_cpp, 'registered next to getFightMode')
check('player->setChaosFist(getNumber<float>(L, 2, 0.0f), getNumber<float>(L, 3, 1.0f));' in lua_cpp, 'the setter takes (attack, multiplier) with the defaults 0 and 1')
check('lua_pushnil(L);' in lua_cpp, 'a player that is gone gives nil')
check(lua_cpp.count('static') == 0, 'no static state in the Lua functions')

# player.h: the value is not saved, starts at the stock hit, is cleaned on the way in
player_h = body[body.index('diff --git a/src/player.h'):body.index('diff --git a/src/weapons.cpp')]
check('float chaosFistAttack = 0.0f;' in player_h and 'float chaosFistMultiplier = 1.0f;' in player_h, 'the player starts at no attack set, multiplier 1')
check('ChaosFist::cleanAttack(attack)' in player_h and 'ChaosFist::cleanMultiplier(multiplier)' in player_h, 'the setter cleans both numbers')
check('chaosFistAttack > 0.0f ? ChaosFist::cleanMultiplier(multiplier) : 1.0f' in player_h, 'no attack set also resets the multiplier')
check('#include "chaosfist.h"' in player_h, 'player.h includes the header')
check(not re.search(r'[Ss]ave|sql|SQL|db\b', ''.join(l.split('//')[0] for l in added)), 'no code saves the value')

# the header
header = body[body.index('diff --git a/src/chaosfist.h'):]
check('constexpr float MAX_ATTACK = 2000.0f;' in header and 'constexpr float MAX_MULTIPLIER = 10.0f;' in header, 'the limits are 2000 and 10')
check('!std::isfinite(attack) || attack <= 0.0f || attack > MAX_ATTACK' in header, 'a bad attack is none set')
check('!std::isfinite(multiplier) || multiplier <= 0.0f || multiplier > MAX_MULTIPLIER' in header, 'a bad multiplier is 1')
check('(level / 5) + (((((attackSkill / 4.) + 1) * (attack / 3.)) * 1.03) / attackFactor)' in header, "the formula is Weapons::getMaxWeaponDamage's")
check('std::round(base * multiplier)' in header, 'rounded once')
check('#include <cmath>' in header and '#include <cstdint>' in header, 'standard headers only')

# the arithmetic: a Monk's maximum with and without (engine rounding; the Lua side: monk_chi_core.lua M.enginePush / M.unarmedFactor)


def stock(level, skill, attack, factor):
    return int(math.floor((level // 5 + ((skill / 4.0 + 1) * (attack / 3.0) * 1.03) / factor) + 0.5))


def patched(level, skill, attack, mult, factor):
    base = (level // 5) + ((((skill / 4.0) + 1) * (attack / 3.0)) * 1.03) / factor
    return int(math.floor(base * mult + 0.5))


# level: (stock max, Monk max at the fist attack 40 + 0.025 x level x 1.2) at the skills of the measurement rig (SP o501 / o505)
TABLE = {20: (10, 20, 1.0), 100: (70, 100, 1.0), 300: (100, 300, 1.0), 500: (120, 500, 1.0)}
for level, (skill, _, factor) in TABLE.items():
    atk = min(60.0, 40 + 0.025 * level)
    s, p = stock(level, skill, 7, factor), patched(level, skill, atk, 1.2, factor)
    check(p > 3 * s, 'level %d: the Monk rolls over 3 times the stock maximum (%d against %d)' % (level, p, s))
    check(p < 12 * s, 'level %d: and under 12 times (%d against %d)' % (level, p, s))
eq(stock(100, 70, 7, 1.0), 64, 'a stock fist at level 100, skill 70 rolls up to 64 (measured 63 on the local server)')
eq(patched(100, 70, 7, 1.0, 1.0), 64, 'attack 7 and multiplier 1 through the patched formula is the stock number')
for level in (1, 8, 20, 100, 500, 1000, 2500):
    for skill in (10, 70, 135):
        for factor in (1.0, 1.2, 2.0):
            eq(patched(level, skill, 7.0, 1.0, factor), stock(level, skill, 7, factor), 'no change at attack 7 / 1: level %d skill %d factor %s' % (level, skill, factor))

# optional: the dry run on a patched source tree
tree = os.environ.get('SRC_TREE')
if tree:
    tmp = tempfile.mkdtemp(prefix='fistpatch')
    try:
        shutil.copytree(os.path.join(tree, 'src'), os.path.join(tmp, 'src'))
        r = subprocess.run(['patch', '-p1', '--fuzz=0', '--dry-run', '-i', os.path.join(PATCHES, NAME)], cwd=tmp, capture_output=True, text=True)
        check(r.returncode == 0, 'patch -p1 --fuzz=0 --dry-run on SRC_TREE: ' + r.stdout[-300:] + r.stderr[-300:])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('fist attack patch tests: ok')
