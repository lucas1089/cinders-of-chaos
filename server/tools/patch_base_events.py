#!/usr/bin/env python3
"""Small, idempotent fixes to base server scripts that are not part of this repository.

usage: python3 -I patch_base_events.py DATA_DIR [--dry-run]

1. data/events/scripts/player.lua: make Player:onGainExperience run the script callbacks
   (EventCallback onGainExperience).

The base server's data/events/scripts/player.lua computes experience itself (stages, stamina, the double
experience potion, pets) and never calls EVENT_CALLBACK_ONGAINEXPERIENCE, so every Chaos experience bonus
registered as an EventCallback (Blood Moon in events_schedule.lua, the passive tree, monster tiers, world
buffs from the store) was silently ignored. This inserts the dispatch after the potion bonus, before the
pet share, so the bonuses multiply the staged experience and the pet gets its share of the result.

2. data/scripts/eventcallbacks/monster/default_onDropLoot.lua: the waystone character upgrades "Loot" and
   "Rarity" (customs/waystone_system/character_upgrades.lua) only wrote their level into storages 405789 and
   405790, which nothing read. Item drop chances now get x(1 + level/100) and the rarity roll gets
   +level % chance to roll at all and +level/2 % per tier, as the upgrades' own comments describe.
   (The "Experience" upgrade, storage 405788, is read by data/scripts/chaos/waystone_bonuses.lua.)

3. data/events/scripts/creature.lua: Creature:onTargetCombat asks ChaosSiege.targetCombat first (guild siege,
   data/scripts/chaos/siege.lua). The base rules refuse an attack on a player with secure mode on or in the same
   party BEFORE the script callbacks run, so without the hook members of enemy guilds could not always fight in the
   siege arena. The hook returns nil outside the siege (the base rules then run as before).

Idempotent: every inserted block carries a marker comment and is not added twice.
"""
import os, re, sys

MARKER = '-- Chaos: experience bonuses registered as EventCallback (patch_base_events.py)'
BLOCK = (
    '\t' + MARKER + '\n'
    '\tif hasEventCallback(EVENT_CALLBACK_ONGAINEXPERIENCE) then\n'
    '\t\texp = EventCallback(EVENT_CALLBACK_ONGAINEXPERIENCE, self, source, exp, rawExp) or exp\n'
    '\tend\n\n'
)


def patch(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    if MARKER in text:
        return text, 'already'
    start = text.find('function Player:onGainExperience(')
    if start < 0:
        return text, 'Player:onGainExperience not found'
    end = text.find('\nend', start)
    body = text[start:end]
    # before the pet share when there is one, else before the final return
    m = re.search(r'\n([ \t]*)local pet = self:getPet\(\)', body)
    if not m:
        m = re.search(r'\n([ \t]*)return exp\s*$', body)
    if not m:
        return text, 'no insertion point (pet share or final return) in Player:onGainExperience'
    at = start + m.start() + 1
    return text[:at] + BLOCK + text[at:], 'patched'


LOOT_MARKER = '-- Chaos: waystone Loot / Rarity upgrades (patch_base_events.py)'
LOOT_HELPERS = (
    LOOT_MARKER + '\n'
    'local CHAOS_WAYSTONE_LOOT, CHAOS_WAYSTONE_RARITY = 405789, 405790\n'
    'local function chaosUpgradeLevel(player, key)\n'
    '\tif not player or not player.getStorageValue then\n'
    '\t\treturn 0\n'
    '\tend\n'
    '\treturn math.max(0, player:getStorageValue(key) or 0)\n'
    'end\n\n'
)


def patch_loot(text):
    """returns (new text, status)"""
    if LOOT_MARKER in text:
        return text, 'already'
    old_roll = re.search(r'local function rollRarity\(\)\n(.*?)\nend\n', text, re.S)
    old_chance = 'if roll <= lootData.chance then'
    if not old_roll or text.count(old_chance) != 1 or 'rollRarity(player)' not in text:
        return text, 'unexpected default_onDropLoot.lua (rollRarity / loot chance not found)'
    new_roll = (
        'local function rollRarity(player)\n'
        '\tlocal level = chaosUpgradeLevel(player, CHAOS_WAYSTONE_RARITY)\n'
        '\tif math.random(100) > 70 + level then\n'
        '\t\treturn 0\n'
        '\tend\n\n'
        '\tfor _, r in ipairs(rarities) do\n'
        '\t\tlocal roll = math.random(100)\n'
        '\t\tif roll <= r.chance + level * 0.5 then\n'
        '\t\t\treturn r.id\n'
        '\t\tend\n'
        '\tend\n'
        '\treturn 0\n'
        'end\n'
    )
    text = text[:old_roll.start()] + LOOT_HELPERS + new_roll + text[old_roll.end():]
    text = text.replace(old_chance,
        'if roll <= lootData.chance * (1 + chaosUpgradeLevel(player, CHAOS_WAYSTONE_LOOT) / 100) then', 1)
    return text, 'patched'


COMBAT_MARKER = '-- Chaos: guild siege rules before the base PvP rules (patch_base_events.py)'
COMBAT_BLOCK = (
    '\t' + COMBAT_MARKER + '\n'
    '\tif ChaosSiege and ChaosSiege.targetCombat then\n'
    '\t\tlocal chaosSiegeRet = ChaosSiege.targetCombat(self, target)\n'
    '\t\tif chaosSiegeRet then\n'
    '\t\t\treturn chaosSiegeRet\n'
    '\t\tend\n'
    '\tend\n'
)


def patch_target_combat(text):
    """returns (new text, status)"""
    if COMBAT_MARKER in text:
        return text, 'already'
    start = text.find('function Creature:onTargetCombat(')
    if start < 0:
        return text, 'Creature:onTargetCombat not found'
    end = text.find('\nend', start)
    body = text[start:end]
    # after the base guard and its registerEvent lines, before the first PvP rule; else right after the signature
    m = re.search(r'\n[ \t]*if self:isMonster\(\) and target:isPlayer\(\) then', body)
    if m:
        at = start + m.start() + 1
    else:
        at = text.find('\n', start) + 1
    return text[:at] + COMBAT_BLOCK + text[at:], 'patched'


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
    ok = apply(os.path.join(args[0], 'events', 'scripts', 'player.lua'), patch, dry)
    ok = apply(os.path.join(args[0], 'scripts', 'eventcallbacks', 'monster', 'default_onDropLoot.lua'),
               patch_loot, dry) and ok
    ok = apply(os.path.join(args[0], 'events', 'scripts', 'creature.lua'), patch_target_combat, dry) and ok
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
