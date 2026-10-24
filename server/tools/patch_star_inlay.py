#!/usr/bin/env python3
"""The base star stones keep a piece's rolled text and refuse a worn piece (idempotent; O181).
install_all.py step `starinlay`; server/README.md "Star inlay stones".

usage: python3 -I patch_star_inlay.py DATA_DIR [--dry-run] [--check]

DATA_DIR is the base server's data folder. The base system (data/scripts/customs/tier_system): a Star Inlay Stone (27133)
opens the three stars of a plain Skeletal, Netherwave, Ironwrath, Blightwoven or Ashborne piece, a Common .. Legendary
stone of 1, 2 or 3 stars (27134-27148) fills them (the piece becomes one of the star variants 26813-27112), the Star
Extractor (27149) takes them out again. Master of the Elements and the Ironhorn monsters drop the stones. It works; two
faults of the stock scripts are fixed here, and the tooltips say what the stones are for:

1. upgrade_system_tiers.lua: the stone wrote the item type's description over the item's own description attribute,
   which holds the Chaos crafting text ("Item Level: N. modifiers", sockets). StarInlay.refineItem keeps that text and
   adds one "Refined by <name>." line (data/scripts/chaos/star_inlay_core.lua).
2. upgrade_system_tiers.lua and star_extractor.lua: a worn piece is refused (the item type changes, but the equip event
   added the old type's speed and skills: taking the piece off took the new type's away). The extractor also removes
   the stale "Refined by" line from the empty-star piece.
3. items.xml: the descriptions of 27133 .. 27149 name the five sets and say "not worn" (the stock text said "certain
   equipment").

Nothing else changes: the drops, the item ids, the star variants and what a character holds stay. A second run changes
nothing. --check changes nothing and exits 1 while a file is left to patch.
"""
import os
import re
import sys

sys.dont_write_bytecode = True

TIER = os.path.join('scripts', 'customs', 'tier_system')
UPGRADE = os.path.join(TIER, 'upgrade_system_tiers.lua')
EXTRACTOR = os.path.join(TIER, 'star_extractor.lua')
ITEMS = os.path.join('items', 'items.xml')
MARK = '-- Chaos (patch_star_inlay.py)'
CORE = 'data/scripts/chaos/star_inlay_core.lua'
HEADER = 'local StarInlay = dofile("%s") %s' % (CORE, MARK)

SETS = 'Skeletal, Netherwave, Ironwrath, Blightwoven or Ashborne'
DESCRIPTIONS = {
    27133: 'Works on a plain %s helmet, armor, legs or boots that is not worn: the piece gets three empty stars '
           'for the star stones.' % SETS,
    27149: 'Works on a %s piece with stars that is not worn: you get the stone back and the piece keeps its empty '
           'stars.' % SETS,
}
for _i in range(27134, 27149):
    DESCRIPTIONS[_i] = ('Fits a %s piece with empty stars (opened with a Star Inlay Stone) that is not worn. '
                        'A Star Extractor takes the stars out and gives the stone back.' % SETS)

LF = r'\r?\n'
TARGET_ID = re.compile(r'^([ \t]*)local targetId = target\.itemid[ \t]*(?=\r?$)', re.M)
DESCRIPTION_LINE = re.compile(
    r'^([ \t]*)target:setAttribute\(ITEM_ATTRIBUTE_DESCRIPTION, ItemType\(target:getId\(\)\):getDescription\(\)'
    r'\.\."\\nRefined by "\.\.player:getName\(\)\.\."\."\)[ \t]*$', re.M)
TRANSFORM_LINE = re.compile(r'^([ \t]*)target:transform\(extractionData\.transformId\)[ \t]*$', re.M)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def _nl(text):
    return '\r\n' if '\r\n' in text else '\n'


def _guard(text):
    """the worn-piece refusal before `local targetId = target.itemid`: -> (text, changed)"""
    if 'StarInlay.isWorn' in text:
        return text, False
    nl = _nl(text)
    new, n = TARGET_ID.subn(lambda m: '%sif StarInlay.isWorn(toPosition) then %s%s%s    return StarInlay.refuseWorn(player)%s%send%s%s'
                            % (m.group(1), MARK, nl, m.group(1), nl, m.group(1), nl, m.group(0)), text, count=1)
    return new, bool(n)


def _header(text):
    if HEADER in text:
        return text, False
    return HEADER + _nl(text) + text, True


def patch_upgrade(text):
    """-> (new text, notes)"""
    notes = []
    new, changed = text, False
    if 'StarInlay.refineItem' not in new:
        new, n = DESCRIPTION_LINE.subn(
            lambda m: '%sStarInlay.refineItem(target, ItemType(target:getId()):getDescription(), player:getName()) %s'
            % (m.group(1), MARK), new)
        if not n:
            return text, ['upgrade_system_tiers.lua: the description line was not found (a changed base script?)']
        notes.append('upgrade_system_tiers.lua: the stone keeps the item text')
        changed = True
    new, g = _guard(new)
    if g:
        notes.append('upgrade_system_tiers.lua: a worn piece is refused')
    if changed or g:
        new, _ = _header(new)
    return new, notes


def patch_extractor(text):
    notes = []
    new, changed = text, False
    if 'StarInlay.unrefineItem' not in new:
        nl = _nl(new)
        new, n = TRANSFORM_LINE.subn(
            lambda m: '%s%s%s%sStarInlay.unrefineItem(target) %s' % (m.group(0), nl, m.group(1), '', MARK), new)
        if not n:
            return text, ['star_extractor.lua: the transform line was not found (a changed base script?)']
        notes.append('star_extractor.lua: the stale "Refined by" line goes')
        changed = True
    new, g = _guard(new)
    if g:
        notes.append('star_extractor.lua: a worn piece is refused')
    if changed or g:
        new, _ = _header(new)
    return new, notes


def patch_items(xml):
    """the descriptions of the stones and the extractor -> (new items.xml, notes)"""
    notes = []
    for iid, sentence in sorted(DESCRIPTIONS.items()):
        m = re.search(r'(<item\s+id="%d"[^>]*[^/]>)(.*?)(</item>)' % iid, xml, re.S)
        if not m:
            notes.append('items.xml: %d not found' % iid)
            continue
        body = m.group(2)
        if sentence in body:
            continue
        d = re.search(r'(<attribute\s+key="description"\s+value=")([^"]*)(")', body)
        if d:
            old = d.group(2).rstrip()
            body = body[:d.start()] + d.group(1) + (old + ' ' if old else '') + sentence + d.group(3) + body[d.end():]
        else:
            indent = re.search(r'\n([ \t]*)<attribute', body)
            nl = _nl(body)
            body = '%s%s<attribute key="description" value="%s" />' % (
                nl, indent.group(1) if indent else '\t\t', sentence) + body
        xml = xml[:m.start(2)] + body + xml[m.end(2):]
        notes.append('items.xml: %d described' % iid)
    return xml, notes


def run(data, dry=False):
    """-> (report lines, number of files that change)"""
    report, changed = [], 0
    for rel, fn in ((UPGRADE, patch_upgrade), (EXTRACTOR, patch_extractor), (ITEMS, patch_items)):
        path = os.path.join(data, rel)
        name = rel.replace(os.sep, '/')
        if not os.path.isfile(path):
            report.append('%s: not found, skipped' % name)
            continue
        text = read(path)
        new, notes = fn(text)
        report += notes
        if new != text:
            changed += 1
            if not dry:
                write(path, new)
        elif not notes:
            report.append('%s: nothing to do' % name)
    return report, changed


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    check = '--check' in argv
    report, changed = run(args[0], dry=check or '--dry-run' in argv)
    for line in report:
        print(line)
    if check and changed:
        print('%d file(s) still to patch' % changed)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
