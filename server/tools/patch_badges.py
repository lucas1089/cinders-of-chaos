#!/usr/bin/env python3
"""Retire the base server's badges and amplifier catalysts (idempotent). install_all.py step `badges`.

usage: python3 -I patch_badges.py DATA_DIR [--dry-run] [--check]

server/README.md "Retired badges". The base has 40 badges (server ids 27803-27842, slot type "deckbadge": the base
engine's deck and badge inventory slots 12 and 13) and 31 amplifier catalysts (27843-27873) that upgrade a badge one
tier. Our client draws inventory slots 1-10 only, so no badge can be put on, and 16 base bosses dropped about 40 badge
and catalyst lines each. The rules are data/scripts/chaos/badges_core.lua; this tool changes the base data:

1. data/monster/**: every loot line of a badge or catalyst goes (Lua `{id = ...}` / `{name = ...}` lines inside
   monster.loot, XML `<item id=... />` / `<item name=... />` lines inside <loot>), by id or by the item's name in
   items.xml, any case. Nothing else of a file is rewritten.
2. data/scripts/** (not scripts/chaos): a roulette prize line `{itemId = <badge>, ...}` and a task reward line
   `{Type = RewardType.Item, Id = <badge or catalyst>, ...}` go.
3. the base catalyst action (the script with `upgraderType = 'amplifier'`): ChaosBadges.onCatalystUse runs first; it
   explains and keeps the catalyst and its target as they are.
4. data/events/scripts/player.lua: Player:onMoveItem asks ChaosBadges.onMoveItem first (a badge into slot 12 or 13 is
   refused; a packet our client cannot send, but a bot could).
5. data/items/items.xml: the description of every badge and catalyst says it cannot be worn and the Loot Buyer buys it.

Copies the players hold keep selling (the price table: data/items/item_price_rules.csv). A second run changes nothing.
--check changes nothing and exits 1 when something is still to do.
"""
import os
import re
import sys

sys.dont_write_bytecode = True

BADGES = range(27803, 27843)
CATALYSTS = range(27843, 27874)
IDS = set(BADGES) | set(CATALYSTS)
BADGE_DESC = 'A badge of the old orders. Badges cannot be worn any more; the Loot Buyer buys it.'
CATALYST_DESC = 'An amplifier of the old badge rite. Badges cannot be worn any more, so it upgrades nothing; the Loot Buyer buys it.'

MARK = 'Chaos: badges are retired (patch_badges.py)'
USE_HOOK = ('\t-- {mark}: the catalyst explains, nothing is used up\n'
            '\tif ChaosBadges and ChaosBadges.onCatalystUse and ChaosBadges.onCatalystUse(player, item, target) then\n'
            '\t\treturn true\n'
            '\tend\n').format(mark=MARK)
USE_LINE = re.compile(r'^function action\.onUse\(player, item, fromPosition, target, toPosition, isHotkey\)[ \t]*\n', re.M)
MOVE_HOOK = ('\t-- {mark}: no badge goes into the deck or badge slot\n'
             '\tif ChaosBadges and ChaosBadges.onMoveItem then\n'
             '\t\tlocal chaosBadgeRet = ChaosBadges.onMoveItem(self, item, toPosition)\n'
             '\t\tif chaosBadgeRet then\n'
             '\t\t\treturn chaosBadgeRet\n'
             '\t\tend\n'
             '\tend\n').format(mark=MARK)
MOVE_LINE = re.compile(r'^function Player:onMoveItem\(item, count, fromPosition, toPosition, fromCylinder, toCylinder\)'
                       r'[ \t]*\n', re.M)

LUA_LOOT = re.compile(r'^[ \t]*\{[ \t]*(?:id|name)[ \t]*=[ \t]*(?:"([^"\n]*)"|(\d+))[ \t]*[,}][^\n]*\n', re.M)
XML_LOOT = re.compile(r'^[ \t]*<item\s+(?:id="(\d+)"|name="([^"]*)")[^>\n]*/>[^\n]*\n', re.M)
PRIZE = re.compile(r'^[ \t]*\{[ \t]*itemId[ \t]*=[ \t]*(\d+)[ \t]*,[^\n]*\}[ \t]*,?[ \t]*(?:--[^\n]*)?\n', re.M)
REWARD = re.compile(r'^[ \t]*\{[ \t]*Type[ \t]*=[ \t]*RewardType\.Item[ \t]*,[ \t]*Id[ \t]*=[ \t]*(\d+)[ \t]*,[^\n]*\}'
                    r'[ \t]*,?[ \t]*(?:--[^\n]*)?\n', re.M)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def names_of(items_xml):
    """{lower-case name: id} of the retired ids in items.xml"""
    out = {}
    for m in re.finditer(r'<item\s+id="(\d+)"[^>]*?\bname="([^"]*)"', items_xml):
        if int(m.group(1)) in IDS:
            out[m.group(2).strip().lower()] = int(m.group(1))
    return out


def retired(ident, num, names):
    if num:
        return int(num) in IDS
    return (ident or '').strip().lower() in names


def lua_loot(text, names):
    m = re.search(r'monster\.loot\s*=\s*\{[ \t]*\n(.*?)\n\}', text, re.S)
    if not m:
        return text, 0
    n = [0]

    def drop(x):
        if retired(x.group(1), x.group(2), names):
            n[0] += 1
            return ''
        return x.group(0)
    body = LUA_LOOT.sub(drop, m.group(1) + '\n')[:-1]
    return text[:m.start(1)] + body + text[m.end(1):], n[0]


def xml_loot(text, names):
    n = [0]

    def drop(x):
        if retired(x.group(2), x.group(1), names):
            n[0] += 1
            return ''
        return x.group(0)

    def block(m):
        return XML_LOOT.sub(drop, m.group(0))
    return re.sub(r'<loot>.*?</loot>', block, text, flags=re.S), n[0]


def script_lines(text):
    n = [0]

    def drop(x):
        if int(x.group(1)) in IDS:
            n[0] += 1
            return ''
        return x.group(0)
    text = PRIZE.sub(drop, text) if 'prizePool' in text else text
    text = REWARD.sub(drop, text) if 'RewardType' in text else text
    return text, n[0]


def hook(text, line_re, code):
    if MARK in text:
        return text, 0
    m = line_re.search(text)
    if not m:
        return text, 0
    return text[:m.end()] + code + text[m.end():], 1


def descriptions(xml):
    """(new items.xml, changed count): each retired id's description attribute set to its text"""
    n = 0

    def item(m):
        nonlocal n
        iid = int(m.group(2))
        if iid not in IDS:
            return m.group(0)
        want = BADGE_DESC if iid in BADGES else CATALYST_DESC
        body = m.group(3)
        d = re.search(r'<attribute\s+key="description"\s+value="([^"]*)"\s*/>', body)
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
    xml_path = os.path.join(data, 'items', 'items.xml')
    names = names_of(read(xml_path)) if os.path.isfile(xml_path) else {}

    def apply(path, fn):
        nonlocal changed
        raw = read(path)
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        new, n = fn(text)
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

    for path in files(os.path.join(data, 'monster'), ('.lua', '.xml')):
        if path.endswith('.lua'):
            apply(path, lambda t: lua_loot(t, names))
        else:
            apply(path, lambda t: xml_loot(t, names))
    scripts = os.path.join(data, 'scripts')
    chaos = os.path.join(scripts, 'chaos') + os.sep
    for path in files(scripts, ('.lua',)):
        if path.startswith(chaos):
            continue
        apply(path, script_lines)
        text = read(path)
        if "upgraderType = 'amplifier'" in text:
            apply(path, lambda t: hook(t, USE_LINE, USE_HOOK))
            if MARK not in read(path) and not dry:
                report.append('%s: catalyst action not found (skipped)' % os.path.relpath(path, data))
    player = os.path.join(data, 'events', 'scripts', 'player.lua')
    if os.path.isfile(player):
        apply(player, lambda t: hook(t, MOVE_LINE, MOVE_HOOK))
        if MARK not in read(player) and not dry:
            report.append('events/scripts/player.lua: Player:onMoveItem not found (skipped)')
    if os.path.isfile(xml_path):
        apply(xml_path, descriptions)
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
