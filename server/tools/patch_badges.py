#!/usr/bin/env python3
"""The base server's extra inventory slots: the badge slot in use, the others retired (idempotent). install_all.py
step `badges`.

usage: python3 -I patch_badges.py DATA_DIR [--dry-run] [--check]

server/README.md "Badge slot". The base engine has five extra slots: deck (12), badge (13), ship (14), belt (15),
gloves (16). Engine patch 0058 and client base patch 0113 put the badge slot where the second ring slot was; the other
four take nothing. The rules are data/scripts/chaos/badges_core.lua; this tool changes the base data:

1. data/items/items.xml: the 40 badges (27803-27842) get slot type "badge" (0058: the badge bit only; "deckbadge" also
   has the deck bit, and the badge slot refuses an item with it). The decks, ships, belts and gloves get a description
   that says they can't be worn and what they still do; the Loot Buyer buys them (data/items/item_price_rules.csv).
   The 76 cards a deck turns on (CARDS) get the description of data/items/card_descriptions.csv (written by
   tools/gen_card_descriptions.lua from cards_config.lua): what the card gives, with the Chaos name of the spell it acts
   on (the base text named the stock spell), then CARD_HINT: where a card goes. A card the file lacks keeps its
   description with CARD_HINT appended.
2. data/monster/**: the base boss loot lists "exiled amplifier catalyst [3]" twice and the Fury catalyst [3] (27848)
   never: the second one, right after "fury amplifier catalyst [2]", becomes "fury amplifier catalyst [3]".
3. data/events/scripts/player.lua: Player:onMoveItem asks ChaosBadges.onMoveItem first (a move into a retired slot is
   refused with a message; the engine refuses it too).
4. the base deck system (the script with `getSlotItem(CONST_SLOT_DECK)`): its card action asks ChaosCards.use first
   (cards.lua: a card carried anywhere goes into a deck and turns on or off, with a clear message; "Cards and decks"),
   and the cards are looked for in the deck the player carries (ChaosBadges.deckOf), not in slot 12.
5. the base sea tiles (the script with `function boatSystem.onStepIn`): ChaosBadges.boardShip sets the ship storages
   from the ships the player carries first, so a carried ship sails.
6. the NPC that builds the first ship (the script that gives 27799 and names the "Boat Slot"): it says to carry the
   ship, not to wear it.
7. data/creaturescripts/scripts/droploot.lua: the death loss runs over slots 1-10 only, so a badge (and the Eternal
   Moon Badge, a container of 10, with everything in it) would never drop. The loop takes the badge slot too (never
   11, the store inbox, nor the retired slots).
8. the base crafting recipe lists (`Crafting.<table> = {` in data/scripts; the armorsmith): the belt and gloves recipes
   are wrapped in a block comment, so nobody crafts an item no slot takes. The Loot Buyer still buys the copies players
   hold. The other recipes keep their order.

9. the base legendary cards (the script with `config.itemidKnights`, legendary_cards_system.lua): a hit fires a card only
   when the item in the left hand is in one of four lists of stock item ids (itemidKnights, itemidDruid, itemidSorcerer,
   itemidPaladin). They miss most stock weapons and every Chaos weapon, fist weapon and bare fist, so "my card does not
   work" (beta 2026-10-23). The 16 checks `leftHand and table.find(config.<list>, leftHand.itemid)` become
   chaosHolds(player, "<class>", leftHand, config.<list>), a local function put before whenPlayerAttack that asks
   ChaosCards.holds (cards.lua: the weapon type decides, the stock ids still count) and falls back to the base check
   while cards.lua is not loaded. cards.lua also frees the base's "one summon at a time" lock when the summon died.

Nothing is taken out of a drop: the decks and ships keep their uses (the monster loot, the task reward and the first
ship stay); the belts and gloves drop nowhere and step 8 takes them out of the armorsmith. A second run changes nothing. --check changes nothing and exits 1 when something is still to
do.
"""
import csv
import os
import re
import sys

sys.dont_write_bytecode = True

BADGES = range(27803, 27843)
DECKS = (27632, 27633, 27634)
SHIPS = tuple(range(27796, 27803))
BELTGLOVES = (29577, 29578, 29582, 29583, 29584, 29586, 29587, 29588, 29589, 29590, 29591, 29592, 29593, 29594, 29595,
              29596, 29597, 29598, 29914, 29915, 29916, 29917, 29918, 29919)
DECK_DESC = ("A deck for cards. It can't be worn: carry it, then use a card you carry to put it in the deck and turn it "
             "on. Veyra the Apothecary sells decks. The Loot Buyer buys it.")
SHIP_DESC = "A ship. It can't be worn: carry it and walk from a dock onto the sea to sail. The Loot Buyer buys it."
BELTGLOVES_DESC = "It can't be worn. The Loot Buyer buys it."
# the cards the base deck system turns on (its cardsAllowed): the 60 common to mythic cards and the level 6 legendaries;
# the legendary levels 1-5 only upgrade and keep their text. Players did not find where a card goes (beta,
# 2026-10-22: "como eu acesso o deck?"), so their description ends with where to put it.
CARDS = tuple(range(27482, 27542)) + tuple(range(27547, 27632, 6)) + (27640,)
CARD_HINT = ("Use it to put it in a deck you carry and turn it on, use it again to turn it off. "
             "Veyra the Apothecary sells decks.")
# earlier texts of the hint: replaced, so a second install never appends two
CARD_DESCRIPTIONS_CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'items',
                                     'card_descriptions.csv')


def card_texts(path=None):
    """{card id: description} from card_descriptions.csv (gen_card_descriptions.lua); {} when the file is not there"""
    try:
        with open(path or CARD_DESCRIPTIONS_CSV, encoding='utf-8', newline='') as f:
            return {int(r['id']): r['description'] for r in csv.DictReader(f)}
    except OSError:
        return {}


CARD_TEXTS = card_texts()
OLD_CARD_HINTS = ("Put it in a Bronze, Silver or Golden Deck you carry and use it there to turn it on or off.",)
DESCRIPTIONS = {}
DESCRIPTIONS.update({i: DECK_DESC for i in DECKS})
DESCRIPTIONS.update({i: SHIP_DESC for i in SHIPS})
DESCRIPTIONS.update({i: BELTGLOVES_DESC for i in BELTGLOVES})

MARK = 'Chaos: the badge slot and the retired slots (patch_badges.py)'
MOVE_HOOK = ('\t-- {mark}: nothing goes into a retired slot\n'
             '\tif ChaosBadges and ChaosBadges.onMoveItem then\n'
             '\t\tlocal chaosBadgeRet = ChaosBadges.onMoveItem(self, item, toPosition)\n'
             '\t\tif chaosBadgeRet then\n'
             '\t\t\treturn chaosBadgeRet\n'
             '\t\tend\n'
             '\tend\n').format(mark=MARK)
MOVE_LINE = re.compile(r'^function Player:onMoveItem\(item, count, fromPosition, toPosition, fromCylinder, toCylinder\)'
                       r'[ \t]*\n', re.M)
SEA_HOOK = ('\t-- {mark}: a ship carried is a ship aboard\n'
            '\tlocal chaosSailor = creature and creature:getPlayer()\n'
            '\tif chaosSailor and ChaosBadges and ChaosBadges.boardShip then\n'
            '\t\tChaosBadges.boardShip(chaosSailor)\n'
            '\tend\n').format(mark=MARK)
SEA_LINE = re.compile(r'^function boatSystem\.onStepIn\(creature, item, position, fromPosition\)[ \t]*\n', re.M)
DECK_CALL = 'player:getSlotItem(CONST_SLOT_DECK)'
DECK_NEW = ('(ChaosBadges and ChaosBadges.deckOf and ChaosBadges.deckOf(player) or player:getSlotItem(CONST_SLOT_DECK))'
            ' -- ' + MARK)
USE_LINE = re.compile(r'^function deckSystem\.onUse\(player, item, fromPosition, target, toPosition, isHotkey\)[ \t]*\n', re.M)
USE_HOOK_TEST = 'ChaosCards.use(player, item)'
USE_HOOK = ('    -- {mark}: cards.lua puts a card carried anywhere into a deck and turns it on or off\n'
            '    if ChaosCards and ChaosCards.use then\n'
            '        local chaosCardRet = ChaosCards.use(player, item)\n'
            '        if chaosCardRet ~= nil then\n'
            '            return chaosCardRet\n'
            '        end\n'
            '    end\n').format(mark=MARK)
NPC_TEXTS = (
    (re.compile(r'place the explorer to the boat slot on your inventory and walk'), 'carry the explorer with you and walk'),
    (re.compile(r'Equip the explorer on the Boat Slot of your inventory, and walk'), 'Carry the explorer with you and walk'),
)
DROP_LINE = re.compile(r'^([ \t]*)for i = CONST_SLOT_HEAD, CONST_SLOT_AMMO do[ \t]*$', re.M)
DROP_NEW = r'\1for _, i in ipairs({CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR, ' \
    r'CONST_SLOT_RIGHT, CONST_SLOT_LEFT, CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO, ' \
    r'CONST_SLOT_BADGE}) do -- ' + MARK.replace('\\', '\\\\')
RECIPE_TABLE = re.compile(r'^Crafting\.\w+[ \t]*=[ \t]*\{', re.M)
RECIPE_HEAD = re.compile(r'^([ \t]*)\{[ \t]*\n[ \t]*id[ \t]*=[ \t]*(\d+)[ \t]*,', re.M)
RECIPE_OPEN = '--[==[ ' + MARK + ': belts and gloves can\'t be worn, so they are not crafted'
FURY = re.compile(r'(\{[ \t]*(?:id|name)[ \t]*=[ \t]*"fury amplifier catalyst \[2\]"[^\n]*\n[ \t]*\{[ \t]*(?:id|name)'
                  r'[ \t]*=[ \t]*")exiled( amplifier catalyst \[3\]")', re.I)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def fury(text):
    new, n = FURY.subn(lambda m: m.group(1) + ('Fury' if m.group(0)[len(m.group(1))] == 'E' else 'fury') + m.group(2),
                       text)
    return new, n


def hook(text, line_re, code):
    if MARK in text:
        return text, 0
    m = line_re.search(text)
    if not m:
        return text, 0
    return text[:m.end()] + code + text[m.end():], 1


def deck_system(text):
    """the carried deck instead of slot 12, and cards.lua first: a card used anywhere in the bags goes into a deck"""
    n = 0
    if MARK not in text and DECK_CALL in text:
        text, n = text.replace(DECK_CALL, DECK_NEW, 1), 1
    m = USE_LINE.search(text)
    if m and USE_HOOK_TEST not in text:
        text, n = text[:m.end()] + USE_HOOK + text[m.end():], n + 1
    return text, n


LEGENDARY_CHECK = re.compile(r'leftHand and table\.find\(config\.(itemid(Knights|Druid|Sorcerer|Paladin)), leftHand\.itemid\)')
LEGENDARY_CLASS = {'Knights': 'Knight', 'Druid': 'Druid', 'Sorcerer': 'Sorcerer', 'Paladin': 'Paladin'}
LEGENDARY_FUNC = re.compile(r'^local function whenPlayerAttack\(player, damage\)[ \t]*\n', re.M)
LEGENDARY_HELPER = ('-- {mark}: the weapon decides, not a list of stock item ids (cards.lua ChaosCards.holds)\n'
                    'local function chaosHolds(player, class, leftHand, stockIds)\n'
                    '    if ChaosCards and ChaosCards.holds then\n'
                    '        return ChaosCards.holds(player, class, leftHand, stockIds)\n'
                    '    end\n'
                    '    return leftHand and table.find(stockIds, leftHand.itemid)\n'
                    'end\n\n').format(mark=MARK)


def legendary(text):
    """the 16 left-hand item id checks of the legendary cards ask chaosHolds (ChaosCards.holds) instead"""
    if 'chaosHolds(' in text:
        return text, 0
    m = LEGENDARY_FUNC.search(text)
    if not m or not LEGENDARY_CHECK.search(text):
        return text, 0
    new, n = LEGENDARY_CHECK.subn(
        lambda c: 'chaosHolds(player, "%s", leftHand, config.%s)' % (LEGENDARY_CLASS[c.group(2)], c.group(1)), text)
    m = LEGENDARY_FUNC.search(new)
    return new[:m.start()] + LEGENDARY_HELPER + new[m.start():], n + 1


def droploot(text):
    if MARK in text:
        return text, 0
    return DROP_LINE.subn(DROP_NEW, text, count=1)


def recipes(text):
    """the belt and gloves recipes of a base crafting list inside a block comment"""
    out, pos, n = [], 0, 0
    for m in RECIPE_HEAD.finditer(text):
        if int(m.group(2)) not in BELTGLOVES or m.start() < pos:
            continue
        before = text[:m.start()].rstrip('\n').rsplit('\n', 1)[-1]
        if RECIPE_OPEN in before:
            continue
        indent = m.group(1)
        close = re.compile(r'^' + re.escape(indent) + r'\},?[ \t]*$', re.M).search(text, m.end())
        if not close:
            continue
        out.append(text[pos:m.start()])
        out.append(indent + RECIPE_OPEN + '\n' + text[m.start():close.end()] + '\n' + indent + ']==]')
        pos = close.end()
        n += 1
    out.append(text[pos:])
    return ''.join(out), n


def npc_texts(text):
    n = 0
    for pat, new in NPC_TEXTS:
        text, k = pat.subn(new, text)
        n += k
    return text, n


def items_xml(xml):
    """(new items.xml, changed count): the badges' slot type and the retired items' descriptions"""
    n = 0

    def item(m):
        nonlocal n
        iid = int(m.group(2))
        body = m.group(3)
        if iid in BADGES:
            new = re.sub(r'(<attribute\s+key="slotType"\s+value=")deckbadge(")', r'\1badge\2', body)
            if new != body:
                n += 1
            return m.group(1) + new + m.group(4)
        want = DESCRIPTIONS.get(iid)
        d = re.search(r'<attribute\s+key="description"\s+value="([^"]*)"\s*/>', body)
        if iid in CARDS:
            old = d.group(1).rstrip() if d else ''
            for gone in OLD_CARD_HINTS:
                if old.endswith(gone):
                    old = old[:-len(gone)].rstrip()
            if iid in CARD_TEXTS:
                want = CARD_TEXTS[iid].replace('&', '&amp;').replace('<', '&lt;').replace('"', '&quot;')
            else:
                want = old if old.endswith(CARD_HINT) else (old + ' ' + CARD_HINT).lstrip()
        if want is None:
            return m.group(0)
        if d:
            if d.group(1) == want:
                return m.group(0)
            body = body[:d.start(1)] + want + body[d.end(1):]
        else:
            indent = re.search(r'\n([ \t]*)<attribute', body)
            body = '\n%s<attribute key="description" value="%s" />' % (indent.group(1) if indent else '\t\t', want) + body
        n += 1
        return m.group(1) + body + m.group(4)
    out = re.sub(r'(<item\s+id="(\d+)"[^>]*[^/]>)(.*?)(</item>)', item, xml, flags=re.S)
    return out, n


def files(root, exts):
    for d, _sub, fs in sorted(os.walk(root)):
        for f in sorted(fs):
            if f.endswith(exts):
                yield os.path.join(d, f)


def run(data, dry=False):
    """-> (lines of the report, how many files change)"""
    report, changed = [], 0
    found = set()

    def apply(path, fn, what=None):
        nonlocal changed
        raw = read(path)
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        new, n = fn(text)
        if what and (n or MARK in text):
            found.add(what)
        if not n:
            return
        if fn(new)[1]:
            raise SystemExit('%s: not idempotent' % path)
        if crlf:
            new = new.replace('\n', '\r\n')
        changed += 1
        report.append('%s: %d change(s)' % (os.path.relpath(path, data).replace(os.sep, '/'), n))
        if not dry:
            write(path, new)

    for path in files(os.path.join(data, 'monster'), ('.lua',)):
        apply(path, fury)
    for path in files(os.path.join(data, 'scripts'), ('.lua',)):
        if os.sep + 'chaos' + os.sep in path:
            continue
        text = read(path)
        if DECK_CALL in text or MARK in text and 'deckOf' in text:
            apply(path, deck_system, 'deck')
        if 'config.itemidKnights' in text and 'whenPlayerAttack' in text:
            apply(path, legendary, 'legendary')
        if SEA_LINE.search(text.replace('\r\n', '\n')):
            apply(path, lambda t: hook(t, SEA_LINE, SEA_HOOK), 'sea')
        if RECIPE_TABLE.search(text.replace('\r\n', '\n')):
            apply(path, recipes, 'recipes')
    npc_dir = os.path.join(data, 'npc', 'scripts')
    if os.path.isdir(npc_dir):
        for path in files(npc_dir, ('.lua',)):
            text = read(path)
            if 'addItem(27799' in text:
                apply(path, npc_texts)
    drop = os.path.join(data, 'creaturescripts', 'scripts', 'droploot.lua')
    if os.path.isfile(drop):
        apply(drop, droploot, 'drop')
    player = os.path.join(data, 'events', 'scripts', 'player.lua')
    if os.path.isfile(player):
        apply(player, lambda t: hook(t, MOVE_LINE, MOVE_HOOK), 'move')
    xml_path = os.path.join(data, 'items', 'items.xml')
    if os.path.isfile(xml_path):
        apply(xml_path, items_xml)
    if not dry:
        for what, where in (('move', 'Player:onMoveItem'), ('deck', 'the deck system'), ('sea', 'the sea tiles'),
                            ('drop', 'the death loss (droploot.lua)'), ('recipes', 'the belt and gloves recipes'),
                            ('legendary', 'the legendary cards')):
            if what not in found:
                report.append('%s not found (skipped)' % where)
    return report, changed


def main(argv):
    dry = '--dry-run' in argv or '--check' in argv
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    report, changed = run(args[0], dry)
    for line in report:
        print(line)
    verb = 'would change' if dry else 'changed'
    print('badges: %d file(s) %s' % (changed, verb) if changed else 'badges: nothing to change')
    return 1 if ('--check' in argv and changed) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
