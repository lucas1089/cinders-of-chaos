#!/usr/bin/env python3
"""Test of patch_badges.py (run: python3 -I server/tools/patch_badges_test.py) on a small data folder: the badges'
slot type, the retired items' descriptions (replaced or added; badges and other items untouched), the cards' hint
(appended once; not on an upgrade-only legendary), the Fury catalyst
typo of the boss loot (only the line after "fury amplifier catalyst [2]"; nothing else of the loot changes), the
Player:onMoveItem, deck system and sea tile hooks (CRLF kept), the first ship NPC's texts, the death loss over the badge
slot, the belt and gloves recipes out of the armorsmith (the list still loads), a second run that changes nothing,
--check, and the ids against data/scripts/chaos/badges_core.lua."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_badges as P  # noqa: E402

ITEMS = '''<items>
	<item id="27632" article="a" name="Bronze Deck">
		<attribute key="description" value="Intial Deck for adventurers." />
		<attribute key="containerSize" value="5" />
		<attribute key="slotType" value="deckbadge" />
	</item>
	<item id="27799" article="a" name="The Explorer">
		<attribute key="slotType" value="ship" />
	</item>
	<item id="29577" name="Shadowwoven Gloves">
		<attribute key="slotType" value="beltgloves" />
		<attribute key="description" value="Old text." />
	</item>
	<item id="27811" article="a" name="Raging Moon Badge">
		<attribute key="weight" value="350" />
		<attribute key="slotType" value="deckbadge" />
	</item>
	<item id="27849" article="a" name="Moon Amplifier Catalyst [1]">
		<attribute key="description" value="Use this Amplifier on Moon Badge to upgrade it to the next tier."/>
	</item>
	<item id="27482" name="Common Ember Card">
	<attribute key="description" value="Enabling this card on your Deck give the possibility to turn a strike to Earth damage." />
	<attribute key="weight" value="10" />
	</item>
	<item id="27640" name="Legendary Ancestral Card Lv6">
	<attribute key="weight" value="10" />
	</item>
	<item id="27639" name="Legendary Ancestral Card Lv5">
	<attribute key="description" value="Upgrade this card to the level 6.&#10;Second line." />
	</item>
	<item id="2160" article="a" name="crystal coin">
		<attribute key="description" value="Keep me." />
	</item>
</items>
'''
BOSS = '''local monster = {}
monster.loot = {
	{id = "rare essence", chance = 50000, maxCount = 5},
	{id = "exiled amplifier catalyst [3]", chance = 2000},
	{id = "fury amplifier catalyst [1]", chance = 5000, maxCount = 2},
	{id = "fury amplifier catalyst [2]", chance = 4200, maxCount = 2},
	{id = "exiled amplifier catalyst [3]", chance = 2000},
	{id = "moon amplifier catalyst [1]", chance = 5000, maxCount = 2},
	{id = "golden deck", chance = 10000},
	{id = "raging moon badge", chance = 3500},
}
'''
BOSS_OUT = BOSS.replace('''maxCount = 2},
	{id = "exiled amplifier catalyst [3]", chance = 2000},
	{id = "moon''', '''maxCount = 2},
	{id = "fury amplifier catalyst [3]", chance = 2000},
	{id = "moon''')
PLAYER = ('function Player:onMoveItem(item, count, fromPosition, toPosition, fromCylinder, toCylinder)\r\n'
          '\tlocal x = 1\r\n'
          '\treturn true\r\n'
          'end\r\n')
DECK = '''function deckSystem.onUse(player, item, fromPosition, target, toPosition, isHotkey)
    local deckSystemCard = player:getSlotItem(CONST_SLOT_DECK)
    return true
end
'''
SEA = '''local boatSystem = MoveEvent()
function boatSystem.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	return true
end
'''
NPC = '''	if x then
		npcHandler:say("Fantastic! To start navigating, place the explorer to the boat slot on your inventory and walk through the deck.", cid)
		player:say("Equip the explorer on the Boat Slot of your inventory, and walk to the ocean.", TALKTYPE_MONSTER_SAY)
		player:addItem(27799, 1)
	end
'''
DROP = '''	else
		for i = CONST_SLOT_HEAD, CONST_SLOT_AMMO do
			local item = player:getSlotItem(i)
		end
	end
'''

RECIPES = ('Crafting.armorsmith = {\r\n'
           '    {\r\n        id = 2457,\r\n        name = "Steel Helmet",\r\n        materials = {\r\n'
           '            {id = 12435, count = 5},\r\n        }\r\n    },\r\n'
           '    {\r\n        id = 29577,\r\n        name = "Shadowwoven Gloves",\r\n        materials = {\r\n'
           '            {id = 29541, count = 125},\r\n        }\r\n    },\r\n'
           '    {\r\n        id = 29576,\r\n        name = "Soulbinder Sandals",\r\n        materials = {\r\n'
           '            {id = 29541, count = 50},\r\n        }\r\n    },\r\n'
           '    {\r\n        id = 29919,\r\n        name = "Dawnforged Gloves",\r\n        materials = {\r\n'
           '            {id = 29902, count = 20},\r\n        }\r\n    },\r\n'
           '}\r\n')
RECIPE_RUN = """
local n, names = 0, {}
for _, r in ipairs(Crafting.armorsmith) do n = n + 1 names[#names + 1] = r.name end
print(n .. ":" .. table.concat(names, ","))
"""

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


def item_block(xml, iid):
    return re.search(r'<item id="%d"[^>]*>(.*?)</item>' % iid, xml, re.S).group(1)


def main():
    tmp = tempfile.mkdtemp(prefix='badges_test_')
    try:
        data = os.path.join(tmp, 'data')
        put(data, 'items/items.xml', ITEMS)
        put(data, 'monster/lua/bosses/boss.lua', BOSS)
        put(data, 'monster/lua/other.lua', 'monster.loot = {\n\t{id = "exiled amplifier catalyst [3]", chance = 1},\n}\n')
        put(data, 'events/scripts/player.lua', PLAYER)
        put(data, 'scripts/customs/deck_system/deck_system.lua', DECK)
        put(data, 'scripts/customs/boat/boat_navigation.lua', SEA)
        put(data, 'scripts/chaos/mine.lua', DECK)  # our own scripts are never touched
        put(data, 'npc/scripts/builder.lua', NPC)
        put(data, 'creaturescripts/scripts/droploot.lua', DROP)
        put(data, 'scripts/customs/crafting/armorsmith.lua', RECIPES)

        ok(P.main([data, '--check']) == 1, '--check before: work to do')
        ok(get(data, 'items/items.xml') == ITEMS, '--check changes nothing')
        report, changed = P.run(data)
        ok(changed == 8, 'eight files change (%d): %s' % (changed, report))

        xml = get(data, 'items/items.xml')
        ok('value="badge"' in item_block(xml, 27811), 'a badge gets slot type "badge"')
        ok('value="deckbadge"' in item_block(xml, 27632), 'a deck keeps "deckbadge"')
        ok(P.DECK_DESC in item_block(xml, 27632) and 'Intial' not in xml, 'the deck description is replaced')
        ok(P.SHIP_DESC in item_block(xml, 27799), 'the ship description is added')
        ok(P.BELTGLOVES_DESC in item_block(xml, 29577) and 'Old text' not in xml, 'the gloves description is replaced')
        ok('Use this Amplifier on Moon Badge' in item_block(xml, 27849), 'a catalyst keeps its base description')
        ok('Keep me.' in item_block(xml, 2160), 'another item is untouched')
        ok('description' not in item_block(xml, 27811), 'a badge gets no description')
        ok('value="%s"' % P.CARD_TEXTS[27482] in item_block(xml, 27482) and 'Enabling this card' not in xml,
           'a card gets the description of card_descriptions.csv (the base text named the stock spell)')
        ok('Reaping Gyre deals Earth damage instead' in item_block(xml, 27482), 'and it names the current spell')
        ok('value="%s"' % P.CARD_TEXTS[27640] in item_block(xml, 27640), 'a card without a description gets one')
        ok(P.CARD_HINT not in item_block(xml, 27639), 'an upgrade-only legendary (level 5) gets no hint')
        ok(xml.count(P.CARD_HINT) == 2, 'the hint once per card')

        # a card patched by the earlier hint gets the new one, never both
        # (a card the descriptions file lacks keeps its text with the hint appended)
        old = P.OLD_CARD_HINTS[0]
        saved, P.CARD_TEXTS = P.CARD_TEXTS, {}
        migrated, count = P.items_xml('<item id="27482" name="x"><attribute key="description" value="Base text. %s" /></item>' % old)
        ok(count == 1 and P.CARD_HINT in migrated and old not in migrated and migrated.count('Base text.') == 1,
           'the earlier card hint is replaced')
        ok(P.items_xml(migrated)[1] == 0, 'and the new one is stable')
        P.CARD_TEXTS = saved
        again = P.items_xml(P.items_xml(ITEMS)[0])
        ok(again[1] == 0, 'the card descriptions are stable on a second run')

        # card_descriptions.csv: one per card, ends with the hint, no stock spell word
        ok(set(P.CARD_TEXTS) == set(P.CARDS), 'a description for each of the 76 cards')
        ok(all(t.endswith(P.CARD_HINT) for t in P.CARD_TEXTS.values()), 'each ends with the hint')
        ok(not any(w in t.lower() for t in P.CARD_TEXTS.values() for w in ('exori', 'exevo', 'exura', 'utito', 'exeta')),
           'none has a stock spell word')
        ok(not any(' give ' in t for t in P.CARD_TEXTS.values()), 'the grammar of the base text ("give") is gone')

        ok(get(data, 'monster/lua/bosses/boss.lua') == BOSS_OUT, 'only the line after Fury [2] becomes Fury [3]')
        ok('exiled amplifier catalyst [3]' in get(data, 'monster/lua/other.lua'), 'a lone Exiled [3] stays')

        player = get(data, 'events/scripts/player.lua')
        ok(P.MARK in player and 'ChaosBadges.onMoveItem(self, item, toPosition)' in player, 'the move hook is in')
        ok('\n' not in player.replace('\r\n', ''), 'player.lua keeps CRLF')
        ok(player.index('ChaosBadges') < player.index('local x = 1'), 'the move hook runs first')

        deck = get(data, 'scripts/customs/deck_system/deck_system.lua')
        ok('ChaosBadges.deckOf(player) or player:getSlotItem(CONST_SLOT_DECK)' in deck, 'the deck system asks deckOf')
        ok('ChaosCards.use(player, item)' in deck and deck.index('ChaosCards.use') < deck.index('deckSystemCard'),
           'the card action asks cards.lua first')
        ok(deck.count('ChaosCards.use(player, item)') == 1, 'the cards hook once')
        ok(get(data, 'scripts/chaos/mine.lua') == DECK, 'scripts/chaos is not touched')
        sea = get(data, 'scripts/customs/boat/boat_navigation.lua')
        ok('ChaosBadges.boardShip(chaosSailor)' in sea and sea.index('boardShip') < sea.index('local player ='),
           'the sea tiles board a carried ship first')
        npc = get(data, 'npc/scripts/builder.lua')
        ok('carry the explorer with you and walk' in npc and 'Carry the explorer with you and walk' in npc
           and 'Boat Slot' not in npc and 'boat slot' not in npc, 'the ship NPC says to carry the ship')

        drop = get(data, 'creaturescripts/scripts/droploot.lua')
        loop = re.search(r'for _, i in ipairs\(\{([^}]*)\}\) do', drop)
        ok(loop is not None and 'CONST_SLOT_AMMO do' not in drop, 'the death loss loop is replaced')
        names = [s.strip() for s in loop.group(1).split(',')] if loop else []
        ok('CONST_SLOT_BADGE' in names and len(names) == 11, 'it runs over slots 1-10 and the badge slot')
        ok(not any(n in names for n in ('CONST_SLOT_STORE_INBOX', 'CONST_SLOT_DECK')), 'never the inbox or a retired slot')
        ok(drop.startswith('\telse\n\t\tfor _, i in ipairs(') and '\t\t\tlocal item = player:getSlotItem(i)' in drop,
           'indent and body kept')
        smith = get(data, 'scripts/customs/crafting/armorsmith.lua')
        ok('\n' not in smith.replace('\r\n', ''), 'armorsmith.lua keeps CRLF')
        ok(smith.count('--[==[ ' + P.MARK) == 2 and smith.count(']==]') == 2, 'two recipes in block comments')
        live = re.sub(r'--\[==\[.*?\]==\]', '', smith, flags=re.S)
        ok('Shadowwoven Gloves' not in live and 'Dawnforged Gloves' not in live, 'no gloves recipe is live')
        ok('Steel Helmet' in live and 'Soulbinder Sandals' in live, 'the other recipes stay, in order')
        lua = shutil.which('luajit') or shutil.which('lua5.3')
        if lua:
            script = os.path.join(tmp, 'run.lua')
            with open(script, 'w') as f:
                f.write('Crafting = {}\n' + smith.replace('\r\n', '\n') + RECIPE_RUN)
            res = subprocess.run([lua, script], capture_output=True, text=True)
            ok(res.stdout.strip() == '2:Steel Helmet,Soulbinder Sandals', 'the patched list loads: %r %r'
               % (res.stdout, res.stderr))
        before = {rel: get(data, rel) for rel in ('items/items.xml', 'monster/lua/bosses/boss.lua',
                                                    'scripts/customs/crafting/armorsmith.lua',
                                                    'creaturescripts/scripts/droploot.lua',
                                                    'events/scripts/player.lua', 'npc/scripts/builder.lua',
                                                    'scripts/customs/deck_system/deck_system.lua',
                                                    'scripts/customs/boat/boat_navigation.lua')}
        report, changed = P.run(data)
        ok(changed == 0, 'a second run changes nothing (%s)' % report)
        ok(all(get(data, rel) == text for rel, text in before.items()), 'the files are the same after it')
        ok(P.main([data, '--check']) == 0, '--check after: nothing to do')

        # the ids against the Lua rules
        core = open(os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'badges_core.lua'), encoding='utf-8').read()
        ok('K.FIRST_BADGE, K.LAST_BADGE = 27803, 27842' in core, 'badge range matches badges_core.lua')
        ok(list(P.BADGES) == list(range(27803, 27843)), 'forty badges')
        decks = re.search(r'K\.DECKS = \{([^}]*)\}', core).group(1)
        ok(sorted(int(x) for x in decks.split(',')) == list(P.DECKS), 'decks match badges_core.lua')
        ships = sorted(int(x) for x in re.findall(r'\[(\d+)\] = \{storage', core))
        ok(ships == list(P.SHIPS), 'ships match badges_core.lua')
        ok(len(P.CARDS) == len(set(P.CARDS)) == 76 and P.CARDS[60:62] == (27547, 27553) and P.CARDS[-2:] == (27631, 27640)
           and not set(P.CARDS) & set(P.DECKS + P.SHIPS + P.BELTGLOVES), 'the 76 cards of the base deck system')
        bg = re.search(r'K\.BELTGLOVES = \{([^}]*)\}', core).group(1)
        ok([int(x) for x in re.findall(r'\d+', bg)] == list(P.BELTGLOVES), 'belts and gloves match badges_core.lua')
    finally:
        shutil.rmtree(tmp)
    print('patch_badges_test: %d checks, %d failures' % (checks, failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
