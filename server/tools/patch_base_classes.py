#!/usr/bin/env python3
"""The base server's own scripts and the Chaos classes (docs/CLASSES.md, "Base scripts"; idempotent).

usage: python3 -I patch_base_classes.py DATA_DIR [--dry-run]

The base server's scripts, NPCs and quests test the stock vocation ids (1-10) by number or with
Player.isSorcerer / isDruid / isKnight / isPaladin / isMage. The classes keep some of those ids (Warrior 4, Ranger 3,
Mystic 1, ...) but 2, 6 and 9 are retired and the Thief (11-13), Berserker (14), Beastmaster (15), Monk (17-19),
Necromancer (20-22) and Templar (23-25) lines are new, so those checks refused them, indexed nil (script errors) or put
them on retired ids. Every class now counts as the stock vocation whose base content it gets:

    Warrior 4 / Juggernaut 8 / Berserker 14      -> Knight 4 / Elite Knight 8
    Templar 23 / Inquisitor 24 / Sentinel 25     -> Knight 4 / Elite Knight 8
    Ranger 3 / Deadeye 7 / Beastmaster 15        -> Paladin 3 / Royal Paladin 7
    Thief 11 / Ninja 12 / Samurai 13             -> Paladin 3 / Royal Paladin 7
    Monk 17 / Shadowfist 18 / Iron Sage 19       -> Paladin 3 / Royal Paladin 7
    Mystic 1 / Elementalist 5                    -> Sorcerer 1 / Master Sorcerer 5
    Necromancer 20 / Lich 21 / Bone Lord 22      -> Sorcerer 1 / Master Sorcerer 5
    Illusionist 10                               -> Elder Druid 6 (the druid's heals, docs/CLASSES.md)

1. data/lib/core/player.lua: CHAOS_STOCK_VOCATION (the table above), Player.getStockVocationId() and
   Player.getStockBaseVocationId() (1-4); isSorcerer / isDruid / isKnight / isPaladin / isMage / isIllusionist answer
   by it (the six stock functions, also as add_vocations.py left them, are replaced). Every script that asks them
   follows: Bozo, the mirror image boss, Arkulius (elemental spheres), the free first wand, ...
2. Scripts that index or compare by the vocation id or its base id use the stock ids instead: the elemental spheres
   (lever, machine, soils, enchanting gems), the desert dungeon (one of each vocation), the Pits of Inferno fire tiles,
   the sorcerer guild tiles, the shrine and Daram portals, the soil portals, the free first wand / rod NPCs (Magido,
   Asima, Rachel, Topsy, Alexander, Xodet, Fenech, runes.lua) and the monster spell Astro Wave (it hit only the stock
   ids: the new lines were immune). The refusal texts name our classes.
3. Per-case decisions:
   - NPC spell teachers (npc/lib/npcsystem/customModules.lua, KeywordHandler:addSpellKeyword): the spell's own
     vocation list in spells.xml decides who is offered a spell (the NPC's stock vocation only when the spell is
     unknown), so an NPC teaches every class what it may learn there.
   - Familiars (scripts/customs/pet_system/pet_system.lua): Warrior line Knight Familiar, Ranger, Thief and Templar
     lines Paladin Familiar (holy for the Templar), Mystic, Elementalist and the Necromancer line Sorcerer Familiar,
     Illusionist Illusionist Familiar, Monk line Druid Familiar. Before, the new lines got nothing ("pet nil").
   - Exercise weapons (actions/scripts/other/exercise_weapons.lua): sword: Warrior, Thief, Templar lines; axe:
     Warrior, Templar lines; club: Warrior, Monk, Templar lines; shield: Warrior, Templar lines; bow (distance):
     Ranger, Thief lines; rod and wand (magic level): Mystic line and Necromancer line. The Berserker was refused before.
   - Party shared experience (events/scripts/party.lua): the bonus for different vocations counts the class lines,
     at most 5 (the stock maximum, x2.5); with seven lines it would reach x3.8.
   - The vocation Oracles (The Oracle, The Oracle3, Captain Dreadnought): they set the retired ids 2 (druid) and
     9 (illusionist) and looked the equipment up by the stock names (an error after the vocation was set). They now
     offer Warrior, Ranger, Mystic and Thief (the old words choose the matching class); the Monk, Necromancer and
     Templar stay with the store's class unlock.
   - The Dead Bureaucrats (Pits of Inferno): they say the base class's weapon / spelled name; config[11..23] was nil.
   - Arkulius (elemental spheres reward): the Royal Paladin's crossbow (the ironworker) only for the Ranger and the
     Deadeye; the Beastmaster, Thief and Monk lines, who cannot fire it, get the frozen plate (ice, their armour).
   - Item upgrade slots (scripts/customs/upgrade/upgrade_slot_item.lua): the skill bonus a slot rolls is read from the
     item's "wielded properly by ..." text, which names our classes now; their names are added.
   - The opcode 73 highscores handler (scripts/customs/highscores/highscores.lua): the vocation filter is reduced
     to numbers (it went into the SQL as sent) and a stock id also lists the classes that count as it.
4. Not changed (reviewed): firstitems.lua and the starter chest (vocation 0 / old ids only; the Chaos new-player kit
   gives the class kits, newplayer_config.lua), the rook advance / chat channel / droploot checks (vocation 0), the
   Oracles' "already have a vocation" check, compat getPlayerVocation, the party icons and inspect (names), offline
   training (vocation attributes), the promotion paths (patch_promotion.py), potions (add_vocations.py).

Every edit is an exact match on the stock lines; a file that differs is reported and left alone, a missing file is
skipped. Idempotent: the new lines are recognised on the next run. CRLF files keep their line ends.
After the edits the tool lists any other line of the data folder (outside the Chaos folders) that tests a vocation, as
a hint for a base server update.
"""
import os
import re
import sys

MARK = 'Chaos: classes (patch_base_classes.py)'

# class id -> the stock vocation it counts as (the table above); kept in step with the Lua table below
STOCK = {0: 0, 1: 1, 5: 5, 10: 6, 4: 4, 8: 8, 14: 8, 3: 3, 7: 7, 15: 7, 11: 3, 12: 7, 13: 7, 17: 3, 18: 7, 19: 7,
         20: 1, 21: 5, 22: 5, 23: 4, 24: 8, 25: 8}

# ---------------------------------------------------------------------------------------------- 1. lib/core/player.lua
PLAYER_RE = re.compile(r'function Player\.isSorcerer\(self\)\n.*?function Player\.isMage\(self\)\n.*?\nend\n', re.S)
PLAYER_FUNCS = ('isSorcerer', 'isDruid', 'isKnight', 'isIllusionist', 'isPaladin', 'isMage')
PLAYER_NEW = '''-- ''' + MARK + '''
-- The base server's scripts know the stock vocations only: every class counts as the stock vocation whose content it
-- gets (docs/CLASSES.md "Base scripts"). An id not listed counts as itself.
CHAOS_STOCK_VOCATION = {
	[0] = 0,
	[1] = 1, [5] = 5, [10] = 6, -- Mystic, Elementalist -> Sorcerer, Master Sorcerer; Illusionist -> Elder Druid
	[4] = 4, [8] = 8, [14] = 8, -- Warrior, Juggernaut, Berserker -> Knight, Elite Knight
	[3] = 3, [7] = 7, [15] = 7, -- Ranger, Deadeye, Beastmaster -> Paladin, Royal Paladin
	[11] = 3, [12] = 7, [13] = 7, -- Thief, Ninja, Samurai -> Paladin, Royal Paladin
	[17] = 3, [18] = 7, [19] = 7, -- Monk, Shadowfist, Iron Sage -> Paladin, Royal Paladin
	[20] = 1, [21] = 5, [22] = 5, -- Necromancer, Lich, Bone Lord -> Sorcerer, Master Sorcerer
	[23] = 4, [24] = 8, [25] = 8, -- Templar, Inquisitor, Sentinel -> Knight, Elite Knight
}
CHAOS_STOCK_BASE = {[0] = 0, [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 1, [6] = 2, [7] = 3, [8] = 4, [9] = 9, [10] = 9}

function chaosStockVocationOf(vocationId)
	return CHAOS_STOCK_VOCATION[vocationId] or vocationId
end

function Player.getStockVocationId(self)
	return chaosStockVocationOf(self:getVocation():getId())
end

function Player.getStockBaseVocationId(self)
	local id = self:getStockVocationId()
	return CHAOS_STOCK_BASE[id] or id
end

function Player.isSorcerer(self)
	return self:getStockBaseVocationId() == VOCATION.ID.SORCERER
end

function Player.isDruid(self)
	return self:getStockBaseVocationId() == VOCATION.ID.DRUID
end

function Player.isKnight(self)
	return self:getStockBaseVocationId() == VOCATION.ID.KNIGHT
end

-- the base server's own Illusionist (9 / 10) is retired; our Illusionist counts as a Druid
function Player.isIllusionist(self)
	return self:getStockBaseVocationId() == VOCATION.ID.ILLUSIONIST
end

function Player.isPaladin(self)
	return self:getStockBaseVocationId() == VOCATION.ID.PALADIN
end

function Player.isMage(self)
	local base = self:getStockBaseVocationId()
	return base == VOCATION.ID.SORCERER or base == VOCATION.ID.DRUID
end
'''


def patch_player(text):
    if MARK in text:
        return text, 'already'
    m = PLAYER_RE.search(text)
    if not m or any('function Player.%s(self)' % f not in m.group(0) for f in PLAYER_FUNCS):
        return text, 'unexpected player.lua (the six stock vocation functions not found together)'
    return text[:m.start()] + PLAYER_NEW + text[m.end():], 'patched'


# ---------------------------------------------------------------------------------------------- 3. NPC spell teachers
SPELL_OLD = (
    '\t\tfunction(player)\n'
    '\t\t\tlocal baseVocationId = player:getVocation():getBase():getId()\n'
    '\t\t\tif type(vocationId) == \'table\' then\n'
)
SPELL_NEW = (
    '\t\tfunction(player)\n'
    '\t\t\t-- ' + MARK + ': the spell\'s own vocation list (spells.xml) decides\n'
    '\t\t\tlocal spell = Spell and Spell(spellName)\n'
    '\t\t\tif spell then\n'
    '\t\t\t\tlocal own = player:getVocation():getName():lower()\n'
    '\t\t\t\tfor _, name in ipairs(spell:vocation() or {}) do\n'
    '\t\t\t\t\tif name:lower() == own then\n'
    '\t\t\t\t\t\treturn true\n'
    '\t\t\t\t\tend\n'
    '\t\t\t\tend\n'
    '\t\t\t\treturn false\n'
    '\t\t\tend\n'
    '\t\t\tlocal baseVocationId = player:getStockBaseVocationId()\n'
    '\t\t\tif type(vocationId) == \'table\' then\n'
)

# ---------------------------------------------------------------------------------------------- familiars
PET_OLD = '  local vocationBaseId = player:getVocation():getId()\n'
PET_NEW = (
    '  local vocationBaseId = player:getVocation():getId()\n'
    '  -- ' + MARK + ': the familiar of each class line (Warrior: Knight, Ranger / Thief / Templar: Paladin,\n'
    '  -- Mystic / Elementalist / Necromancer: Sorcerer, Illusionist: Illusionist, Monk: Druid)\n'
    '  local chaosFamiliar = {[14] = 4, [15] = 3, [11] = 3, [12] = 3, [13] = 3, [17] = 2, [18] = 2, [19] = 2,\n'
    '    [20] = 1, [21] = 1, [22] = 1, [23] = 3, [24] = 3, [25] = 3}\n'
    '  vocationId = chaosFamiliar[vocationBaseId] or vocationBaseId\n'
    '  vocationBaseId = vocationId\n'
)

# ---------------------------------------------------------------------------------------------- exercise weapons
EXERCISE = [
    ('id=SKILL_SWORD, voc={4,8}}', 'id=SKILL_SWORD, voc={4,8,14,11,12,13,23,24,25}}'),
    ('id=SKILL_AXE, voc={4,8}}', 'id=SKILL_AXE, voc={4,8,14,23,24,25}}'),
    ('id=SKILL_CLUB, voc={4,8}}', 'id=SKILL_CLUB, voc={4,8,14,17,18,19,23,24,25}}'),
    ('id=SKILL_SHIELD, voc={4,8}}', 'id=SKILL_SHIELD, voc={4,8,14,23,24,25}}'),
    ('id=SKILL_DISTANCE, voc={3,7},', 'id=SKILL_DISTANCE, voc={3,7,15,11,12,13},'),
    ('id=SKILL_MAGLEVEL, voc={1,2,5,6,9,10},', 'id=SKILL_MAGLEVEL, voc={1,5,10,20,21,22},'),
]

# ---------------------------------------------------------------------------------------------- the vocation Oracles
ORACLE_WORDS_OLD = '{KNIGHT}, {PALADIN}, {SORCERER}, {ILLUSIONIST} OR {DRUID}'
ORACLE_WORDS_NEW = '{WARRIOR}, {RANGER}, {MYSTIC} OR {THIEF}'
ORACLE_ANCHOR = 'function onCreatureAppear(cid)'
ORACLE_BLOCK = (
    '-- ' + MARK + ': the base classes; the old words choose the matching class, the equipment is\n'
    '-- looked up by the class name (Vocation(id):getName()). Monk, Necromancer, Templar: the store\'s class unlock.\n'
    'do\n'
    '\tlocal v = config.vocations\n'
    '\tlocal function class(word, text, id, from)\n'
    '\t\tv[word] = {text = text, vocationId = id, v[from][1], v[from][2]}\n'
    '\tend\n'
    '\tclass("warrior", "A WARRIOR! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!", 4, "knight")\n'
    '\tclass("ranger", "A RANGER! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!", 3, "paladin")\n'
    '\tclass("mystic", "A MYSTIC! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!", 1, "sorcerer")\n'
    '\tclass("thief", "A THIEF! ARE YOU SURE? THIS DECISION IS IRREVERSIBLE!", 11, "paladin")\n'
    '\tv.knight, v.paladin, v.sorcerer, v.druid, v.illusionist = v.warrior, v.ranger, v.mystic, v.mystic, v.mystic\n'
    'end\n'
    '\n'
)

# ---------------------------------------------------------------------------------------------- Dead Bureaucrats
BUREAUCRAT1_OLD = '\t[4] = "sword"\n}\n'
BUREAUCRAT1_NEW = ('\t[4] = "sword",\n'
                   '\t[11] = "daggers", [17] = "fists", [20] = "wand", [23] = "mace" -- ' + MARK + '\n'
                   '}\n')
BUREAUCRAT4_OLD = ('\t[1] = "S O R C E R E R",\n\t[2] = "D R U I D",\n\t[3] = "P A L A D I N",\n'
                   '\t[4] = "K N I G H T"\n}\n')
BUREAUCRAT4_NEW = ('\t[1] = "M Y S T I C",\n\t[2] = "D R U I D",\n\t[3] = "R A N G E R",\n'
                   '\t[4] = "W A R R I O R",\n'
                   '\t[11] = "T H I E F", [17] = "M O N K", [20] = "N E C R O M A N C E R", [23] = "T E M P L A R" -- '
                   + MARK + '\n}\n')

# ---------------------------------------------------------------------------------------------- upgrade slots
UPGRADE = [
    ('    ["Arch Illusionist"] = {"MagicLevel", "Shield"},\n}\n',
     '    ["Arch Illusionist"] = {"MagicLevel", "Shield"},\n'
     '    -- ' + MARK + '\n'
     '    ["Warrior"] = {"Axe", "Club", "Sword", "Shield"}, ["Juggernaut"] = {"Axe", "Club", "Sword", "Shield"},\n'
     '    ["Berserker"] = {"Axe", "Club", "Sword", "Shield"}, ["Templar"] = {"Club", "Sword", "Shield"},\n'
     '    ["Inquisitor"] = {"Club", "Sword", "Shield"}, ["Sentinel"] = {"Club", "Sword", "Shield"},\n'
     '    ["Ranger"] = {"Distance", "Shield"}, ["Deadeye"] = {"Distance", "Shield"}, ["Beastmaster"] = {"Distance", "Shield"},\n'
     '    ["Mystic"] = {"MagicLevel", "Shield"}, ["Elementalist"] = {"MagicLevel", "Shield"},\n'
     '    ["Necromancer"] = {"MagicLevel", "Shield"}, ["Lich"] = {"MagicLevel", "Shield"}, ["Bone Lord"] = {"MagicLevel", "Shield"},\n'
     '    ["Thief"] = {"Sword", "Distance", "Shield"}, ["Ninja"] = {"Sword", "Distance", "Shield"},\n'
     '    ["Samurai"] = {"Sword", "Distance", "Shield"},\n'
     '    ["Monk"] = {"Club", "Shield"}, ["Shadowfist"] = {"Club", "Shield"}, ["Iron Sage"] = {"Club", "Shield"},\n'
     '}\n'),
    ('        ["arch illusionists"] = "Arch Illusionist",\n    }\n',
     '        ["arch illusionists"] = "Arch Illusionist",\n'
     '        -- ' + MARK + ': the engine writes the lower case name + "s"\n'
     '        ["warriors"] = "Warrior", ["juggernauts"] = "Juggernaut", ["berserkers"] = "Berserker",\n'
     '        ["templars"] = "Templar", ["inquisitors"] = "Inquisitor", ["sentinels"] = "Sentinel",\n'
     '        ["rangers"] = "Ranger", ["deadeyes"] = "Deadeye", ["beastmasters"] = "Beastmaster",\n'
     '        ["mystics"] = "Mystic", ["elementalists"] = "Elementalist",\n'
     '        ["necromancers"] = "Necromancer", ["lichs"] = "Lich", ["bone lords"] = "Bone Lord",\n'
     '        ["thiefs"] = "Thief", ["ninjas"] = "Ninja", ["samurais"] = "Samurai",\n'
     '        ["monks"] = "Monk", ["shadowfists"] = "Shadowfist", ["iron sages"] = "Iron Sage",\n'
     '    }\n'),
]

# ---------------------------------------------------------------------------------------------- highscores (opcode 73)
# anchored on the second line only: the opcodeinputs step rewrites the first one
HIGHSCORES_OLD = '  if #vocs == 0 then vocs = { vocation } end\n'
HIGHSCORES_NEW = ('  if #vocs == 0 then vocs = { vocation } end\n'
                  '  -- ' + MARK + ': numbers only (they go into the SQL); a stock id lists its classes too\n'
                  '  local chaosVocs, chaosSeen = {}, {}\n'
                  '  local function chaosAdd(id)\n'
                  '    if id and not chaosSeen[id] then chaosSeen[id] = true; chaosVocs[#chaosVocs + 1] = id end\n'
                  '  end\n'
                  '  for _, v in ipairs(type(vocs) == "table" and vocs or {}) do\n'
                  '    local id = tonumber(v)\n'
                  '    id = id and math.floor(id)\n'
                  '    chaosAdd(id)\n'
                  '    for class, stock in pairs(CHAOS_STOCK_VOCATION or {}) do\n'
                  '      if id and stock == id then chaosAdd(class) end\n'
                  '    end\n'
                  '  end\n'
                  '  if #chaosVocs == 0 then chaosVocs = { 0 } end\n'
                  '  vocs = chaosVocs\n')

# ---------------------------------------------------------------------------------------------- the edits per file
GET_BASE = 'player:getVocation():getBase():getId()'
GET_ID = 'player:getVocation():getId()'
STOCK_BASE = 'player:getStockBaseVocationId()'
STOCK_ID = 'player:getStockVocationId()'
WAND_TEXT_OLD = "'Sorry, you aren\\'t a druid either a sorcerer.'"
WAND_TEXT_NEW = "'Sorry, only Mystics and Necromancers get one.'"
PORTAL_TEXT_OLD = "(portal.vocation == 1 and 'Sorcerers' or 'Druids')"
PORTAL_TEXT_NEW = "(portal.vocation == 1 and 'Mystics, Elementalists and Necromancers' or 'Illusionists')"

# (path below data, [(old, new, count or None for all)])
EDITS = [
    ('npc/lib/npcsystem/customModules.lua', [(SPELL_OLD, SPELL_NEW, 1)]),
    ('scripts/customs/pet_system/pet_system.lua', [(PET_OLD, PET_NEW, 1)]),
    ('actions/scripts/other/exercise_weapons.lua', [(o, n, None) for o, n in EXERCISE]),
    ('events/scripts/party.lua', [('\tlocal size = #vocationsIds\n',
                                   '\tlocal size = math.min(#vocationsIds, 5) -- ' + MARK + ': at most the stock x2.5\n', 1)]),
    ('scripts/customs/upgrade/upgrade_slot_item.lua', [(o, n, 1) for o, n in UPGRADE]),
    ('scripts/customs/highscores/highscores.lua', [(HIGHSCORES_OLD, HIGHSCORES_NEW, 1)]),
    ('npc/scripts/Arkulius.lua', [('player:isPaladin() and 8853 or',
                                   'player:isPaladin() and (table.contains({3, 7}, player:getVocation():getId()) and 8853 or 8887) or',
                                   1)]),
    ('npc/scripts/A Dead Bureaucrat1.lua', [(BUREAUCRAT1_OLD, BUREAUCRAT1_NEW, 1)]),
    ('npc/scripts/A Dead Bureaucrat4.lua', [(BUREAUCRAT4_OLD, BUREAUCRAT4_NEW, 1)]),
    ('actions/scripts/quests/elemental spheres/soils2.lua', [(GET_ID, STOCK_ID, 1), (GET_BASE, STOCK_BASE, 1)]),
    ('actions/scripts/quests/elemental spheres/lever.lua',
     [('creature:getVocation():getBase():getId()', 'creature:getStockBaseVocationId()', 1)]),
    ('actions/scripts/quests/elemental spheres/machine.lua', [(GET_BASE, STOCK_BASE, 1)]),
    ('actions/scripts/other/enchanting.lua', [(GET_ID, STOCK_ID, 1)]),
    ('actions/scripts/quests/desertdungeonquest.lua',
     [('creature:getVocation():getBase():getId()', 'creature:getStockBaseVocationId()', 1)]),
    ('movements/scripts/quests/pits of inferno/fireTiles.lua', [(GET_BASE, STOCK_BASE, 1)]),
    ('movements/scripts/others/sorcererthais.lua', [(GET_BASE, STOCK_BASE, 1)]),
    ('movements/scripts/others/sorcererdaram.lua', [(GET_BASE, STOCK_BASE, 1)]),
    ('movements/scripts/others/shrinesportal.lua', [(GET_BASE, STOCK_BASE, 1), (PORTAL_TEXT_OLD, PORTAL_TEXT_NEW, 1)]),
    ('movements/scripts/others/daramsecret.lua', [(GET_BASE, STOCK_BASE, 1), (PORTAL_TEXT_OLD, PORTAL_TEXT_NEW, 1)]),
    ('movements/scripts/new/soil.lua', [(GET_BASE, STOCK_BASE, 1)]),
    ('scripts/spells/monsters/astro_wave.lua', [(GET_ID, STOCK_ID, 1)]),
    ('npc/scripts/runes.lua', [(GET_ID, STOCK_ID, 1), (WAND_TEXT_OLD, WAND_TEXT_NEW, None)]),
] + [('npc/scripts/%s.lua' % n, [(GET_BASE, STOCK_BASE, 1), (WAND_TEXT_OLD, WAND_TEXT_NEW, None)])
     for n in ('Magido', 'Asima', 'Rachel', 'Topsy', 'Alexander', 'Xodet', 'Fenech')] + [
    ('npc/scripts/%s.lua' % n, [(ORACLE_WORDS_OLD, ORACLE_WORDS_NEW, None),
                                (ORACLE_ANCHOR, ORACLE_BLOCK + ORACLE_ANCHOR, 1)])
    for n in ('The Oracle', 'The Oracle3', 'Captain Dreadnought')]

def apply_edits(text, edits):
    """returns (new text, status, number of edits applied); status: patched / already / unexpected: ..."""
    crlf = text.count('\r\n') * 2 > text.count('\n')
    work = text.replace('\r\n', '\n') if crlf else text
    applied, missing = 0, []
    for old, new, count in edits:
        if old in new:
            if new in work:
                continue
        elif old not in work and new in work:
            continue
        n = work.count(old)
        if n == 0:
            missing.append(old.strip().split('\n')[0][:70])
            continue
        if count is not None and n != count:
            missing.append('%s (found %d times, expected %d)' % (old.strip().split('\n')[0][:60], n, count))
            continue
        work = work.replace(old, new)
        applied += 1
    if missing:
        return text, 'unexpected: not found: ' + '; '.join(missing), 0
    if not applied:
        return text, 'already', 0
    return (work.replace('\n', '\r\n') if crlf else work), 'patched', applied


def patch_file(rel, text):
    """the edits of one file (path below data, '/' separators); returns (new text, status)"""
    if rel == 'lib/core/player.lua':
        return patch_player(text)
    for path, edits in EDITS:
        if path == rel:
            new, status, _ = apply_edits(text, edits)
            return new, status
    return text, 'no edits for ' + rel


# ---------------------------------------------------------------------------------------------- the review scan
CHECK_RE = re.compile(r'isDruid|isSorcerer|isKnight|isPaladin|isMage|isIllusionist|getVocation\(\)\s*:\s*getId|'
                      r'getVocation\(\)\s*:\s*getBase|getPlayerVocation|VOCATION\.ID\.')
SCAN_SKIP = ('scripts/chaos/', 'spells/chaos/', 'spells/scripts/chaos/', 'lib/chaos_', 'lib/core/player.lua',
             'lib/compat/compat.lua')
# reviewed, no change needed (docs/CLASSES.md "Base scripts")
REVIEWED = ('creaturescripts/scripts/firstitems.lua', 'scripts/customs/actions/first_chest.lua',
            'creaturescripts/scripts/rookgaard/advance.lua', 'creaturescripts/scripts/droploot.lua',
            'chatchannels/scripts/', 'creaturescripts/scripts/login.lua', 'creaturescripts/scripts/offlinetraining.lua',
            'npc/lib/npcsystem/modules.lua', 'npc/scripts/promo bug.lua',
            'npc/scripts/Bozo.lua', 'npc/scripts/A Dead Bureaucrat3.lua', 'npc/scripts/Muzir.lua', 'npc/scripts/Naji.lua',
            'scripts/customs/bosses_others/mirror_image_transform.lua', 'scripts/customs/stats_inspect/inspect.lua',
            'scripts/customs/party/partyIcons.lua', 'actions/scripts/other/potions.lua',
            'actions/scripts/other/strengthening_potions.lua', 'events/scripts/player.lua')


REPO_DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')


def scan(data):
    """lines that test a vocation in files neither patched nor reviewed here (files of this repo are ours: skipped)"""
    known = set(p for p, _ in EDITS) | {'lib/core/player.lua'}
    out = []
    for root, dirs, files in os.walk(data):
        dirs.sort()
        for name in sorted(files):
            if not name.endswith('.lua'):
                continue
            rel = os.path.relpath(os.path.join(root, name), data).replace(os.sep, '/')
            if rel in known or rel.startswith(SCAN_SKIP) or rel.startswith(REVIEWED) or rel.startswith('monster/'):
                continue
            if os.path.isfile(os.path.join(REPO_DATA, *rel.split('/'))):
                continue
            try:
                lines = open(os.path.join(root, name), encoding='utf-8', errors='replace').read().split('\n')
            except OSError:
                continue
            for i, line in enumerate(lines, 1):
                if CHECK_RE.search(line):
                    out.append('%s:%d: %s' % (rel, i, line.strip()[:100]))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    dry = '--dry-run' in sys.argv
    data = args[0]
    if not os.path.isdir(data):
        print('missing', data)
        return 1
    ok = True
    counts = {}
    for rel in ['lib/core/player.lua'] + [p for p, _ in EDITS]:
        path = os.path.join(data, *rel.split('/'))
        if not os.path.isfile(path):
            print('%s: not found, skipped' % rel)
            counts['skipped'] = counts.get('skipped', 0) + 1
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, status = patch_file(rel, text)
        key = status.split(':')[0].split(' ')[0]
        counts[key] = counts.get(key, 0) + 1
        if status == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        if status != 'already':
            print('%s: %s' % (rel, status))
        if status not in ('patched', 'already'):
            ok = False
    print('base scripts: %s' % ', '.join('%d %s' % (n, k) for k, n in sorted(counts.items())))
    rest = scan(data)
    if rest:
        print('vocation checks not covered (review them by hand, docs/CLASSES.md "Base scripts"):')
        for line in rest:
            print('  ' + line)
    if dry:
        print('dry run: nothing written')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
