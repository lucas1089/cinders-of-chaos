#!/usr/bin/env python3
"""Guard for engine src-patch 0045: hit effects and missiles swapped from Lua (pair 29 VFX packs).

Checks that the patch touches only game.h / game.cpp / luascript.h / luascript.cpp; that both hit effect sends of
Game::combatChangeHealth go through Game::addHitEffect with the damage origin; that addHitEffect picks a condition
tick by its combat type, a physical hit by the target's race and any other hit by its combat type, sends the override
at its offset (0 = none) and the stock effect without one; that the static Game::addDistanceEffect (the one every
missile goes through) swaps a listed stock missile and shifts both ends; that the three Lua functions are declared
and registered; that nothing is set by default (the maps start empty); that no later patch sends the hit effect
directly again; and that data/lib/chaos_pack29_vfx.lua sets them only behind the switch and with an engine that has
them. A model of the rules runs on a few hits.

Run: python3 -I server/tools/effect_overrides_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
LIB = os.path.join(HERE, '..', 'data', 'lib', 'chaos_pack29_vfx.lua')


def files_of(text):
    return [line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/')]


def added(text):
    return '\n'.join(line[1:] for line in text.splitlines() if line.startswith('+') and not line.startswith('+++'))


# the rules of Game::addHitEffect, as a model: overrides {(kind, key): (effect, dx, dy)}
def hit_effect(overrides, ctype, origin, race, stock, pos):
    if origin == 'condition':
        o = overrides.get((2, ctype))
    elif ctype == 'physical':
        o = overrides.get((0, race))
    else:
        o = overrides.get((1, ctype))
    if o is not None:
        effect, dx, dy = o
        return None if effect == 0 else (effect, (pos[0] + dx, pos[1] + dy))
    return None if stock == 0 else (stock, pos)


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0045-')]
    check(mine == ['0045-effect-overrides-from-lua.patch'], 'one patch 0045: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    check(sorted(files_of(text)) == ['src/game.cpp', 'src/game.h', 'src/luascript.cpp', 'src/luascript.h'],
          'files: %s' % files_of(text))
    plus = added(text)
    minus = '\n'.join(line[1:] for line in text.splitlines() if line.startswith('-') and not line.startswith('---'))

    # combatChangeHealth: the two direct sends replaced by addHitEffect with the origin
    check(minus.count('addMagicEffect(spectators, targetPos, hitEffect);') == 2, 'both stock hit sends removed')
    check('addHitEffect(spectators, target, targetPos, damage.primary.type, damage.origin, hitEffect);' in plus,
          'the primary part goes through addHitEffect')
    check('addHitEffect(spectators, target, targetPos, damage.secondary.type, damage.origin, hitEffect);' in plus,
          'the secondary part goes through addHitEffect')

    m = re.search(r'void Game::addHitEffect\(.*?\n\+\{\n(.*?)\n\+\}', text, re.S)
    body = m.group(1) if m else ''
    check('origin == ORIGIN_CONDITION' in body and 'chaosHitOverride(2, combatType)' in body,
          'a condition tick by its combat type')
    check('combatType == COMBAT_PHYSICALDAMAGE' in body and 'chaosHitOverride(0, target->getRace())' in body,
          'a physical hit by the race')
    check('chaosHitOverride(1, combatType)' in body, 'any other hit by its combat type')
    check(body.find('ORIGIN_CONDITION') < body.find('COMBAT_PHYSICALDAMAGE'),
          'the condition tick wins (a bleeding tick is physical)')
    check('if (o->effect != 0)' in body and 'chaosShifted(pos, o->dx, o->dy)' in body, 'override at its offset, 0 none')
    check('if (stock != CONST_ME_NONE)' in body and 'addMagicEffect(spectators, pos, stock);' in body,
          'the stock effect without an override')

    m = re.search(r'void Game::addDistanceEffect\(const SpectatorVec& spectators.*?\n.\{\n(.*?)\n.\}', text, re.S)
    body = m.group(1) if m else ''
    check('chaosMissileOverrides.find(effect)' in body, 'the static addDistanceEffect looks the missile up')
    check('chaosShifted(fromPos' in body and 'chaosShifted(toPos' in body, 'both ends shifted')
    check('sendDistanceShoot(from, to, effect)' in body, 'the swapped missile is sent')

    check('std::map<uint32_t, ChaosFxOverride> chaosHitOverrides;' in plus and
          'std::map<uint8_t, ChaosFxOverride> chaosMissileOverrides;' in plus, 'empty maps: stock by default')
    for fn in ('setHitEffect', 'setMissileEffect', 'clearEffectOverrides'):
        lua = 'luaGame' + fn[0].upper() + fn[1:]
        check('registerMethod("Game", "%s", LuaScriptInterface::%s);' % (fn, lua) in plus, fn + ' registered')
        check('static int %s(lua_State* L);' % lua in plus, fn + ' declared')
    check('if (kind > 2)' in plus, 'setHitEffect refuses an unknown kind')
    check('if (effect > 0xFFFF)' in plus, 'setHitEffect refuses an effect beyond u16')
    check('static void addHitEffect(' in plus, 'addHitEffect declared')

    # no later patch sends the hit effect directly again
    for name in names:
        if name > mine[0] and name.endswith('.patch'):
            later = added(open(os.path.join(PATCHES, name), encoding='utf-8').read())
            check('addMagicEffect(spectators, targetPos, hitEffect);' not in later, name + ' sends the stock hit again')

    # the Lua side: only behind the switch, only with an engine that has the functions
    lib = open(LIB, encoding='utf-8').read()
    m = re.search(r'function C\.applyEngine\(\)\n(.*?)\nend\n', lib, re.S)
    body = m.group(1) if m else ''
    check('if not (Game and Game.setHitEffect and Game.setMissileEffect) then' in body, 'an engine without 0045: nothing')
    check(body.find('Game.clearEffectOverrides()') < body.find('if not C.live() then'), 'off: cleared, nothing set')
    check('Game.setHitEffect(h[1], h[2], h[3], h[4], h[5])' in body, 'hit rows set')
    check('Game.setMissileEffect(s[1], s[2], s[3], s[4])' in body, 'missile rows set')

    # the model
    ov = {(2, 'fire'): (780, 0, 0), (0, 'blood'): (828, 0, 0), (1, 'ice'): (800, 1, 1), (1, 'holy'): (0, 0, 0)}
    check(hit_effect(ov, 'fire', 'condition', 'blood', 16, (10, 10)) == (780, (10, 10)), 'model: a burning tick')
    check(hit_effect(ov, 'fire', 'spell', 'blood', 16, (10, 10)) == (16, (10, 10)), 'model: a fire hit keeps stock')
    check(hit_effect(ov, 'physical', 'melee', 'blood', 1, (10, 10)) == (828, (10, 10)), 'model: the blood splash')
    check(hit_effect(ov, 'physical', 'melee', 'undead', 10, (10, 10)) == (10, (10, 10)), 'model: undead stock')
    check(hit_effect(ov, 'physical', 'condition', 'blood', 1, (10, 10)) == (1, (10, 10)),
          'model: a bleeding tick without its override: stock, not the race splash')
    check(hit_effect(ov, 'ice', 'spell', 'blood', 43, (10, 10)) == (800, (11, 11)), 'model: the ice blast at +1, +1')
    check(hit_effect(ov, 'holy', 'spell', 'blood', 40, (10, 10)) is None, 'model: effect 0 sends none')

    if failures:
        print('%d failure(s)' % len(failures))
        return 1
    print('effect_overrides_patch_test: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
