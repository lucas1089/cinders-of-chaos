#!/usr/bin/env python3
"""Small, idempotent fixes to base server scripts that are not part of this repository.

usage: python3 -I patch_base_events.py DATA_DIR [--dry-run] [--enable-spell-events]

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

4. data/creaturescripts/scripts/login.lua: the stock login demoted every character whose vocation has no promotion
   (vocation:getDemotion()) when the account is not premium (freePremium = false on this server). Since the class
   rework every ascended class (!ascend, data/scripts/chaos/ascension.lua) is such a vocation, so a free account lost
   its ascension at each login. The demotion branch is removed; the premium branch (promotion storage) is unchanged.
   The engine itself never demotes (Vocation:getDemotion is only a lookup; premium only gates spells, items, outfits).

5. data/scripts/creaturescripts/autoloot.lua: the engine rolls the stats of an item with a "rarity" in
   Monster::dropLoot after all onDropLoot callbacks, so an item the autoloot moved out of the corpse kept its rarity
   but never got its stats. The autoloot now hands each item to ChaosLoot.finalizeRarity (data/scripts/chaos/loot.lua)
   first, which rolls it once on the way out.

6. data/items/items.xml: the stock critical hit / life leech / mana leech chances (criticalhitchance,
   lifeleechchance, manaleechchance) become about two thirds (round(2 * v / 3), at least 1; 100 stays 100). Engine
   patch 0004 rolls these chances uniformly; the base engine's bell-curve roll made them fire far less often than
   written (10% fired ~3%, 30% ~19%), see server/README.md "Critical and leech chances".

7. data/scripts/customs/waystone_system/character_upgrades.lua: the waystone upgrades "Critical Chance",
   "Life Chance" and "Mana Chance" give about two thirds of their level as chance (same rule as 6).

8. Spell events (engine patch 0008-spell-events.patch): data/events/events.xml gets the Player entries onSpellCost,
   onSpellPreCast, onSpellCast and onSpellCooldown, shipped DISABLED (enabled="0": an engine without the patch warns
   about unknown methods only when they are enabled), and data/events/scripts/player.lua gets the four stubs. A stub
   calls ChaosSpellEvents.<name> when a script defines that table and otherwise does nothing (the cost and the cooldown
   come back unchanged), so enabling them without a script changes no behaviour. `--enable-spell-events` sets the four
   entries to enabled="1" (run it only where the engine has patch 0008); without the flag an existing value is kept.

9. data/scripts/customs/rarity/rarity_onCombat_elementdamage.lua: with two different rarity elements (e.g. fire on the
   weapon, ice on the shield) the onHealthChange handler returned nothing, which the engine reads as 0 damage: the whole
   hit was lost. That bare `return` now hands the hit to ChaosRarityElements.onHealthChange
   (data/scripts/chaos/rarity_elements.lua: each element its own share, the primary damage unchanged) and falls back to
   the unchanged damage when that script is missing. The onManaChange handler stopped at the second element too
   (no bonus at all); every element's % now counts there (mana damage has no element). Exact match on the stock lines;
   anything else is reported and left alone.

10. data/scripts/eventcallbacks/monster/default_onDropLoot.lua: "Loot of ..." names the monster by its type's
   nameDescription, so a renamed monster (a rift monster wearing its rift name, an invader) showed its pool type there.
   Both lines now ask Chaos.monsterNameDescription(self) (data/scripts/chaos/chaos_constants.lua), which gives the
   type's description for a monster that was not renamed; without that helper the stock call is used.

11. data/events/scripts/creature.lua: Creature:onTargetCombat also asks ChaosPvpZone.targetCombat (the Scorched Marches,
   data/scripts/chaos/pvpzone.lua) before the base rules, right after the siege hook: inside the zone the target's secure
   mode does not protect it (open PvP), protected players and attacks across the zone border are refused. The hook
   returns nil outside the zone (the base rules then run as before).

12. data/events/scripts/player.lua: Player:onReportBug (System > Report a Bug in the client) hands the report to
   ChaosReports.onReportBug first (data/scripts/chaos/reports.lua): every account may report, the report is a
   chaos_reports row (reason "bug") that staff read with /reports, the admin panel and the website, and the player gets
   an answer. The stock callback (scripts/eventcallbacks/player/default_onReportBug.lua) refused normal accounts
   (`getAccountType() == ACCOUNT_TYPE_NORMAL` -> return false, no message) and wrote text files under data/reports/bugs/
   that nobody reads; it still runs when reports.lua is missing.

13. data/creaturescripts/scripts/regeneratestamina.lua: offline stamina regeneration (one minute per 3 minutes offline,
   one per 10 above 40 hours) goes x1.5 faster while the Chaos Pact is active (owner 2026-10-13, "restaura stamina mais
   rapido"): the offline time past the 10 minute grace is multiplied by ChaosPactPerks.staminaMult(player)
   (data/scripts/chaos/pact_perks.lua, pact_config.lua perks.staminaRegen). Without that script the time is unchanged.

14. data/scripts/customs/actions/trainer_tile_stamina.lua: the stamina trainer tile gives one stamina minute every
   120 s; while the Pact is active every ChaosPactPerks.staminaRestMs(player, 120000) ms instead (80 s at x1.5). Without
   that script the 120 s stay.

15. data/creaturescripts/scripts/droploot.lua: store-bound items never drop (live test 2026-10-14: a death on shallow
   water lost the Loot Bag and the Everfull Ration). The stock script moves each dropped slot item into the corpse and
   removes it when that fails, and a tile that cannot hold a corpse (water) has none. Before a slot item drops it now
   asks ChaosDeathKeep.beforeDrop(player, item, corpse) (data/scripts/chaos/death_keep.lua): the store-bound items in it
   go to the character's inbox first (back in the backpack at the next login), and a store-bound item worn in a slot
   stays there (true: not dropped). Without that script the stock rule runs unchanged.

16. data/scripts/eventcallbacks/monster/default_onDropLoot.lua: at or below 14 hours of stamina the stock callback dropped
   NOTHING ("Loot of ...: nothing (due to low stamina)"). Now it asks ChaosCatchup.staminaLootMult(player)
   (data/scripts/chaos/catchup.lua, catchup_config.lua stamina.lootMult, 0.5): above 0 the loot is rolled with every
   chance x that factor (1 above 14 h); only 0 keeps the stock "nothing" branch. Without that script the stock rule
   holds (0 at low stamina, 1 above). Runs after step 2 (it multiplies the waystone-patched chance line too).

17. data/creaturescripts/scripts/regeneratestamina.lua: the offline time past the 10 minute grace is also multiplied by
   ChaosCatchup.offlineStaminaMult(player) (catchup_config.lua stamina.offlineMult, 2.0): stamina comes back twice as
   fast offline, and the Pact's x1.5 of step 13 multiplies on top (x3). Without that script the time is unchanged.

18. Gentle deaths (data/scripts/chaos/gentledeath.lua): data/events/scripts/player.lua Player:onLoseExperience asks
   ChaosGentleDeath.onLoseExperience(self, exp) first (new characters lose little or nothing, the first death of a day
   half); a player.lua without that function gets a plain one. data/events/events.xml gets
   <event class="Player" method="onLoseExperience" enabled="1" /> (added, or turned on). Without the script the loss
   the engine computed is kept.

19. Gentle deaths, items (owner decision 2026-10-15): data/creaturescripts/scripts/droploot.lua returns before the item
   loss (and before the amulet of loss is used up) when ChaosGentleDeath.keepAll(player) says so: nobody loses items
   on death except with a red or black skull (data/scripts/chaos/gentledeath.lua). Without that script the stock rule
   (and step 15) runs unchanged.

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


ZONE_MARKER = '-- Chaos: Scorched Marches PvP rules before the base PvP rules (patch_base_events.py)'
ZONE_BLOCK = (
    '\t' + ZONE_MARKER + '\n'
    '\tif ChaosPvpZone and ChaosPvpZone.targetCombat then\n'
    '\t\tlocal chaosZoneRet = ChaosPvpZone.targetCombat(self, target)\n'
    '\t\tif chaosZoneRet then\n'
    '\t\t\treturn chaosZoneRet\n'
    '\t\tend\n'
    '\tend\n'
)


def patch_zone_combat(text):
    """returns (new text, status): after the siege block (step 3), else where step 3 would put it"""
    if ZONE_MARKER in text:
        return text, 'already'
    start = text.find('function Creature:onTargetCombat(')
    if start < 0:
        return text, 'Creature:onTargetCombat not found'
    end = text.find('\nend', start)
    body = text[start:end]
    if COMBAT_MARKER in body:
        i = body.find(COMBAT_MARKER)
        j = body.find('\n\tend\n', i)
        if j < 0:
            return text, 'siege block of step 3 not recognised'
        at = start + j + len('\n\tend\n')
    else:
        m = re.search(r'\n[ \t]*if self:isMonster\(\) and target:isPlayer\(\) then', body)
        at = start + m.start() + 1 if m else text.find('\n', start) + 1
    return text[:at] + ZONE_BLOCK + text[at:], 'patched'


DEMOTION_MARKER = '-- Chaos: no demotion without premium, ascended classes stay (patch_base_events.py)'


def patch_login_demotion(text):
    """returns (new text, status)"""
    if DEMOTION_MARKER in text:
        return text, 'already'
    m = list(re.finditer(r'\n([ \t]*)elseif not promotion then[ \t]*\r?\n[ \t]*player:setVocation\(vocation:getDemotion\(\)\)[ \t]*(\r?\n)', text))
    if len(m) != 1:
        return text, 'unexpected login.lua (demotion branch "elseif not promotion then" not found once)'
    m = m[0]
    return text[:m.start()] + '\n' + m.group(1) + DEMOTION_MARKER + m.group(2) + text[m.end():], 'patched'


AUTOLOOT_MARKER = '-- Chaos: rarity stats rolled before the item leaves the corpse (patch_base_events.py)'


def patch_autoloot(text):
    """returns (new text, status)"""
    if AUTOLOOT_MARKER in text:
        return text, 'already'
    m = list(re.finditer(r'\n([ \t]*)if not item:moveTo\(corpseOwner\) then', text))
    if len(m) != 1:
        return text, 'unexpected autoloot.lua ("if not item:moveTo(corpseOwner) then" not found once)'
    m = m[0]
    ind = m.group(1)
    block = (f'\n{ind}{AUTOLOOT_MARKER}\n'
             f'{ind}if ChaosLoot and ChaosLoot.finalizeRarity then\n'
             f'{ind}    item = ChaosLoot.finalizeRarity(item)\n'
             f'{ind}end')
    return text[:m.start()] + block + text[m.start():], 'patched'


CHANCE_MARKER = '<!-- Chaos: critical / leech chances rescaled for uniform rolls (patch_base_events.py) -->'


def chance_value(v):
    """the rescaled chance: round(2 * v / 3), at least 1; 100 (always) stays 100"""
    return v if v >= 100 else max(1, (2 * v + 1) // 3)


def patch_item_chances(text):
    if CHANCE_MARKER in text:
        return text, 'already'
    m = re.search(r'<items>[^\n]*\n', text)
    if not m:
        return text, '<items> not found'
    rx = re.compile(r'(<attribute\s+key="(?:criticalhitchance|lifeleechchance|manaleechchance)"\s+value=")(\d+)(")',
                    re.IGNORECASE)
    text = rx.sub(lambda a: a.group(1) + str(chance_value(int(a.group(2)))) + a.group(3), text)
    return text[:m.end()] + '\t' + CHANCE_MARKER + '\n' + text[m.end():], 'patched'


WAYSTONE_MARKER = '-- Chaos: chance upgrades give two thirds of their level (patch_base_events.py)'


def patch_waystone_chances(text):
    if WAYSTONE_MARKER in text:
        return text, 'already'
    m = re.search(r'\n([ \t]*)cond:setParameter\(param, lvl\)', text)
    if not m:
        return text, 'cond:setParameter(param, lvl) not found'
    ind = m.group(1)
    block = (f'\n{ind}{WAYSTONE_MARKER}\n'
             f'{ind}local value = lvl\n'
             f'{ind}if offer.upgradeType == "criticalch" or offer.upgradeType == "lifech" or offer.upgradeType == "manach" then\n'
             f'{ind}  value = math.max(1, math.floor((2 * lvl + 1) / 3))\n'
             f'{ind}end\n'
             f'{ind}cond:setParameter(param, value)')
    return text[:m.start()] + block + text[m.end():], 'patched'


SPELL_MARKER = '-- Chaos: spell events (engine patch 0008, patch_base_events.py)'
SPELL_METHODS = ('onSpellCost', 'onSpellPreCast', 'onSpellCast', 'onSpellCooldown')
SPELL_STUBS = (
    '\n' + SPELL_MARKER + '\n'
    '-- A script sets ChaosSpellEvents.onSpellCost / onSpellPreCast / onSpellCast / onSpellCooldown to take part;\n'
    '-- the arguments are the ones the engine passes (self first). Without a function the defaults apply.\n'
    'function Player:onSpellCost(spellName, spellId, spellGroup, aggressive, manaCost)\n'
    '\tlocal hook = ChaosSpellEvents and ChaosSpellEvents.onSpellCost\n'
    '\tif hook then\n'
    '\t\treturn hook(self, spellName, spellId, spellGroup, aggressive, manaCost)\n'
    '\tend\n'
    '\treturn manaCost, 0\n'
    'end\n\n'
    'function Player:onSpellPreCast(spellName, spellId, spellGroup, aggressive, manaCost, healthCost)\n'
    '\tlocal hook = ChaosSpellEvents and ChaosSpellEvents.onSpellPreCast\n'
    '\tif hook then\n'
    '\t\treturn hook(self, spellName, spellId, spellGroup, aggressive, manaCost, healthCost)\n'
    '\tend\n'
    '\treturn true\n'
    'end\n\n'
    'function Player:onSpellCast(spellName, spellId, spellGroup, aggressive, manaCost, healthCost)\n'
    '\tlocal hook = ChaosSpellEvents and ChaosSpellEvents.onSpellCast\n'
    '\tif hook then\n'
    '\t\thook(self, spellName, spellId, spellGroup, aggressive, manaCost, healthCost)\n'
    '\tend\n'
    'end\n\n'
    'function Player:onSpellCooldown(spellName, spellId, spellGroup, aggressive, cooldownType, cooldown)\n'
    '\tlocal hook = ChaosSpellEvents and ChaosSpellEvents.onSpellCooldown\n'
    '\tif hook then\n'
    '\t\treturn hook(self, spellName, spellId, spellGroup, aggressive, cooldownType, cooldown)\n'
    '\tend\n'
    '\treturn cooldown\n'
    'end\n'
)


def patch_spell_stubs(text):
    """returns (new text, status)"""
    if SPELL_MARKER in text:
        return text, 'already'
    if 'function Player:onSpellCost(' in text:
        return text, 'player.lua already defines Player:onSpellCost'
    if not text.endswith('\n'):
        text += '\n'
    return text + SPELL_STUBS, 'patched'


def make_spell_events(enable):
    """patch function for events.xml: adds the four entries (disabled) and, with enable, turns them on"""
    def patch_spell_events(text):
        out = text
        for method in SPELL_METHODS:
            pat = re.compile(r'(<event class="Player" method="%s" enabled=")(\d)(" */>)' % method)
            m = pat.search(out)
            if not m:
                line = '\t<event class="Player" method="%s" enabled="%d" />\n' % (method, 1 if enable else 0)
                at = out.rfind('\t<!-- Monster methods -->')
                if at < 0:
                    at = out.rfind('</events>')
                if at < 0:
                    return text, '</events> not found in events.xml'
                out = out[:at] + line + out[at:]
            elif enable and m.group(2) != '1':
                out = out[:m.start()] + m.group(1) + '1' + m.group(3) + out[m.end():]
        return out, ('patched' if out != text else 'already')
    return patch_spell_events


RARITY_MARKER = '-- Chaos: several rarity elements, each its own share, never 0 damage (patch_base_events.py)'
RARITY_HEALTH_RX = re.compile(r'(\n([ \t]*)elseif chosenBonusType ~= elemData\.combatType then[ \t]*\r?\n)'
                              r'[ \t]*return[ \t]*(\r?\n)')
RARITY_MANA_RX = re.compile(r'(\n([ \t]*)elseif chosenBonusType ~= elemData\.combatType then[ \t]*\r?\n)'
                            r'[ \t]*return manaChange[ \t]*(\r?\n)')


def patch_rarity_elements(text):
    """returns (new text, status)"""
    if RARITY_MARKER in text:
        return text, 'already'
    health = list(RARITY_HEALTH_RX.finditer(text))
    mana = list(RARITY_MANA_RX.finditer(text))
    if len(health) != 1 or len(mana) != 1:
        return text, ('unexpected rarity_onCombat_elementdamage.lua (the stock "elseif chosenBonusType ~= '
                      'elemData.combatType then" + "return" / "return manaChange" lines not found once each)')
    h, m = health[0], mana[0]
    ind, nl = h.group(2) + '    ', h.group(3)
    hblock = (h.group(1)
              + ind + RARITY_MARKER + nl
              + ind + 'if ChaosRarityElements and ChaosRarityElements.onHealthChange then' + nl
              + ind + '    return ChaosRarityElements.onHealthChange(source, target, baseElement, baseElementType,' + nl
              + ind + '        primaryDamage, primaryType, secondaryDamage, secondaryType)' + nl
              + ind + 'end' + nl
              + ind + 'return primaryDamage, primaryType, secondaryDamage, secondaryType' + nl)
    mind, mnl = m.group(2) + '    ', m.group(3)
    mblock = m.group(1) + mind + RARITY_MARKER + ': every element counts for mana' + mnl
    # replace the later match first so the earlier offsets stay valid
    parts = sorted([(h, hblock), (m, mblock)], key=lambda x: x[0].start(), reverse=True)
    for match, block in parts:
        text = text[:match.start()] + block + text[match.end():]
    return text, 'patched'


LOOTNAME_MARKER = '-- Chaos: loot lines name a renamed monster by its shown name (patch_base_events.py)'
LOOTNAME_OLD = 'mType:getNameDescription()'
LOOTNAME_NEW = 'chaosLootName(self, mType)'
LOOTNAME_HELPER = (
    LOOTNAME_MARKER + '\n'
    'local function chaosLootName(monster, mType)\n'
    '\tif Chaos and Chaos.monsterNameDescription then\n'
    '\t\treturn Chaos.monsterNameDescription(monster)\n'
    '\tend\n'
    '\treturn mType:getNameDescription()\n'
    'end\n\n'
)


def patch_loot_name(text):
    """returns (new text, status)"""
    if LOOTNAME_MARKER in text:
        return text, 'already'
    at = text.find('ec.onDropLoot = function(self, corpse)')
    if at < 0 or text.count(LOOTNAME_OLD) != 2:
        return text, ('unexpected default_onDropLoot.lua (ec.onDropLoot or the two "Loot of" '
                      'mType:getNameDescription() calls not found)')
    body = text[at:].replace(LOOTNAME_OLD, LOOTNAME_NEW)
    return text[:at] + LOOTNAME_HELPER + body, 'patched'

BUG_MARKER = '-- Chaos: bug reports from every account into chaos_reports (patch_base_events.py)'
BUG_RX = re.compile(r'function Player:onReportBug\(\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\)[ \t]*(\r?\n)')


def patch_report_bug(text):
    """returns (new text, status): ChaosReports.onReportBug first in Player:onReportBug"""
    if BUG_MARKER in text:
        return text, 'already'
    m = list(BUG_RX.finditer(text))
    if len(m) != 1:
        return text, 'unexpected player.lua (function Player:onReportBug(message, position, category) not found once)'
    m = m[0]
    msg, pos, cat, nl = m.group(1), m.group(2), m.group(3), m.group(4)
    block = ('\t' + BUG_MARKER + nl
             + '\tif ChaosReports and ChaosReports.onReportBug then' + nl
             + '\t\treturn ChaosReports.onReportBug(self, %s, %s, %s)' % (msg, pos, cat) + nl
             + '\tend' + nl)
    return text[:m.end()] + block + text[m.end():], 'patched'


STAMINA_MARKER = '-- Chaos: the Chaos Pact regenerates stamina faster (patch_base_events.py)'
STAMINA_RE = re.compile(r'^([ \t]*)offlineTime = offlineTime - 600[ \t]*(\r?\n)', re.M)


def patch_offline_stamina(text):
    if STAMINA_MARKER in text:
        return text, 'already'
    m = STAMINA_RE.search(text)
    if not m:
        return text, 'unexpected regeneratestamina.lua ("offlineTime = offlineTime - 600" not found)'
    ind, nl = m.group(1), m.group(2)
    block = (ind + STAMINA_MARKER + nl
             + ind + 'if offlineTime > 0 and ChaosPactPerks and ChaosPactPerks.staminaMult then' + nl
             + ind + '\tofflineTime = offlineTime * ChaosPactPerks.staminaMult(player)' + nl
             + ind + 'end' + nl)
    return text[:m.end()] + block + text[m.end():], 'patched'


TRAINER_MARKER = '-- Chaos: the Chaos Pact rests stamina faster on the trainer tile (patch_base_events.py)'
TRAINER_RE = re.compile(r'^([ \t]*)addEvent\(Stamina, 120000, playerId, seconds - 1\)[ \t]*(\r?\n)', re.M)


def patch_trainer_stamina(text):
    if TRAINER_MARKER in text:
        return text, 'already'
    m = TRAINER_RE.search(text)
    if not m:
        return text, 'unexpected trainer_tile_stamina.lua ("addEvent(Stamina, 120000, playerId, seconds - 1)" not found)'
    ind, nl = m.group(1), m.group(2)
    block = (ind + TRAINER_MARKER + nl
             + ind + 'local restMs = 120000' + nl
             + ind + 'if ChaosPactPerks and ChaosPactPerks.staminaRestMs then' + nl
             + ind + '    restMs = ChaosPactPerks.staminaRestMs(player, 120000)' + nl
             + ind + 'end' + nl
             + ind + 'addEvent(Stamina, restMs, playerId, seconds - 1)' + nl)
    return text[:m.start()] + block + text[m.end():], 'patched'


DEATHKEEP_MARKER = '-- Chaos: store-bound items never drop (patch_base_events.py)'
DEATHKEEP_RE = re.compile(r'^([ \t]*)if \(isRedOrBlack or lossPercent ~= 0\) and not item:moveTo\(corpse\) then[ \t]*(\r?\n)',
                          re.M)


def patch_death_keep(text):
    if DEATHKEEP_MARKER in text:
        return text, 'already'
    m = DEATHKEEP_RE.search(text)
    if not m:
        return text, ('unexpected droploot.lua ("if (isRedOrBlack or lossPercent ~= 0) and not item:moveTo(corpse) then" '
                      'not found)')
    ind, nl = m.group(1), m.group(2)
    block = (ind + DEATHKEEP_MARKER + nl
             + ind + 'if (isRedOrBlack or lossPercent ~= 0) and not (ChaosDeathKeep and ChaosDeathKeep.beforeDrop'
             + ' and ChaosDeathKeep.beforeDrop(player, item, corpse)) and not item:moveTo(corpse) then' + nl)
    return text[:m.start()] + block + text[m.end():], 'patched'


LOSE_MARKER = '-- Chaos: gentle deaths (patch_base_events.py)'
LOSE_RE = re.compile(r'^function Player:onLoseExperience\(([A-Za-z_][A-Za-z_0-9]*)\)[ \t]*(\r?\n)', re.M)


def patch_lose_experience(text):
    """player.lua: Player:onLoseExperience asks ChaosGentleDeath first; returns (new text, status)"""
    if LOSE_MARKER in text:
        return text, 'already'
    m = LOSE_RE.search(text)
    if m:
        var, nl = m.group(1), m.group(2)
        block = ('\t' + LOSE_MARKER + nl
                 + '\tif ChaosGentleDeath and ChaosGentleDeath.onLoseExperience then' + nl
                 + '\t\t' + var + ' = ChaosGentleDeath.onLoseExperience(self, ' + var + ') or ' + var + nl
                 + '\tend' + nl)
        return text[:m.end()] + block + text[m.end():], 'patched'
    if 'Player:onLoseExperience' in text:
        return text, 'unexpected player.lua (Player:onLoseExperience with an unknown signature)'
    nl = '\r\n' if '\r\n' in text else '\n'
    tail = '' if text.endswith(nl) or text == '' else nl
    fn = (nl + 'function Player:onLoseExperience(exp)' + nl
          + '\t' + LOSE_MARKER + nl
          + '\tif ChaosGentleDeath and ChaosGentleDeath.onLoseExperience then' + nl
          + '\t\texp = ChaosGentleDeath.onLoseExperience(self, exp) or exp' + nl
          + '\tend' + nl
          + '\treturn exp' + nl
          + 'end' + nl)
    return text + tail + fn, 'patched'


LOSE_EVENT_RE = re.compile(r'(<event class="Player" method="onLoseExperience" enabled=")(\d)("\s*/>)')


def patch_lose_event(text):
    """events.xml: the Player onLoseExperience event on; returns (new text, status)"""
    m = LOSE_EVENT_RE.search(text)
    if m:
        if m.group(2) == '1':
            return text, 'already'
        return text[:m.start()] + m.group(1) + '1' + m.group(3) + text[m.end():], 'patched'
    nl = '\r\n' if '\r\n' in text else '\n'
    line = '\t<event class="Player" method="onLoseExperience" enabled="1" />' + nl
    at = text.rfind('\t<!-- Monster methods -->')
    if at < 0:
        at = text.rfind('</events>')
    if at < 0:
        return text, '</events> not found in events.xml'
    return text[:at] + line + text[at:], 'patched'


LOWLOOT_MARKER = '-- Chaos: low stamina cuts the loot instead of zeroing it (patch_base_events.py)'
LOWLOOT_GATE_RE = re.compile(r'^([ \t]*)if player:getStamina\(\) <= 840 then[ \t]*(\r?\n)', re.M)
LOWLOOT_CHANCE_RE = re.compile(r'(if roll <= lootData\.chance)([^\n]*?)( then)')


def patch_low_stamina_loot(text):
    """returns (new text, status): the low stamina gate asks the factor, every loot chance is x the factor"""
    if LOWLOOT_MARKER in text:
        return text, 'already'
    at = text.find('ec.onDropLoot = function(self, corpse)')
    gates = list(LOWLOOT_GATE_RE.finditer(text))
    chances = list(LOWLOOT_CHANCE_RE.finditer(text))
    if at < 0 or len(gates) != 1 or len(chances) != 1:
        return text, ('unexpected default_onDropLoot.lua (ec.onDropLoot, "if player:getStamina() <= 840 then" or '
                      '"if roll <= lootData.chance ... then" not found once)')
    nl = gates[0].group(2)
    c = chances[0]
    text = text[:c.start()] + c.group(1) + c.group(2) + ' * chaosStaminaLootMult(player)' + c.group(3) + text[c.end():]
    g = list(LOWLOOT_GATE_RE.finditer(text))[0]
    text = (text[:g.start()] + g.group(1) + 'if player:getStamina() <= 840 and chaosStaminaLootMult(player) <= 0 then'
            + g.group(2) + text[g.end():])
    helper = (LOWLOOT_MARKER + nl
              + 'local function chaosStaminaLootMult(player)' + nl
              + '\tif ChaosCatchup and ChaosCatchup.staminaLootMult then' + nl
              + '\t\tlocal ok, m = pcall(ChaosCatchup.staminaLootMult, player)' + nl
              + '\t\tif ok and tonumber(m) then' + nl
              + '\t\t\treturn tonumber(m)' + nl
              + '\t\tend' + nl
              + '\tend' + nl
              + '\treturn player:getStamina() <= 840 and 0 or 1' + nl
              + 'end' + nl + nl)
    at = text.find('ec.onDropLoot = function(self, corpse)')
    return text[:at] + helper + text[at:], 'patched'


OFFLINE_MARKER = '-- Chaos: stamina comes back faster offline (patch_base_events.py)'


def patch_offline_catchup(text):
    """returns (new text, status): the offline time x ChaosCatchup.offlineStaminaMult, right after the 10 minute grace"""
    if OFFLINE_MARKER in text:
        return text, 'already'
    m = STAMINA_RE.search(text)
    if not m:
        return text, 'unexpected regeneratestamina.lua ("offlineTime = offlineTime - 600" not found)'
    ind, nl = m.group(1), m.group(2)
    block = (ind + OFFLINE_MARKER + nl
             + ind + 'if offlineTime > 0 and ChaosCatchup and ChaosCatchup.offlineStaminaMult then' + nl
             + ind + '\tofflineTime = offlineTime * ChaosCatchup.offlineStaminaMult(player)' + nl
             + ind + 'end' + nl)
    return text[:m.end()] + block + text[m.end():], 'patched'


KEEPALL_MARKER = '-- Chaos: gentle deaths keep every item (patch_base_events.py)'
KEEPALL_RE = re.compile(r'^([ \t]*)local amulet = player:getSlotItem\(CONST_SLOT_NECKLACE\)[ \t]*(\r?\n)', re.M)


def patch_keep_all(text):
    """droploot.lua: no item loss when ChaosGentleDeath.keepAll(player); returns (new text, status)"""
    if KEEPALL_MARKER in text:
        return text, 'already'
    m = KEEPALL_RE.search(text)
    if not m or len(KEEPALL_RE.findall(text)) != 1:
        return text, 'unexpected droploot.lua ("local amulet = player:getSlotItem(CONST_SLOT_NECKLACE)" not found once)'
    ind, nl = m.group(1), m.group(2)
    block = (ind + KEEPALL_MARKER + nl
             + ind + 'if ChaosGentleDeath and ChaosGentleDeath.keepAll and ChaosGentleDeath.keepAll(player) then' + nl
             + ind + '\treturn true' + nl
             + ind + 'end' + nl)
    return text[:m.start()] + block + text[m.start():], 'patched'


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
    ok = apply(os.path.join(args[0], 'scripts', 'eventcallbacks', 'monster', 'default_onDropLoot.lua'),
               patch_loot_name, dry) and ok
    ok = apply(os.path.join(args[0], 'events', 'scripts', 'creature.lua'), patch_target_combat, dry) and ok
    ok = apply(os.path.join(args[0], 'events', 'scripts', 'creature.lua'), patch_zone_combat, dry) and ok
    ok = apply(os.path.join(args[0], 'creaturescripts', 'scripts', 'login.lua'), patch_login_demotion, dry) and ok
    ok = apply(os.path.join(args[0], 'scripts', 'creaturescripts', 'autoloot.lua'), patch_autoloot, dry) and ok
    ok = apply(os.path.join(args[0], 'items', 'items.xml'), patch_item_chances, dry) and ok
    ok = apply(os.path.join(args[0], 'scripts', 'customs', 'waystone_system', 'character_upgrades.lua'),
               patch_waystone_chances, dry) and ok
    ok = apply(os.path.join(args[0], 'events', 'scripts', 'player.lua'), patch_spell_stubs, dry) and ok
    ok = apply(os.path.join(args[0], 'events', 'events.xml'),
               make_spell_events('--enable-spell-events' in sys.argv), dry) and ok
    ok = apply(os.path.join(args[0], 'scripts', 'customs', 'rarity', 'rarity_onCombat_elementdamage.lua'),
               patch_rarity_elements, dry) and ok
    ok = apply(os.path.join(args[0], 'events', 'scripts', 'player.lua'), patch_report_bug, dry) and ok
    ok = apply(os.path.join(args[0], 'creaturescripts', 'scripts', 'regeneratestamina.lua'),
               patch_offline_stamina, dry) and ok
    ok = apply(os.path.join(args[0], 'scripts', 'customs', 'actions', 'trainer_tile_stamina.lua'),
               patch_trainer_stamina, dry) and ok
    ok = apply(os.path.join(args[0], 'creaturescripts', 'scripts', 'droploot.lua'), patch_death_keep, dry) and ok
    ok = apply(os.path.join(args[0], 'scripts', 'eventcallbacks', 'monster', 'default_onDropLoot.lua'),
               patch_low_stamina_loot, dry) and ok
    ok = apply(os.path.join(args[0], 'creaturescripts', 'scripts', 'regeneratestamina.lua'),
               patch_offline_catchup, dry) and ok
    ok = apply(os.path.join(args[0], 'events', 'scripts', 'player.lua'), patch_lose_experience, dry) and ok
    ok = apply(os.path.join(args[0], 'events', 'events.xml'), patch_lose_event, dry) and ok
    ok = apply(os.path.join(args[0], 'creaturescripts', 'scripts', 'droploot.lua'), patch_keep_all, dry) and ok
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
