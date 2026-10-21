#!/usr/bin/env python3
"""One melee skill on equipment (idempotent). install_all.py step `meleeskill`.

usage: python3 -I patch_melee_skill.py DATA_DIR [--dry-run]

Beta report 2026-10-22 (server/README.md "One melee skill", "Melee and Ranged on equipment"): equipment still said and
gave "+2 Club", "+2 Axe" or "+2 Sword". The player's Melee is the best of the three engine skills, so a club bonus helped
only a player whose best skill was club. DATA_DIR is the base server's data folder.

1. items.xml: an item with any of skillSword, skillAxe, skillClub gets all three, each at the highest of them (the
   engine's own look text and the Chaos tooltip then show one melee number; data/scripts/chaos/melee_skill_look.lua
   writes it as "melee +N"). Fist (the Monk line's own skill) and distance stay as they are.
2. scripts/customs/rarity/base_rarity.lua: a rolled melee modifier (rarity_swordSkill, rarity_axeSkill,
   rarity_clubSkill: the stock roll, the Chaos orbs and the uniques) adds its number to all three engine skills.
   Marker: `-- Chaos: one melee skill (patch_melee_skill.py)`.

Exact match on the stock lines; anything else is reported and left alone. A second run changes nothing.
"""
import os
import re
import sys

MARK = '-- Chaos: one melee skill (patch_melee_skill.py)'
MELEE = ('skillSword', 'skillAxe', 'skillClub')

# ---------------------------------------------------------------- 1. items.xml
ITEM_BLOCK = re.compile(r'(<item\b[^>]*[^/]>)(.*?)(</item>)', re.S)
SKILL_ATTR = re.compile(r'^([ \t]*)<attribute\s+key="(skill(?:sword|axe|club))"\s+value="(-?\d+)"\s*/>[ \t]*\r?$',
                        re.I | re.M)


def patch_items(text):
    """(new text, number of items changed)"""
    changed = [0]

    def block(m):
        body = m.group(2)
        found = SKILL_ATTR.findall(body)
        if not found:
            return m.group(0)
        have = {}
        for _, key, value in found:
            have[key.lower()] = int(value)
        best = max(have.values())
        if len(have) == 3 and all(v == best for v in have.values()):
            return m.group(0)
        if best <= 0:
            return m.group(0)
        indent = found[-1][0]
        eol = '\r\n' if '\r\n' in body else '\n'

        def fix(a):
            return '%s<attribute key="%s" value="%d" />%s' % (a.group(1), a.group(2), best,
                                                              '\r' if a.group(0).endswith('\r') else '')
        body = SKILL_ATTR.sub(fix, body)
        missing = [k for k in MELEE if k.lower() not in have]
        if missing:
            last = list(SKILL_ATTR.finditer(body))[-1]
            add = ''.join('%s%s<attribute key="%s" value="%d" />' % (eol, indent, k, best) for k in missing)
            end = last.end()
            if body[end - 1:end] == '\r':
                end -= 1
            body = body[:end] + add + body[end:]
        changed[0] += 1
        return m.group(1) + body + m.group(3)

    return ITEM_BLOCK.sub(block, text), changed[0]


# ---------------------------------------------------------------- 2. base_rarity.lua
RARITY = os.path.join('scripts', 'customs', 'rarity', 'base_rarity.lua')
RARITY_OLD = re.compile(r'^([ \t]*)condition:setParameter\(info\.condition\.param, value\)[ \t]*$', re.M)
RARITY_NEW = (r'\g<0>' '\n'
              r'\1' + MARK + ': a melee modifier raises all three melee skills\n'
              r'\1if index == "swordSkill" or index == "axeSkill" or index == "clubSkill" then\n'
              r'\1    condition:setParameter(CONDITION_PARAM_SKILL_SWORD, value)\n'
              r'\1    condition:setParameter(CONDITION_PARAM_SKILL_AXE, value)\n'
              r'\1    condition:setParameter(CONDITION_PARAM_SKILL_CLUB, value)\n'
              r'\1end')


def patch_rarity(text):
    if MARK in text:
        return text, []
    if len(RARITY_OLD.findall(text)) != 1 or 'for index, info in pairs(conditions) do' not in text:
        return text, ['REFUSED: expected stock onEquip lines not found']
    return RARITY_OLD.sub(RARITY_NEW, text, count=1), ['a melee modifier raises all three melee skills']


def read(path, enc):
    with open(path, encoding=enc, errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text, enc):
    with open(path, 'w', encoding=enc, errors='surrogateescape', newline='') as f:
        f.write(text)


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    data = args[0]
    files, bad = 0, 0
    items = os.path.join(data, 'items', 'items.xml')
    if os.path.isfile(items):
        text = read(items, 'latin-1')
        new, n = patch_items(text)
        if n:
            if not dry:
                write(items, new, 'latin-1')
            files += 1
            print('items/items.xml: %d item(s) with one melee number on sword, axe and club' % n)
    else:
        print('items/items.xml: not found (skipped)')
    rarity = os.path.join(data, RARITY)
    if os.path.isfile(rarity):
        text = read(rarity, 'utf-8')
        crlf = '\r\n' in text
        new, changes = patch_rarity(text.replace('\r\n', '\n'))
        if changes and changes[0].startswith('REFUSED'):
            print('%s: %s' % (RARITY.replace(os.sep, '/'), changes[0]))
            bad += 1
        elif changes:
            if crlf:
                new = new.replace('\n', '\r\n')
            if not dry:
                write(rarity, new, 'utf-8')
            files += 1
            print('%s: %s' % (RARITY.replace(os.sep, '/'), ', '.join(changes)))
    else:
        print('%s: not found (skipped)' % RARITY.replace(os.sep, '/'))
    print('one melee skill: %d file(s) %s' % (files, 'would change' if dry else 'changed') if files
          else 'one melee skill: nothing to change')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
