#!/usr/bin/env python3
"""Tests of tools/ci/check_topbar_tree.py: the parsers on small texts, one case per failure kind, and the real repository."""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('check_topbar_tree', os.path.join(HERE, 'check_topbar_tree.py'))
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)

TREE = """T.HUBS = {
  { id = 'a', name = 'Alpha', glyph = 'gx', tabs = {
    { id = 'one', name = 'One', cards = { 'Card 1', 'Card 2' } },
    { id = 'two', name = 'Two', cards = { 'Card 3' } },
  } },
}
T.CATEGORY_HUB = { hunt = 'a', admin = 'a' }
T.DROPPED = { ['Old'] = true }
T.SHARED = { ['Alt Card'] = 'Card 1' }
T.TEXT_ONLY = { ['Menu Style'] = true }
"""
CARDS = """C.CARDS = {
  ['Card 1'] = { 'gx', 'Line one' },
  ['Card 2'] = { 'gy', 'Line two' },
  ['Card 3'] = { 'gx', 'Line three' },
}
C.ICON_GLYPH = {
  skills = 'gx', help = 'gy',
}
C.FALLBACK_GLYPH = 'gx'
"""
PT = {'hub.a': 'Alfa', 'tab.a.one': 'Um', 'tab.a.two': 'Dois', 'Line one': 'Linha um', 'Line two': 'Linha dois', 'Line three': 'Linha tres'}
REG = {'Card 1': {'key': 'Alt+1'}, 'Card 2': {'key': ''}, 'Card 3': {'key': ''}, 'Old': {'key': ''}, 'Alt Card': {'key': ''}}


def run(tree=TREE, cards=CARDS, names=('gx', 'gy'), reg=REG, npc=(), pt=PT):
    return C.problems(C.parse_tree(tree), C.parse_cards(cards), set(names), dict(reg), set(npc), dict(pt))


def has(found, word):
    return any(word in p for p in found)


n = 0


def check(cond, msg):
    global n
    n += 1
    if not cond:
        print('FAIL: ' + msg)
        sys.exit(1)


# parsers
t = C.parse_tree(TREE)
check(len(t['hubs']) == 1 and len(t['hubs'][0]['tabs']) == 2, 'tree parsed')
check(t['hubs'][0]['tabs'][0]['cards'] == ['Card 1', 'Card 2'], 'cards parsed')
check(t['category_hub'] == {'hunt': 'a', 'admin': 'a'}, 'category table')
check(t['dropped'] == {'Old'} and t['text_only'] == {'Menu Style'} and t['shared'] == {'Alt Card': 'Card 1'}, 'the three tables')
c = C.parse_cards(CARDS)
check(c['cards']['Card 2'] == ('gy', 'Line two') and c['fallback'] == 'gx' and c['icon_glyph']['help'] == 'gy', 'cards parsed')
check(C.parse_glyph_names("NAMES = (\n  'a', 'b',\n  'c',\n)\n") == {'a', 'b', 'c'}, 'glyph names')
check(C.parse_npc_only("T.NPC_ONLY = { ['The Gambler'] = true, ['Factions'] = true }") == {'The Gambler', 'Factions'}, 'npc only')
check(C.parse_pt_br('  ["a \\"b\\""] = "c",\n  ["d"] = "e",\n') == {'a "b"': 'c', 'd': 'e'}, 'pt-BR reader')
reg, bad = C.registered_from_modules({'m.lua': "pcall(api.addEntry, 'hunt', { text = 'X', icon = 'a', key = 'Alt+X' })\n"
                                                "pcall(api.addEntry, 'hunt', { text = 'Y', icon = 'a' }, 'More')\n"})
check(set(reg) == {'X', 'Y'} and reg['X']['key'] == 'Alt+X' and not bad, 'module entries')
reg, bad = C.registered_from_modules({'m.lua': "pcall(api.addEntry, 'hunt', makeEntry())\n"})
check(bad and 'm.lua' in bad[0], 'an addEntry call the checker cannot read fails')

# the good case
check(run() == [], 'the synthetic tree is clean: %s' % run())

# one case per failure
check(has(run(reg=dict(REG, **{'New Window': {'key': ''}})), "'New Window'"), 'an entry with no card fails')
check(has(run(reg={k: v for k, v in REG.items() if k != 'Card 3'}), "card 'Card 3': no module"), 'a card nobody registers fails')
check(has(run(tree=TREE.replace("'Card 2' }", "'Card 2', 'Card 1' }")), 'card twice'), 'a card twice fails')
check(has(run(tree=TREE.replace("'Card 2' }", "'Card 2', 'C4', 'C5', 'C6', 'C7', 'C8' }")), 'cards (1 to 6)'), 'a tab over 6 cards fails')
check(has(run(cards=CARDS.replace("  ['Card 3'] = { 'gx', 'Line three' },\n", "")), 'no glyph and line'), 'a card with no glyph fails')
check(has(run(cards=CARDS.replace("'gy', 'Line two'", "'gy', 'Line two that is far longer than a card can take'")), 'characters'), 'a long line fails')
check(has(run(cards=CARDS.replace("'gy', 'Line two'", "'gq', 'Line two'")), "glyph 'gq'"), 'an undrawn glyph fails')
check(has(run(cards=CARDS.replace("'gy', 'Line two'", "'gx', 'Line two'")), 'used twice'), 'a glyph twice on a tab fails')
check(has(run(pt={k: v for k, v in PT.items() if k != 'hub.a'}), 'pt-BR name'), 'a hub with no pt-BR fails')
check(has(run(pt={k: v for k, v in PT.items() if k != 'tab.a.two'}), 'pt-BR name'), 'a tab with no pt-BR fails')
check(has(run(pt={k: v for k, v in PT.items() if k != 'Line one'}), 'pt-BR text'), 'a line with no pt-BR fails')
check(has(run(reg=dict(REG, **{'Card 3': {'key': 'Alt+3'}})), 'first tab'), 'a hotkey on a later tab fails')
check(has(run(npc=['Card 2']), 'NPC'), 'an NPC window on a card fails')
check(has(run(tree=TREE.replace("hunt = 'a'", "hunt = 'zz'")), 'no such hub'), 'a category to a missing hub fails')
check(has(run(tree=TREE.replace("'Card 1' }", "'Nope' }", 1).replace("['Alt Card'] = 'Card 1'", "['Alt Card'] = 'Nope2'")), 'SHARED'), 'a shared slot that is no card fails')
many = TREE.replace("T.CATEGORY_HUB", "".join("  { id = 'h%d', name = 'H', glyph = 'gx', tabs = {\n  } },\n" % i for i in range(7)) + "T.CATEGORY_HUB")
check(has(run(tree=many), 'hubs'), 'more than six hubs fails')

# the real repository
check(C.main() == 0, 'the real tree passes')
print('check_topbar_tree_test: %d checks ok' % n)
