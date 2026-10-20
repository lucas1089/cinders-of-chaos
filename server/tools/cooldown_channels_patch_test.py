#!/usr/bin/env python3
"""Guard for engine src-patch 0042: cooldown channels (server/README.md "Cooldown channels").

Owner 2026-10-16: attack spells, healing spells, the auto attack and moving things must have cooldowns that never
conflict; using one never delays or blocks another. This test reads 0042 and checks that
  * it is the only patch numbered 0042 and touches only the files it should,
  * the channels exist (enums.h) with the numbers cooldown_channels_core.lua uses,
  * every stock shared gate of game.cpp now asks a channel: the item and creature moves the MOVE channel, the three
    use paths the item's channel (Actions::getUseChannel), with one queued task per channel,
  * Actions::useItem / useItemEx set the delay of the item's own channel, a rune by its spell group,
  * the auto attack has its own queued check (setNextAttackTask) and a use no longer holds the distance swing,
  * every channel delay has the 50 ms floor (no zero-delay channel), and cooldownChannels = false is the stock rule,
  * the config options and Game.setItemCooldownChannel are registered,
  * no later patch puts a stock gate back,
and that the Lua side matches: cooldown_channels.lua registers the potions on COOLDOWN_CHANNEL_POTION.

Run: python3 -I server/tools/cooldown_channels_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
PATCHES = os.path.join(ROOT, 'src-patches')
CHAOS = os.path.join(ROOT, 'data', 'scripts', 'chaos')


def files_of(text):
    return [line[6:].split()[0] for line in text.splitlines() if line.startswith('+++ b/')]


def added(text):
    return '\n'.join(line[1:] for line in text.splitlines() if line.startswith('+') and not line.startswith('+++'))


def removed(text):
    return '\n'.join(line[1:] for line in text.splitlines() if line.startswith('-') and not line.startswith('---'))


def file_part(text, name):
    m = re.search(r'^diff --git a/%s b/%s\n(.*?)(?=^diff --git |\Z)' % (re.escape(name), re.escape(name)), text,
                  re.S | re.M)
    return m.group(1) if m else ''


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0042-')]
    check(mine == ['0042-cooldown-channels.patch'], 'one patch 0042: %s' % mine)
    if not mine:
        return 1
    text = open(os.path.join(PATCHES, mine[0]), encoding='utf-8').read()
    check(sorted(files_of(text)) == sorted(['src/actions.cpp', 'src/actions.h', 'src/configmanager.cpp',
                                            'src/configmanager.h', 'src/enums.h', 'src/game.cpp', 'src/luascript.cpp',
                                            'src/luascript.h', 'src/player.cpp', 'src/player.h']),
          'files: %s' % files_of(text))
    plus, minus = added(text), removed(text)

    # the channels and their numbers (cooldown_channels_core.lua K.CHANNELS)
    want = {'ACTION': 0, 'MOVE': 1, 'ATTACK': 2, 'HEAL': 3, 'SUPPORT': 4, 'POTION': 5}
    for name, value in want.items():
        check('COOLDOWN_CHANNEL_%s = %d,' % (name, value) in plus, 'enum COOLDOWN_CHANNEL_%s = %d' % (name, value))
    core = open(os.path.join(CHAOS, 'cooldown_channels_core.lua'), encoding='utf-8').read()
    check('K.CHANNELS = {action = 0, move = 1, attack = 2, heal = 3, support = 4, potion = 5}' in core,
          'cooldown_channels_core.lua has the same numbers')

    # game.cpp: no stock gate left, every one asks a channel
    game = file_part(text, 'src/game.cpp')
    game_plus, game_minus = added(game), removed(game)
    check(game_minus.count('if (!player->canDoAction()) {') == 5, 'the five stock gates of game.cpp go')
    check('if (!player->canDoAction()) {' not in game_plus, 'no stock gate added back')
    check(game_plus.count('player->canDoAction(COOLDOWN_CHANNEL_MOVE)') == 3, 'moves and the equip hotkey: MOVE')
    check(game_plus.count('const CooldownChannel_t channel = g_actions->getUseChannel(item);') == 2,
          'use with / use on a creature: the item channel')
    check('g_actions->getUseChannel(item);' in game_plus and 'chaosMultiUseEquip && chaosMoveDelay() > 0 ? '
          'COOLDOWN_CHANNEL_MOVE' in game_plus, 'plain use: the item channel, the right-click equip MOVE')
    check(game_plus.count('player->setNextActionTask(task, true, channel);') == 3, 'a queued use per channel')
    check(game_plus.count('player->setNextActionTask(nullptr, true, channel);') == 3, 'a use clears only its channel')
    check('player->setNextActionTask(task);' not in game_plus and 'player->setNextActionTask(nullptr);' not in game_plus,
          'no shared queued task added back')
    check('std::max<int64_t>(SCHEDULER_MINTICKS, g_config.getNumber(ConfigManager::MOVE_ITEM_DELAY))' in game_plus,
          'move delay floor 50 ms')

    # actions.cpp: the delay of the item's own channel; runes by group
    acts = added(file_part(text, 'src/actions.cpp'))
    check(acts.count('const CooldownChannel_t channel = getUseChannel(item);') == 2, 'useItem / useItemEx: its channel')
    check('player->setNextAction(OTSYS_TIME() + getUseDelay(channel, false), channel);' in acts, 'useItem delay')
    check('player->setNextAction(OTSYS_TIME() + getUseDelay(channel, true), channel);' in acts, 'useItemEx delay')
    check('dynamic_cast<const RuneSpell*>(getAction(item))' in acts, 'a rune by its spell')
    check('case SPELLGROUP_HEALING:\n\t\t\t\treturn COOLDOWN_CHANNEL_HEAL;' in acts, 'healing rune: HEAL')
    check('case SPELLGROUP_SUPPORT:\n\t\t\t\treturn COOLDOWN_CHANNEL_SUPPORT;' in acts, 'support rune: SUPPORT')
    check('default:\n\t\t\t\treturn COOLDOWN_CHANNEL_ATTACK;' in acts, 'attack and special runes: ATTACK')
    for key in ('RUNE_CHANNEL_DELAY', 'POTION_CHANNEL_DELAY', 'MOVE_ITEM_DELAY'):
        check('std::max<int64_t>(SCHEDULER_MINTICKS, g_config.getNumber(ConfigManager::%s))' % key in acts,
              '%s floor 50 ms' % key)
    check('if (!item || !g_config.getBoolean(ConfigManager::COOLDOWN_CHANNELS)) {\n\t\treturn COOLDOWN_CHANNEL_ACTION;'
          in acts, 'channels off: every use on ACTION (stock)')

    # player.cpp: channels, the attack's own task, the step
    pl = added(file_part(text, 'src/player.cpp'))
    check("if (channel >= COOLDOWN_CHANNEL_COUNT || !g_config.getBoolean(ConfigManager::COOLDOWN_CHANNELS)) {"
          "\n\t\treturn COOLDOWN_CHANNEL_ACTION;" in pl, 'effectiveChannel: off or unknown = ACTION')
    check('uint32_t& event = channelTaskEvent[channel];' in pl, 'one queued task per channel')
    check('} else if (channels) {\n\t\t\tsetNextAttackTask(task);' in pl, 'the auto attack queues its own check')
    check('(channels ? now < stepEndTime : !canDoAction())' in pl, 'only a step holds the distance swing')
    check('stepEndTime = OTSYS_TIME() + getStepDuration(dir);' in pl, 'the step sets its end')
    check('setNextAction(OTSYS_TIME() + getStepDuration(dir), COOLDOWN_CHANNEL_MOVE);' in pl, 'a step holds moves')
    check('std::max<int64_t>(SCHEDULER_MINTICKS, channelNextAction[channel] - OTSYS_TIME())' in pl,
          'queued channel task at least 50 ms away')

    # config and Lua
    check('boolean[COOLDOWN_CHANNELS] = getGlobalBoolean(L, "cooldownChannels", true);' in plus, 'cooldownChannels')
    check('integer[MOVE_ITEM_DELAY] = getGlobalNumber(L, "moveItemDelay", 50);' in plus, 'moveItemDelay')
    check('integer[RUNE_CHANNEL_DELAY] = getGlobalNumber(L, "runeChannelDelay", 1000);' in plus, 'runeChannelDelay')
    check('integer[POTION_CHANNEL_DELAY] = getGlobalNumber(L, "potionChannelDelay", 1000);' in plus,
          'potionChannelDelay')
    check('registerMethod("Game", "setItemCooldownChannel", LuaScriptInterface::luaGameSetItemCooldownChannel);' in plus,
          'Game.setItemCooldownChannel registered')
    check('static int luaGameSetItemCooldownChannel(lua_State* L);' in plus, 'and declared')
    check('registerEnum(COOLDOWN_CHANNEL_POTION)' in plus, 'COOLDOWN_CHANNEL_POTION for Lua')
    check(not minus.strip() or 'canDoAction()' in minus, 'removed lines are the stock gates and their neighbours')

    # no later patch puts a shared gate back into game.cpp
    for name in names:
        if name > mine[0] and name.endswith('.patch'):
            later = added(file_part(open(os.path.join(PATCHES, name), encoding='utf-8').read(), 'src/game.cpp'))
            check('if (!player->canDoAction()) {' not in later, '%s adds a shared action gate back' % name)

    # the Lua side
    lua = open(os.path.join(CHAOS, 'cooldown_channels.lua'), encoding='utf-8').read()
    check('Game.setItemCooldownChannel(id, channel)' in lua and 'K.channelValue("potion")' in lua,
          'cooldown_channels.lua puts the potions on the potion channel')

    # the production config writes the same defaults
    sys.path.insert(0, HERE)
    import prod_config
    prod = dict(prod_config.settings({'--public-host': 'play.example.com'}))
    for key, value in (('cooldownChannels', 'true'), ('moveItemDelay', '50'), ('runeChannelDelay', '1000'),
                       ('potionChannelDelay', '500')):
        check(prod.get(key) == value, 'prod_config.py %s = %s' % (key, value))
        check('"%s"' % key in plus, 'the engine reads %s' % key)

    if failures:
        print('%d failure(s)' % len(failures))
        return 1
    print('cooldown_channels_patch_test: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
